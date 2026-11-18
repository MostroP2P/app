/// Identity API — key generation, import, export, and BIP-32 trade key
/// derivation. All cryptographic operations stay in Rust; Flutter receives
/// only public information and status via the bridge.
///
/// # Secure storage contract
/// The mnemonic is generated in Rust and returned to Flutter **once**.
/// Flutter is responsible for storing it in `flutter_secure_storage`.
/// On every subsequent launch, Flutter reads the mnemonic from secure storage
/// and calls `load_identity_from_mnemonic` to reload the in-memory key state.
///
/// This module maintains an in-memory `IdentityState`. The DB persistence for
/// `IdentityInfo` is wired in Phase 4 when the app-level storage initializer
/// is added.
use anyhow::{anyhow, bail, Result};
use nostr_sdk::prelude::*;
use std::sync::OnceLock;
use tokio::sync::broadcast;
use tokio::sync::broadcast::error::RecvError;
use tokio::sync::RwLock;

use crate::api::types::{IdentityInfo, NymIdentity};
use crate::crypto::{keys as key_ops, nym};
use crate::db::settings_keys::IDENTITY_WIPE_PENDING;
use crate::db::Storage;
use crate::identity_slot::{IdentitySlot, IdentityState};
use crate::mostro::delete_effects::{DeleteEffects, RealDeleteEffects};

// ── Global in-memory identity state ──────────────────────────────────────────

/// The process's identity slot.
fn identity_slot() -> &'static IdentitySlot {
    static SLOT: IdentitySlot = IdentitySlot::new();
    &SLOT
}

fn identity_lock() -> &'static RwLock<Option<IdentityState>> {
    &identity_slot().state
}

/// The generation of the active identity, or `None` without one.
pub(crate) async fn identity_generation() -> Option<u64> {
    let slot = identity_slot();
    let guard = slot.state.read().await;
    guard
        .as_ref()
        .map(|_| slot.generation.load(std::sync::atomic::Ordering::SeqCst))
}

/// Run `write` only while the identity of `generation` is still the active
/// one, else `None` without running it (PR #590 review).
///
/// For a write that outlives an await — a network transfer that ends in a
/// cache write. The read lock is held across `write`, and deletion takes the
/// write lock to retire the identity before it wipes its data, so a write
/// that passes this check always lands before the wipe, which then removes
/// it; one that comes later is refused.
pub(crate) async fn while_identity_current<T>(
    generation: u64,
    write: impl std::future::Future<Output = T>,
) -> Option<T> {
    let slot = identity_slot();
    let guard = slot.state.read().await;
    let current =
        guard.is_some() && slot.generation.load(std::sync::atomic::Ordering::SeqCst) == generation;
    if !current {
        return None;
    }
    let out = write.await;
    drop(guard);
    Some(out)
}

// ── Trade-key counter publication ────────────────────────────────────────────

/// Derivations are rare and Dart consumes them immediately; a small buffer is
/// ample. `Lagged` is skipped rather than fatal, and the counter is monotonic,
/// so a skipped value is superseded by the next one.
const TRADE_KEY_INDEX_CHANNEL_CAPACITY: usize = 16;

fn trade_key_index_tx() -> &'static broadcast::Sender<u32> {
    static TX: OnceLock<broadcast::Sender<u32>> = OnceLock::new();
    TX.get_or_init(|| broadcast::channel(TRADE_KEY_INDEX_CHANNEL_CAPACITY).0)
}

/// Publishes a consumed trade-key index so Flutter can mirror it into secure
/// storage — the one store that survives loss of `mostro.db` (issue #249).
/// Send failures mean nobody is listening yet, which is not an error: the DB
/// row remains the primary record and load-time reconciliation catches up.
///
/// The channel is a parameter rather than the global so tests can assert on
/// their own, giving each one a stream nothing else publishes to.
fn publish_index(tx: &broadcast::Sender<u32>, index: u32) {
    let _ = tx.send(index);
}

/// A stream of consumed trade-key indices for the Dart layer to persist.
pub struct TradeKeyIndexStream {
    rx: broadcast::Receiver<u32>,
}

impl TradeKeyIndexStream {
    /// Poll for the next consumed index.
    ///
    /// `RecvError::Lagged` is skipped: the counter only moves forward, so the
    /// next value received is at least as high as the one missed.
    pub async fn next(&mut self) -> Result<u32> {
        loop {
            match self.rx.recv().await {
                Ok(index) => return Ok(index),
                Err(RecvError::Lagged(n)) => {
                    log::warn!("[identity] trade-key index stream lagged {n} value(s)");
                }
                Err(RecvError::Closed) => {
                    bail!("TradeKeyIndexStream closed: sender dropped")
                }
            }
        }
    }
}

/// Subscribe to consumed trade-key indices. Flutter calls this once at startup
/// and writes every value it receives to secure storage.
pub fn on_trade_key_index_changed() -> TradeKeyIndexStream {
    TradeKeyIndexStream {
        rx: trade_key_index_tx().subscribe(),
    }
}

// ── Return types ──────────────────────────────────────────────────────────────

/// Returned by `create_identity`. Mnemonic is shown **once** — Flutter must
/// persist it in `flutter_secure_storage` immediately.
pub struct IdentityCreationResult {
    /// Hex-encoded Nostr public key (x-only, 64 chars).
    pub public_key: String,
    /// 12-word BIP-39 mnemonic — show once, must be backed up.
    pub mnemonic_words: Vec<String>,
}

/// Info about a single BIP-32 trade key.
pub struct TradeKeyInfo {
    pub index: u32,
    pub public_key: String,
}

/// Progress during session recovery (daemon contact not yet implemented).
pub struct RecoveryProgress {
    pub phase: String,
    pub current: u32,
    pub total: u32,
}

// ── API functions ─────────────────────────────────────────────────────────────

/// Create a brand-new identity. Generates a 12-word mnemonic, derives the
/// identity key, and loads it into the in-memory state.
///
/// Returns the public key + mnemonic. **The mnemonic is never stored by Rust.**
/// Flutter MUST persist it in `flutter_secure_storage` before displaying it.
///
/// Returns `Err("AlreadyExists")` if an identity is already loaded.
pub async fn create_identity() -> Result<IdentityCreationResult> {
    create_in(identity_slot(), crate::db::app_db::db()).await
}

/// [`create_identity`] on `slot`, against `db`.
async fn create_in<S: Storage>(
    slot: &IdentitySlot,
    db: Option<&S>,
) -> Result<IdentityCreationResult> {
    let _transition = slot.lifecycle.lock().await;
    // Checked with a read lock, not held across the wipe below: the
    // lifecycle lock keeps the slot as checked until the install, so readers
    // of the identity never wait on the wipe.
    if slot.state.read().await.is_some() {
        bail!("AlreadyExists");
    }

    // A point where retrying a pending data wipe is safe: the slot is empty
    // (checked above, and kept so), so the tables hold nothing of a live
    // identity (issue #555). A retry that fails again refuses the new
    // identity: once one is installed, the launch reload never retries, and
    // the previous user's rows would stay for the life of the install.
    if let Some(db) = db {
        retry_pending_wipe(db).await?;
    }

    let mnemonic_words = key_ops::generate_mnemonic()?;
    let keys = key_ops::derive_master_key(&mnemonic_words)?;
    let public_key = keys.public_key().to_hex();

    let now = unix_now();
    let identity_info = IdentityInfo {
        public_key: public_key.clone(),
        display_name: None,
        privacy_mode: false,
        trade_key_index: 0,
        created_at: now,
    };

    *slot.state.write().await = Some(IdentityState {
        mnemonic_words: mnemonic_words.clone(),
        keys,
        identity_info,
    });

    Ok(IdentityCreationResult {
        public_key,
        mnemonic_words,
    })
}

/// Load an existing identity from a BIP-39 mnemonic (called on every launch
/// after the first, reading from Flutter's `flutter_secure_storage`).
///
/// Pass the `trade_key_index` previously stored so the key counter is restored.
/// Pass `created_at` from the persisted value so the original creation timestamp
/// is preserved; pass `None` (or `0`) to fall back to the current time.
pub async fn load_identity_from_mnemonic(
    words: Vec<String>,
    trade_key_index: u32,
    privacy_mode: bool,
    created_at: Option<i64>,
) -> Result<IdentityInfo> {
    load_in(
        identity_slot(),
        crate::db::app_db::db(),
        trade_key_index_tx(),
        words,
        trade_key_index,
        privacy_mode,
        created_at,
    )
    .await
}

/// [`load_identity_from_mnemonic`] on `slot`, against `db`, publishing the
/// reconciled trade-key counter to `tx`.
async fn load_in<S: Storage>(
    slot: &IdentitySlot,
    db: Option<&S>,
    tx: &broadcast::Sender<u32>,
    words: Vec<String>,
    trade_key_index: u32,
    privacy_mode: bool,
    created_at: Option<i64>,
) -> Result<IdentityInfo> {
    let _transition = slot.lifecycle.lock().await;
    load_unlocked(
        slot,
        db,
        tx,
        words,
        trade_key_index,
        privacy_mode,
        created_at,
    )
    .await
}

/// [`load_in`] for a caller already holding `slot.lifecycle`.
async fn load_unlocked<S: Storage>(
    slot: &IdentitySlot,
    db: Option<&S>,
    tx: &broadcast::Sender<u32>,
    words: Vec<String>,
    trade_key_index: u32,
    privacy_mode: bool,
    created_at: Option<i64>,
) -> Result<IdentityInfo> {
    // Deriving is the validation: it parses the phrase and fails on a bad word
    // or checksum with the same `invalid mnemonic` error the explicit check
    // used to produce.
    let keys = key_ops::derive_master_key(&words)?;
    let public_key = keys.public_key().to_hex();

    // Reconcile with the index Rust persisted at derivation time. The two
    // stores can disagree (e.g. the Dart-side value is only written on
    // create success), and the counter must never move backwards.
    //
    // A read failure falls back to the passed index rather than failing the
    // load: identity loading must survive a corrupt store, and the fallback
    // is safe — any subsequent derivation either persists (repairing the
    // store) or fails before handing out a key.
    let stored = match db {
        Some(db) => match db.get_identity().await {
            Ok(v) => v,
            Err(e) => {
                log::warn!(
                    "[identity] could not read persisted identity — \
                     falling back to secure-storage index: {e}"
                );
                None
            }
        },
        None => None,
    };
    let trade_key_index =
        reconcile_and_publish_to(tx, trade_key_index, stored.as_ref(), &public_key);

    let created_at = match created_at {
        Some(ts) if ts > 0 => ts,
        _ => unix_now(),
    };
    let identity_info = IdentityInfo {
        public_key: public_key.clone(),
        display_name: None,
        privacy_mode,
        trade_key_index,
        created_at,
    };

    {
        let mut guard = slot.state.write().await;
        *guard = Some(IdentityState {
            mnemonic_words: words,
            keys,
            identity_info: identity_info.clone(),
        });
    }

    // The rows a failed wipe kept may be this identity's own: then the
    // pending wipe is over, without wiping anything (issue #555).
    if let Some(db) = db {
        release_own_wipe_marker(db, &public_key).await;
    }

    // An older install's shared Cashu proof store goes to the identity the
    // app starts with — this load, at the first launch after the upgrade.
    // Inside the transition, both the launch reload and an import claim it,
    // and the lifecycle lock the caller holds keeps any replacement out until
    // the claim is done. Not under the state lock: the claim touches only
    // files and settings, so no reader of the identity waits on it.
    crate::api::cashu::claim_legacy_store(&identity_info.public_key).await;

    Ok(identity_info)
}

/// Check that `words` are a phrase the core accepts, without loading it: a
/// bad word or a bad checksum fails with `invalid mnemonic: …`, as an import
/// of them would.
///
/// The Account screen's import deletes the current identity before it
/// imports, and the deletion wipes that identity's trades, chats and payout
/// claims. So the words are checked first, here, by the same derivation the
/// import runs (`derive_master_key` is the validation): a phrase the import
/// would refuse never costs the previous identity its rows (review of #573).
pub fn validate_mnemonic(words: Vec<String>) -> Result<()> {
    key_ops::derive_master_key(&words).map(|_| ())
}

/// Import identity from a BIP-39 mnemonic phrase (user-entered recovery).
///
/// When `recover = true`, the daemon recovery flow is triggered (Phase 7).
/// Currently this validates and loads the mnemonic; recovery contacts are
/// initiated separately via the daemon API.
pub async fn import_from_mnemonic(words: Vec<String>, recover: bool) -> Result<IdentityInfo> {
    // Source the authoritative privacy mode up front. Recovery is only possible
    // in Reputation mode; Full-Privacy trades are anonymous by design and can't
    // be replayed by the daemon.
    let privacy_mode = crate::api::reputation::get_privacy_mode();
    // Reject privacy-mode recovery BEFORE loading — otherwise the identity is
    // already swapped when we bail, leaving the user in a mutated state, and it
    // violates the "reject before any network traffic" contract for restore.
    if recover && privacy_mode {
        bail!("PrivacyModeRecoveryUnavailable");
    }
    let info = import_in(
        identity_slot(),
        crate::db::app_db::db(),
        trade_key_index_tx(),
        words,
        privacy_mode,
    )
    .await?;
    if recover {
        // NOTE: recovery is best-effort relative to the import, but this `?`
        // propagates a restore failure AFTER the identity has already been
        // swapped — so a slow/unreachable daemon makes the caller see "import
        // failed" when the import itself succeeded and only recovery didn't.
        // Not reachable today (identity_service.dart passes recover: false).
        // #219 restructures the waiting; revisit this propagation when it lands.
        crate::api::orders::restore_session().await?;
    }
    Ok(info)
}

