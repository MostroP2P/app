/// Identity API — exposed to Flutter via flutter_rust_bridge.
///
/// Key storage model (Phase 3):
///   • On create/import: a random 32-byte `master_key` is generated.
///   • The BIP-39 seed (or raw nsec privkey) is encrypted with master_key
///     using ChaCha20-Poly1305 and stored in the DB.
///   • `master_key_hex` is returned to Dart, which persists it in
///     `flutter_secure_storage` (platform keychain).
///   • On app restart Dart reads master_key_hex and calls
///     `unlock_with_master_key()` to re-establish the session.
///   • PIN is stored as SHA-256(pin) in the settings table.
///
/// Trade key derivation:
///   • Path m/44'/1237'/38383'/0/N (N ≥ 1) derived from stored seed.
///   • nsec imports cannot derive BIP-32 trade keys.
///
/// DO NOT change the derivation path — it would break v1 recovery (R8).
use anyhow::{anyhow, bail, Context, Result};
use uuid::Uuid;

use crate::api::types::{IdentityInfo, NymIdentity};
use crate::crypto::{file_encrypt, keys};
use crate::storage::{IdentityRecord, Storage};

#[cfg(not(target_arch = "wasm32"))]
use crate::api::runtime::native::runtime_lock;

// ─── Result types ─────────────────────────────────────────────────────────────

/// Returned by `create_identity()`.
/// `mnemonic` MUST be shown to the user exactly once and then discarded.
/// `master_key_hex` MUST be persisted by Dart in flutter_secure_storage.
pub struct CreateIdentityResult {
    pub info: IdentityInfo,
    /// 12-word BIP-39 phrase — show once, never store.
    pub mnemonic: String,
    /// 64-hex-char master key — Dart stores in flutter_secure_storage.
    pub master_key_hex: String,
}

/// Returned by `import_from_mnemonic()` and `import_from_nsec()`.
pub struct ImportIdentityResult {
    pub info: IdentityInfo,
    /// 64-hex-char master key — Dart stores in flutter_secure_storage.
    pub master_key_hex: String,
}

/// Returned by `derive_trade_key()` and `get_trade_key()`.
pub struct TradeKeyInfo {
    /// BIP-32 index N (≥ 1).
    pub index: u32,
    /// Hex-encoded public key for this trade key.
    pub public_key: String,
}

// ─── Initialization ───────────────────────────────────────────────────────────

/// Open (or create) the SQLite database at `db_path`.
/// Must be called once at app startup before any other identity function.
#[cfg(not(target_arch = "wasm32"))]
pub async fn initialize(db_path: String) -> Result<()> {
    use crate::storage::sqlite::SqliteStorage;
    use crate::api::runtime::native::AppRuntime;

    let storage = SqliteStorage::open(&db_path)
        .await
        .context("open SQLite database")?;

    let mut guard = runtime_lock().lock().await;
    *guard = Some(AppRuntime {
        storage,
        master_key: None,
        identity_pubkey: None,
        relay_pool: None,
    });
    Ok(())
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

fn generate_master_key() -> [u8; 32] {
    use chacha20poly1305::aead::{KeyInit, OsRng};
    use chacha20poly1305::ChaCha20Poly1305;
    let key = ChaCha20Poly1305::generate_key(&mut OsRng);
    key.into()
}

pub(crate) fn encrypt_blob(data: &[u8], master_key: &[u8; 32]) -> Result<Vec<u8>> {
    file_encrypt::encrypt(data, master_key)
}

pub(crate) fn decrypt_blob(blob: &[u8], master_key: &[u8; 32]) -> Result<Vec<u8>> {
    file_encrypt::decrypt(blob, master_key)
}

/// Hash a PIN using Argon2id (memory-hard KDF) with a random salt.
/// The PHC string format encodes salt + params + hash — store as-is.
#[cfg(not(target_arch = "wasm32"))]
fn hash_pin(pin: &str) -> Result<String> {
    use argon2::{
        password_hash::{rand_core::OsRng, PasswordHasher, SaltString},
        Argon2,
    };
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(pin.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| anyhow!("argon2 hash: {}", e))
}

/// Verify a PIN against a stored Argon2id PHC string.
/// Uses constant-time comparison internally.
#[cfg(not(target_arch = "wasm32"))]
fn verify_pin(pin: &str, stored_phc: &str) -> bool {
    use argon2::{
        password_hash::{PasswordHash, PasswordVerifier},
        Argon2,
    };
    PasswordHash::new(stored_phc)
        .map(|h| Argon2::default().verify_password(pin.as_bytes(), &h).is_ok())
        .unwrap_or(false)
}

fn now_secs() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}

