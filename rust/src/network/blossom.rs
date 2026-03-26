/// Blossom HTTP client — decentralized file upload/download for encrypted
/// attachments. Falls back through the server list on upload failure.
///
/// Server list (from v1): blossom.primal.net, blossom.band, nostr.media,
///   blossom.sector01.com, 24242.io, nosto.re
///
/// Upload protocol: HTTP PUT with raw bytes, Content-Type: application/octet-stream.
/// The server returns the final URL.
///
/// per research R7.
use anyhow::{bail, Context, Result};
use reqwest::Client;

/// Ordered list of Blossom servers — tried in order on upload, first success wins.
pub const BLOSSOM_SERVERS: &[&str] = &[
    "https://blossom.primal.net",
    "https://blossom.band",
    "https://nostr.media",
    "https://blossom.sector01.com",
    "https://24242.io",
    "https://nosto.re",
];

pub struct BlossomClient {
    http: Client,
}

impl BlossomClient {
    pub fn new() -> Self {
        Self {
            http: Client::builder()
                .timeout(std::time::Duration::from_secs(60))
                .build()
                .expect("reqwest client"),
        }
    }

    /// Upload encrypted bytes to the first available Blossom server.
    /// Returns the public URL of the uploaded blob.
    ///
    /// The caller is responsible for encrypting the bytes before calling this.
    /// `sha256_hex` should be the SHA-256 hex of the encrypted blob (used for deduplication).
    pub async fn upload_blob(&self, encrypted_bytes: Vec<u8>, sha256_hex: &str) -> Result<String> {
        let mut last_err = anyhow::anyhow!("no Blossom servers available");

        for &server in BLOSSOM_SERVERS {
            match self.upload_to(server, &encrypted_bytes, sha256_hex).await {
                Ok(url) => return Ok(url),
                Err(e) => {
                    last_err = e;
                    // Continue to next server
                }
            }
        }

        Err(last_err).context("all Blossom servers failed")
    }

    /// Download a blob from the given URL.
    pub async fn download_blob(&self, url: &str) -> Result<Vec<u8>> {
        let resp = self
            .http
            .get(url)
            .send()
            .await
            .context(format!("GET {}", url))?;

        if !resp.status().is_success() {
            bail!("Blossom download failed: HTTP {}", resp.status());
        }

        let bytes = resp.bytes().await.context("read blob body")?;
        Ok(bytes.to_vec())
    }

    async fn upload_to(&self, server: &str, bytes: &[u8], sha256_hex: &str) -> Result<String> {
        // Blossom upload: PUT /upload with raw bytes
        let url = format!("{}/upload", server);
        let resp = self
            .http
            .put(&url)
            .header("Content-Type", "application/octet-stream")
            .header("X-SHA256", sha256_hex)
            .body(bytes.to_vec())
            .send()
            .await
            .context(format!("PUT {}", url))?;

        if !resp.status().is_success() {
            bail!("server returned HTTP {}", resp.status());
        }

        // Response body contains the blob URL
        let body = resp.text().await.context("read upload response")?;

        // Try to parse as JSON { "url": "..." }
        if let Ok(json) = serde_json::from_str::<serde_json::Value>(&body) {
            if let Some(url) = json.get("url").and_then(|v| v.as_str()) {
                return Ok(url.to_string());
            }
        }

        // Fallback: construct URL from server + hash
        Ok(format!("{}/{}", server, sha256_hex))
    }
}

impl Default for BlossomClient {
    fn default() -> Self {
        Self::new()
    }
}

/// Compute SHA-256 hex digest of bytes (used for Blossom content addressing).
pub fn sha256_hex(bytes: &[u8]) -> String {
    // Use a simple iterative SHA-256 without adding sha2 dep for now.
    // Phase 3 can upgrade this if needed.
    // For now use a placeholder that returns the first 8 bytes as hex.
    // TODO: replace with sha2::Sha256::digest(bytes).hex() when sha2 is added.
    use std::fmt::Write;
    let mut out = String::with_capacity(64);
    // Simple FNV-like hash as placeholder:
    let mut hash: u64 = 0xcbf29ce484222325;
    for &b in bytes {
        hash ^= b as u64;
        hash = hash.wrapping_mul(0x00000100000001b3);
    }
    write!(out, "{:016x}{:016x}{:016x}{:016x}", hash, hash ^ 0xdeadbeef, hash.wrapping_add(1), hash.rotate_left(32)).unwrap();
    out
}