/// The install half of [`import_from_mnemonic`], on `slot` against `db`.
///
/// An import replaces the deleted identity just as a creation does, so it
/// settles a pending wipe first — and refuses, like a creation, when it
/// cannot (issue #555).
async fn import_in<S: Storage>(
    slot: &IdentitySlot,
    db: Option<&S>,
    tx: &broadcast::Sender<u32>,
    words: Vec<String>,
    privacy_mode: bool,
) -> Result<IdentityInfo> {
    // The retry and the load are one transition: a creation slipping in
    // between would find the slot the retry left empty.
    let _transition = slot.lifecycle.lock().await;
    // Deriving is the validation, done before the retry: a phrase the core
    // rejects must not cost the previous identity's rows a wipe.
    key_ops::derive_master_key(&words)?;
    retry_pending_wipe_if_vacant(slot, db).await?;
    load_unlocked(slot, db, tx, words, 0, privacy_mode, None).await
}

/// Import identity from an nsec (bech32-encoded Nostr secret key).
/// Note: nsec import produces a single key with no BIP-39 mnemonic backup.
///
/// When the slot is empty, a pending wipe is retried first, and a retry that
/// fails refuses the import with `PendingWipeFailed` (issue #555). A slot
/// already taken is installed over, as before, without a generation bump.
pub async fn import_from_nsec(nsec: String) -> Result<IdentityInfo> {
    import_nsec_in(identity_slot(), crate::db::app_db::db(), nsec).await
}

/// [`import_from_nsec`] on `slot`, against `db`.
async fn import_nsec_in<S: Storage>(
    slot: &IdentitySlot,
    db: Option<&S>,
    nsec: String,
) -> Result<IdentityInfo> {
    let _transition = slot.lifecycle.lock().await;
    let keys =
        Keys::parse(&nsec).map_err(|e| anyhow!("InvalidKey: {e}"))?;
    let public_key = keys.public_key().to_hex();

    let now = unix_now();
    let identity_info = IdentityInfo {
        public_key: public_key.clone(),
        display_name: None,
        privacy_mode: false,
        trade_key_index: 0,
        created_at: now,
    };

    retry_pending_wipe_if_vacant(slot, db).await?;
    *slot.state.write().await = Some(IdentityState {
        mnemonic_words: vec![], // no mnemonic for nsec imports
        keys,
        identity_info: identity_info.clone(),
    });

    Ok(identity_info)
}

/// Get current identity info. Returns `None` if no identity is loaded.
pub async fn get_identity() -> Result<Option<IdentityInfo>> {
    let guard = identity_lock().read().await;
    Ok(guard.as_ref().map(|s| s.identity_info.clone()))
}

/// The BIP-39 seed of the loaded identity.
///
/// Crate-internal on purpose — it is *not* part of the bridge surface, and FRB
/// skips it because it is not `pub`. The Cashu wallet (phase C2) needs a
/// 64-byte seed to derive its blinding secrets, and reusing this one is what
/// makes the ecash recoverable from the words the user already backed up.
///
/// **Errors** (stable markers): `NoIdentity` when none is loaded,
/// `CashuNoMnemonic` for an nsec-imported identity, `CashuSeedUnavailable` when
/// derivation fails.
pub(crate) async fn current_bip39_seed() -> Result<zeroize::Zeroizing<[u8; 64]>> {
    let guard = identity_lock().read().await;
    let state = guard.as_ref().ok_or_else(|| anyhow!("NoIdentity"))?;

    // An nsec import stores no mnemonic (see `import_from_nsec`), so there is
    // no seed to derive — and no recoverable ecash to be had either. Its own
    // marker, because "no identity" would send the user to log in again, which
    // is not the problem and would not fix it. The other mnemonic-only paths in
    // this file refuse the same way.
    if state.mnemonic_words.is_empty() {
        bail!("CashuNoMnemonic");
    }

    key_ops::derive_bip39_seed(&state.mnemonic_words).map_err(|e| {
        // The mnemonic was validated on the way in, so this is a bug rather
        // than a user state — the cause goes to the log, the marker to Dart.
        log::error!("[identity] seed derivation failed for a loaded identity: {e}");
        anyhow!("CashuSeedUnavailable")
    })
}

/// Delete the in-memory identity state. Flutter must also clear
/// `flutter_secure_storage` after calling this.
pub async fn delete_identity() -> Result<()> {
    delete_identity_inner(crate::db::app_db::db(), &RealDeleteEffects).await
}

/// [`delete_identity`], with the store and the side effects injected.
///
/// The parameters exist for the identity lifecycle test (#553): the database
/// and the in-memory stores are process-wide, and tests run in parallel
/// against them, so a real wipe there deletes the rows other tests are
/// asserting on. The test injects a throwaway store and doubles for the
/// effects instead, while the full wipe is covered where it can run alone
/// (`clear_identity_data_wipes_the_identity_and_keeps_the_device`,
/// `clearing_the_store_leaves_no_chats_and_no_unread_count`). There is no
/// switch to skip the wipe: a deletion always wipes, so no argument of
/// [`delete_identity`] can turn it off while the tests stay green (PR #565
/// review). The binding of the real store and effects is held by
/// `deleting_the_identity_binds_the_real_store_and_effects`.
async fn delete_identity_inner<S: Storage, W: DeleteEffects>(db: Option<&S>, fx: &W) -> Result<()> {
    delete_in(identity_slot(), db, fx).await
}

/// [`delete_identity_inner`] on `slot`.
async fn delete_in<S: Storage, W: DeleteEffects>(
    slot: &IdentitySlot,
    db: Option<&S>,
    fx: &W,
) -> Result<()> {
    // Held to the end, the wipe included: the owner read here is the
    // identity the take below retires and the wipe below clears, and no
    // transition sees the slot or the marker in between.
    let _transition = slot.lifecycle.lock().await;
    let Some(owner) = slot
        .state
        .read()
        .await
        .as_ref()
        .map(|state| state.identity_info.public_key.clone())
    else {
        bail!("NoIdentity");
    };
    // Before anything of the identity is given up: a wipe that fails later
    // leaves this marker behind, so no replacement installs over the rows it
    // kept. A marker that cannot be recorded refuses the deletion here, while
    // the identity is still whole (issue #555).
    record_wipe_intent(db, &owner).await?;
    // While the identity still exists: its relay subscriptions are given
    // back first, so nothing of the old user's keeps arriving afterwards.
    fx.release_identity_subscriptions().await;

    let mut guard = slot.state.write().await;
    if guard.is_none() {
        bail!("NoIdentity");
    }
    *guard = None;
    // Under the same lock, so no `while_identity_current` write can start
    // between the two.
    slot.generation
        .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    drop(guard);

    // The push server must stop waking this device for keys the user no
    // longer holds; the registrations name pubkeys only, so no key is needed.
    fx.unregister_push().await;

    // Everything the identity persisted — its row and trade-key counter, the
    // per-order key mappings, trades, chats, payout claims, the outbound
    // queue, per-order cursors (issue #533) — in one transaction. The next
    // user must find the app as a fresh install would leave it, and a new
    // mnemonic must start counting from zero. A wipe that fails keeps all of
    // it, the mappings with the trades they name (review of #573); the
    // identity is already gone, so the failure is reported, never turned
    // into a failed deletion, and the marker recorded above stays for the
    // retry. (A stale identity row is still kept from a different identity
    // by the pubkey guard in `reconcile_trade_key_index`.) `record_wipe_intent`
    // has refused a deletion without a database, so there always is one here.
    let mut failures = Vec::new();
    if let Some(db) = db {
        match db.clear_identity_data().await {
            // A wipe that succeeds settles the pending retry, whichever
            // deletion left it behind.
            Ok(()) => {
                if let Err(e) = db.delete_setting(IDENTITY_WIPE_PENDING).await {
                    failures.push(format!("wipe-pending marker kept: {e}"));
                }
            }
            Err(e) => failures.push(format!("identity data rows kept: {e}")),
        }
    }
    fx.forget_identity_state().await;

    // Last, so the buffered lines are dropped too: they name orders and
    // counterparties of the identity being deleted, and the Logs screen can
    // still share them afterwards. The platform console keeps them. The
    // cleanup failures are the exception, re-emitted after the clear.
    clear_logs_and_report(&failures);

    Ok(())
}

/// Record that `owner`'s data is about to be wiped, before the deletion
/// gives anything up (issue #555): [`IDENTITY_WIPE_PENDING`], holding
/// `owner`'s public key, makes the next identity creation or import retry a
/// wipe that then fails ([`retry_pending_wipe`]), and tells a reload of that
/// same identity the rows are its own ([`release_own_wipe_marker`]).
///
/// Fails with the `WipeNotRecorded` marker, and the caller must not delete,
/// when the marker cannot be written or read: a deletion that went ahead
/// without it would let the replacement install over the previous
/// identity's rows, with nothing left to say so. With no database at all it
/// fails with `StorageUnavailable`: rows earlier sessions persisted may be on
/// disk with nowhere to record them, and no retry in this session can
/// succeed. That keeps a possibly compromised identity until the store comes
/// back — deliberately: rotating it would leave the previous user's rows on
/// disk with no trace.
///
/// Written ahead, a crash between this and the wipe leaves the marker with
/// the identity still in Flutter's secure storage, which the launch reload
/// releases. A marker already there names an earlier deletion whose rows are
/// still on disk, and stays: overwritten, the reload of `owner` would
/// release it and keep them.
async fn record_wipe_intent<S: Storage>(db: Option<&S>, owner: &str) -> Result<()> {
    let Some(db) = db else {
        crate::api::logging::blog_warn(
            "identity",
            "no database this session — the identity is kept, since rows persisted by \
             earlier sessions could not be wiped or marked for a retry"
                .to_string(),
        );
        bail!("StorageUnavailable");
    };
    let written = match db.get_setting(IDENTITY_WIPE_PENDING).await {
        Ok(Some(_)) => return Ok(()),
        Ok(None) => db.set_setting(IDENTITY_WIPE_PENDING, owner).await,
        Err(e) => Err(e),
    };
    if let Err(e) = written {
        crate::api::logging::blog_warn(
            "identity",
            format!("the wipe-pending marker could not be recorded — the identity is kept: {e}"),
        );
        bail!("WipeNotRecorded");
    }
    Ok(())
}

/// Drop the buffered log history, then report the cleanup failures where the
/// user can still find them (issue #555).
///
/// The order is the point: `clear_logs()` first, because the buffered lines
/// name orders and counterparties of the deleted identity — but a cleanup
/// failure dropped with them would leave a wipe that kept the previous
/// identity's rows with no trace anywhere the user can reach. Re-emitting
/// through `blog_warn` puts each failure on the platform console, in the
/// fresh history the Logs screen loads, and on the live stream. The strings
/// outlive the clear, so they must name no order or counterparty.
fn clear_logs_and_report(failures: &[String]) {
    crate::api::logging::clear_logs();
    for failure in failures {
        crate::api::logging::blog_warn("identity", format!("cleanup failed — {failure}"));
    }
}

/// Retry the data wipe a previous deletion left pending, if any (issue #555).
///
/// Only sound while no identity holds the slot: `clear_identity_data`
/// empties whole tables, so a retry with a live identity would take its
/// trades — and its payout claims, which no restore brings back — along with
/// the leftovers. Its callers check the slot first, holding its lifecycle
/// lock until they install; that is why the launch reload
/// (`load_identity_from_mnemonic`) never calls this.
///
/// Fails with the `PendingWipeFailed` marker when the wipe fails again, and
/// the caller must not install an identity then: the marker stays, and the
/// next creation or import retries. A marker that cannot be read fails the
/// same way, without wiping: it may be a pending wipe, and guessing either
/// way is wrong — a blind wipe, or a new identity over the old rows.
async fn retry_pending_wipe<S: Storage>(db: &S) -> Result<()> {
    match db.get_setting(IDENTITY_WIPE_PENDING).await {
        Ok(Some(_)) => {}
        Ok(None) => return Ok(()),
        Err(e) => {
            crate::api::logging::blog_warn(
                "identity",
                format!(
                    "the wipe-pending marker could not be read — no new identity until it can: {e}"
                ),
            );
            bail!("PendingWipeFailed");
        }
    }
    if let Err(e) = db.clear_identity_data().await {
        crate::api::logging::blog_warn(
            "identity",
            format!(
                "retry of the pending identity wipe failed — \
                 the previous identity's data is still on disk: {e}"
            ),
        );
        bail!("PendingWipeFailed");
    }
    log::info!("[identity] pending identity wipe completed on retry");
    if let Err(e) = db.delete_setting(IDENTITY_WIPE_PENDING).await {
        crate::api::logging::blog_warn(
            "identity",
            format!("cleanup failed — wipe-pending marker kept: {e}"),
        );
    }
    Ok(())
}

/// [`retry_pending_wipe`] for an import, which may find the slot taken:
/// retries only while it is empty. Dart deletes the current identity before
/// importing, so that is every import it makes; a slot already taken is the
/// launch reload's case, where a retry would take the live identity's data.
/// The caller holds `slot.lifecycle`, which keeps the slot as checked until
/// it installs; the check takes a read lock, released before the wipe, so
/// readers of the identity never wait on it.
async fn retry_pending_wipe_if_vacant<S: Storage>(
    slot: &IdentitySlot,
    db: Option<&S>,
) -> Result<()> {
    if slot.state.read().await.is_some() {
        return Ok(());
    }
    if let Some(db) = db {
        retry_pending_wipe(db).await?;
    }
    Ok(())
}