// ─── Identity CRUD ────────────────────────────────────────────────────────────

/// Create a new Nostr identity with a fresh BIP-39 mnemonic.
#[cfg(not(target_arch = "wasm32"))]
pub async fn create_identity() -> Result<CreateIdentityResult> {
    let mnemonic_str = keys::generate_mnemonic().context("generate mnemonic")?;

    let privkey = keys::derive_identity_key(&mnemonic_str)
        .context("derive identity key")?;
    let nostr_keys = keys::keys_from_privkey(&privkey).context("build nostr keys")?;
    let pubkey_hex = nostr_keys.public_key().to_hex();

    let master_key = generate_master_key();

    // Encrypt the 64-byte BIP-39 seed (needed for trade key derivation).
    let seed_bytes = bip39::Mnemonic::parse(&mnemonic_str)
        .context("parse mnemonic")?
        .to_seed("");
    let encrypted_seed = encrypt_blob(&seed_bytes, &master_key)
        .context("encrypt seed")?;

    let now = now_secs();
    let record = IdentityRecord {
        id: Uuid::new_v4().to_string(),
        public_key: pubkey_hex.clone(),
        encrypted_private_key: encrypted_seed,
        mnemonic_hash: keys::mnemonic_hash(&mnemonic_str),
        display_name: None,
        created_at: now,
        last_used_at: now,
        trade_key_index: 0,
        privacy_mode: false,
        derivation_path: "m/44'/1237'/38383'/0".to_string(),
    };

    let mut guard = runtime_lock().lock().await;
    let rt = guard
        .as_mut()
        .ok_or_else(|| anyhow!("runtime not initialized — call initialize() first"))?;

    rt.storage
        .save_identity(record)
        .await
        .map_err(|e| anyhow!("save identity: {}", e))?;

    rt.master_key = Some(master_key);
    rt.identity_pubkey = Some(pubkey_hex.clone());

    Ok(CreateIdentityResult {
        info: IdentityInfo {
            public_key: pubkey_hex,
            display_name: None,
            privacy_mode: false,
            trade_key_index: 0,
            created_at: now,
        },
        mnemonic: mnemonic_str,
        master_key_hex: hex::encode(master_key),
    })
}

/// Import an identity from a BIP-39 mnemonic phrase.
/// If `recover` is true, a session-recovery attempt will be made once nostr
/// is initialized (i.e., after `initialize_nostr()` completes).
#[cfg(not(target_arch = "wasm32"))]
pub async fn import_from_mnemonic(words: String, recover: bool) -> Result<ImportIdentityResult> {
    let _ = recover; // recovery wired in T036 nostr init phase

    let mnemonic = bip39::Mnemonic::parse(&words)
        .map_err(|_| anyhow!("invalid BIP-39 mnemonic"))?;

    let privkey = keys::derive_identity_key(&words).context("derive identity key")?;
    let nostr_keys = keys::keys_from_privkey(&privkey).context("build nostr keys")?;
    let pubkey_hex = nostr_keys.public_key().to_hex();

    let master_key = generate_master_key();
    let seed_bytes = mnemonic.to_seed("");
    let encrypted_seed = encrypt_blob(&seed_bytes, &master_key).context("encrypt seed")?;

    let now = now_secs();
    let record = IdentityRecord {
        id: Uuid::new_v4().to_string(),
        public_key: pubkey_hex.clone(),
        encrypted_private_key: encrypted_seed,
        mnemonic_hash: keys::mnemonic_hash(&words),
        display_name: None,
        created_at: now,
        last_used_at: now,
        trade_key_index: 0,
        privacy_mode: false,
        derivation_path: "m/44'/1237'/38383'/0".to_string(),
    };

    let mut guard = runtime_lock().lock().await;
    let rt = guard
        .as_mut()
        .ok_or_else(|| anyhow!("runtime not initialized"))?;

    rt.storage
        .save_identity(record)
        .await
        .map_err(|e| anyhow!("save identity: {}", e))?;

    rt.master_key = Some(master_key);
    rt.identity_pubkey = Some(pubkey_hex.clone());

    Ok(ImportIdentityResult {
        info: IdentityInfo {
            public_key: pubkey_hex,
            display_name: None,
            privacy_mode: false,
            trade_key_index: 0,
            created_at: now,
        },
        master_key_hex: hex::encode(master_key),
    })
}

