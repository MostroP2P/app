/// ECDH shared-key derivation for P2P trade chat encryption.
///
/// Encryption model: each party encrypts outbound messages with their trade
/// key + the peer's trade public key, producing a NIP-44 ciphertext.
/// Both parties derive the same conversation key independently.
use anyhow::{anyhow, Result};
use nostr_sdk::prelude::*;
use nostr_sdk::nips::nip44;

/// Derive a 32-byte shared secret using NIP-04 semantics:
///   `SHA-256(x-coordinate of ECDH(privA, pubB))`
///
/// This is symmetric — `derive_nip04_shared_key(alice, bob_pub) == derive_nip04_shared_key(bob, alice_pub)`.
///
/// Use this when raw key bytes are needed for symmetric operations such as
/// file-attachment encryption with `chacha20poly1305`.  For end-to-end trade
/// chat use `encrypt_message` / `decrypt_message` directly, which apply the
/// full NIP-44 v2 protocol (including HKDF key derivation) internally.
pub fn derive_nip04_shared_key(my_keys: &Keys, peer_pubkey: &PublicKey) -> Result<[u8; 32]> {
    ecdh_sha256(my_keys.secret_key(), peer_pubkey)
}

/// Encrypt `plaintext` from `my_keys` to `peer_pubkey` using NIP-44 v2.
pub fn encrypt_message(my_keys: &Keys, peer_pubkey: &PublicKey, plaintext: &str) -> Result<String> {
    nip44::encrypt(my_keys.secret_key(), peer_pubkey, plaintext, nip44::Version::V2)
        .map_err(|e| anyhow!("NIP-44 encrypt failed: {e}"))
}

/// Decrypt a NIP-44 ciphertext sent by `sender_pubkey` to `my_keys`.
pub fn decrypt_message(
    my_keys: &Keys,
    sender_pubkey: &PublicKey,
    ciphertext: &str,
) -> Result<String> {
    nip44::decrypt(my_keys.secret_key(), sender_pubkey, ciphertext)
        .map_err(|e| anyhow!("NIP-44 decrypt failed: {e}"))
}

// ── Internal ─────────────────────────────────────────────────────────────────

/// Compute a 32-byte shared secret compatible with NIP-04:
///   SHA-256(x-coordinate of ECDH(privkey, pubkey))
///
/// This is used when raw bytes are needed (e.g. for file-attachment
/// symmetric encryption with `chacha20poly1305`).
fn ecdh_sha256(secret: &nostr_sdk::prelude::SecretKey, peer: &PublicKey) -> Result<[u8; 32]> {
    use k256::ecdh::diffie_hellman;
    use sha2::{Digest, Sha256};

    // nostr-sdk SecretKey wraps secp256k1 — extract the inner key bytes.
    let secret_bytes: [u8; 32] = secret.to_secret_bytes();

    let scalar = k256::SecretKey::from_bytes((&secret_bytes).into())
        .map_err(|e| anyhow!("invalid secret scalar: {e}"))?;

    let peer_bytes = hex::decode(peer.to_hex())
        .map_err(|e| anyhow!("peer pubkey hex decode: {e}"))?;
    let peer_point = k256::PublicKey::from_sec1_bytes(&compress_from_xonly(&peer_bytes)?)
        .map_err(|e| anyhow!("invalid peer pubkey: {e}"))?;

    // Use the proper k256 Diffie-Hellman function.
    let shared = diffie_hellman(scalar.to_nonzero_scalar(), peer_point.as_affine());
    let x_bytes = shared.raw_secret_bytes();

    let mut hasher = Sha256::new();
    hasher.update(x_bytes);
    Ok(hasher.finalize().into())
}

/// Convert a 32-byte x-only pubkey to a 33-byte compressed SEC1 point.
///
/// BIP-340 (Schnorr / Nostr) defines x-only pubkeys as always having an even
/// Y coordinate, so the SEC1 prefix is unconditionally `0x02`. This is not
/// a guess — it is the normative parity assumption of the Nostr protocol.
fn compress_from_xonly(xonly: &[u8]) -> Result<Vec<u8>> {
    if xonly.len() != 32 {
        return Err(anyhow!("expected 32-byte x-only pubkey, got {}", xonly.len()));
    }
    let mut out = Vec::with_capacity(33);
    out.push(0x02); // even Y — BIP-340/Nostr convention
    out.extend_from_slice(xonly);
    Ok(out)
}
