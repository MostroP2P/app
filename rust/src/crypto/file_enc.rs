/// File encryption/decryption using ChaCha20-Poly1305.
///
/// Output format: `[12-byte nonce][ciphertext + 16-byte AEAD tag]`, no
/// associated data — byte for byte what v1 (`MostroP2P/mobile`,
/// `EncryptionService.toBlob`) uploads to Blossom, so either app decrypts the
/// other's attachments (#589).
///
/// The nonce is randomly generated per call and prepended so the receiver
/// can decrypt using the same key without any out-of-band nonce exchange.
///
/// The key is [`attachment_key`]: the raw ECDH secret between the sender's
/// trade key and the counterpart (the peer's trade key in the P2P chat, the
/// solver's pubkey in the dispute chat).
use anyhow::{anyhow, Result};
use chacha20poly1305::{
    aead::{Aead, KeyInit},
    ChaCha20Poly1305, Nonce,
};
use rand::RngCore;

/// The ChaCha20-Poly1305 key for chat attachments between `own` and
/// `counterpart`: the raw x-coordinate of their ECDH, **not** hashed.
///
/// v1 derives exactly this (`Nip44.computeSharedSecret` →
/// `NostrUtils.sharedKeyToBytes`); the SHA-256 form of
/// `ecdh::derive_nip04_shared_key` would make every file unreadable across
/// the two apps. Symmetric: both parties derive the same key.
pub fn attachment_key(
    own: &nostr_sdk::prelude::Keys,
    counterpart: &nostr_sdk::prelude::PublicKey,
) -> Result<zeroize::Zeroizing<[u8; 32]>> {
    crate::crypto::ecdh::raw_shared_x(own.secret_key(), counterpart)
}

/// Encrypt raw bytes with ChaCha20-Poly1305.
///
/// Returns `[nonce:12][ciphertext][tag:16]`.
pub fn encrypt_file(bytes: &[u8], key: &[u8; 32]) -> Result<Vec<u8>> {
    let mut nonce_bytes = [0u8; 12];
    rand::rngs::OsRng.fill_bytes(&mut nonce_bytes);
    encrypt_file_with_nonce(bytes, key, &nonce_bytes)
}

/// [`encrypt_file`] with a caller-chosen nonce. Only for test vectors: a
/// nonce must never repeat under one key.
fn encrypt_file_with_nonce(bytes: &[u8], key: &[u8; 32], nonce_bytes: &[u8; 12]) -> Result<Vec<u8>> {
    let cipher = ChaCha20Poly1305::new(key.into());
    let nonce = Nonce::from_slice(nonce_bytes);

    let ciphertext = cipher
        .encrypt(nonce, bytes)
        .map_err(|e| anyhow!("file encryption failed: {e}"))?;

    // Prepend nonce so the receiver can decrypt: [12-byte nonce][ciphertext+tag]
    let mut out = Vec::with_capacity(12 + ciphertext.len());
    out.extend_from_slice(nonce_bytes);
    out.extend_from_slice(&ciphertext);
    Ok(out)
}