/// Import an identity from a bech32-encoded private key (nsec…).
#[cfg(not(target_arch = "wasm32"))]
pub async fn import_from_nsec(nsec: String) -> Result<ImportIdentityResult> {
    let nostr_keys =
        nostr_sdk::Keys::parse(&nsec).map_err(|_| anyhow!("invalid nsec key format"))?;
    let pubkey_hex = nostr_keys.public_key().to_hex();

    // Extract raw private key bytes via the underlying secp256k1 key.
    let secp_sk: &nostr_sdk::secp256k1::SecretKey = nostr_keys.secret_key();
    let privkey_bytes: [u8; 32] = secp_sk.secret_bytes();

    let master_key = generate_master_key();
    let encrypted_privkey =
        encrypt_blob(&privkey_bytes, &master_key).context("encrypt private key")?;

    let now = now_secs();
    let record = IdentityRecord {
        id: Uuid::new_v4().to_string(),
        public_key: pubkey_hex.clone(),
        encrypted_private_key: encrypted_privkey,
        mnemonic_hash: String::new(), // no mnemonic for nsec imports
        display_name: None,
        created_at: now,
        last_used_at: now,
        trade_key_index: 0,
        privacy_mode: false,
        derivation_path: "nsec".to_string(), // marker: no BIP-32 seed
    };

    let mut guard = runtime_lock().lock().await;
    let rt = guard
        .as_mut()
        .ok_or_else(|| anyhow!("runtime not initialized"))?;

    rt.storage
        .save_identity(record)
        .await
        .map_err(|e| anyhow!("save identity: {}", e))?;

    rt.master_key = Some(master_key);
    rt.identity_pubkey = Some(pubkey_hex.clone());

    Ok(ImportIdentityResult {
        info: IdentityInfo {
            public_key: pubkey_hex,
            display_name: None,
            privacy_mode: false,
            trade_key_index: 0,
            created_at: now,
        },
        master_key_hex: hex::encode(master_key),
    })
}

/// Get the current identity info, or `None` if no identity has been created.
#[cfg(not(target_arch = "wasm32"))]
pub async fn get_identity() -> Result<Option<IdentityInfo>> {
    let guard = runtime_lock().lock().await;
    let rt = guard
        .as_ref()
        .ok_or_else(|| anyhow!("runtime not initialized"))?;

    let record = rt
        .storage
        .get_identity()
        .await
        .map_err(|e| anyhow!("storage: {}", e))?;

    Ok(record.map(|r| IdentityInfo {
        public_key: r.public_key,
        display_name: r.display_name,
        privacy_mode: r.privacy_mode,
        trade_key_index: r.trade_key_index,
        created_at: r.created_at,
    }))
}

