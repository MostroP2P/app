/// File encryption/decryption using ChaCha20-Poly1305.
///
/// Output format: `[12-byte nonce][ciphertext + 16-byte AEAD tag]`
///
/// The nonce is randomly generated per call and prepended so the receiver
/// can decrypt using the same key without any out-of-band nonce exchange.
///
/// The key should be a 32-byte ECDH shared secret derived via
/// `crate::crypto::ecdh::derive_nip04_shared_key` (for P2P messages) or
/// a BIP-32 trade key (for admin/dispute messages).
use anyhow::{anyhow, Result};
use chacha20poly1305::{
    aead::{Aead, KeyInit},
    ChaCha20Poly1305, Nonce,
};
use rand::RngCore;

/// Encrypt raw bytes with ChaCha20-Poly1305.
///
/// Returns `[nonce:12][ciphertext][tag:16]`.
pub fn encrypt_file(bytes: &[u8], key: &[u8; 32]) -> Result<Vec<u8>> {
    let cipher = ChaCha20Poly1305::new(key.into());

    let mut nonce_bytes = [0u8; 12];
    rand::rngs::OsRng.fill_bytes(&mut nonce_bytes);
    let nonce = Nonce::from_slice(&nonce_bytes);

    let ciphertext = cipher
        .encrypt(nonce, bytes)
        .map_err(|e| anyhow!("file encryption failed: {e}"))?;

    // Prepend nonce so the receiver can decrypt: [12-byte nonce][ciphertext+tag]
    let mut out = Vec::with_capacity(12 + ciphertext.len());
    out.extend_from_slice(&nonce_bytes);
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