/// Decrypt bytes produced by `encrypt_file`.
///
/// Input must start with a 12-byte nonce followed by the AEAD ciphertext+tag.
pub fn decrypt_file(encrypted: &[u8], key: &[u8; 32]) -> Result<Vec<u8>> {
    if encrypted.len() < 12 + 16 {
        return Err(anyhow!(
            "encrypted data too short: {} bytes (minimum 28)",
            encrypted.len()
        ));
    }

    let (nonce_bytes, ciphertext) = encrypted.split_at(12);
    let cipher = ChaCha20Poly1305::new(key.into());
    let nonce = Nonce::from_slice(nonce_bytes);

    cipher
        .decrypt(nonce, ciphertext)
        .map_err(|e| anyhow!("file decryption failed: {e}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_key() -> [u8; 32] {
        let mut k = [0u8; 32];
        // Non-trivial test key
        for (i, b) in k.iter_mut().enumerate() {
            *b = (i * 7 + 13) as u8;
        }
        k
    }

    #[test]
    fn round_trip_small() {
        let key = test_key();
        let plaintext = b"hello, world!";
        let encrypted = encrypt_file(plaintext, &key).unwrap();
        let decrypted = decrypt_file(&encrypted, &key).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn round_trip_empty() {
        let key = test_key();
        let encrypted = encrypt_file(b"", &key).unwrap();
        let decrypted = decrypt_file(&encrypted, &key).unwrap();
        assert!(decrypted.is_empty());
    }

    #[test]
    fn wrong_key_fails() {
        let key = test_key();
        let mut bad_key = key;
        bad_key[0] ^= 0xFF;
        let encrypted = encrypt_file(b"secret", &key).unwrap();
        assert!(decrypt_file(&encrypted, &bad_key).is_err());
    }

    #[test]
    fn tampered_ciphertext_fails() {
        let key = test_key();
        let mut encrypted = encrypt_file(b"tamper test", &key).unwrap();
        // Flip a bit in the ciphertext body (after the 12-byte nonce)
        encrypted[15] ^= 0x01;
        assert!(decrypt_file(&encrypted, &key).is_err());
    }

    #[test]
    fn output_format_starts_with_nonce() {
        let key = test_key();
        let encrypted = encrypt_file(b"format test", &key).unwrap();
        // Output must be at least nonce(12) + tag(16) = 28 bytes
        assert!(encrypted.len() >= 28);
    }

    // Cross-client vector (#589), produced by running v1's own code
    // (MostroP2P/mobile v1.4.2: dart-nip44 @73379b8 `computeSharedSecret` →
    // `sharedKeyToBytes`, pointycastle ChaCha20Poly1305 → `toBlob`) over the
    // chat spec's test-vector trade keys, plaintext "Mostro v1 attachment
    // vector" and nonce 01..0c.
    const ALICE_SK: &str = "548f68890c49fa42f104c60352395e60ff030b0b407e955f1eed1400d6c0347a";
    const BOB_SK: &str = "f258e73f07386d37133718b6127f873dd7c391b8f43b331ff8254034a13d2943";
    const V1_FILE_KEY: &str = "def6633a53d07d1e829484c4d4bdbbeed2f4b14c21743e63871c174338e39475";
    const V1_BLOB: &str = "0102030405060708090a0b0cd56fcf60b9ccf71bd15877dc98c919bf9be866f8629872d02b1d4ef15dff60106750e95b4098ea21a1fc98";
    const V1_PLAINTEXT: &[u8] = b"Mostro v1 attachment vector";

    fn v1_parties() -> (nostr_sdk::prelude::Keys, nostr_sdk::prelude::Keys) {
        (
            nostr_sdk::prelude::Keys::parse(ALICE_SK).unwrap(),
            nostr_sdk::prelude::Keys::parse(BOB_SK).unwrap(),
        )
    }

    #[test]
    fn attachment_key_is_the_one_v1_derives() {
        let (alice, bob) = v1_parties();
        let from_alice = attachment_key(&alice, &bob.public_key()).unwrap();
        let from_bob = attachment_key(&bob, &alice.public_key()).unwrap();
        assert_eq!(hex::encode(*from_alice), V1_FILE_KEY);
        assert_eq!(*from_alice, *from_bob, "both parties must derive the same key");
        // Not the hashed NIP-04 form, which is what v2 used before #589.
        let hashed = crate::crypto::ecdh::derive_nip04_shared_key(&alice, &bob.public_key()).unwrap();
        assert_ne!(hex::encode(hashed), V1_FILE_KEY);
    }

    #[test]
    fn decrypts_a_blob_v1_encrypted() {
        let (alice, bob) = v1_parties();
        let key = attachment_key(&bob, &alice.public_key()).unwrap();
        let blob = hex::decode(V1_BLOB).unwrap();
        assert_eq!(decrypt_file(&blob, &key).unwrap(), V1_PLAINTEXT);
    }

    #[test]
    fn encrypts_byte_for_byte_like_v1() {
        let (alice, bob) = v1_parties();
        let key = attachment_key(&alice, &bob.public_key()).unwrap();
        let nonce: [u8; 12] = core::array::from_fn(|i| i as u8 + 1);
        let blob = encrypt_file_with_nonce(V1_PLAINTEXT, &key, &nonce).unwrap();
        assert_eq!(hex::encode(blob), V1_BLOB);
    }

    #[test]
    fn each_call_produces_different_ciphertext() {
        let key = test_key();
        let plaintext = b"same plaintext";
        let enc1 = encrypt_file(plaintext, &key).unwrap();
        let enc2 = encrypt_file(plaintext, &key).unwrap();
        // Different random nonces → different ciphertexts
        assert_ne!(enc1, enc2);
    }
}
