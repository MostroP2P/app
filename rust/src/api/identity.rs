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

// ── Global in-memory identity state ──────────────────────────────────────────

struct IdentityState {
    mnemonic_words: Vec<String>,
    keys: Keys,
    identity_info: IdentityInfo,
}

fn identity_lock() -> &'static RwLock<Option<IdentityState>> {
    static IDENTITY: OnceLock<RwLock<Option<IdentityState>>> = OnceLock::new();
    IDENTITY.get_or_init(|| RwLock::new(None))
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
    let mut guard = identity_lock().write().await;
    if guard.is_some() {
        bail!("AlreadyExists");
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

    *guard = Some(IdentityState {
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
    key_ops::validate_mnemonic(&words)?;
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
    let stored = match crate::db::app_db::db() {
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
    let trade_key_index = reconcile_and_publish_to(
        trade_key_index_tx(),
        trade_key_index,
        stored.as_ref(),
        &public_key,
    );

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

    let mut guard = identity_lock().write().await;
    *guard = Some(IdentityState {
        mnemonic_words: words,
        keys,
        identity_info: identity_info.clone(),
    });

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
    let info = load_identity_from_mnemonic(words, 0, privacy_mode, None).await?;
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

/// Import identity from an nsec (bech32-encoded Nostr secret key).
/// Note: nsec import produces a single key with no BIP-39 mnemonic backup.
pub async fn import_from_nsec(nsec: String) -> Result<IdentityInfo> {
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

    let mut guard = identity_lock().write().await;
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

/// Delete the in-memory identity state. Flutter must also clear
/// `flutter_secure_storage` after calling this.
pub async fn delete_identity() -> Result<()> {
    let mut guard = identity_lock().write().await;
    if guard.is_none() {
        bail!("NoIdentity");
    }
    *guard = None;
    drop(guard);

    // Clear the persisted trade key counter and per-order key mappings: both
    // belong to the deleted identity's derivation tree, and a new mnemonic
    // must start counting from zero instead of inheriting them. (If this
    // cleanup fails, the pubkey guard in `reconcile_trade_key_index` still
    // prevents the stale row from leaking into a different identity.)
    if let Some(db) = crate::db::app_db::db() {
        if let Err(e) = db.delete_identity().await {
            log::warn!("[identity] failed to clear persisted identity: {e}");
        }
        if let Err(e) = db.clear_trade_keys().await {
            log::warn!("[identity] failed to clear trade key mappings: {e}");
        }
    }

    // Last, so the cleanup warnings above are dropped too: buffered lines name
    // orders and counterparties of the identity being deleted, and the Logs
    // screen can still share them afterwards. The platform console keeps them.
    crate::api::logging::clear_logs();

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
            "[identity] no local store on web — the resynced trade-key counter              is durable only through the Flutter mirror"
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

/// Expose the in-memory `Keys` for other Rust modules (relay pool, gift wrap).
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
        // Regression (the bug #217 fixes): the next derived key is FRESH —
        // index 51, past every recovered trade — not a reused recovered index.
        let after = derive_trade_key_with(Some(&db), &tx).await.unwrap();
        assert_eq!(after.index, 51);

        crate::api::logging::forward_log(log::Level::Info, "identity_probe", "before delete");

        delete_identity().await.unwrap();
        assert!(get_identity().await.unwrap().is_none());
        assert!(
            !crate::api::logging::recent_logs()
                .iter()
                .any(|e| e.tag == "identity_probe"),
            "delete_identity must drop the buffered log history",
        );

        // Deleting again fails: there is no identity left.
        assert!(delete_identity().await.is_err());
    }
}