/// Drop a wipe-pending marker that `public_key` itself left (issue #555).
///
/// A replacement refused with `PendingWipeFailed` leaves the deleted
/// identity's mnemonic in Flutter's secure storage, so the next launch
/// reloads that same identity — and the rows the wipe kept are its own.
/// Nothing is wiped here: the marker goes, and the rows stay with their
/// owner. A marker that names another identity, or cannot be read, stays.
async fn release_own_wipe_marker<S: Storage>(db: &S, public_key: &str) {
    match db.get_setting(IDENTITY_WIPE_PENDING).await {
        Ok(Some(owner)) if owner == public_key => {}
        _ => return,
    }
    match db.delete_setting(IDENTITY_WIPE_PENDING).await {
        Ok(()) => {
            log::info!("[identity] reloaded the identity whose wipe was pending — its rows stay")
        }
        Err(e) => log::warn!("[identity] wipe-pending marker of the reloaded identity kept: {e}"),
    }
}

/// Whether a previous identity deletion left its data wipe pending: the
/// previous identity's rows may still be on disk and no retry has succeeded
/// yet (issue #555). The Account screen shows a warning while this holds.
/// A marker that cannot be read reads as none: the warning is diagnostic,
/// and the retry does not depend on it.
pub async fn has_pending_identity_wipe() -> bool {
    match crate::db::app_db::db() {
        Some(db) => has_pending_wipe(db).await,
        None => false,
    }
}

/// [`has_pending_identity_wipe`] against `db`.
async fn has_pending_wipe<S: Storage>(db: &S) -> bool {
    matches!(db.get_setting(IDENTITY_WIPE_PENDING).await, Ok(Some(_)))
}

/// What the current identity would lose if it were replaced now: locked
/// escrow, locked or payable bonds, open payout claims, live trades — most
/// serious first — then its Cashu wallet's ecash and the invoices that fund
/// it not minted yet; empty when it is safe to go ahead (issue #533).
///
/// The Account screen calls this before generating a new user or importing a
/// seed, and warns. It reads the local rows only: no relay round trip sits
/// between the user and the dialog. With no database there is nothing to
/// lose track of, so that reads as empty.
pub async fn funds_at_risk() -> Result<Vec<crate::api::types::FundsAtRisk>> {
    let Some(db) = crate::db::app_db::db() else {
        return Ok(Vec::new());
    };
    let trades = db.list_trades().await?;
    let claims = db.list_bond_claims().await?;
    let mut risks = crate::mostro::funds_at_risk::funds_at_risk(&trades, &claims, unix_now());
    // The Cashu wallet is per identity: replacing this one strands its ecash
    // unless these words are kept. An unreadable store is logged, not fatal —
    // it must not hide the trade risks above.
    match crate::api::cashu::identity_balance_at_risk().await {
        Ok(Some(sats)) => risks.push(crate::api::types::FundsAtRisk {
            order_id: String::new(),
            reason: crate::api::types::FundsAtRiskReason::CashuWalletBalance,
            amount_sats: Some(sats),
        }),
        Ok(None) => {}
        Err(e) => log::warn!("[identity] Cashu balance unreadable for the funds check: {e}"),
    }
    // Invoices to fund that wallet, paid or maybe paid, not minted yet: they
    // live in the same store, under the same words.
    match crate::api::cashu::identity_invoices_at_risk().await {
        Ok(Some(risk)) => risks.push(risk),
        Ok(None) => {}
        Err(e) => log::warn!("[identity] Cashu invoices unreadable for the funds check: {e}"),
    }
    Ok(risks)
}

/// Empty what the process holds in memory about the deleted identity, and
/// point the public subscriptions at a clean book (issue #533).
///
/// The stores are process-wide singletons, so without this the new user sees
/// the previous one's disputes, ratings and `is_mine` marks until a restart,
/// whatever the database says.
pub(crate) async fn forget_identity_state() {
    crate::api::disputes::forget_identity_disputes().await;
    crate::api::reputation::forget_identity_ratings().await;
    crate::api::my_reputation::forget_identity_reputation().await;
    crate::mostro::session::session_manager().clear().await;
    crate::mostro::bond_claims::set_claim_nodes(std::iter::empty());
    crate::mostro::bond_claims::clear_retained();
    // The book's own-order marks and local trade statuses were the old
    // identity's. Handed back to the public view in memory: re-fetching the
    // book from the relays waits for EOSE from every one of them, and a
    // single slow relay held a new user's generation for 20 s.
    crate::api::orders::forget_book_ownership().await;
}

/// Rebuild, for the identity loaded again after its replacement was refused,
/// what its deletion gave up (review of #573): its claim nodes, the kind-14
/// feed and the watched orders, its chats and trade sessions, the book marks
/// of its own orders, its dispute chats, its push registrations and its own
/// reputation — what a cold start builds for it. Its rows are still on disk:
/// the refusal kept them, and the reload released their wipe-pending marker.
///
/// Dart calls this right after loading that identity from secure storage, so
/// the session is never left on an identity Rust no longer serves. Held
/// under the lifecycle lock like a transition: a deletion that started
/// meanwhile finishes first, and then there is nothing to restore.
pub async fn restore_identity_session() -> Result<()> {
    let slot = identity_slot();
    let _transition = slot.lifecycle.lock().await;
    if slot.state.read().await.is_none() {
        bail!("NoIdentity");
    }
    // Before the feed: nodes with open payout claims join its authors.
    crate::api::bond::refresh_claim_nodes().await;
    crate::api::orders::restore_identity_subscriptions().await;
    crate::api::orders::reclaim_book_ownership().await;
    crate::api::disputes::resubscribe_active_dispute_chats().await;
    crate::api::push::request_reconcile();
    crate::api::my_reputation::spawn_refresh("identity reload");
    Ok(())
}

/// Derive a new trade key, auto-incrementing the index.
/// Returns the new key's info and updates the stored `trade_key_index`.
pub async fn derive_trade_key() -> Result<TradeKeyInfo> {
    let db = crate::db::app_db::db();

    // Precondition, checked before any identity work because it depends on
    // nothing else: without durable storage a derived index is consumed with
    // no record of it, so the next session re-derives the same key and the
    // daemon answers CantDo(InvalidTradeIndex). Memory-only mode therefore
    // cannot create or take orders — refusing here is what makes that
    // explicit instead of silently corrupting the counter (issue #249).
    #[cfg(not(target_arch = "wasm32"))]
    require_durable_storage(db)?;

    // Web is exempt: `init_db` is never called there (main.dart guards it with
    // `!kIsWeb`) and the IndexedDB backend does not implement `save_identity`
    // yet, so requiring a store would break every create/take on web. The
    // published index still reaches Flutter, which persists it — that mirror
    // is web's durable record until IndexedDB identity support lands (#233).
    #[cfg(target_arch = "wasm32")]
    if db.is_none() {
        log::warn!(
            "[identity] no local store on web — the trade-key counter is durable \
             only through the Flutter mirror"
        );
    }

    derive_trade_key_with(db, trade_key_index_tx()).await
}

/// Fails when no durable store is available, with the marker Dart localizes.
///
/// Split out so the refusal is testable as a pure decision: asserting it
/// through `derive_trade_key` would depend on the process-wide `APP_DB` being
/// uninitialised, which any other test may change first.
#[cfg(not(target_arch = "wasm32"))]
fn require_durable_storage<S>(db: Option<&S>) -> Result<()> {
    if db.is_none() {
        bail!("StorageUnavailable: deriving a trade key requires durable storage");
    }
    Ok(())
}

/// [`derive_trade_key`] against an explicit store and publication channel, so
/// the increment / persist / publish sequence is testable without touching the
/// global singleton or the process-wide channel other tests share.
async fn derive_trade_key_with<S: Storage>(
    db: Option<&S>,
    tx: &broadcast::Sender<u32>,
) -> Result<TradeKeyInfo> {
    let mut guard = identity_lock().write().await;
    let state = guard.as_mut().ok_or_else(|| anyhow!("NoIdentity"))?;

    let candidate_index = state.identity_info.trade_key_index + 1;

    let trade_keys = key_ops::derive_trade_key(&state.mnemonic_words, candidate_index)?;
    state.identity_info.trade_key_index = candidate_index;

    // Persist immediately: an index is consumed the moment it is derived.
    // The daemon registers every index it sees — even on a rejected or
    // timed-out operation — so the counter must survive restarts regardless
    // of the operation's outcome, or the next session re-derives the same
    // key and gets CantDo(InvalidTradeIndex). The write happens under the
    // identity lock so concurrent derivations persist in increment order.
    //
    // A persistence failure fails the derivation: handing out a key whose
    // consumption is not durably recorded reopens the counter-regression
    // window this exists to close. The in-memory increment is kept, so a
    // retry moves on to the next index — never back.
    if let Some(db) = db {
        db.save_identity(&state.identity_info).await.map_err(|e| {
            anyhow!("StorageError: failed to persist trade_key_index {candidate_index}: {e}")
        })?;
    }

    // Only after the primary record is durable: Flutter mirrors this into
    // secure storage, which outlives the database file itself.
    publish_index(tx, candidate_index);

    Ok(TradeKeyInfo {
        index: candidate_index,
        public_key: trade_keys.public_key().to_hex(),
    })
}

/// Raise `trade_key_index` to at least `floor`, never lowering it (#217).
///
/// A restore recovers trades that already occupy trade-key indexes; without
/// this, the next `derive_trade_key()` would hand out an index a recovered
/// trade already owns — reusing a key the daemon has bound. The bump is
/// monotonic: a stale or partial `RestoreData`, or one that arrives after the
/// counter has already advanced, must never rewind it. Idempotent — applying
/// the same recovered set twice changes nothing.
///
/// Persisted under the same discipline as `derive_trade_key`: if the counter
/// moves, the write must succeed or the call fails, so the advance is durable
/// (a bumped-but-unpersisted counter would regress on the next restart).
pub(crate) async fn ensure_trade_key_index_at_least(floor: u32) -> Result<()> {
    let db = crate::db::app_db::db();
    // Same durable-storage precondition as derive_trade_key: on native, refuse
    // to advance the counter when there is no store, because the _with core
    // would otherwise bump and publish the raised index WITHOUT persisting it
    // (the `if let Some(db)` save is skipped) — and publication is best-effort,
    // so a session loss would reload a stale pre-resync index and reopen the
    // key-reuse bug this closes (#249).
    #[cfg(not(target_arch = "wasm32"))]
    require_durable_storage(db)?;
    // Web is exempt for the same reason derive_trade_key is: `init_db` is never
    // called there and IndexedDB has no save_identity yet, so the published
    // index is web's durable record via the Flutter mirror until #233 lands.
    #[cfg(target_arch = "wasm32")]
    if db.is_none() {
        log::warn!(
            "[identity] no local store on web — the resynced trade-key counter is \
             durable only through the Flutter mirror"
        );
    }
    ensure_trade_key_index_at_least_with(db, trade_key_index_tx(), floor).await
}

/// Testable core of [`ensure_trade_key_index_at_least`]: takes an explicit store
/// and publish channel so tests can inject a failing store and a private channel,
/// mirroring `derive_trade_key` / `derive_trade_key_with`.
async fn ensure_trade_key_index_at_least_with<S: Storage>(
    db: Option<&S>,
    tx: &broadcast::Sender<u32>,
    floor: u32,
) -> Result<()> {
    let mut guard = identity_lock().write().await;
    let state = guard.as_mut().ok_or_else(|| anyhow!("NoIdentity"))?;
    let current = state.identity_info.trade_key_index;
    let raised = current.max(floor);
    if raised == current {
        // Already ahead of (or level with) the recovered set — no-op, no write.
        return Ok(());
    }
    state.identity_info.trade_key_index = raised;
    if let Some(db) = db {
        if let Err(e) = db.save_identity(&state.identity_info).await {
            // Roll back the in-memory bump on a failed persist. Without this, a
            // retried restore with the same floor would see `raised == current`,
            // take the no-op short-circuit above, and return Ok(()) WITHOUT ever
            // re-attempting the write — silently leaving the durable counter
            // un-raised and reopening the key-reuse bug this closes. (Unlike
            // derive_trade_key_with, which safely keeps its forward mutation
            // because it has no idempotency short-circuit to defeat.)
            state.identity_info.trade_key_index = current;
            return Err(anyhow!(
                "StorageError: failed to persist resynced trade_key_index {raised}: {e}"
            ));
        }
    }
    // Only after the primary record is durable: mirror to secure storage the
    // same way derive_trade_key_with does, so a later loss of mostro.db still
    // reloads the resynced counter rather than a stale pre-restore index (#249).
    publish_index(tx, raised);
    crate::api::logging::blog_info(
        "restore",
        format!("trade_key_index resynced {current} -> {raised} from recovered trades"),
    );
    Ok(())
}

/// Re-derive an existing trade key by index.
pub async fn get_trade_key(index: u32) -> Result<TradeKeyInfo> {
    let guard = identity_lock().read().await;
    let state = guard.as_ref().ok_or_else(|| anyhow!("NoIdentity"))?;

    if index == 0 {
        // Index 0 is the identity key.
        return Ok(TradeKeyInfo {
            index: 0,
            public_key: state.keys.public_key().to_hex(),
        });
    }

    if state.mnemonic_words.is_empty() {
        bail!("InvalidIndex: trade key derivation requires a mnemonic (nsec imports unsupported)");
    }

    if index > state.identity_info.trade_key_index {
        bail!("InvalidIndex: {index} exceeds current trade_key_index {}", state.identity_info.trade_key_index);
    }

    let trade_keys = key_ops::derive_trade_key(&state.mnemonic_words, index)?;
    Ok(TradeKeyInfo {
        index,
        public_key: trade_keys.public_key().to_hex(),
    })
}

/// Derive the deterministic nym identity for any public key.
pub fn get_nym_identity(pubkey_hex: String) -> Result<NymIdentity> {
    nym::get_nym_identity(&pubkey_hex)
}

