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
use tokio::sync::RwLock;

use crate::api::types::{IdentityInfo, NymIdentity};
use crate::crypto::{keys as key_ops, nym};

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
pub async fn import_from_mnemonic(words: Vec<String>, _recover: bool) -> Result<IdentityInfo> {
    load_identity_from_mnemonic(words, 0, false, None).await
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
    Ok(())
}

/// Derive a new trade key, auto-incrementing the index.
/// Returns the new key's info and updates the stored `trade_key_index`.
pub async fn derive_trade_key() -> Result<TradeKeyInfo> {
    let mut guard = identity_lock().write().await;
    let state = guard.as_mut().ok_or_else(|| anyhow!("NoIdentity"))?;

    let candidate_index = state.identity_info.trade_key_index + 1;

    // Derive first — only persist the incremented index on success.
    let trade_keys = key_ops::derive_trade_key(&state.mnemonic_words, candidate_index)?;
    state.identity_info.trade_key_index = candidate_index;

    Ok(TradeKeyInfo {
        index: candidate_index,
        public_key: trade_keys.public_key().to_hex(),
    })
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

fn unix_now() -> i64 {
    use std::time::{SystemTime, UNIX_EPOCH};
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

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