/// Re-establish the session from a persisted master key (called at app startup).
/// Returns `true` if the key decrypts the stored identity successfully.
#[cfg(not(target_arch = "wasm32"))]
pub async fn unlock_with_master_key(master_key_hex: String) -> Result<bool> {
    let key_bytes = hex::decode(&master_key_hex)
        .map_err(|_| anyhow!("invalid master key hex string"))?;
    if key_bytes.len() != 32 {
        bail!("master key must be exactly 32 bytes (64 hex chars)");
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&key_bytes);

    let mut guard = runtime_lock().lock().await;
    let rt = guard
        .as_mut()
        .ok_or_else(|| anyhow!("runtime not initialized"))?;

    let record = rt
        .storage
        .get_identity()
        .await
        .map_err(|e| anyhow!("storage: {}", e))?;

    if let Some(rec) = record {
        // Verify the key is correct by attempting decryption.
        decrypt_blob(&rec.encrypted_private_key, &key)
            .map_err(|_| anyhow!("wrong master key — cannot decrypt identity"))?;
        rt.master_key = Some(key);
        rt.identity_pubkey = Some(rec.public_key);
        Ok(true)
    } else {
        Ok(false)
    }
}

/// Delete the current identity and all associated local data.
#[cfg(not(target_arch = "wasm32"))]
pub async fn delete_identity() -> Result<()> {
    let mut guard = runtime_lock().lock().await;
    let rt = guard
        .as_mut()
        .ok_or_else(|| anyhow!("runtime not initialized"))?;

    rt.storage
        .delete_identity()
        .await
        .map_err(|e| anyhow!("delete identity: {}", e))?;

    rt.master_key = None;
    rt.identity_pubkey = None;
    rt.relay_pool = None;

    Ok(())
}

// ─── PIN management ──────────────────────────────────────────────────────────

/// Set or update the device unlock PIN (4–8 digits).
#[cfg(not(target_arch = "wasm32"))]
pub async fn set_pin(pin: String) -> Result<()> {
    if pin.len() < 4 || pin.len() > 8 || !pin.chars().all(|c| c.is_ascii_digit()) {
        bail!("PIN must be 4–8 digits");
    }

    let guard = runtime_lock().lock().await;
    let rt = guard
        .as_ref()
        .ok_or_else(|| anyhow!("runtime not initialized"))?;

    rt.storage
        .get_identity()
        .await
        .map_err(|e| anyhow!("storage: {}", e))?
        .ok_or_else(|| anyhow!("no identity"))?;

    let phc = hash_pin(&pin)?;
    rt.storage
        .set_setting("pin_hash", &phc)
        .await
        .map_err(|e| anyhow!("save pin: {}", e))?;

    Ok(())
}

/// Enable biometric unlock on this device.
/// Returns `true` if biometric hardware is available (Phase 3: always true).
#[cfg(not(target_arch = "wasm32"))]
pub async fn enable_biometric() -> Result<bool> {
    let guard = runtime_lock().lock().await;
    let rt = guard
        .as_ref()
        .ok_or_else(|| anyhow!("runtime not initialized"))?;

    rt.storage
        .set_setting("biometric_enabled", "true")
        .await
        .map_err(|e| anyhow!("storage: {}", e))?;

    // TODO: real platform capability check wired via flutter_secure_storage in Phase 3+.
    Ok(true)
}

/// Verify a PIN.  Returns `true` if correct (or if no PIN is set).
#[cfg(not(target_arch = "wasm32"))]
pub async fn unlock(pin: String) -> Result<bool> {
    let guard = runtime_lock().lock().await;
    let rt = guard
        .as_ref()
        .ok_or_else(|| anyhow!("runtime not initialized"))?;

    let stored = rt
        .storage
        .get_setting("pin_hash")
        .await
        .map_err(|e| anyhow!("storage: {}", e))?;

    match stored {
        Some(phc) => Ok(verify_pin(&pin, &phc)),
        None => Ok(true), // No PIN set → always unlocked
    }
}

// ─── Trade key derivation ─────────────────────────────────────────────────────