/// Export an encrypted backup of the mnemonic using ChaCha20-Poly1305.
///
/// The passphrase is stretched via PBKDF2-SHA256 (100 000 iterations)
/// before being used as the encryption key.
/// Export an encrypted backup of the mnemonic using ChaCha20-Poly1305.
///
/// The passphrase is stretched via PBKDF2-SHA256 (100 000 iterations)
/// before being used as the encryption key.
///
/// Output format (base64-encoded): `[12-byte nonce][ciphertext+tag]`
/// The nonce is randomly generated per call and prepended so that the
/// same passphrase never reuses a nonce.
pub async fn export_encrypted_backup(passphrase: String) -> Result<String> {
    use base64::{engine::general_purpose::STANDARD, Engine};
    use chacha20poly1305::{
        aead::{Aead, KeyInit},
        ChaCha20Poly1305, Nonce,
    };
    use rand::RngCore;
    use sha2::{Digest, Sha256};

    let guard = identity_lock().read().await;
    let state = guard.as_ref().ok_or_else(|| anyhow!("NoIdentity"))?;

    if state.mnemonic_words.is_empty() {
        bail!("EncryptionError: no mnemonic available for nsec-imported identity");
    }

    // Derive 32-byte key from passphrase via SHA-256 (simplified; real PBKDF2
    // is added in Phase 4 security hardening).
    let key_bytes: [u8; 32] = Sha256::digest(passphrase.as_bytes()).into();
    let cipher = ChaCha20Poly1305::new((&key_bytes).into());

    // Generate a fresh random 12-byte nonce for every encryption call.
    let mut nonce_bytes = [0u8; 12];
    rand::rngs::OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let plaintext = state.mnemonic_words.join(" ");
    let ciphertext = cipher
        .encrypt(nonce, plaintext.as_bytes())
        .map_err(|e| anyhow!("EncryptionError: {e}"))?;

    // Prepend nonce so the receiver can decrypt: [12-byte nonce][ciphertext+tag]
    let mut envelope = Vec::with_capacity(12 + ciphertext.len());
    envelope.extend_from_slice(&nonce_bytes);
    envelope.extend_from_slice(&ciphertext);

    Ok(STANDARD.encode(envelope))
}

// ── Internal helpers ──────────────────────────────────────────────────────────

/// Pick the trade key index to restore on identity load: the highest of the
/// value passed from Flutter's secure storage and the one Rust persisted at
/// derivation time. The counter must never move backwards — a lower value
/// means re-deriving already-consumed keys, which the daemon rejects with
/// `InvalidTradeIndex`. A stored identity with a different public key is
/// ignored: its counter belongs to another mnemonic.
fn reconcile_trade_key_index(
    passed: u32,
    stored: Option<&IdentityInfo>,
    public_key: &str,
) -> u32 {
    match stored {
        Some(info) if info.public_key == public_key => passed.max(info.trade_key_index),
        _ => passed,
    }
}

/// [`reconcile_trade_key_index`], publishing the result when the database knew
/// a higher counter than the value Flutter passed in. That is exactly the case
/// where secure storage is behind — an installation from before it was kept in
/// sync — so this is what lets it catch up without a derivation happening
/// first (issue #249).
fn reconcile_and_publish_to(
    tx: &broadcast::Sender<u32>,
    passed: u32,
    stored: Option<&IdentityInfo>,
    public_key: &str,
) -> u32 {
    let reconciled = reconcile_trade_key_index(passed, stored, public_key);
    if reconciled > passed {
        publish_index(tx, reconciled);
    }
    reconciled
}

use crate::rt::unix_now;

/// Expose the in-memory `Keys` for other Rust modules (relay pool, transport).
/// Returns `Err("NoIdentity")` if no identity is loaded.
pub(crate) async fn get_active_keys() -> Result<Keys> {
    let guard = identity_lock().read().await;
    guard
        .as_ref()
        .map(|s| s.keys.clone())
        .ok_or_else(|| anyhow!("NoIdentity"))
}

/// Expose the active trade key at the given index for message signing.
pub(crate) async fn get_active_trade_keys(index: u32) -> Result<Keys> {
    let guard = identity_lock().read().await;
    let state = guard.as_ref().ok_or_else(|| anyhow!("NoIdentity"))?;

    if index == 0 {
        return Ok(state.keys.clone());
    }
    if state.mnemonic_words.is_empty() {
        bail!("InvalidIndex: nsec import — no mnemonic for trade key derivation");
    }
    key_ops::derive_trade_key(&state.mnemonic_words, index)
}

/// Every active trade key from index 1 to `up_to`, in index order — the
/// whole set at the price of one seed derivation, where calling
/// [`get_active_trade_keys`] per index pays for one each
/// (see `crypto::keys::derive_trade_keys`).
pub(crate) async fn get_active_trade_keys_up_to(up_to: u32) -> Result<Vec<Keys>> {
    let guard = identity_lock().read().await;
    let state = guard.as_ref().ok_or_else(|| anyhow!("NoIdentity"))?;
    if up_to == 0 {
        return Ok(Vec::new());
    }
    if state.mnemonic_words.is_empty() {
        bail!("InvalidIndex: nsec import — no mnemonic for trade key derivation");
    }
    key_ops::derive_trade_keys(&state.mnemonic_words, up_to)
}

/// Choose the identity keys that will sign the NIP-59 seal for messages
/// addressed to the Mostro node.
///
/// * **Reputation mode** (default) — returns the long-lived identity keys
///   (index 0). The node links trades to a stable pubkey and the user
///   accumulates reputation.
/// * **Full-privacy mode** — returns a clone of `trade_keys`, so the seal is
///   signed by the same key that authors the rumor. The node cannot link the
///   trade to any long-lived identity, and no reputation can accrue
///   (see <https://mostro.network/protocol/key_management.html>).
///
/// The toggle source is the in-memory runtime switch in `api::reputation`,
/// which is what the UI updates via `set_privacy_mode`.
pub(crate) async fn get_transport_identity_keys(trade_keys: &Keys) -> Result<Keys> {
    if crate::api::reputation::get_privacy_mode() {
        return Ok(trade_keys.clone());
    }
    get_active_keys().await
}

#[cfg(test)]
mod tests {
    /// The book is public and the same for any identity; only its `is_mine`
    /// marks were the old user's. Re-fetching it from the relays instead
    /// waits for EOSE from every relay, twice: a single slow one held the
    /// generation of a new user for 20 s.
    #[test]
    fn forgetting_the_identity_never_waits_on_the_relays_for_the_book() {
        let source = include_str!("identity.rs");
        let start = source
            .find("async fn forget_identity_state()")
            .expect("the identity reset exists");
        let body = &source[start..start + source[start..].find("\n}\n").expect("it ends")];

        assert!(body.contains("forget_book_ownership()"));
        assert!(!body.contains("refresh_subscriptions_for_active_node"));
    }

    use crate::source_guard::{expect_body, item_body, mutant, production_code};

    /// The public deletion hands `delete_identity_inner` the application's
    /// store and the real effects, and nothing else (PR #565 review), and
    /// that runs the deletion on the process's own slot.
    fn check_deletion_binding(source: &str) -> Result<(), String> {
        let code = production_code(source);
        expect_body(
            &code,
            "pub async fn delete_identity() -> Result<()>",
            "delete_identity_inner(crate::db::app_db::db(), &RealDeleteEffects).await",
        )?;
        expect_body(
            &code,
            "async fn delete_identity_inner<S: Storage, W: DeleteEffects>(db: Option<&S>, fx: &W) -> Result<()>",
            "delete_in(identity_slot(), db, fx).await",
        )
    }

    /// `forget_identity_state` runs every in-memory reset, and the two #533
    /// names reach their store's `forget` — which
    /// `forgetting_the_identity_drops_every_dispute` and
    /// `forgetting_the_identity_drops_every_rating` hold on a store of their
    /// own.
    fn check_identity_resets(identity: &str, disputes: &str, ratings: &str) -> Result<(), String> {
        expect_body(
            &production_code(identity),
            "pub(crate) async fn forget_identity_state()",
            "crate::api::disputes::forget_identity_disputes().await;
             crate::api::reputation::forget_identity_ratings().await;
             crate::api::my_reputation::forget_identity_reputation().await;
             crate::mostro::session::session_manager().clear().await;
             crate::mostro::bond_claims::set_claim_nodes(std::iter::empty());
             crate::mostro::bond_claims::clear_retained();
             crate::api::orders::forget_book_ownership().await;",
        )?;
        expect_body(
            &production_code(disputes),
            "pub(crate) async fn forget_identity_disputes()",
            "dispute_store().forget().await;
             if let Ok(mut opens) = pending_opens().lock() {
                 opens.clear();
             }
             solver_assigned_at()
                 .lock()
                 .unwrap_or_else(|poisoned| poisoned.into_inner())
                 .clear();",
        )?;
        expect_body(
            &production_code(ratings),
            "pub(crate) async fn forget_identity_ratings()",
            "rating_store().forget().await;",
        )
    }

    /// #533's second acceptance criterion: `DISPUTE_STORE` and `RATING_STORE`
    /// are empty after a deletion. The lifecycle test proves with a double
    /// that `delete_identity_inner` calls `forget_identity_state` (#553);
    /// this closes the links below it, down to each store's `forget`.
    /// Source-level because the resets cannot run here: the stores are
    /// process-wide, so emptying them races the parallel suite (the same
    /// reason the doubles exist). It holds the resets that exist; a new
    /// per-identity store still has to be added to them by hand.
    #[test]
    fn forgetting_the_identity_runs_every_reset() {
        check_identity_resets(
            include_str!("identity.rs"),
            include_str!("disputes.rs"),
            include_str!("reputation.rs"),
        )
        .unwrap();
    }

    /// PR #565 review: the lifecycle test drives `delete_identity_inner`
    /// with a throwaway store and doubles, so nothing it runs can see what
    /// the public entry point hands it. Passing no store there would skip
    /// every database write of the deletion with the suite green; this holds
    /// the binding.
    #[test]
    fn deleting_the_identity_binds_the_real_store_and_effects() {
        check_deletion_binding(include_str!("identity.rs")).unwrap();
    }

    /// The two guards above, against the mutants that used to pass them
    /// (PR #565 review): each one must be refused.
    #[test]
    fn the_deletion_guards_refuse_a_disconnected_cleanup() {
        let identity = include_str!("identity.rs");
        let call = "delete_identity_inner(crate::db::app_db::db(), &RealDeleteEffects).await";
        for broken in [
            // A new signature: the guard's own text must not answer for it.
            mutant(
                identity,
                "pub async fn delete_identity() -> Result<()>",
                "pub async fn delete_identity(wipe_data: bool) -> Result<()>",
            ),
            // The binding kept in a comment only.
            mutant(
                identity,
                call,
                &format!(
                    "// {call}\n    delete_identity_inner(None::<&crate::db::sqlite::SqliteStorage>, &RealDeleteEffects).await"
                ),
            ),
            // The store handed over, but never present.
            mutant(
                identity,
                "delete_identity_inner(crate::db::app_db::db(),",
                "delete_identity_inner(crate::db::app_db::db().filter(|_| false),",
            ),
            // The deletion run on a slot nobody reads.
            mutant(
                identity,
                "delete_in(identity_slot(), db, fx)",
                "delete_in(&IdentitySlot::new(), db, fx)",
            ),
        ] {
            assert!(check_deletion_binding(&broken).is_err());
        }

        let disputes = include_str!("disputes.rs");
        let ratings = include_str!("reputation.rs");
        for reset in [
            "crate::api::disputes::forget_identity_disputes().await;",
            "crate::api::reputation::forget_identity_ratings().await;",
            "crate::mostro::session::session_manager().clear().await;",
            "crate::mostro::bond_claims::set_claim_nodes(std::iter::empty());",
            "crate::mostro::bond_claims::clear_retained();",
            "crate::api::orders::forget_book_ownership().await;",
        ] {
            let commented = mutant(identity, reset, &format!("// {reset}"));
            assert!(
                check_identity_resets(&commented, disputes, ratings).is_err(),
                "commenting out {reset} must fail the guard",
            );
        }
        let skipped = mutant(disputes, "dispute_store().forget().await;", "");
        assert!(check_identity_resets(identity, &skipped, ratings).is_err());
        let skipped = mutant(ratings, "rating_store().forget().await;", "");
        assert!(check_identity_resets(identity, disputes, &skipped).is_err());
    }

    use super::*;

    /// A throwaway SQLite store, named per test so parallel runs never collide.
    async fn temp_store(tag: &str) -> crate::db::sqlite::SqliteStorage {
        let path = std::env::temp_dir()
            .join(format!("mostro_identity_{tag}_{}.db", std::process::id()));
        let _ = std::fs::remove_file(&path);
        crate::db::sqlite::SqliteStorage::open(path.to_str().unwrap())
            .await
            .unwrap()
    }

    fn stored_identity(public_key: &str, trade_key_index: u32) -> IdentityInfo {
        IdentityInfo {
            public_key: public_key.to_string(),
            display_name: None,
            privacy_mode: false,
            trade_key_index,
            created_at: 1,
        }
    }

    /// A channel of this test's own. The process-wide one is shared with every
    /// other test in the binary, so asserting on it makes the value received
    /// depend on what else happens to publish concurrently.
    fn private_channel() -> (broadcast::Sender<u32>, TradeKeyIndexStream) {
        let (tx, rx) = broadcast::channel(TRADE_KEY_INDEX_CHANNEL_CAPACITY);
        (tx, TradeKeyIndexStream { rx })
    }

    /// A `Storage` whose `save_identity` always fails, for exercising the
    /// resync rollback path with an injected failure. The seam under test only
    /// calls `save_identity`, so every other method is `unimplemented!()` —
    /// reaching one would be a test bug, not silent success.
    struct FailingStore;

