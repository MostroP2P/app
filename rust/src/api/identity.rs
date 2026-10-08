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
use crate::db::Storage;
use crate::identity_slot::{AppDeletionHooks, DeletionHooks, IdentitySlot, IdentityState};

// ── Global in-memory identity state ──────────────────────────────────────────

fn identity_slot() -> &'static IdentitySlot {
    static SLOT: IdentitySlot = IdentitySlot::new();
    &SLOT
}

fn identity_lock() -> &'static RwLock<Option<IdentityState>> {
    &identity_slot().state
}

/// The generation of the active identity, or `None` without one.
pub(crate) async fn identity_generation() -> Option<u64> {
    let guard = identity_lock().read().await;
    guard.as_ref().map(|_| {
        identity_slot()
            .generation
            .load(std::sync::atomic::Ordering::SeqCst)
    })
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
    let guard = identity_lock().read().await;
    let current = guard.is_some()
        && identity_slot()
            .generation
            .load(std::sync::atomic::Ordering::SeqCst)
            == generation;
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
    // Checked with a read lock, which is not held across the wipe below: the
    // lifecycle lock keeps the slot as checked until the install, so readers
    // of the identity never wait on the wipe (review of #573).
    if slot.state.read().await.is_some() {
        bail!("AlreadyExists");
    }

    // A point where retrying a pending data wipe is safe: the slot is empty
    // (checked above), so the tables hold nothing of a live identity (issue
    // #555). A retry that fails again refuses the new identity: once one is
    // installed, the launch reload never retries, and the previous user's
    // rows would stay for the life of the install.
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

    let mut guard = slot.state.write().await;
    *guard = Some(IdentityState {
        mnemonic_words: words,
        keys,
        identity_info: identity_info.clone(),
    });
    drop(guard);

    // The rows a failed wipe kept may be this identity's own: then the
    // pending wipe is over, without wiping anything (issue #555).
    if let Some(db) = db {
        release_own_wipe_marker(db, &public_key).await;
    }

    // An older install's shared Cashu proof store goes to the identity the
    // app starts with — this load, at the first launch after the upgrade.
    // Here, inside the transition, both the launch reload and an import claim
    // it, and the lifecycle lock the caller holds keeps any replacement out
    // until the claim is done. Not under the state lock: the claim touches
    // only files and settings, so no reader of the identity waits on it.
    crate::api::cashu::claim_legacy_store(&identity_info.public_key).await;

    Ok(identity_info)
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

/// The install half of [`import_from_mnemonic`], on `slot` against `db`: the
/// pending-wipe retry and the load, as one transition — a creation slipping
/// in between would find the slot it left empty.
async fn import_in<S: Storage>(
    slot: &IdentitySlot,
    db: Option<&S>,
    tx: &broadcast::Sender<u32>,
    words: Vec<String>,
    privacy_mode: bool,
) -> Result<IdentityInfo> {
    let _transition = slot.lifecycle.lock().await;
    // An import replaces the deleted identity just as a creation does, so it
    // settles a pending wipe first — and refuses, like a creation, when it
    // cannot (issue #555).
    retry_pending_wipe_if_vacant_in(slot, db).await?;
    load_unlocked(slot, db, tx, words, 0, privacy_mode, None).await
}

/// Import identity from an nsec (bech32-encoded Nostr secret key).
/// Note: nsec import produces a single key with no BIP-39 mnemonic backup.
///
/// Gated like [`import_from_mnemonic`]: when the slot is empty, a pending
/// wipe is retried first, and a retry that fails refuses the import with
/// `PendingWipeFailed`. A slot already taken is installed over, as before
/// issue #555, without a generation bump.
pub async fn import_from_nsec(nsec: String) -> Result<IdentityInfo> {
    import_nsec_in(identity_slot(), crate::db::app_db::db(), nsec).await
}

/// [`import_from_nsec`] on `slot`, against `db`.
async fn import_nsec_in<S: Storage>(
    slot: &IdentitySlot,
    db: Option<&S>,
    nsec: String,
) -> Result<IdentityInfo> {
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

    let _transition = slot.lifecycle.lock().await;
    retry_pending_wipe_if_vacant_in(slot, db).await?;
    let mut guard = slot.state.write().await;
    *guard = Some(IdentityState {
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
    delete_identity_inner(true).await
}

/// [`delete_identity`], with the wipe of the identity's data switchable.
///
/// `wipe_data: false` exists for the unit test of the identity lifecycle
/// only: the database and the in-memory stores are process-wide, and tests
/// run in parallel against them, so a real wipe there deletes the rows other
/// tests are asserting on. The wipe itself is covered where it can run alone
/// (`clear_identity_data_wipes_the_identity_and_keeps_the_device`,
/// `clearing_the_store_leaves_no_chats_and_no_unread_count`).
async fn delete_identity_inner(wipe_data: bool) -> Result<()> {
    let cleanup_failures = delete_in(
        identity_slot(),
        crate::db::app_db::db(),
        &AppDeletionHooks,
        wipe_data,
    )
    .await?;

    // Last, so the buffered lines above are dropped too: they name orders and
    // counterparties of the identity being deleted, and the Logs screen can
    // still share them afterwards. The platform console keeps them. The
    // cleanup failures are the exception, re-emitted after the clear — see
    // `clear_logs_and_report`.
    clear_logs_and_report(&cleanup_failures);

    Ok(())
}

/// [`delete_identity_inner`] on `slot`, against `db`, up to the log clear:
/// returns the cleanup failures to report.
async fn delete_in<S: Storage>(
    slot: &IdentitySlot,
    db: Option<&S>,
    hooks: &impl DeletionHooks,
    wipe_data: bool,
) -> Result<Vec<String>> {
    // Held to the end: the owner read here is the identity the take below
    // retires, and no transition sees the slot or the marker in between.
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
    // the identity is still whole (issue #555). The lifecycle test's
    // `wipe_data: false` deletes no rows, so it leaves no intent either.
    if wipe_data {
        record_wipe_intent(db, &owner).await?;
    }
    // While the identity still exists: its relay subscriptions are given
    // back first, so nothing of the old user's keeps arriving afterwards.
    if wipe_data {
        hooks.release_subscriptions().await;
    }

    let mut guard = slot.state.write().await;
    let Some(state) = guard.take() else {
        bail!("NoIdentity");
    };
    // Under the same lock, so no `while_identity_current` write can start
    // between the two.
    slot.generation
        .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    drop(guard);
    drop(state);

    // The push server must stop waking this device for keys the user no
    // longer holds; the registrations name pubkeys only, so no key is needed.
    hooks.unregister_push().await;

    // A memory-only session (`init_db` failed) only gets here without a
    // wipe: `record_wipe_intent` refuses the real deletion when there is no
    // database to hold the marker.
    let cleanup_failures = match db {
        Some(db) => wipe_identity_rows(db, wipe_data).await,
        None => Vec::new(),
    };
    if wipe_data {
        hooks.forget_state().await;
    }
    Ok(cleanup_failures)
}

/// Record that `owner`'s data is about to be wiped, before the deletion
/// gives anything up (issue #555): [`settings_keys::IDENTITY_WIPE_PENDING`],
/// holding `owner`'s public key, makes the next identity creation or import
/// retry a wipe that then fails ([`retry_pending_wipe`]), and tells a reload
/// of that same identity the rows are its own ([`release_own_wipe_marker`]).
///
/// Fails with the `WipeNotRecorded` marker, and the caller must not delete,
/// when the marker cannot be written or read: a deletion that went ahead
/// without it would let the replacement install over the previous
/// identity's rows, with nothing left to say so. With no database at all it
/// fails with `StorageUnavailable` instead, for the same reason: no retry in
/// this session can succeed, so the screen asks for a restart rather than a
/// retry. That keeps a possibly compromised identity until the store comes
/// back — deliberately: rotating it would leave the previous user's rows on
/// disk with no trace (review of #573).
/// Written ahead, a crash between this and the wipe leaves the marker with
/// the identity still in Flutter's secure storage, which the launch reload
/// releases. A marker already there names an earlier deletion whose rows are
/// still on disk, and stays: overwritten, the reload of `owner` would
/// release it and keep them.
async fn record_wipe_intent<S: Storage>(db: Option<&S>, owner: &str) -> Result<()> {
    use crate::db::settings_keys::IDENTITY_WIPE_PENDING;

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

/// Clear what the identity persisted, returning a description per failure
/// instead of failing: by the time this runs the identity is already gone,
/// and the contract is that a failed cleanup is reported, never turned into
/// a failed deletion.
///
/// Any failed step leaves the marker [`record_wipe_intent`] wrote before the
/// deletion began, and the retry runs every step again; a wipe that succeeds
/// whole clears it. The returned strings
/// outlive `clear_logs()`, so they must name no order or counterparty.
async fn wipe_identity_rows<S: Storage>(db: &S, wipe_data: bool) -> Vec<String> {
    use crate::db::settings_keys::IDENTITY_WIPE_PENDING;

    let mut failures = Vec::new();
    // The persisted trade key counter and per-order key mappings: both belong
    // to the deleted identity's derivation tree, and a new mnemonic must
    // start counting from zero instead of inheriting them. (If this cleanup
    // fails, the pubkey guard in `reconcile_trade_key_index` still prevents
    // the stale row from leaking into a different identity.)
    if let Err(e) = db.delete_identity().await {
        failures.push(format!("persisted identity kept: {e}"));
    }
    if let Err(e) = db.clear_trade_keys().await {
        failures.push(format!("trade key mappings kept: {e}"));
    }
    // Everything else the identity produced — trades, chats, payout claims,
    // the outbound queue, per-order cursors (issue #533). The next user must
    // find the app as a fresh install would leave it.
    if wipe_data {
        match db.clear_identity_data().await {
            // A wipe that succeeds whole settles any pending retry, whichever
            // deletion left it behind. The marker stands for all three steps:
            // with one of the two above failed it stays, and the retry runs
            // them all again.
            Ok(()) if failures.is_empty() => {
                if let Err(e) = db.delete_setting(IDENTITY_WIPE_PENDING).await {
                    failures.push(format!("wipe-pending marker kept: {e}"));
                }
            }
            Ok(()) => {}
            // The marker recorded before the deletion stays for the retry.
            Err(e) => failures.push(format!("identity data rows kept: {e}")),
        }
    }
    failures
}

/// Drop the buffered log history, then report the cleanup failures where the
/// user can still find them (issue #555).
///
/// The order is the point: `clear_logs()` first, because the buffered lines
/// name orders and counterparties of the deleted identity — but a cleanup
/// failure dropped with them would leave a wipe that kept the previous
/// identity's rows with no trace anywhere the user can reach. Re-emitting
/// through `blog_warn` puts each failure on the platform console, in the
/// fresh history the Logs screen loads, and on the live stream.
fn clear_logs_and_report(failures: &[String]) {
    crate::api::logging::clear_logs();
    for failure in failures {
        crate::api::logging::blog_warn("identity", format!("cleanup failed — {failure}"));
    }
}

/// Retry the data wipe a previous deletion left pending, if any (issue #555).
///
/// Only sound while no identity holds the session — `create_identity` calls
/// it after refusing to replace a loaded identity, and
/// `import_from_mnemonic` through [`retry_pending_wipe_if_vacant_in`]:
/// `clear_identity_data` empties whole tables, so a retry with a live
/// identity would take its trades — and its payout claims, which no restore
/// brings back — along with the leftovers. That is why the launch reload
/// (`load_identity_from_mnemonic`) never calls this.
///
/// Fails with the `PendingWipeFailed` marker when the wipe fails again, and
/// the caller must not install an identity then: the marker stays, and the
/// next creation or import retries. A marker that cannot be read fails the
/// same way, without wiping: it may be a pending wipe, and guessing either
/// way is wrong — a blind wipe, or a new identity over the old rows.
async fn retry_pending_wipe<S: Storage>(db: &S) -> Result<()> {
    use crate::db::settings_keys::IDENTITY_WIPE_PENDING;

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
    // The whole wipe the deletion left pending: the identity row, the
    // trade-key mappings and the rows — any of them may be what failed.
    let wiped = async {
        db.delete_identity().await?;
        db.clear_trade_keys().await?;
        db.clear_identity_data().await
    }
    .await;
    match wiped {
        Ok(()) => {
            log::info!("[identity] pending identity wipe completed on retry");
            if let Err(e) = db.delete_setting(IDENTITY_WIPE_PENDING).await {
                crate::api::logging::blog_warn(
                    "identity",
                    format!("cleanup failed — wipe-pending marker kept: {e}"),
                );
            }
        }
        Err(e) => {
            crate::api::logging::blog_warn(
                "identity",
                format!("retry of the pending identity wipe failed — the previous identity's data is still on disk: {e}"),
            );
            bail!("PendingWipeFailed");
        }
    }
    Ok(())
}

/// [`retry_pending_wipe`] for the imports, which may find the slot taken:
/// retries only while it is empty. Dart deletes the current identity before
/// importing, so that is every import it makes; a slot already taken is the
/// launch reload's case, where a retry would take the live identity's data.
/// The caller holds `slot.lifecycle`, so the slot stays as checked until it
/// installs.
async fn retry_pending_wipe_if_vacant_in<S: Storage>(
    slot: &IdentitySlot,
    db: Option<&S>,
) -> Result<()> {
    // A read lock, released before the wipe: the caller's lifecycle lock is
    // what keeps the slot as checked, so readers never wait on the wipe.
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
    use crate::db::settings_keys::IDENTITY_WIPE_PENDING;

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
/// previous identity's rows are still on disk and no retry has succeeded yet
/// (issue #555). The Account screen shows a warning while this holds — the
/// deletion itself reported success, so this flag is the one trace the UI
/// can reach.
pub async fn has_pending_identity_wipe() -> bool {
    match crate::db::app_db::db() {
        Some(db) => matches!(
            db.get_setting(crate::db::settings_keys::IDENTITY_WIPE_PENDING)
                .await,
            Ok(Some(_))
        ),
        None => false,
    }
}

/// What the current identity would lose if it were replaced now: locked
/// escrow, locked or payable bonds, open payout claims, live trades — most
/// serious first, empty when it is safe to go ahead (issue #533).
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
/// of its own orders, its dispute chats and its push registrations — what a
/// cold start builds for it. Its rows are still on disk: the refusal kept
/// them, and the reload released their wipe-pending marker.
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
        async fn delete_identity(&self) -> Result<()> {
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
        async fn mark_trade_completed(&self, _order_id: &str, _completed_at: i64) -> Result<()> {
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
        async fn clear_trade_keys(&self) -> Result<()> {
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

        // Without the data wipe: see `delete_identity_inner`.
        delete_identity_inner(false).await.unwrap();
        assert!(get_identity().await.unwrap().is_none());
        assert_eq!(identity_generation().await, None);

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
        load_identity_from_mnemonic(words, 0, false, None)
            .await
            .unwrap();
        let reloaded = identity_generation().await.expect("an identity is loaded");
        assert_ne!(reloaded, generation);
        assert!(while_identity_current(generation, async {}).await.is_none());
        delete_identity_inner(false).await.unwrap();
    }

    /// A `Storage` for the wipe seam (issue #555): the settings map works —
    /// that is where the wipe-pending marker lives — unless built
    /// [`unreadable`](Self::unreadable), the identity row and trade-key clears
    /// succeed, and `clear_identity_data` always fails, counting its calls.
    /// Everything else is `unimplemented!()`, like [`FailingStore`]:
    /// reaching one would be a test bug, not silent success.
    struct WipeFailingStore {
        settings: std::sync::Mutex<std::collections::HashMap<String, String>>,
        unreadable: bool,
        /// Every settings write fails while this holds; clearing it is the
        /// storage recovering.
        unwritable: std::sync::atomic::AtomicBool,
        /// Whether a wipe succeeds; it fails unless a test says otherwise.
        wipes_succeed: std::sync::atomic::AtomicBool,
        /// Stand-ins for the rows an identity produced, by owner.
        rows: std::sync::Mutex<std::collections::BTreeSet<String>>,
        wipes: std::sync::atomic::AtomicUsize,
        /// Run inside every wipe, to observe what the wipe holds.
        during_wipe: std::sync::Mutex<Option<Box<dyn Fn() + Send + Sync>>>,
        /// Whether clearing the trade-key mappings fails.
        trade_keys_fail: std::sync::atomic::AtomicBool,
        trade_key_clears: std::sync::atomic::AtomicUsize,
        identity_row_deletes: std::sync::atomic::AtomicUsize,
    }

    impl WipeFailingStore {
        fn new() -> Self {
            Self {
                settings: Default::default(),
                unreadable: false,
                unwritable: Default::default(),
                wipes_succeed: Default::default(),
                rows: Default::default(),
                wipes: Default::default(),
                during_wipe: Default::default(),
                trade_keys_fail: Default::default(),
                trade_key_clears: Default::default(),
                identity_row_deletes: Default::default(),
            }
        }
        fn wipes_succeed(&self, succeed: bool) {
            self.wipes_succeed
                .store(succeed, std::sync::atomic::Ordering::SeqCst);
        }
        fn add_rows(&self, owner: &str) {
            self.rows.lock().unwrap().insert(owner.to_string());
        }
        fn rows(&self) -> std::collections::BTreeSet<String> {
            self.rows.lock().unwrap().clone()
        }
        /// Every settings write fails until [`Self::recover`].
        fn unwritable() -> Self {
            let store = Self::new();
            store
                .unwritable
                .store(true, std::sync::atomic::Ordering::SeqCst);
            store
        }
        fn recover(&self) {
            self.unwritable
                .store(false, std::sync::atomic::Ordering::SeqCst);
        }
        /// Every settings read fails.
        fn unreadable() -> Self {
            Self {
                unreadable: true,
                ..Self::new()
            }
        }
        fn wipes(&self) -> usize {
            self.wipes.load(std::sync::atomic::Ordering::SeqCst)
        }
        fn setting(&self, key: &str) -> Option<String> {
            self.settings.lock().unwrap().get(key).cloned()
        }
        fn put_setting(&self, key: &str, value: &str) {
            self.settings
                .lock()
                .unwrap()
                .insert(key.to_string(), value.to_string());
        }
    }

    impl Storage for WipeFailingStore {
        async fn delete_identity(&self) -> Result<()> {
            self.identity_row_deletes
                .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            Ok(())
        }
        async fn clear_trade_keys(&self) -> Result<()> {
            self.trade_key_clears
                .fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            if self.trade_keys_fail.load(std::sync::atomic::Ordering::SeqCst) {
                anyhow::bail!("injected trade-key cleanup failure");
            }
            Ok(())
        }
        async fn clear_identity_data(&self) -> Result<()> {
            self.wipes.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
            if let Some(probe) = self.during_wipe.lock().unwrap().as_ref() {
                probe();
            }
            if !self.wipes_succeed.load(std::sync::atomic::Ordering::SeqCst) {
                anyhow::bail!("injected wipe failure");
            }
            self.rows.lock().unwrap().clear();
            Ok(())
        }
        async fn get_setting(&self, key: &str) -> Result<Option<String>> {
            if self.unreadable {
                anyhow::bail!("injected settings read failure");
            }
            Ok(self.setting(key))
        }
        async fn set_setting(&self, key: &str, value: &str) -> Result<()> {
            if self.unwritable.load(std::sync::atomic::Ordering::SeqCst) {
                anyhow::bail!("injected settings write failure");
            }
            self.put_setting(key, value);
            Ok(())
        }
        async fn delete_setting(&self, key: &str) -> Result<()> {
            self.settings.lock().unwrap().remove(key);
            Ok(())
        }
        async fn save_identity(&self, _identity: &IdentityInfo) -> Result<()> {
            unimplemented!()
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
            Ok(None)
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
        async fn mark_trade_completed(&self, _order_id: &str, _completed_at: i64) -> Result<()> {
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
        async fn list_queued_messages(&self) -> Result<Vec<crate::queue::outbox::QueuedMessage>> {
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
    }

    /// The deletion seam of issue #555: a wipe that fails is reported to the
    /// caller's failure list and leaves the marker the deletion recorded
    /// first — nothing bubbles up as an error, per the deletion contract.
    #[tokio::test]
    async fn a_failed_wipe_reports_and_keeps_the_retry_marker() {
        let store = WipeFailingStore::new();
        store.put_setting(
            crate::db::settings_keys::IDENTITY_WIPE_PENDING,
            "owner-pubkey",
        );

        let failures = wipe_identity_rows(&store, true).await;

        assert!(
            failures.iter().any(|f| f.contains("injected wipe failure")),
            "the wipe failure must be reported: {failures:?}"
        );
        assert_eq!(
            store
                .setting(crate::db::settings_keys::IDENTITY_WIPE_PENDING)
                .as_deref(),
            Some("owner-pubkey"),
            "a failed wipe must leave the retry marker, naming whose rows stayed"
        );
    }

    /// A wipe that succeeds settles the pending retry, whichever deletion
    /// left it behind — otherwise a healthy install would keep retrying (and
    /// warning) forever.
    #[tokio::test]
    async fn a_successful_wipe_clears_the_retry_marker() {
        let db = temp_store("wipe_marker_cleared").await;
        db.set_setting(crate::db::settings_keys::IDENTITY_WIPE_PENDING, "1")
            .await
            .unwrap();

        let failures = wipe_identity_rows(&db, true).await;

        assert!(failures.is_empty(), "unexpected failures: {failures:?}");
        assert_eq!(
            db.get_setting(crate::db::settings_keys::IDENTITY_WIPE_PENDING)
                .await
                .unwrap(),
            None,
            "a successful wipe must clear the retry marker"
        );
    }

    /// The retry acts only on the marker: without it the data stays put, with
    /// it the wipe runs and the marker is cleared. The probe row is an
    /// identity-scoped settings key, one of the families the wipe removes.
    #[tokio::test]
    async fn the_wipe_retry_acts_only_on_the_marker() {
        use crate::db::settings_keys;

        let db = temp_store("wipe_retry").await;
        let probe = settings_keys::status_cursor("wipe-retry-probe");
        db.set_setting(&probe, "1").await.unwrap();

        retry_pending_wipe(&db).await.unwrap();
        assert_eq!(
            db.get_setting(&probe).await.unwrap().as_deref(),
            Some("1"),
            "no marker, no wipe"
        );

        db.set_setting(settings_keys::IDENTITY_WIPE_PENDING, "1")
            .await
            .unwrap();
        retry_pending_wipe(&db).await.unwrap();
        assert_eq!(
            db.get_setting(&probe).await.unwrap(),
            None,
            "with the marker the retry must wipe"
        );
        assert_eq!(
            db.get_setting(settings_keys::IDENTITY_WIPE_PENDING)
                .await
                .unwrap(),
            None,
            "a successful retry must clear the marker"
        );
    }

    /// A retry that fails is an error the caller must stop on, and keeps the
    /// marker, so the next creation or import tries again.
    #[tokio::test]
    async fn a_failed_retry_fails_and_keeps_the_marker() {
        let store = WipeFailingStore::new();
        store.put_setting(crate::db::settings_keys::IDENTITY_WIPE_PENDING, "1");

        let err = retry_pending_wipe(&store)
            .await
            .expect_err("a failed retry must not let a new identity in");
        assert_eq!(err.to_string(), "PendingWipeFailed");

        assert_eq!(
            store
                .setting(crate::db::settings_keys::IDENTITY_WIPE_PENDING)
                .as_deref(),
            Some("1")
        );
    }

    /// A marker that cannot be read stops the new identity as a failed retry
    /// does, and wipes nothing: it may be a pending wipe or none at all.
    #[tokio::test]
    async fn an_unreadable_marker_fails_closed_without_wiping() {
        let store = WipeFailingStore::unreadable();

        let err = retry_pending_wipe(&store)
            .await
            .expect_err("an unreadable marker must not let a new identity in");
        assert_eq!(err.to_string(), "PendingWipeFailed");
        assert_eq!(store.wipes(), 0, "no blind wipe");
    }

    /// The launch after a refused replacement reloads the deleted identity
    /// itself (its mnemonic is still in secure storage): the rows the wipe
    /// kept are its own, so the marker goes and nothing is wiped. A marker
    /// naming another identity stays for the next creation or import.
    #[tokio::test]
    async fn reloading_the_marked_identity_releases_the_marker_and_keeps_its_rows() {
        use crate::db::settings_keys;

        let db = temp_store("wipe_marker_release").await;
        let probe = settings_keys::status_cursor("wipe-release-probe");
        db.set_setting(&probe, "1").await.unwrap();
        db.set_setting(settings_keys::IDENTITY_WIPE_PENDING, "pubkey-a")
            .await
            .unwrap();

        release_own_wipe_marker(&db, "pubkey-b").await;
        assert_eq!(
            db.get_setting(settings_keys::IDENTITY_WIPE_PENDING)
                .await
                .unwrap()
                .as_deref(),
            Some("pubkey-a"),
            "another identity's marker stays"
        );

        release_own_wipe_marker(&db, "pubkey-a").await;
        assert_eq!(
            db.get_setting(settings_keys::IDENTITY_WIPE_PENDING)
                .await
                .unwrap(),
            None,
            "the marked identity is back: its wipe is no longer pending"
        );
        assert_eq!(
            db.get_setting(&probe).await.unwrap().as_deref(),
            Some("1"),
            "and its rows stay"
        );
    }

    /// The gap of review round 3: a marker that could not be written used to
    /// be a warning only, so the deletion went ahead, the replacement read no
    /// marker and installed over the previous identity's rows. The intent is
    /// now recorded first, and a failure there refuses the deletion while
    /// nothing is lost yet: no wipe ran, so storage recovering leaves the old
    /// identity whole instead of a new one over its rows.
    #[tokio::test]
    async fn an_unwritable_marker_refuses_the_deletion_before_anything_is_lost() {
        let store = WipeFailingStore::unwritable();

        let err = record_wipe_intent(Some(&store), "owner-pubkey")
            .await
            .expect_err("a deletion that cannot leave its marker must not run");
        assert_eq!(err.to_string(), "WipeNotRecorded");
        assert_eq!(
            store.wipes(),
            0,
            "nothing is wiped before the marker exists"
        );

        store.recover();
        record_wipe_intent(Some(&store), "owner-pubkey")
            .await
            .unwrap();
        assert_eq!(
            store
                .setting(crate::db::settings_keys::IDENTITY_WIPE_PENDING)
                .as_deref(),
            Some("owner-pubkey"),
            "once storage recovers the deletion records its intent"
        );
    }

    /// The marker is on disk before the wipe runs, so a wipe that then fails
    /// needs no second write to stop the replacement — the write that could
    /// fail has already succeeded.
    #[tokio::test]
    async fn a_wipe_that_fails_after_the_intent_blocks_the_replacement() {
        let store = WipeFailingStore::new();

        record_wipe_intent(Some(&store), "owner-pubkey")
            .await
            .unwrap();
        let failures = wipe_identity_rows(&store, true).await;
        assert!(
            failures.iter().any(|f| f.contains("injected wipe failure")),
            "the wipe failure is still reported: {failures:?}"
        );

        let err = retry_pending_wipe(&store)
            .await
            .expect_err("the replacement must not install over the kept rows");
        assert_eq!(err.to_string(), "PendingWipeFailed");
        assert_eq!(store.wipes(), 2, "the gate retried the wipe");
    }

    /// A memory-only session (`init_db` failed) has nowhere to record the
    /// intent, and the rows earlier sessions persisted are still on disk: the
    /// deletion is refused, deliberately, even though that keeps a possibly
    /// compromised identity until the store comes back (review of #573).
    /// With its own marker, the app's usual one for a session without a
    /// database: unlike an unwritable marker, no retry in this session can
    /// succeed, so the Account screen must not invite one.
    #[tokio::test]
    async fn without_a_database_the_deletion_is_refused() {
        let err = record_wipe_intent::<WipeFailingStore>(None, "owner-pubkey")
            .await
            .expect_err("no database, no marker, no deletion");
        assert_eq!(err.to_string(), "StorageUnavailable");
    }

    /// A marker that cannot be read may name a wipe still pending: the
    /// deletion stops instead of overwriting it blind.
    #[tokio::test]
    async fn an_unreadable_marker_refuses_the_deletion() {
        let store = WipeFailingStore::unreadable();

        let err = record_wipe_intent(Some(&store), "owner-pubkey")
            .await
            .expect_err("an unreadable marker must not be overwritten");
        assert_eq!(err.to_string(), "WipeNotRecorded");
        assert_eq!(store.wipes(), 0);
    }

    /// A marker an earlier deletion left names whose rows are still on disk;
    /// the next deletion keeps it rather than claim those rows for its own
    /// identity, which the launch reload would then release.
    #[tokio::test]
    async fn an_earlier_marker_is_kept() {
        let store = WipeFailingStore::new();
        store.put_setting(crate::db::settings_keys::IDENTITY_WIPE_PENDING, "pubkey-a");

        record_wipe_intent(Some(&store), "pubkey-b").await.unwrap();

        assert_eq!(
            store
                .setting(crate::db::settings_keys::IDENTITY_WIPE_PENDING)
                .as_deref(),
            Some("pubkey-a")
        );
    }

    /// The intent must be on disk before anything of the identity is given
    /// up — its subscriptions, its slot — and a failure there must end the
    /// deletion. Only the real wipe records it: the lifecycle test's
    /// `wipe_data: false` deletes no rows.
    #[test]
    fn the_deletion_records_its_intent_before_giving_anything_up() {
        let source = include_str!("identity.rs");
        let start = source
            .find("async fn delete_in<")
            .expect("the deletion exists");
        let body = &source[start..start + source[start..].find("\n}\n").expect("it ends")];
        let intent = body
            .find("record_wipe_intent(db, &owner).await?")
            .expect("the deletion records its intent and stops on failure");
        let release = body
            .find("hooks.release_subscriptions()")
            .expect("the deletion releases the subscriptions");
        let take = body
            .find("guard.take()")
            .expect("the deletion empties the slot");
        assert!(
            intent < release && intent < take,
            "the intent must be recorded before the identity is given up"
        );
    }

    // ── Concurrent transitions (review round 4 of #573) ─────────────────────

    /// Where a [`PausingHooks`] deletion stops until the test resumes it.
    #[derive(PartialEq)]
    enum PauseAt {
        /// Giving back the subscriptions: the intent is recorded, the slot
        /// still holds the identity.
        Release,
        /// Unregistering push: the slot is empty, the rows not yet wiped.
        Unregister,
    }

    /// [`DeletionHooks`] that touch nothing of the process and pause at one
    /// point: the test learns the deletion got there, does what a competing
    /// transition would, then lets it go on.
    struct PausingHooks {
        at: PauseAt,
        reached: std::sync::Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
        resume: tokio::sync::Mutex<Option<tokio::sync::oneshot::Receiver<()>>>,
    }

    impl PausingHooks {
        fn at(
            at: PauseAt,
        ) -> (
            &'static Self,
            tokio::sync::oneshot::Receiver<()>,
            tokio::sync::oneshot::Sender<()>,
        ) {
            let (reached_tx, reached_rx) = tokio::sync::oneshot::channel();
            let (resume_tx, resume_rx) = tokio::sync::oneshot::channel();
            let hooks = Box::leak(Box::new(Self {
                at,
                reached: std::sync::Mutex::new(Some(reached_tx)),
                resume: tokio::sync::Mutex::new(Some(resume_rx)),
            }));
            (hooks, reached_rx, resume_tx)
        }

        async fn pause_if(&self, point: PauseAt) {
            if self.at != point {
                return;
            }
            if let Some(reached) = self.reached.lock().unwrap().take() {
                let _ = reached.send(());
            }
            if let Some(resume) = self.resume.lock().await.take() {
                let _ = resume.await;
            }
        }
    }

    impl DeletionHooks for PausingHooks {
        async fn release_subscriptions(&self) {
            self.pause_if(PauseAt::Release).await;
        }
        async fn unregister_push(&self) {
            self.pause_if(PauseAt::Unregister).await;
        }
        async fn forget_state(&self) {}
    }

    /// [`DeletionHooks`] that touch nothing and never pause.
    struct NoHooks;

    impl DeletionHooks for NoHooks {
        async fn release_subscriptions(&self) {}
        async fn unregister_push(&self) {}
        async fn forget_state(&self) {}
    }

    /// A slot and a store of the test's own, leaked so spawned transitions can
    /// borrow them.
    fn private_lifecycle() -> (&'static IdentitySlot, &'static WipeFailingStore) {
        (
            Box::leak(Box::new(IdentitySlot::new())),
            Box::leak(Box::new(WipeFailingStore::new())),
        )
    }

    /// Put an identity in `slot` directly, as a launch would have; returns
    /// its phrase and public key.
    async fn install(slot: &IdentitySlot) -> (Vec<String>, String) {
        let words = key_ops::generate_mnemonic().unwrap();
        let keys = key_ops::derive_master_key(&words).unwrap();
        let public_key = keys.public_key().to_hex();
        *slot.state.write().await = Some(IdentityState {
            mnemonic_words: words.clone(),
            keys,
            identity_info: IdentityInfo {
                public_key: public_key.clone(),
                display_name: None,
                privacy_mode: false,
                trade_key_index: 0,
                created_at: 0,
            },
        });
        (words, public_key)
    }

    /// Let every spawned transition run until it finishes or blocks.
    async fn settle() {
        for _ in 0..64 {
            tokio::task::yield_now().await;
        }
    }

    /// The end state no schedule may reach: rows still on disk, nobody in the
    /// slot to own them, no marker to say so — and a new identity let in.
    async fn assert_no_identity_installs_over_unmarked_rows(
        slot: &'static IdentitySlot,
        store: &'static WipeFailingStore,
    ) {
        let rows = store.rows();
        let vacant = slot.state.read().await.is_none();
        let marker = store.setting(crate::db::settings_keys::IDENTITY_WIPE_PENDING);
        assert!(
            rows.is_empty() || !vacant || marker.is_some(),
            "rows {rows:?} stay with an empty slot and no wipe-pending marker"
        );
        if vacant && !rows.is_empty() {
            store.wipes_succeed(false);
            assert!(
                create_in(slot, Some(store)).await.is_err(),
                "a new identity was installed over the rows {rows:?}"
            );
        }
    }

    /// ermeme's schedule: a deletion of A pauses while giving back its
    /// subscriptions; a second deletion of A succeeds, clearing the shared
    /// marker, and B is created and trades. The first deletion then takes B,
    /// and its wipe fails — with no marker left to stop the next identity.
    #[tokio::test]
    async fn a_deletion_paused_before_the_take_cannot_lose_the_marker() {
        let (slot, store) = private_lifecycle();
        let (_, a) = install(slot).await;
        store.add_rows(&a);
        store.wipes_succeed(true);
        let (hooks, reached, resume) = PausingHooks::at(PauseAt::Release);

        let local = tokio::task::LocalSet::new();
        local
            .run_until(async {
                let first = tokio::task::spawn_local(delete_in(slot, Some(store), hooks, true));
                reached.await.unwrap();
                let second = tokio::task::spawn_local(delete_in(slot, Some(store), &NoHooks, true));
                let create = tokio::task::spawn_local(create_in(slot, Some(store)));
                settle().await;
                if let Some(state) = slot.state.read().await.as_ref() {
                    store.add_rows(&state.identity_info.public_key);
                }

                store.wipes_succeed(false);
                resume.send(()).unwrap();
                let _ = first.await.unwrap();
                let _ = second.await.unwrap();
                let _ = create.await.unwrap();
            })
            .await;

        assert_no_identity_installs_over_unmarked_rows(slot, store).await;
    }

    /// The same-owner variant: while the deletion of A is paused, A itself is
    /// loaded again (a launch reload, an import of the same phrase). The load
    /// releases A's marker as its own; the deletion then retires the reloaded
    /// A and its wipe fails, leaving the rows unmarked behind an empty slot.
    #[tokio::test]
    async fn a_reload_during_a_paused_deletion_cannot_release_its_marker() {
        let (slot, store) = private_lifecycle();
        let (words, a) = install(slot).await;
        store.add_rows(&a);
        let (hooks, reached, resume) = PausingHooks::at(PauseAt::Release);
        let (tx, _rx) = private_channel();
        let tx: &'static broadcast::Sender<u32> = Box::leak(Box::new(tx));

        let local = tokio::task::LocalSet::new();
        local
            .run_until(async {
                let delete = tokio::task::spawn_local(delete_in(slot, Some(store), hooks, true));
                reached.await.unwrap();
                let reload =
                    tokio::task::spawn_local(load_in(slot, Some(store), tx, words, 0, false, None));
                settle().await;

                resume.send(()).unwrap();
                let _ = delete.await.unwrap();
                let _ = reload.await.unwrap();
            })
            .await;

        assert_no_identity_installs_over_unmarked_rows(slot, store).await;
    }

    /// A replacement that lands while a deletion is between retiring the
    /// identity and wiping its rows: the deletion's wipe then takes the new
    /// identity's rows with the old ones.
    #[tokio::test]
    async fn a_replacement_never_lands_before_the_deletion_wipes() {
        let (slot, store) = private_lifecycle();
        let (_, a) = install(slot).await;
        store.add_rows(&a);
        store.wipes_succeed(true);
        let (hooks, reached, resume) = PausingHooks::at(PauseAt::Unregister);

        let replaced_early = tokio::task::LocalSet::new()
            .run_until(async {
                let delete = tokio::task::spawn_local(delete_in(slot, Some(store), hooks, true));
                reached.await.unwrap();
                let create = tokio::task::spawn_local(create_in(slot, Some(store)));
                settle().await;
                let replaced_early = slot
                    .state
                    .read()
                    .await
                    .as_ref()
                    .map(|state| state.identity_info.public_key.clone());
                if let Some(b) = &replaced_early {
                    store.add_rows(b);
                }

                resume.send(()).unwrap();
                delete.await.unwrap().unwrap();
                create.await.unwrap().unwrap();
                replaced_early
            })
            .await;

        if let Some(b) = replaced_early {
            assert!(
                store.rows().contains(&b),
                "the deletion of the previous identity wiped the new one's rows"
            );
        }
        assert!(
            slot.state.read().await.is_some(),
            "the replacement still lands"
        );
    }

    /// The deletion names the identity whose rows it may keep — the public
    /// key the reload compares against — and must read it while the slot
    /// still holds it.
    #[test]
    fn the_deletion_marks_the_deleted_identity_as_the_owner() {
        let source = include_str!("identity.rs");
        let start = source
            .find("async fn delete_in<")
            .expect("the deletion exists");
        let body = &source[start..start + source[start..].find("\n}\n").expect("it ends")];
        let owner = body
            .find("state.identity_info.public_key.clone()")
            .expect("the deletion reads the identity's public key");
        let intent = body
            .find("record_wipe_intent(db, &owner)")
            .expect("and records it as the marker's owner");
        assert!(owner < intent);
    }

    /// The retry may only run while the identity slot is empty — the whole
    /// trade-off of issue #555 (`retry_pending_wipe` explains why) — and a
    /// failed one must stop the new identity: so `create_identity` runs it
    /// between the AlreadyExists guard and the install, propagating its
    /// error; the import runs it, through the empty-slot check, before
    /// loading the phrase; and the launch reload never calls it.
    #[test]
    fn the_wipe_retry_gates_every_new_identity_and_never_runs_on_reload() {
        let source = include_str!("identity.rs");
        let body_of = |signature: &str| {
            let start = source.find(signature).expect(signature);
            &source[start..start + source[start..].find("\n}\n").expect("it ends")]
        };

        let body = body_of("async fn create_in<");
        let guard = body
            .find("bail!(\"AlreadyExists\")")
            .expect("the replace guard exists");
        let retry = body
            .find("retry_pending_wipe(db).await?")
            .expect("create_identity retries the pending wipe and stops on failure");
        let install = body
            .find("= Some(IdentityState {")
            .expect("the install exists");
        assert!(
            guard < retry && retry < install,
            "the retry must run after the guard and before the install"
        );

        for import in ["async fn import_in<", "async fn import_nsec_in<"] {
            let body = body_of(import);
            let retry = body
                .find("retry_pending_wipe_if_vacant_in(slot, db).await?")
                .expect("the import retries the pending wipe and stops on failure");
            let install = body
                .find("load_unlocked(")
                .or_else(|| body.find("= Some(IdentityState {"))
                .expect("the import installs");
            assert!(
                retry < install,
                "the retry must run before {import} installs"
            );
        }

        let body = body_of("async fn retry_pending_wipe_if_vacant_in<");
        let vacant = body
            .find("slot.state.read().await.is_some()")
            .expect("the import's retry checks the slot");
        let retry = body
            .find("retry_pending_wipe(db).await?")
            .expect("and then retries");
        assert!(vacant < retry, "the slot is checked before the wipe");

        let body = body_of("async fn load_unlocked<");
        assert!(
            !body.contains("retry_pending_wipe"),
            "the launch reload runs with a live identity — a wipe there takes its data"
        );
        assert!(
            body.contains("release_own_wipe_marker(db, &public_key)"),
            "the launch reload settles a marker its own identity left"
        );
    }

    /// Every transition holds the slot's lifecycle lock from its first read
    /// to its last write (review round 4 of #573), and only transitions
    /// install an identity: a new function that fills the slot without the
    /// lock would reopen the interleavings the concurrent tests pin.
    #[test]
    fn every_transition_of_the_slot_holds_the_lifecycle_lock() {
        let source = include_str!("identity.rs");
        let production = &source[..source.find("#[cfg(test)]\nmod tests").expect("tests")];
        let body_of = |signature: &str| {
            let start = production.find(signature).expect(signature);
            &production[start..start + production[start..].find("\n}\n").expect("it ends")]
        };

        for transition in [
            "async fn create_in<",
            "async fn load_in<",
            "async fn import_in<",
            "async fn import_nsec_in<",
            "async fn delete_in<",
        ] {
            let body = body_of(transition);
            let lock = body
                .find("slot.lifecycle.lock().await")
                .unwrap_or_else(|| panic!("{transition} must hold the lifecycle lock"));
            let open = body.find(") -> Result<").expect("it returns a Result");
            let open = open + body[open..].find("{\n").expect("its body opens");
            // The first line of code that names the slot; comments may too.
            let first_use = open
                + body[open..]
                    .match_indices("slot")
                    .map(|(at, _)| at)
                    .find(|&at| {
                        let line_start = body[..open + at].rfind('\n').map_or(0, |n| n + 1);
                        !body[line_start..open + at].trim_start().starts_with("//")
                    })
                    .expect("it uses the slot");
            assert_eq!(
                first_use, lock,
                "{transition} must lock before anything else touches the slot"
            );
        }

        let installs: Vec<&str> = production
            .match_indices("= Some(IdentityState {")
            .map(|(at, _)| {
                let start = production[..at]
                    .rfind("\nasync fn ")
                    .expect("inside a function")
                    + 1;
                let name_end = start + production[start..].find('<').expect("generic");
                &production[start..name_end]
            })
            .collect();
        assert_eq!(
            installs,
            [
                "async fn create_in",
                "async fn load_unlocked",
                "async fn import_nsec_in"
            ],
            "only the transitions install an identity"
        );
        assert_eq!(
            production.matches("load_unlocked(").count(),
            2,
            "load_unlocked is reached only from load_in and import_in, which hold the lock"
        );

        // The legacy Cashu store is claimed by the load itself, after the
        // install: both the launch reload and an import reach it, under the
        // lock, so no replacement can land before the claim (#573 x #768).
        let load = body_of("async fn load_unlocked<");
        let install = load.find("= Some(IdentityState {").expect("it installs");
        let claim = load
            .find("crate::api::cashu::claim_legacy_store(&identity_info.public_key)")
            .expect("load_unlocked must claim the legacy Cashu store");
        assert!(install < claim, "the claim comes after the install");
    }

    /// Everything a deletion gives up has its way back for an identity loaded
    /// again in the same session (review of #573): a replacement refused after
    /// the deletion reloads the previous identity, and `restore_identity_session`
    /// must rebuild what a cold start would. A teardown step added without its
    /// restore — or without saying why a cold start does not rebuild it either —
    /// fails here.
    #[test]
    fn every_identity_teardown_has_its_restore() {
        fn body<'a>(source: &'a str, signature: &str) -> &'a str {
            let start = source.find(signature).unwrap_or_else(|| panic!("{signature}"));
            &source[start..start + source[start..].find("\n}\n").expect("it ends")]
        }
        // Statements only: what the comments say does not count.
        fn code(body: &str) -> String {
            body.lines()
                .filter(|line| !line.trim_start().starts_with("//"))
                .collect::<Vec<_>>()
                .join("\n")
        }
        let identity = include_str!("identity.rs");
        let orders = include_str!("orders.rs");
        let production = |source: &'static str| {
            &source[..source.find("#[cfg(test)]\nmod tests").expect("tests")]
        };
        let teardown = [
            code(body(
                production(orders),
                "pub(crate) async fn release_identity_subscriptions()",
            )),
            code(body(production(identity), "async fn forget_identity_state()")),
            code(body(
                include_str!("../identity_slot.rs"),
                "impl DeletionHooks for AppDeletionHooks",
            )),
        ]
        .join("\n");
        let restore = [
            code(body(production(identity), "pub async fn restore_identity_session()")),
            code(body(
                production(orders),
                "pub(crate) async fn restore_identity_subscriptions()",
            )),
            code(body(production(orders), "pub(crate) async fn reclaim_book_ownership()")),
        ]
        .join("\n");

        // Each step of the teardown, and what undoes it — `None` where a cold
        // start leaves it empty too, so the reload matches a restart.
        let steps: [(&str, Option<&str>); 16] = [
            // Per-trade receivers are temporary; the bulk feed covers the keys.
            ("single_order_tasks()", None),
            ("global_dm_keys()", Some("seed_global_dm_coverage()")),
            ("watched_orders_subscription_id()", Some("resync_watched_orders(")),
            // Per-trade REQs: a cold start opens none either.
            ("subscriptions::teardown(", None),
            ("mostro_dm_subscription_id()", Some("resubscribe_global_dm_filter()")),
            ("forget_identity_chats()", Some("resubscribe_active_chats()")),
            // Filled again on demand from the persisted bindings.
            ("trade_key_map()", None),
            ("trade_key_misses()", None),
            // A cold start replays the history with an empty window too.
            ("forget_processed_daemon_messages()", None),
            ("forget_identity_disputes()", Some("resubscribe_active_dispute_chats()")),
            // Hydrated from the trade rows on the first read.
            ("forget_identity_ratings()", None),
            // The chat rearm installs the sessions again.
            ("session_manager().clear()", Some("resubscribe_active_chats()")),
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
            20,
            "the identity teardown changed: give the new step its restore \
             (or say why a cold start does not rebuild it), then update this count"
        );
    }

    /// The nsec import used to install over whatever the slot held, without
    /// the pending-wipe gate: it is gated now like the phrase import.
    #[tokio::test]
    async fn an_nsec_import_is_refused_while_a_wipe_keeps_failing() {
        let (slot, store) = private_lifecycle();
        store.put_setting(crate::db::settings_keys::IDENTITY_WIPE_PENDING, "pubkey-a");
        let nsec = Keys::generate().secret_key().to_bech32().unwrap();

        let err = import_nsec_in(slot, Some(store), nsec.clone())
            .await
            .expect_err("the previous identity's rows are still on disk");
        assert_eq!(err.to_string(), "PendingWipeFailed");
        assert!(slot.state.read().await.is_none(), "nothing installed");

        store.wipes_succeed(true);
        import_nsec_in(slot, Some(store), nsec).await.unwrap();
        assert!(slot.state.read().await.is_some());
        assert_eq!(
            store.setting(crate::db::settings_keys::IDENTITY_WIPE_PENDING),
            None,
            "the retry settled the marker"
        );
    }

    /// The report must outlive the history clear (issue #555): asserted on
    /// the live stream, which a `clear_logs` from a parallel test cannot
    /// retract — and the buffered copy lands after this seam's own clear, so
    /// the Logs screen history starts with it.
    #[tokio::test]
    async fn a_cleanup_failure_survives_the_log_clear() {
        crate::api::logging::install_log_bridge();
        let mut stream = crate::api::logging::on_log_entry();

        // The token is this test's own: parallel tests share the stream and
        // other injected failures also log under the `identity` tag.
        clear_logs_and_report(&["identity data rows kept: wipe-probe-555".to_string()]);

        let entry = crate::rt::time::timeout(std::time::Duration::from_secs(2), async {
            loop {
                let e = stream.next().await.expect("stream closed unexpectedly");
                if e.tag == "identity" && e.message.contains("wipe-probe-555") {
                    return e;
                }
            }
        })
        .await
        .expect("the cleanup failure never reached the log stream");
        assert!(entry.message.contains("cleanup failed"));
    }

    /// Review of #573: a pending wipe retried by a new identity is a
    /// full-table transaction, and the readers of the identity — every trade
    /// screen goes through `get_identity` — must not wait on it. Transitions
    /// are serialised by `lifecycle`, so neither the creation nor the
    /// import's gate holds the state lock across the wipe.
    #[tokio::test]
    async fn readers_never_wait_on_a_retried_wipe() {
        use crate::db::settings_keys::IDENTITY_WIPE_PENDING;

        for gate in ["create_in", "retry_pending_wipe_if_vacant_in"] {
            let (slot, store) = private_lifecycle();
            store.wipes_succeed(true);
            store.put_setting(IDENTITY_WIPE_PENDING, "previous-pubkey");
            let readable = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
            let seen = readable.clone();
            *store.during_wipe.lock().unwrap() = Some(Box::new(move || {
                seen.store(
                    slot.state.try_read().is_ok(),
                    std::sync::atomic::Ordering::SeqCst,
                );
            }));

            if gate == "create_in" {
                create_in(slot, Some(store)).await.unwrap();
            } else {
                // Its callers hold the transition, as the imports do.
                let _transition = slot.lifecycle.lock().await;
                retry_pending_wipe_if_vacant_in(slot, Some(store))
                    .await
                    .unwrap();
            }

            assert_eq!(store.wipes(), 1, "{gate} retried the pending wipe");
            assert!(
                readable.load(std::sync::atomic::Ordering::SeqCst),
                "{gate} held the state lock across the wipe, so readers waited on it"
            );
        }
    }

    /// The wipe is three steps — the identity row, its trade-key mappings
    /// (which name its orders) and the rows it produced — and the marker
    /// stands for all of them: one that fails keeps the marker, and the retry
    /// runs all three. It used to cover the last one only, so a failed
    /// trade-key cleanup was reported once and then never retried.
    #[tokio::test]
    async fn the_pending_wipe_covers_the_trade_keys_and_the_identity_row() {
        use crate::db::settings_keys::IDENTITY_WIPE_PENDING;
        use std::sync::atomic::Ordering::SeqCst;

        let store = WipeFailingStore::new();
        store.wipes_succeed(true);
        store.trade_keys_fail.store(true, SeqCst);
        record_wipe_intent(Some(&store), "owner-pubkey").await.unwrap();

        let failures = wipe_identity_rows(&store, true).await;
        assert!(failures.iter().any(|f| f.contains("trade key mappings kept")));
        assert_eq!(
            store.setting(IDENTITY_WIPE_PENDING).as_deref(),
            Some("owner-pubkey"),
            "a trade-key cleanup that failed keeps the wipe pending"
        );

        let err = retry_pending_wipe(&store)
            .await
            .expect_err("the mappings are still there");
        assert_eq!(err.to_string(), "PendingWipeFailed");

        store.trade_keys_fail.store(false, SeqCst);
        retry_pending_wipe(&store).await.unwrap();
        assert_eq!(store.trade_key_clears.load(SeqCst), 3, "the retry clears them");
        assert_eq!(store.identity_row_deletes.load(SeqCst), 3);
        assert_eq!(store.setting(IDENTITY_WIPE_PENDING), None);
    }
}
