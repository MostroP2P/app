/// ChaCha20-Poly1305 AEAD file encryption for Blossom attachments.
///
/// Blob format: `[nonce:12 bytes][ciphertext + auth_tag:16 bytes]`
/// The 12-byte nonce is prepended to the ciphertext. chacha20poly1305
/// appends the 16-byte auth tag to the ciphertext automatically.
///
/// per research R7.
use anyhow::{bail, Result};
use chacha20poly1305::{
    aead::{Aead, AeadCore, KeyInit, OsRng},
    ChaCha20Poly1305, Key, Nonce,
};

/// Supported MIME types for file attachments (25 MB limit).
pub const MAX_FILE_SIZE: usize = 25 * 1024 * 1024;

/// Encrypt plaintext bytes using ChaCha20-Poly1305.
///
/// Returns `[nonce:12][ciphertext+tag:N+16]` — the full encrypted blob
/// suitable for uploading to a Blossom server.
pub fn encrypt(plaintext: &[u8], key: &[u8; 32]) -> Result<Vec<u8>> {
    if plaintext.len() > MAX_FILE_SIZE {
        bail!("file too large: {} bytes (max {})", plaintext.len(), MAX_FILE_SIZE);
    }

    let key = Key::from_slice(key);
    let cipher = ChaCha20Poly1305::new(key);
    let nonce = ChaCha20Poly1305::generate_nonce(&mut OsRng);

    let ciphertext = cipher
        .encrypt(&nonce, plaintext)
        .map_err(|e| anyhow::anyhow!("encryption failed: {}", e))?;

    // Prepend nonce to ciphertext
    let mut blob = Vec::with_capacity(12 + ciphertext.len());
    blob.extend_from_slice(nonce.as_slice());
    blob.extend_from_slice(&ciphertext);
    Ok(blob)
}

/// Decrypt a blob produced by [`encrypt`].
///
/// Input format: `[nonce:12][ciphertext+tag]`
pub fn decrypt(blob: &[u8], key: &[u8; 32]) -> Result<Vec<u8>> {
    if blob.len() < 12 + 16 {
        bail!("blob too short to be a valid encrypted blob ({} bytes)", blob.len());
    }

    let (nonce_bytes, ciphertext) = blob.split_at(12);
    let key = Key::from_slice(key);
    let cipher = ChaCha20Poly1305::new(key);
    let nonce = Nonce::from_slice(nonce_bytes);

    cipher
        .decrypt(nonce, ciphertext)
        .map_err(|e| anyhow::anyhow!("decryption failed (wrong key or corrupt blob): {}", e))
}

/// Generate a random 32-byte encryption key for use with [`encrypt`] / [`decrypt`].
pub fn generate_key() -> [u8; 32] {
    let key = ChaCha20Poly1305::generate_key(&mut OsRng);
    key.into()
}

/// Detect the FileType from a MIME type string.
pub fn file_type_from_mime(mime: &str) -> crate::api::types::FileType {
    use crate::api::types::FileType;
    match mime.split('/').next().unwrap_or("") {
        "image" => FileType::Image,
        "video" => FileType::Video,
        _ => FileType::Document,
    }
}