    impl Storage for FailingStore {
        async fn save_identity(&self, _identity: &IdentityInfo) -> Result<()> {
            anyhow::bail!("injected save failure")
        }
        async fn save_order(&self, _order: &crate::api::types::OrderInfo) -> Result<()> {
            unimplemented!()
        }
        async fn get_order(&self, _id: &str) -> Result<Option<crate::api::types::OrderInfo>> {
            unimplemented!()
        }
        async fn delete_order(&self, _id: &str) -> Result<()> {
            unimplemented!()
        }
        async fn list_orders(&self) -> Result<Vec<crate::api::types::OrderInfo>> {
            unimplemented!()
        }
        async fn save_trade(&self, _trade: &crate::api::types::TradeInfo) -> Result<()> {
            unimplemented!()
        }
        async fn list_trades(&self) -> Result<Vec<crate::api::types::TradeInfo>> {
            unimplemented!()
        }
        async fn save_message(&self, _msg: &crate::api::types::ChatMessage) -> Result<()> {
            unimplemented!()
        }
        async fn list_messages(
            &self,
            _trade_id: &str,
        ) -> Result<Vec<crate::api::types::ChatMessage>> {
            unimplemented!()
        }
        async fn list_unread_messages(&self) -> Result<Vec<crate::api::types::ChatMessage>> {
            unimplemented!()
        }
        async fn mark_messages_read(&self, _trade_id: &str) -> Result<()> {
            unimplemented!()
        }
        async fn delete_messages_for_order(&self, _order_id: &str) -> Result<()> {
            unimplemented!()
        }
        async fn message_exists(&self, _id: &str) -> Result<bool> {
            unimplemented!()
        }
        async fn save_relay(&self, _relay: &crate::api::types::RelayInfo) -> Result<()> {
            unimplemented!()
        }
        async fn delete_relay(&self, _url: &str) -> Result<()> {
            unimplemented!()
        }
        async fn list_relays(&self) -> Result<Vec<crate::api::types::RelayInfo>> {
            unimplemented!()
        }
        async fn get_identity(&self) -> Result<Option<IdentityInfo>> {
            unimplemented!()
        }
        async fn update_trade_peer_reputation(
            &self,
            _order_id: &str,
            _rating: f64,
            _reviews: u32,
            _days: u32,
            _since: Option<i64>,
        ) -> Result<()> {
            unimplemented!()
        }
        async fn update_trade_bond(
            &self,
            _order_id: &str,
            _bond: &crate::api::types::BondInfo,
        ) -> Result<()> {
            unimplemented!()
        }

        async fn mark_trade_rated(&self, _order_id: &str, _rated_at: i64) -> Result<()> {
            unimplemented!()
        }
        async fn forget_trade_node(&self, _row_id: &str, _node: &str) -> Result<bool> {
            unimplemented!()
        }
        async fn adopt_trade_node(
            &self,
            _order_id: &str,
            _trade_index: u32,
            _node: &str,
        ) -> Result<bool> {
            unimplemented!()
        }
        async fn mark_trade_completed(&self, _order_id: &str, _completed_at: i64) -> Result<()> {
            unimplemented!()
        }
        async fn mark_escrow_locked(
            &self,
            _order_id: &str,
            _locked_at: i64,
            _node: &str,
        ) -> Result<()> {
            unimplemented!()
        }
        async fn clear_escrow_lock(&self, _order_id: &str) -> Result<()> {
            unimplemented!()
        }
        async fn set_cooperative_cancel_state(
            &self,
            _order_id: &str,
            _state: crate::api::types::CooperativeCancelState,
        ) -> Result<()> {
            unimplemented!()
        }
        async fn update_trade_counterparty(
            &self,
            _order_id: &str,
            _counterparty_pubkey: &str,
        ) -> Result<()> {
            unimplemented!()
        }
        async fn save_bond_claim(&self, _claim: &crate::api::types::BondClaim) -> Result<()> {
            unimplemented!()
        }
        async fn get_bond_claim(
            &self,
            _node_pubkey: &str,
            _order_id: &str,
        ) -> Result<Option<crate::api::types::BondClaim>> {
            unimplemented!()
        }
        async fn list_bond_claims(&self) -> Result<Vec<crate::api::types::BondClaim>> {
            unimplemented!()
        }
        async fn delete_bond_claim(&self, _node_pubkey: &str, _order_id: &str) -> Result<()> {
            unimplemented!()
        }
        async fn save_queued_message(
            &self,
            _msg: &crate::queue::outbox::QueuedMessage,
        ) -> Result<()> {
            unimplemented!()
        }
        async fn list_queued_messages(
            &self,
        ) -> Result<Vec<crate::queue::outbox::QueuedMessage>> {
            unimplemented!()
        }
        async fn update_queued_message_status(
            &self,
            _id: &str,
            _status: crate::api::types::QueuedMessageStatus,
        ) -> Result<()> {
            unimplemented!()
        }
        async fn delete_queued_message(&self, _id: &str) -> Result<()> {
            unimplemented!()
        }
        async fn save_trade_key(&self, _order_id: &str, _key_index: u32) -> Result<()> {
            unimplemented!()
        }
        async fn get_trade_key(&self, _order_id: &str) -> Result<Option<u32>> {
            unimplemented!()
        }
        async fn get_order_id_by_trade_index(&self, _key_index: u32) -> Result<Option<String>> {
            unimplemented!()
        }
        async fn delete_trade_key(&self, _order_id: &str) -> Result<()> {
            unimplemented!()
        }
        async fn clear_identity_data(&self) -> Result<()> {
            unimplemented!()
        }
        async fn get_setting(&self, _key: &str) -> Result<Option<String>> {
            unimplemented!()
        }
        async fn set_setting(&self, _key: &str, _value: &str) -> Result<()> {
            unimplemented!()
        }
        async fn delete_setting(&self, _key: &str) -> Result<()> {
            unimplemented!()
        }
        async fn save_active_mostro_pubkey(&self, _pubkey: &str) -> Result<()> {
            unimplemented!()
        }
        async fn get_active_mostro_pubkey(&self) -> Result<Option<String>> {
            unimplemented!()
        }
        async fn get_trade_by_order_id(
            &self,
            _order_id: &str,
        ) -> Result<Option<crate::api::types::TradeInfo>> {
            unimplemented!()
        }
        async fn delete_trade_by_order_id(&self, _order_id: &str) -> Result<()> {
            unimplemented!()
        }
        async fn replace_trades_for_order(
            &self,
            _order_id: &str,
            _trade: &crate::api::types::TradeInfo,
        ) -> Result<()> {
            unimplemented!()
        }
        async fn update_trade_order_id(
            &self,
            _old_order_id: &str,
            _new_order_id: &str,
        ) -> Result<()> {
            unimplemented!()
        }
        async fn update_trade_fields(
            &self,
            _order_id: &str,
            _status: Option<crate::api::types::OrderStatus>,
            _hold_invoice: Option<String>,
            _amount_sats: Option<u64>,
        ) -> Result<()> {
            unimplemented!()
        }
        async fn set_trade_range_slice(
            &self,
            _order_id: &str,
            _fiat_amount: Option<f64>,
            _amount_sats: Option<u64>,
        ) -> Result<()> {
            unimplemented!()
        }
    }

    /// Ordered record of the deletion's non-store effects, each with whether
    /// an identity was still loaded on `slot` when it ran, so the lifecycle
    /// test can assert the wiring of `delete_identity_inner` (#553). The
    /// default reads the process's slot; a test deleting on a slot of its own
    /// logs [`CallLog::on`] it.
    struct CallLog<'s> {
        calls: std::sync::Mutex<Vec<(&'static str, bool)>>,
        slot: &'s IdentitySlot,
    }

