/// BIP-32/39 key derivation for Mostro Mobile v2.
///
/// Derivation path: m/44'/1237'/38383'/0/N
///   N = 0  → master identity key (Nostr keypair)
///   N ≥ 1  → trade-specific keys (one per order)
///
/// DO NOT change the derivation path — changing it would break session
/// recovery for users migrating from v1 (research R8).
use anyhow::{bail, Context, Result};
use bip32::{DerivationPath, XPrv};
use bip39::Mnemonic;
use std::str::FromStr;

/// Base derivation path for all Mostro keys.
const BASE_PATH: &str = "m/44'/1237'/38383'/0";

/// Derive the identity keypair (N=0) from a BIP-39 mnemonic.
/// Returns the 32-byte secp256k1 private key.
pub fn derive_identity_key(mnemonic_words: &str) -> Result<[u8; 32]> {
    derive_key_at_index(mnemonic_words, 0)
}

/// Derive a trade-specific key at BIP-32 index N (N ≥ 1).
/// Returns the 32-byte secp256k1 private key.
pub fn derive_trade_key(mnemonic_words: &str, index: u32) -> Result<[u8; 32]> {
    if index == 0 {
        bail!("index 0 is reserved for the identity key; use derive_identity_key()");
    }
    derive_key_at_index(mnemonic_words, index)
}

fn derive_key_at_index(mnemonic_words: &str, index: u32) -> Result<[u8; 32]> {
    let mnemonic = Mnemonic::parse(mnemonic_words).context("invalid BIP-39 mnemonic")?;
    // BIP-39 seed with empty passphrase
    let seed = mnemonic.to_seed("");
    let path_str = format!("{}/{}", BASE_PATH, index);
    let path = DerivationPath::from_str(&path_str).context("invalid derivation path")?;

    let xprv = XPrv::derive_from_path(seed, &path)
        .context("BIP-32 key derivation failed")?;

    let raw_bytes: [u8; 32] = xprv.to_bytes();
    Ok(raw_bytes)
}

/// Generate a new random BIP-39 mnemonic (12 words).
pub fn generate_mnemonic() -> Result<String> {
    let mnemonic = Mnemonic::generate(12).context("failed to generate mnemonic")?;
    Ok(mnemonic.to_string())
}

/// Validate that the given words form a valid BIP-39 mnemonic.
pub fn validate_mnemonic(words: &str) -> bool {
    Mnemonic::parse(words).is_ok()
}

/// Compute a hash of the mnemonic for storage verification.
/// Never store the plaintext mnemonic — only this hash.
/// NOTE: In production, replace with sha2::Sha256::digest for a proper hash.
pub fn mnemonic_hash(words: &str) -> String {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    let mut hasher = DefaultHasher::new();
    words.hash(&mut hasher);
    format!("{:016x}", hasher.finish())
}

/// Derive a key directly from a 64-byte BIP-39 seed at the given index.
/// Used when the seed is already decrypted in memory (avoids re-parsing mnemonic).
pub fn derive_from_seed_at_index(seed: &[u8; 64], index: u32) -> Result<[u8; 32]> {
    if index == 0 {
        bail!("trade keys start at index 1; use derive_identity_key_from_seed for index 0");
    }
    let path_str = format!("{}/{}", BASE_PATH, index);
    let path = DerivationPath::from_str(&path_str).context("invalid derivation path")?;
    let xprv = XPrv::derive_from_path(seed, &path)
        .context("BIP-32 key derivation failed")?;
    Ok(xprv.to_bytes())
}

/// Derive the identity key (N=0) directly from a 64-byte BIP-39 seed.
pub fn derive_identity_key_from_seed(seed: &[u8; 64]) -> Result<[u8; 32]> {
    let path_str = format!("{}/0", BASE_PATH);
    let path = DerivationPath::from_str(&path_str).context("invalid derivation path")?;
    let xprv = XPrv::derive_from_path(seed, &path)
        .context("BIP-32 key derivation failed")?;
    Ok(xprv.to_bytes())
}

/// Derive a Nostr public key (hex string) from raw private key bytes.
pub fn pubkey_from_privkey(privkey_bytes: &[u8; 32]) -> Result<String> {
    let keys = keys_from_privkey(privkey_bytes)?;
    Ok(keys.public_key().to_hex())
}

/// Convert raw 32-byte private key to a nostr-sdk `Keys` struct.
pub fn keys_from_privkey(privkey_bytes: &[u8; 32]) -> Result<nostr_sdk::Keys> {
    let secp_key = nostr_sdk::secp256k1::SecretKey::from_slice(privkey_bytes)
        .context("invalid secp256k1 private key")?;
    let secret_key = nostr_sdk::SecretKey::from(secp_key);
    Ok(nostr_sdk::Keys::new(secret_key))
}