/// Derive the next trade key (auto-increments index, persists new index to DB).
#[cfg(not(target_arch = "wasm32"))]
pub async fn derive_trade_key() -> Result<TradeKeyInfo> {
    let mut guard = runtime_lock().lock().await;
    let rt = guard
        .as_mut()
        .ok_or_else(|| anyhow!("runtime not initialized"))?;

    let master_key = rt
        .master_key
        .ok_or_else(|| anyhow!("identity is locked — call unlock_with_master_key first"))?;

    let record = rt
        .storage
        .get_identity()
        .await
        .map_err(|e| anyhow!("storage: {}", e))?
        .ok_or_else(|| anyhow!("no identity"))?;

    if record.derivation_path == "nsec" {
        bail!("BIP-32 trade key derivation is not available for nsec imports");
    }

    let seed_bytes = decrypt_blob(&record.encrypted_private_key, &master_key)
        .context("decrypt seed")?;
    let seed: [u8; 64] = seed_bytes
        .try_into()
        .map_err(|_| anyhow!("stored seed has wrong length"))?;

    let new_index = record.trade_key_index + 1;
    let trade_privkey =
        keys::derive_from_seed_at_index(&seed, new_index).context("derive trade key")?;
    let trade_nostr_keys =
        keys::keys_from_privkey(&trade_privkey).context("build trade nostr keys")?;
    let pubkey = trade_nostr_keys.public_key().to_hex();

    rt.storage
        .update_trade_key_index(new_index)
        .await
        .map_err(|e| anyhow!("update trade key index: {}", e))?;

    Ok(TradeKeyInfo {
        index: new_index,
        public_key: pubkey,
    })
}

/// Retrieve a previously derived trade key by index (1-based).
#[cfg(not(target_arch = "wasm32"))]
pub async fn get_trade_key(index: u32) -> Result<Option<TradeKeyInfo>> {
    if index == 0 {
        bail!("index 0 is the identity key, not a trade key");
    }

    let guard = runtime_lock().lock().await;
    let rt = guard
        .as_ref()
        .ok_or_else(|| anyhow!("runtime not initialized"))?;

    let master_key = rt
        .master_key
        .ok_or_else(|| anyhow!("identity is locked"))?;

    let record = rt
        .storage
        .get_identity()
        .await
        .map_err(|e| anyhow!("storage: {}", e))?
        .ok_or_else(|| anyhow!("no identity"))?;

    if index > record.trade_key_index || record.derivation_path == "nsec" {
        return Ok(None);
    }

    let seed_bytes =
        decrypt_blob(&record.encrypted_private_key, &master_key).context("decrypt seed")?;
    let seed: [u8; 64] = seed_bytes
        .try_into()
        .map_err(|_| anyhow!("stored seed has wrong length"))?;

    let trade_privkey =
        keys::derive_from_seed_at_index(&seed, index).context("derive trade key")?;
    let pubkey = keys::keys_from_privkey(&trade_privkey)
        .context("build trade nostr keys")?
        .public_key()
        .to_hex();

    Ok(Some(TradeKeyInfo {
        index,
        public_key: pubkey,
    }))
}

// ─── Nym identity ─────────────────────────────────────────────────────────────

/// Derive a deterministic pseudonym/icon/hue for any Nostr public key.
pub async fn get_nym_identity(pubkey: String) -> Result<NymIdentity> {
    let (pseudonym, icon_index, color_hue) = crate::crypto::nym::deterministic_nym(&pubkey);
    Ok(NymIdentity {
        pseudonym,
        icon_index,
        color_hue,
    })
}

// ─── Utility (sync) ──────────────────────────────────────────────────────────

/// Validate that the given words form a valid BIP-39 mnemonic (sync).
#[flutter_rust_bridge::frb(sync)]
pub fn validate_mnemonic_words(words: String) -> bool {
    keys::validate_mnemonic(&words)
}

/// Generate a fresh 12-word BIP-39 mnemonic without storing it (sync).
#[flutter_rust_bridge::frb(sync)]
pub fn generate_new_mnemonic() -> Result<String> {
    keys::generate_mnemonic()
}