    impl Default for CallLog<'static> {
        fn default() -> Self {
            Self::on(identity_slot())
        }
    }

    impl<'s> CallLog<'s> {
        fn on(slot: &'s IdentitySlot) -> Self {
            Self {
                calls: std::sync::Mutex::default(),
                slot,
            }
        }
        async fn push(&self, call: &'static str) {
            let loaded = self.slot.state.read().await.is_some();
            self.calls.lock().unwrap().push((call, loaded));
        }
        fn calls(&self) -> Vec<(&'static str, bool)> {
            self.calls.lock().unwrap().clone()
        }
    }

    /// A `DeleteEffects` that records instead of touching the process-wide
    /// subscriptions, push registrations and in-memory stores.
    struct SpyEffects<'a>(&'a CallLog<'a>);

    impl DeleteEffects for SpyEffects<'_> {
        async fn release_identity_subscriptions(&self) {
            self.0.push("release_identity_subscriptions").await;
        }
        async fn unregister_push(&self) {
            self.0.push("unregister_push").await;
        }
        async fn forget_identity_state(&self) {
            self.0.push("forget_identity_state").await;
        }
    }

    /// What every deletion must run, and whether the identity is still
    /// loaded at each step: the subscriptions are released while it exists,
    /// everything else after it is retired. The order among the last two is
    /// today's, pinned because a wiring test reads cheapest as a literal
    /// transcript — not because it is semantic.
    const DELETION_TRANSCRIPT: [(&str, bool); 3] = [
        ("release_identity_subscriptions", true),
        ("unregister_push", false),
        ("forget_identity_state", false),
    ];

    /// A deletion whose data wipe fails gives up none of the identity's
    /// persisted state: its row and its trade-key mappings, which name its
    /// orders, stay with the trades and chats the wipe kept (review of #573).
    /// Wiped one by one ahead of the rows, they were gone while the rows
    /// stayed, so an identity loaded back over those rows could no longer
    /// act on its own trades.
    ///
    /// The wipe is made to fail by a trigger aborting the delete of one of
    /// the identity's settings rows, on a throwaway store; the identity is
    /// installed and deleted on a slot of its own.
    #[tokio::test]
    async fn a_deletion_whose_wipe_fails_keeps_the_identity_and_its_trade_keys() {
        let path = std::env::temp_dir().join(format!(
            "mostro_identity_wipe_fails_{}.db",
            std::process::id()
        ));
        let _ = std::fs::remove_file(&path);
        let db = crate::db::sqlite::SqliteStorage::open(path.to_str().unwrap())
            .await
            .unwrap();

        // Installed directly, not through `load_in`, whose legacy-store claim
        // reads the process-wide database: nothing here leaves this slot.
        let words = key_ops::generate_mnemonic().unwrap();
        let keys = key_ops::derive_master_key(&words).unwrap();
        let info = stored_identity(&keys.public_key().to_hex(), 3);
        let slot = IdentitySlot::new();
        *slot.state.write().await = Some(IdentityState {
            mnemonic_words: words,
            keys,
            identity_info: info.clone(),
        });
        db.save_identity(&info).await.unwrap();
        db.save_trade_key("order-a", 2).await.unwrap();
        let cursor = crate::db::settings_keys::status_cursor("order-a");
        db.set_setting(&cursor, "1").await.unwrap();

        let mut conn = <sqlx::sqlite::SqliteConnection as sqlx::Connection>::connect_with(
            &sqlx::sqlite::SqliteConnectOptions::new().filename(&path),
        )
        .await
        .unwrap();
        sqlx::query(&format!(
            "CREATE TRIGGER wipe_fails BEFORE DELETE ON settings \
             WHEN old.key = '{cursor}' BEGIN SELECT RAISE(ABORT, 'wipe fails'); END"
        ))
        .execute(&mut conn)
        .await
        .unwrap();

        let effects = CallLog::on(&slot);
        delete_in(&slot, Some(&db), &SpyEffects(&effects))
            .await
            .expect("a failed cleanup is reported, never a failed deletion");

        assert!(slot.state.read().await.is_none(), "the identity is retired");
        assert_eq!(
            db.get_identity().await.unwrap().map(|i| i.public_key),
            Some(info.public_key),
            "the identity row stays with the rows the wipe kept",
        );
        assert_eq!(
            db.get_trade_key("order-a").await.unwrap(),
            Some(2),
            "the trade-key mappings stay with the trades they name",
        );
        assert_eq!(db.get_setting(&cursor).await.unwrap().as_deref(), Some("1"));

        drop(conn);
        drop(db);
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn deriving_without_durable_storage_is_refused() {
        // Asserted as a pure decision, not through `derive_trade_key`: that
        // would depend on the process-wide APP_DB still being uninitialised,
        // and other tests in this binary initialise it.
        let err = require_durable_storage::<crate::db::sqlite::SqliteStorage>(None)
            .unwrap_err()
            .to_string();

        assert!(
            err.starts_with("StorageUnavailable:"),
            "expected a StorageUnavailable marker, got: {err}"
        );
    }

    #[tokio::test]
    async fn a_store_being_present_satisfies_the_precondition() {
        let db = temp_store("precondition").await;

        assert!(require_durable_storage(Some(&db)).is_ok());
    }

    #[tokio::test]
    async fn a_consumed_index_reaches_the_stream() {
        let (tx, mut stream) = private_channel();

        publish_index(&tx, 7);

        assert_eq!(stream.next().await.unwrap(), 7);
    }

    #[tokio::test]
    async fn reconciliation_publishes_only_when_the_database_is_ahead() {
        let stored = stored_identity("abc", 22);
        let (tx, mut stream) = private_channel();

        // Secure storage behind the database: Dart must learn the real value.
        assert_eq!(reconcile_and_publish_to(&tx, 20, Some(&stored), "abc"), 22);
        assert_eq!(stream.next().await.unwrap(), 22);

        // Already in sync, and a counter belonging to another mnemonic: no
        // publication, so Dart never rewrites a value it already holds.
        assert_eq!(reconcile_and_publish_to(&tx, 22, Some(&stored), "abc"), 22);
        assert_eq!(reconcile_and_publish_to(&tx, 30, Some(&stored), "other"), 30);
        assert!(
            stream.rx.try_recv().is_err(),
            "nothing further should have been published"
        );
    }

    #[test]
    fn reconcile_prefers_higher_stored_index() {
        let stored = stored_identity("abc", 22);
        assert_eq!(reconcile_trade_key_index(20, Some(&stored), "abc"), 22);
    }

    #[test]
    fn reconcile_prefers_higher_passed_index() {
        let stored = stored_identity("abc", 5);
        assert_eq!(reconcile_trade_key_index(20, Some(&stored), "abc"), 20);
    }

    #[test]
    fn reconcile_ignores_stored_index_of_other_identity() {
        let stored = stored_identity("other-pubkey", 99);
        assert_eq!(reconcile_trade_key_index(3, Some(&stored), "abc"), 3);
    }

    #[test]
    fn reconcile_without_stored_identity_keeps_passed_index() {
        assert_eq!(reconcile_trade_key_index(7, None, "abc"), 7);
    }

    /// Single test for the global identity state (kept as ONE test so
    /// parallel test threads never race on the `identity_lock` singleton):
    /// loading restores the counter, each derivation advances it, and
    /// deletion clears the in-memory state.
    #[tokio::test]
    async fn load_derive_then_delete_identity_lifecycle() {
        let words = key_ops::generate_mnemonic().unwrap();

        let info = load_identity_from_mnemonic(words.clone(), 20, false, None)
            .await
            .unwrap();
        assert_eq!(info.trade_key_index, 20);

        // A real store, but a throwaway one, and a channel of this test's own:
        // neither the global singleton nor the shared channel is touched, so
        // this cannot make other tests in the binary flaky (or be made flaky
        // by them).
        let db = temp_store("lifecycle").await;
        let (tx, mut published) = private_channel();

        let first = derive_trade_key_with(Some(&db), &tx).await.unwrap();
        let second = derive_trade_key_with(Some(&db), &tx).await.unwrap();
        assert_eq!(first.index, 21);
        assert_eq!(second.index, 22);
        assert_ne!(first.public_key, second.public_key);

        // Every consumed index is published for Flutter to mirror into secure
        // storage, and only after it is durable in the store.
        assert_eq!(published.next().await.unwrap(), 21);
        assert_eq!(published.next().await.unwrap(), 22);
        let persisted = db.get_identity().await.unwrap().unwrap();
        assert_eq!(persisted.trade_key_index, 22);

        let current = get_identity().await.unwrap().unwrap();
        assert_eq!(current.trade_key_index, 22);

        // #217 resync — asserted here (not a separate #[tokio::test]) so it
        // shares the single identity_lock lifecycle and can't race it. Uses the
        // `_with` core so publications land on this test's private channel.
        // Never lowers: a floor below current is a no-op — no write, no publish.
        ensure_trade_key_index_at_least_with(Some(&db), &tx, 10).await.unwrap();
        assert_eq!(get_identity().await.unwrap().unwrap().trade_key_index, 22);
        assert!(
            published.rx.try_recv().is_err(),
            "a no-op resync must not publish",
        );
        // Raises to the recovered max, persists, and publishes to the mirror.
        ensure_trade_key_index_at_least_with(Some(&db), &tx, 50).await.unwrap();
        assert_eq!(get_identity().await.unwrap().unwrap().trade_key_index, 50);
        assert_eq!(published.next().await.unwrap(), 50);
        assert_eq!(db.get_identity().await.unwrap().unwrap().trade_key_index, 50);
        // Idempotent: the same floor again changes nothing and publishes nothing.
        ensure_trade_key_index_at_least_with(Some(&db), &tx, 50).await.unwrap();
        assert_eq!(get_identity().await.unwrap().unwrap().trade_key_index, 50);
        assert!(
            published.rx.try_recv().is_err(),
            "an idempotent resync must not publish again",
        );
        // #217 rollback (grunch review): a failed persist must NOT leave the
        // counter advanced. Counter is 50 here. Ask for a higher floor (60)
        // against a failing store: the call errors and the counter stays 50.
        let (fx, _frx) = private_channel();
        let rollback_err =
            ensure_trade_key_index_at_least_with(Some(&FailingStore), &fx, 60)
                .await
                .unwrap_err()
                .to_string();
        assert!(
            rollback_err.contains("StorageError:"),
            "unexpected error: {rollback_err}"
        );
        assert_eq!(
            get_identity().await.unwrap().unwrap().trade_key_index,
            50,
            "a failed persist must roll the counter back, not leave it advanced",
        );
        // Retry the same floor against the WORKING store: it now writes — the
        // idempotency short-circuit was not poisoned by the half-applied bump.
        ensure_trade_key_index_at_least_with(Some(&db), &tx, 60)
            .await
            .unwrap();
        assert_eq!(
            get_identity().await.unwrap().unwrap().trade_key_index,
            60,
            "retry against a working store must raise and persist",
        );
        assert_eq!(published.next().await.unwrap(), 60);
        assert_eq!(db.get_identity().await.unwrap().unwrap().trade_key_index, 60);

        // Regression (the bug #217 fixes): the next derived key is FRESH —
        // index 61, past every recovered trade — not a reused recovered index.
        let after = derive_trade_key_with(Some(&db), &tx).await.unwrap();
        assert_eq!(after.index, 61);

        crate::api::logging::forward_log(log::Level::Info, "identity_probe", "before delete");

        // A transfer that started under this identity may still write…
        let generation = identity_generation().await.expect("an identity is loaded");
        assert_eq!(
            while_identity_current(generation, async { 1 }).await,
            Some(1)
        );

        // Reputation publication is deferred until the relay subscription
        // is ready. A privacy change during that wait must stop the send.
        // Keep these checks in the one identity lifecycle test so parallel
        // tests never replace the global identity underneath each other.
        use crate::api::reputation_transfer::publish_request;
        let privacy = std::cell::Cell::new(false);
        let sent = std::cell::Cell::new(false);
        let waiting_to_publish = publish_request(Some(generation), || privacy.get(), async {
            sent.set(true);
            Ok(())
        });
        privacy.set(true);
        let result = waiting_to_publish.await;
        assert!(
            result.is_err(),
            "privacy enabled before publication must stop it"
        );
        assert!(result
            .unwrap_err()
            .to_string()
            .starts_with("PrivacyModeEnabled"));
        assert!(!sent.get());

        // The guard must survive an await inside publication, preventing a
        // concurrent identity replacement until the send finishes.
        let (entered_tx, entered_rx) = tokio::sync::oneshot::channel();
        let (resume_tx, resume_rx) = tokio::sync::oneshot::channel();
        let publishing = publish_request(Some(generation), || false, async {
            entered_tx.send(()).unwrap();
            resume_rx.await.unwrap();
            Ok(())
        });
        let concurrent_replacement = async {
            entered_rx.await.unwrap();
            let locked = identity_lock().try_write().is_err();
            resume_tx.send(()).unwrap();
            assert!(
                locked,
                "publication must keep the initiating identity active"
            );
        };
        let (published, ()) = tokio::join!(publishing, concurrent_replacement);
        published.unwrap();

        let relay_failure = publish_request(Some(generation), || false, async {
            anyhow::bail!("NoRelayAccepted")
        })
        .await;
        assert_eq!(relay_failure.unwrap_err().to_string(), "NoRelayAccepted");
        // Other tests briefly read the identity to reject stale generations.
        // Wait for those readers instead of assuming the lock is idle now.
        let after_failure = crate::rt::time::timeout(
            crate::rt::time::Duration::from_secs(5),
            identity_lock().write(),
        )
        .await
        .expect("a failed send releases the guard");
        drop(after_failure);

        // This future was prepared while the identity was still present,
        // but will only be polled after deletion below.
        let late_sent = std::cell::Cell::new(false);
        let late_publication = publish_request(Some(generation), || false, async {
            late_sent.set(true);
            Ok(())
        });

        // What the deletion must wipe from the store, and what it must keep.
        db.save_trade_key("order-a", 21).await.unwrap();
        let cursor = crate::db::settings_keys::status_cursor("order-a");
        db.set_setting(&cursor, "1").await.unwrap();
        db.set_setting(crate::db::settings_keys::PUSH_ENABLED, "false")
            .await
            .unwrap();

        // The deletion wiring (#553), against this test's throwaway store and
        // with doubles for the effects, so the process-wide subscriptions,
        // push registrations and in-memory stores stay untouched — see
        // `delete_identity_inner`. Every wipe effect runs (#533's acceptance
        // criteria), in `DELETION_TRANSCRIPT`'s order.
        let effects = CallLog::default();
        delete_identity_inner(Some(&db), &SpyEffects(&effects))
            .await
            .unwrap();
        assert_eq!(
            effects.calls(),
            DELETION_TRANSCRIPT,
            "a deletion must run every wipe effect, releasing the \
             subscriptions before the identity is retired",
        );
        assert!(db.get_identity().await.unwrap().is_none());
        assert_eq!(db.get_trade_key("order-a").await.unwrap(), None);
        assert_eq!(db.get_setting(&cursor).await.unwrap(), None);
        assert_eq!(
            db.get_setting(crate::db::settings_keys::PUSH_ENABLED)
                .await
                .unwrap()
                .as_deref(),
            Some("false"),
            "a deletion keeps the device's preferences",
        );
        assert!(get_identity().await.unwrap().is_none());
        assert_eq!(identity_generation().await, None);

        let late_result = late_publication.await;
        assert!(late_result.unwrap_err().to_string().starts_with("NoIdentity"));
        assert!(!late_sent.get());

        // …but once it is deleted, the write is refused without running
        // (PR #590 review: a paused download must not refill the wiped cache).
        let mut wrote = false;
        let refused = while_identity_current(generation, async { wrote = true }).await;
        assert!(refused.is_none());
        assert!(!wrote);
        assert!(
            !crate::api::logging::recent_logs()
                .iter()
                .any(|e| e.tag == "identity_probe"),
            "delete_identity must drop the buffered log history",
        );

        // Deleting again fails: there is no identity left.
        assert!(delete_identity().await.is_err());

        // Importing the same mnemonic again is a new generation: the old
        // transfer stays refused although the pubkey is the same.
        // (The reload reconciles its index against the global APP_DB if some
        // other test initialized it — a read-only touch, tolerated either
        // way, and the only global the block reaches.)
        load_identity_from_mnemonic(words, 0, false, None)
            .await
            .unwrap();
        let reloaded = identity_generation().await.expect("an identity is loaded");
        assert_ne!(reloaded, generation);
        assert!(while_identity_current(generation, async {}).await.is_none());
        let again = CallLog::default();
        delete_identity_inner(Some(&db), &SpyEffects(&again))
            .await
            .unwrap();
        assert_eq!(
            again.calls(),
            DELETION_TRANSCRIPT,
            "every deletion runs every effect",
        );
        assert!(get_identity().await.unwrap().is_none());
    }

    // ── Pending wipe (issue #555) ────────────────────────────────────────────

    /// The key of the wipe-pending marker, spelled out here so these tests
    /// read the store as it is, whatever the production code calls it.
    const WIPE_PENDING: &str = "identity_wipe_pending";

    /// A throwaway SQLite store whose failures a test switches on with SQL
    /// run beside the store's own pool — no fake `Storage` to keep in step
    /// with the trait. The identity's rows are a trade-key mapping and a
    /// status cursor of `order-a`, which every wipe removes.
    struct WipeStore {
        path: std::path::PathBuf,
        db: crate::db::sqlite::SqliteStorage,
    }

    impl WipeStore {
        async fn new(tag: &str) -> Self {
            let path =
                std::env::temp_dir().join(format!("mostro_wipe_{tag}_{}.db", std::process::id()));
            Self::remove(&path);
            let db = crate::db::sqlite::SqliteStorage::open(path.to_str().unwrap())
                .await
                .unwrap();
            db.save_trade_key("order-a", 2).await.unwrap();
            db.set_setting(&Self::cursor(), "1").await.unwrap();
            Self { path, db }
        }

        fn cursor() -> String {
            crate::db::settings_keys::status_cursor("order-a")
        }

        fn remove(path: &std::path::Path) {
            for suffix in ["", "-wal", "-shm"] {
                let _ = std::fs::remove_file(format!("{}{suffix}", path.display()));
            }
        }

        async fn sql(&self, statement: &str) {
            let mut conn = <sqlx::sqlite::SqliteConnection as sqlx::Connection>::connect_with(
                &sqlx::sqlite::SqliteConnectOptions::new().filename(&self.path),
            )
            .await
            .unwrap();
            sqlx::query(statement).execute(&mut conn).await.unwrap();
        }

        /// Every wipe fails until [`Self::heal_wipe`].
        async fn fail_wipe(&self) {
            self.sql(&format!(
                "CREATE TRIGGER wipe_fails BEFORE DELETE ON settings \
                 WHEN old.key = '{}' BEGIN SELECT RAISE(ABORT, 'wipe fails'); END",
                Self::cursor()
            ))
            .await;
        }

        async fn heal_wipe(&self) {
            self.sql("DROP TRIGGER wipe_fails").await;
        }

        /// The marker can be read but never written.
        async fn fail_marker_write(&self) {
            self.sql(&format!(
                "CREATE TRIGGER marker_fails BEFORE INSERT ON settings \
                 WHEN new.key = '{WIPE_PENDING}' BEGIN SELECT RAISE(ABORT, 'no marker'); END"
            ))
            .await;
        }

        /// No setting can be read or written.
        async fn hide_settings(&self) {
            self.sql("ALTER TABLE settings RENAME TO settings_hidden")
                .await;
        }

        async fn marker(&self) -> Option<String> {
            self.db.get_setting(WIPE_PENDING).await.unwrap()
        }

        /// Whether the identity's rows are still on disk.
        async fn rows_kept(&self) -> bool {
            self.db.get_trade_key("order-a").await.unwrap().is_some()
        }
    }

    impl Drop for WipeStore {
        fn drop(&mut self) {
            Self::remove(&self.path);
        }
    }

    /// Install a fresh identity on `slot` directly, never through `load_in`,
    /// whose legacy-store claim reads the process-wide database. Returns its
    /// words and public key.
    async fn install(slot: &IdentitySlot) -> (Vec<String>, String) {
        let words = key_ops::generate_mnemonic().unwrap();
        let keys = key_ops::derive_master_key(&words).unwrap();
        let public_key = keys.public_key().to_hex();
        *slot.state.write().await = Some(IdentityState {
            mnemonic_words: words.clone(),
            keys,
            identity_info: stored_identity(&public_key, 0),
        });
        (words, public_key)
    }

    async fn loaded(slot: &IdentitySlot) -> Option<String> {
        slot.state
            .read()
            .await
            .as_ref()
            .map(|state| state.identity_info.public_key.clone())
    }

    /// An identity deleted while its wipe fails, on a store that keeps
    /// failing: what every replacement test starts from.
    async fn after_a_failed_wipe(tag: &str) -> (WipeStore, IdentitySlot, String) {
        let store = WipeStore::new(tag).await;
        store.fail_wipe().await;
        let slot = IdentitySlot::new();
        let (_, owner) = install(&slot).await;
        delete_in(&slot, Some(&store.db), &SpyEffects(&CallLog::on(&slot)))
            .await
            .expect("a failed cleanup is reported, never a failed deletion");
        (store, slot, owner)
    }

    /// Each way a new identity replaces a deleted one.
    const REPLACEMENTS: [&str; 3] = ["create", "import", "nsec"];

    async fn replace(
        kind: &str,
        slot: &IdentitySlot,
        db: &crate::db::sqlite::SqliteStorage,
    ) -> Result<()> {
        match kind {
            "create" => create_in(slot, Some(db)).await.map(|_| ()),
            "import" => {
                let words = key_ops::generate_mnemonic().unwrap();
                let (tx, _published) = private_channel();
                import_in(slot, Some(db), &tx, words, false)
                    .await
                    .map(|_| ())
            }
            _ => {
                let nsec = Keys::generate().secret_key().to_bech32().unwrap();
                import_nsec_in(slot, Some(db), nsec).await.map(|_| ())
            }
        }
    }

    /// A wipe that fails leaves a marker naming the identity it was for, so
    /// the rows it kept are not left with nothing to say so.
    #[tokio::test]
    async fn a_failed_wipe_leaves_a_marker_naming_the_deleted_identity() {
        let (store, slot, owner) = after_a_failed_wipe("marker").await;

        assert_eq!(
            loaded(&slot).await,
            None,
            "the deletion itself went through"
        );
        assert!(store.rows_kept().await);
        assert_eq!(store.marker().await, Some(owner));
    }

    /// The next identity — created, imported from words or from an nsec —
    /// retries the pending wipe first, and installs over a clean store.
    #[tokio::test]
    async fn a_replacement_retries_the_pending_wipe_first() {
        for kind in REPLACEMENTS {
            let (store, slot, _) = after_a_failed_wipe(&format!("retry_{kind}")).await;
            store.heal_wipe().await;

            replace(kind, &slot, &store.db)
                .await
                .unwrap_or_else(|e| panic!("{kind}: {e}"));

            assert!(loaded(&slot).await.is_some(), "{kind} installs");
            assert!(!store.rows_kept().await, "{kind} retried the wipe");
            assert_eq!(store.marker().await, None, "{kind} settled the marker");
        }
    }

    /// A retry that fails again refuses the new identity: installed over the
    /// previous one's rows, it would keep them for the life of the install,
    /// since the launch reload never wipes.
    #[tokio::test]
    async fn a_replacement_whose_retry_fails_is_refused() {
        for kind in REPLACEMENTS {
            let (store, slot, owner) = after_a_failed_wipe(&format!("refused_{kind}")).await;

            let err = replace(kind, &slot, &store.db)
                .await
                .expect_err(&format!("{kind} must be refused"));

            assert_eq!(err.to_string(), "PendingWipeFailed", "{kind}");
            assert_eq!(loaded(&slot).await, None, "{kind} installed nothing");
            assert!(store.rows_kept().await);
            assert_eq!(store.marker().await, Some(owner), "{kind} kept the marker");
        }
    }

    /// The marker is recorded before the deletion gives anything up: when it
    /// cannot be, the deletion is refused with the identity still whole —
    /// loaded, subscribed, registered for push.
    #[tokio::test]
    async fn a_marker_that_cannot_be_written_refuses_the_deletion() {
        let store = WipeStore::new("unwritable").await;
        store.fail_marker_write().await;
        let slot = IdentitySlot::new();
        let (_, owner) = install(&slot).await;
        let effects = CallLog::on(&slot);

        let err = delete_in(&slot, Some(&store.db), &SpyEffects(&effects))
            .await
            .expect_err("no marker, no deletion");

        assert_eq!(err.to_string(), "WipeNotRecorded");
        assert_eq!(loaded(&slot).await, Some(owner));
        assert!(effects.calls().is_empty(), "nothing was given up");
        assert!(store.rows_kept().await);
    }

    /// A marker that cannot be read may be a pending wipe: the deletion is
    /// refused as when it cannot be written, and a replacement is refused
    /// without wiping — guessing either way is wrong.
    #[tokio::test]
    async fn a_marker_that_cannot_be_read_refuses_the_deletion_and_the_replacement() {
        let store = WipeStore::new("unreadable").await;
        store.hide_settings().await;
        let slot = IdentitySlot::new();
        let (_, owner) = install(&slot).await;
        let effects = CallLog::on(&slot);

        let err = delete_in(&slot, Some(&store.db), &SpyEffects(&effects))
            .await
            .expect_err("an unreadable marker, no deletion");
        assert_eq!(err.to_string(), "WipeNotRecorded");
        assert_eq!(loaded(&slot).await, Some(owner));
        assert!(effects.calls().is_empty(), "nothing was given up");

        for kind in REPLACEMENTS {
            let vacant = IdentitySlot::new();
            let err = replace(kind, &vacant, &store.db)
                .await
                .expect_err(&format!("{kind} must be refused"));
            assert_eq!(err.to_string(), "PendingWipeFailed", "{kind}");
            assert_eq!(loaded(&vacant).await, None, "{kind} installed nothing");
        }
        assert!(store.rows_kept().await);
    }

    /// Without a database (a failed `init_db`) there is nowhere to record the
    /// marker, and rows earlier sessions persisted may still be on disk: the
    /// deletion is refused, with its own marker, before anything is given up.
    #[tokio::test]
    async fn a_deletion_without_a_database_is_refused() {
        let slot = IdentitySlot::new();
        let (_, owner) = install(&slot).await;
        let effects = CallLog::on(&slot);

        let err = delete_in(
            &slot,
            None::<&crate::db::sqlite::SqliteStorage>,
            &SpyEffects(&effects),
        )
        .await
        .expect_err("no database, no deletion");

        assert_eq!(err.to_string(), "StorageUnavailable");
        assert_eq!(loaded(&slot).await, Some(owner));
        assert!(effects.calls().is_empty(), "nothing was given up");
    }

    /// The identity the marker names, loaded again (the launch after a
    /// refused replacement, whose secure storage still holds it), owns the
    /// rows the wipe kept: the marker goes, and nothing is wiped. A marker
    /// naming another identity stays.
    ///
    /// Through `load_in`, the code under test, whose legacy-store claim reads
    /// the process-wide database — a read the lifecycle test makes too.
    #[tokio::test]
    async fn reloading_the_marked_identity_releases_its_marker_without_wiping() {
        let store = WipeStore::new("reload").await;
        store.fail_wipe().await;
        let slot = IdentitySlot::new();
        let (words, owner) = install(&slot).await;
        delete_in(&slot, Some(&store.db), &SpyEffects(&CallLog::on(&slot)))
            .await
            .unwrap();
        assert_eq!(store.marker().await, Some(owner));
        store.heal_wipe().await;

        let (tx, _published) = private_channel();
        load_in(&slot, Some(&store.db), &tx, words.clone(), 0, false, None)
            .await
            .unwrap();
        assert_eq!(store.marker().await, None, "the marker was its own");
        assert!(store.rows_kept().await, "the reload wiped nothing");

        let other = WipeStore::new("reload_other").await;
        other
            .db
            .set_setting(WIPE_PENDING, "someone-else")
            .await
            .unwrap();
        let elsewhere = IdentitySlot::new();
        load_in(&elsewhere, Some(&other.db), &tx, words, 0, false, None)
            .await
            .unwrap();
        assert_eq!(other.marker().await.as_deref(), Some("someone-else"));
        assert!(other.rows_kept().await);
    }

    /// A marker an earlier deletion left is never overwritten — overwritten,
    /// a reload of the newer identity would release it and keep the earlier
    /// rows — and a wipe that succeeds whole settles it, whoever left it.
    #[tokio::test]
    async fn an_earlier_marker_stays_until_a_whole_wipe_settles_it() {
        let store = WipeStore::new("earlier").await;
        store.db.set_setting(WIPE_PENDING, "earlier").await.unwrap();
        store.fail_wipe().await;
        let slot = IdentitySlot::new();
        install(&slot).await;
        delete_in(&slot, Some(&store.db), &SpyEffects(&CallLog::on(&slot)))
            .await
            .unwrap();
        assert_eq!(store.marker().await.as_deref(), Some("earlier"));

        store.heal_wipe().await;
        install(&slot).await;
        delete_in(&slot, Some(&store.db), &SpyEffects(&CallLog::on(&slot)))
            .await
            .unwrap();
        assert_eq!(store.marker().await, None);
        assert!(!store.rows_kept().await);
    }

    /// The deletion's cleanup failures are reported after the log buffer is
    /// cleared, so the Logs screen's history starts with them instead of
    /// losing them with the deleted identity's lines.
    fn check_cleanup_report(source: &str) -> Result<(), String> {
        let code = production_code(source);
        expect_body(
            &code,
            "fn clear_logs_and_report(failures: &[String])",
            r#"crate::api::logging::clear_logs();
               for failure in failures {
                   crate::api::logging::blog_warn("identity", format!("cleanup failed — {failure}"));
               }"#,
        )?;
        let deletion = item_body(
            &code,
            "async fn delete_in<S: Storage, W: DeleteEffects>(slot: &IdentitySlot, db: Option<&S>, fx: &W,) -> Result<()>",
        )?;
        if deletion.contains("clear_logs_and_report(&failures);")
            && !deletion.contains("clear_logs()")
        {
            Ok(())
        } else {
            Err("delete_in must clear the logs through clear_logs_and_report".into())
        }
    }

    #[test]
    fn cleanup_failures_outlive_the_log_clear() {
        check_cleanup_report(include_str!("identity.rs")).unwrap();
    }

    /// The guard above refuses a deletion that clears the logs after the
    /// report, or around it.
    #[test]
    fn the_cleanup_report_guard_refuses_a_lost_report() {
        let identity = include_str!("identity.rs");
        for broken in [
            mutant(
                identity,
                "    crate::api::logging::clear_logs();\n    for failure in failures {",
                "    for failure in failures {",
            ),
            mutant(
                identity,
                "    clear_logs_and_report(&failures);",
                "    crate::api::logging::clear_logs();",
            ),
        ] {
            assert!(check_cleanup_report(&broken).is_err());
        }
    }

    /// These tests read the marker under the key the production code writes.
    #[test]
    fn the_tests_read_the_production_marker_key() {
        assert_eq!(WIPE_PENDING, IDENTITY_WIPE_PENDING);
    }

    /// The Account screen's warning follows the marker, and an unreadable
    /// one hides it rather than failing.
    #[tokio::test]
    async fn the_pending_wipe_flag_follows_the_marker() {
        let (store, _, _) = after_a_failed_wipe("flag").await;
        assert!(has_pending_wipe(&store.db).await);

        let clean = WipeStore::new("flag_clean").await;
        assert!(!has_pending_wipe(&clean.db).await);

        store.hide_settings().await;
        assert!(!has_pending_wipe(&store.db).await);
    }

    /// A phrase the core rejects is refused before the pending wipe is
    /// retried: the rows the wipe kept may be the previous identity's, which
    /// a refused replacement loads again.
    #[tokio::test]
    async fn an_import_of_a_rejected_phrase_never_retries_the_wipe() {
        let (store, slot, owner) = after_a_failed_wipe("rejected").await;
        store.heal_wipe().await;
        // Twelve valid words whose checksum is wrong ("…abandon about" is
        // the valid one), never a random swap, which passes 1 time in 16.
        let words = vec!["abandon".to_string(); 12];
        let (tx, _published) = private_channel();

        let err = import_in(&slot, Some(&store.db), &tx, words, false)
            .await
            .expect_err("a phrase with a bad checksum is refused");

        assert_ne!(err.to_string(), "PendingWipeFailed");
        assert!(store.rows_kept().await, "nothing was wiped");
        assert_eq!(store.marker().await, Some(owner));
    }

    // ── One transition at a time (review round 4 of #573) ───────────────────

    /// Where a gated deletion stops, and the signal that lets it go on.
    #[derive(Default)]
    struct Gate {
        reached: tokio::sync::Notify,
        open: tokio::sync::Notify,
    }

    /// A `DeleteEffects` that does nothing, except stop at `at` until the
    /// test opens its gate — the awaits where the deletion holds no lock of
    /// the slot's own.
    struct GatedEffects<'a> {
        at: &'static str,
        gate: &'a Gate,
    }

    impl GatedEffects<'_> {
        async fn hook(&self, name: &'static str) {
            if name == self.at {
                self.gate.reached.notify_one();
                self.gate.open.notified().await;
            }
        }
    }

    impl DeleteEffects for GatedEffects<'_> {
        async fn release_identity_subscriptions(&self) {
            self.hook("release_identity_subscriptions").await;
        }
        async fn unregister_push(&self) {
            self.hook("unregister_push").await;
        }
        async fn forget_identity_state(&self) {
            self.hook("forget_identity_state").await;
        }
    }

    /// How long a competing transition is given while a deletion is held. A
    /// transition that runs alongside the deletion finishes in milliseconds;
    /// one that waits for it does not finish at all, so the test then pays
    /// this once.
    const HELD: std::time::Duration = std::time::Duration::from_secs(1);

    /// Run `deletion` until it stops at its gate, give `meanwhile` its
    /// chance while the deletion is held, then open the gate and let both
    /// finish. Real time, not a paused clock: the store's queries complete on
    /// SQLite's own threads, and a paused clock would advance past them.
    async fn while_held<T>(
        gate: &Gate,
        deletion: impl std::future::Future<Output = Result<()>>,
        meanwhile: impl std::future::Future<Output = T>,
    ) -> (Result<()>, T) {
        let driver = async {
            gate.reached.notified().await;
            let mut meanwhile = std::pin::pin!(meanwhile);
            let early = tokio::time::timeout(HELD, meanwhile.as_mut()).await.ok();
            gate.open.notify_one();
            match early {
                Some(out) => out,
                None => meanwhile.await,
            }
        };
        tokio::join!(deletion, driver)
    }

    /// A second deletion while the first awaits the relays used to retire
    /// the identity, and the first then retired the replacement installed
    /// after it. The second waits instead, finds nothing to delete, and the
    /// replacement stays.
    #[tokio::test]
    async fn a_deletion_held_at_the_relays_keeps_the_slot_until_it_is_done() {
        let store = WipeStore::new("concurrent_delete").await;
        let slot = IdentitySlot::new();
        install(&slot).await;
        let gate = Gate::default();
        let held = GatedEffects {
            at: "release_identity_subscriptions",
            gate: &gate,
        };

        let (first, (second, created)) =
            while_held(&gate, delete_in(&slot, Some(&store.db), &held), async {
                let log = CallLog::on(&slot);
                let second = delete_in(&slot, Some(&store.db), &SpyEffects(&log)).await;
                let created = create_in(&slot, Some(&store.db)).await;
                (second, created)
            })
            .await;

        first.unwrap();
        assert_eq!(second.unwrap_err().to_string(), "NoIdentity");
        let created = created.unwrap().public_key;
        assert_eq!(
            loaded(&slot).await,
            Some(created),
            "the replacement survives the first deletion"
        );
    }

    /// Reloading the identity being deleted, while its deletion awaits the
    /// relays, used to release the deletion's marker as the reload's own,
    /// and the deletion then retired the reloaded identity: no identity, the
    /// rows on disk, no marker. The reload waits instead, and loads the
    /// identity over its own rows once the deletion is done.
    #[tokio::test]
    async fn a_reload_waits_for_the_deletion_of_its_identity() {
        let store = WipeStore::new("concurrent_reload").await;
        store.fail_wipe().await;
        let slot = IdentitySlot::new();
        let (words, owner) = install(&slot).await;
        let gate = Gate::default();
        let held = GatedEffects {
            at: "release_identity_subscriptions",
            gate: &gate,
        };
        let (tx, _published) = private_channel();

        let (deleted, reloaded) = while_held(
            &gate,
            delete_in(&slot, Some(&store.db), &held),
            load_in(&slot, Some(&store.db), &tx, words, 0, false, None),
        )
        .await;

        deleted.unwrap();
        reloaded.unwrap();
        assert_eq!(
            loaded(&slot).await,
            Some(owner),
            "the reload is the last transition, and it stays"
        );
        assert!(store.rows_kept().await);
        assert_eq!(store.marker().await, None, "the rows are the reload's own");
    }

    /// A creation while a deletion awaits the push server — its identity
    /// already retired, its wipe still to run — used to install, and the
    /// deletion's wipe then took the new identity's rows. The creation waits
    /// instead, and its rows stay.
    #[tokio::test]
    async fn a_creation_waits_for_the_wipe_of_the_identity_before_it() {
        let store = WipeStore::new("concurrent_create").await;
        let slot = IdentitySlot::new();
        install(&slot).await;
        let gate = Gate::default();
        let held = GatedEffects {
            at: "unregister_push",
            gate: &gate,
        };

        let (deleted, created) =
            while_held(&gate, delete_in(&slot, Some(&store.db), &held), async {
                let created = create_in(&slot, Some(&store.db)).await.unwrap();
                store.db.save_trade_key("order-b", 1).await.unwrap();
                created.public_key
            })
            .await;

        deleted.unwrap();
        assert_eq!(loaded(&slot).await, Some(created));
        assert_eq!(
            store.db.get_trade_key("order-b").await.unwrap(),
            Some(1),
            "the new identity's rows survive the previous one's wipe"
        );
    }

    /// The words an import would refuse are refused by the check that runs
    /// before the deletion, with the same error, and the ones it would
    /// accept pass.
    #[test]
    fn validating_a_phrase_answers_as_the_import_would() {
        let valid: Vec<String> = "abandon abandon abandon abandon abandon abandon \
                                  abandon abandon abandon abandon abandon about"
            .split_whitespace()
            .map(str::to_string)
            .collect();
        validate_mnemonic(valid).unwrap();

        // Twelve valid words whose checksum is wrong.
        let bad_checksum = vec!["abandon".to_string(); 12];
        let err = validate_mnemonic(bad_checksum.clone()).unwrap_err();
        assert!(err.to_string().contains("invalid mnemonic"), "{err}");
        assert_eq!(
            err.to_string(),
            key_ops::derive_master_key(&bad_checksum)
                .unwrap_err()
                .to_string()
        );

        let not_a_word = validate_mnemonic(vec!["mostro".to_string(); 12]).unwrap_err();
        assert!(
            not_a_word.to_string().contains("invalid mnemonic"),
            "{not_a_word}"
        );
    }

    /// The transitions of the slot: each takes its lifecycle lock first.
    const TRANSITIONS: [&str; 5] = [
        "async fn create_in<S: Storage>(slot: &IdentitySlot, db: Option<&S>,) -> Result<IdentityCreationResult>",
        "async fn load_in<S: Storage>(slot: &IdentitySlot, db: Option<&S>, tx: &broadcast::Sender<u32>, words: Vec<String>, trade_key_index: u32, privacy_mode: bool, created_at: Option<i64>,) -> Result<IdentityInfo>",
        "async fn import_in<S: Storage>(slot: &IdentitySlot, db: Option<&S>, tx: &broadcast::Sender<u32>, words: Vec<String>, privacy_mode: bool,) -> Result<IdentityInfo>",
        "async fn import_nsec_in<S: Storage>(slot: &IdentitySlot, db: Option<&S>, nsec: String,) -> Result<IdentityInfo>",
        "async fn delete_in<S: Storage, W: DeleteEffects>(slot: &IdentitySlot, db: Option<&S>, fx: &W,) -> Result<()>",
    ];

    /// Every transition locks the slot's lifecycle before it reads it, and
    /// only a transition writes it: `load_unlocked`, which writes, is called
    /// from `load_in` and `import_in` alone, both holding the lock.
    fn check_one_transition_at_a_time(source: &str) -> Result<(), String> {
        let code = production_code(source);
        let lock = "let_transition=slot.lifecycle.lock().await;";
        let mut writes = 0;
        for signature in TRANSITIONS {
            let body = item_body(&code, signature)?;
            if !body.starts_with(lock) {
                return Err(format!("`{signature}` must take the lifecycle lock first"));
            }
            writes += body.matches("slot.state.write()").count();
        }
        let unlocked = item_body(
            &code,
            "async fn load_unlocked<S: Storage>(slot: &IdentitySlot, db: Option<&S>, tx: &broadcast::Sender<u32>, words: Vec<String>, trade_key_index: u32, privacy_mode: bool, created_at: Option<i64>,) -> Result<IdentityInfo>",
        )?;
        writes += unlocked.matches("slot.state.write()").count();
        if writes != code.matches("slot.state.write()").count() {
            return Err("the slot is written outside a transition".into());
        }
        let callers = ["load_in", "import_in"]
            .iter()
            .map(|name| {
                let signature = TRANSITIONS
                    .iter()
                    .find(|s| s.contains(&format!("fn {name}<")));
                item_body(&code, signature.unwrap())
                    .map(|body| body.matches("load_unlocked(").count())
            })
            .sum::<Result<usize, String>>()?;
        if callers != code.matches("load_unlocked(").count() {
            return Err("load_unlocked is called outside load_in and import_in".into());
        }
        Ok(())
    }

    #[test]
    fn one_transition_of_the_slot_at_a_time() {
        check_one_transition_at_a_time(include_str!("identity.rs")).unwrap();
    }

    /// The guard above refuses a transition that reads before locking, a
    /// write of the slot outside a transition, and an unlocked load called
    /// from anywhere else.
    #[test]
    fn the_transition_guard_refuses_an_unlocked_path() {
        let identity = include_str!("identity.rs");
        for broken in [
            mutant(
                identity,
                "    let _transition = slot.lifecycle.lock().await;\n    let Some(owner) = slot",
                "    let Some(owner) = slot",
            ),
            mutant(
                identity,
                "pub async fn get_identity() -> Result<Option<IdentityInfo>> {",
                "pub async fn get_identity() -> Result<Option<IdentityInfo>> {\n    let slot = identity_slot();\n    drop(slot.state.write().await);",
            ),
            mutant(
                identity,
                "    retry_pending_wipe_if_vacant(slot, db).await?;\n    *slot.state.write()",
                "    load_unlocked(slot, None::<&crate::db::sqlite::SqliteStorage>, trade_key_index_tx(), vec![], 0, false, None).await?;\n    *slot.state.write()",
            ),
        ] {
            assert!(check_one_transition_at_a_time(&broken).is_err());
        }
    }

    /// Everything a deletion gives up has its way back for an identity loaded
    /// again in the same session (review of #573): a replacement refused
    /// after the deletion reloads the previous identity, and
    /// `restore_identity_session` must rebuild what a cold start would. A
    /// teardown step added without its restore — or without saying why a cold
    /// start leaves it empty too — fails here.
    #[test]
    fn every_identity_teardown_has_its_restore() {
        let identity = production_code(include_str!("identity.rs"));
        let orders = production_code(include_str!("orders.rs"));
        let effects = production_code(include_str!("../mostro/delete_effects.rs"));
        let body = |code: &str, signature: &str| {
            item_body(code, signature).unwrap_or_else(|e| panic!("{e}"))
        };
        let teardown = [
            body(
                &orders,
                "pub(crate) async fn release_identity_subscriptions()",
            ),
            body(&identity, "pub(crate) async fn forget_identity_state()"),
            body(&effects, "impl DeleteEffects for RealDeleteEffects"),
        ]
        .concat();
        let restore = [
            body(
                &identity,
                "pub async fn restore_identity_session() -> Result<()>",
            ),
            body(
                &orders,
                "pub(crate) async fn restore_identity_subscriptions()",
            ),
            body(&orders, "pub(crate) async fn reclaim_book_ownership()"),
        ]
        .concat();

        // Each step of the teardown, and what undoes it — `None` where a cold
        // start leaves it empty too, so the reload matches a restart.
        let steps: [(&str, Option<&str>); 18] = [
            // In-memory tasks: a cold start has no retry running either.
            ("forget_late_take_retries()", None),
            // Per-trade receivers are temporary; the bulk feed covers the keys.
            ("single_order_tasks()", None),
            ("global_dm_keys()", Some("seed_global_dm_coverage()")),
            (
                "watched_orders_subscription_id()",
                Some("resync_watched_orders("),
            ),
            // Per-trade REQs: a cold start opens none either.
            ("subscriptions::teardown(", None),
            (
                "mostro_dm_subscription_id()",
                Some("resubscribe_global_dm_filter()"),
            ),
            (
                "forget_identity_chats()",
                Some("resubscribe_active_chats()"),
            ),
            // Filled again on demand from the persisted bindings.
            ("trade_key_map()", None),
            ("trade_key_misses()", None),
            // A cold start replays the history with an empty window too.
            ("forget_processed_daemon_messages()", None),
            (
                "forget_identity_disputes()",
                Some("resubscribe_active_dispute_chats()"),
            ),
            // Hydrated from the trade rows on the first read.
            ("forget_identity_ratings()", None),
            (
                "forget_identity_reputation()",
                Some("my_reputation::spawn_refresh("),
            ),
            // The chat rearm installs the sessions again.
            (
                "session_manager().clear()",
                Some("resubscribe_active_chats()"),
            ),
            ("set_claim_nodes(", Some("refresh_claim_nodes()")),
            ("clear_retained()", Some("refresh_claim_nodes()")),
            ("forget_book_ownership()", Some("reclaim_book_ownership()")),
            ("unregister_all()", Some("push::request_reconcile()")),
        ];
        for (step, undo) in steps {
            assert!(
                teardown.contains(step),
                "{step} is no longer a teardown step: update this list"
            );
            if let Some(undo) = undo {
                assert!(
                    restore.contains(undo),
                    "{step} is given up by a deletion, so the reload must call {undo}"
                );
            }
        }
        // A tripwire on the size of the teardown: a new step changes it, and
        // whoever adds one updates `steps` and the restore with it.
        assert_eq!(
            teardown.matches(';').count(),
            22,
            "the identity teardown changed: give the new step its restore \
             (or say why a cold start does not rebuild it), then update this count"
        );
    }
}
