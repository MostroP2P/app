/// Blossom blob storage client (BUD-01/BUD-02).
///
/// Uploads encrypted file blobs to Blossom servers and downloads them back.
/// Servers are tried in priority order; the first successful upload wins.
///
/// Protocol reference: <https://github.com/hzrd149/blossom>
use anyhow::{anyhow, bail, Result};
use sha2::{Digest, Sha256};

/// Maximum permitted file size for uploads (25 MB).
pub const MAX_BLOB_SIZE: usize = 25 * 1024 * 1024;

/// Ordered list of fallback Blossom servers.
/// Tried in sequence; the first server that accepts the upload is used.
pub const BLOSSOM_SERVERS: &[&str] = &[
    "https://blossom.primal.net",
    "https://blossom.band",
    "https://nostr.media",
    "https://blossom.sector01.com",
    "https://24242.io",
    "https://nosto.re",
];

/// Upload an encrypted blob to the first available Blossom server.
///
/// Returns the public URL of the uploaded blob.
///
/// The caller is responsible for encrypting `bytes` before calling this
/// function (see `crate::crypto::file_enc::encrypt_file`).
///
/// `server_url` may be provided to target a specific server; if `None`
/// the default server list is tried in order.
pub async fn upload_blob(
    bytes: Vec<u8>,
    mime_type: String,
    server_url: Option<&str>,
) -> Result<String> {
    if bytes.len() > MAX_BLOB_SIZE {
        bail!("FileTooLarge: {} bytes exceeds 25 MB limit", bytes.len());
    }

    let sha256 = hex::encode(Sha256::digest(&bytes));

    let servers: Vec<&str> = if let Some(url) = server_url {
        vec![url]
    } else {
        BLOSSOM_SERVERS.to_vec()
    };

    let mut last_err = String::new();
    for server in &servers {
        match try_upload(server, &sha256, &bytes, &mime_type).await {
            Ok(url) => return Ok(url),
            Err(e) => {
                last_err = format!("{server}: {e}");
                continue;
            }
        }
    }

    Err(anyhow!("UploadFailed: all servers rejected upload — last error: {last_err}"))
}

/// Download an encrypted blob from a Blossom URL.
///
/// Returns the raw bytes as stored on the server (still encrypted).
/// The caller is responsible for decrypting via
/// `crate::crypto::file_enc::decrypt_file`.
pub async fn download_blob(url: String) -> Result<Vec<u8>> {
    if url.is_empty() {
        bail!("DownloadFailed: URL must not be empty");
    }

    // Native build uses reqwest; WASM build would need a different HTTP client.
    #[cfg(not(target_arch = "wasm32"))]
    {
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(60))
            .build()
            .map_err(|e| anyhow!("HTTP client build failed: {e}"))?;

        let response = client
            .get(&url)
            .send()
            .await
            .map_err(|e| anyhow!("DownloadFailed: {e}"))?;

        if !response.status().is_success() {
            bail!("DownloadFailed: server returned {}", response.status());
        }

        // Reject early if Content-Length already exceeds the limit.
        if let Some(len) = response.content_length() {
            if len > MAX_BLOB_SIZE as u64 {
                bail!("DownloadFailed: Content-Length {len} exceeds 25 MB limit");
            }
        }

        let bytes = response
            .bytes()
            .await
            .map_err(|e| anyhow!("DownloadFailed: reading body: {e}"))?;

        if bytes.len() > MAX_BLOB_SIZE {
            bail!("DownloadFailed: {} bytes exceeds 25 MB limit", bytes.len());
        }

        Ok(bytes.to_vec())
    }

    #[cfg(target_arch = "wasm32")]
    {
        // TODO(WASM): Use web_sys Fetch API or gloo-net.
        let _ = url;
        Err(anyhow!("NotImplemented: Blossom download on WASM"))
    }
}

// ── Internals ────────────────────────────────────────────────────────────────

/// Attempt to upload a blob to a single Blossom server.
///
/// Uses `PUT /{sha256}` per BUD-01.  Builds a Kind-24242 Nostr auth event
/// and attaches it as `Authorization: Nostr {base64_event}` per BUD-02.
/// If no identity is loaded the upload is attempted without auth.
async fn try_upload(
    server: &str,
    sha256: &str,
    bytes: &[u8],
    mime_type: &str,
) -> Result<String> {
    #[cfg(not(target_arch = "wasm32"))]
    {
        use base64::{engine::general_purpose::STANDARD, Engine};
        use nostr_sdk::prelude::*;
        use std::time::{SystemTime, UNIX_EPOCH};

        let expiration = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs()
            + 600; // 10 minutes

        // Build and sign the auth event.
        // Fallback: if no identity is loaded (e.g. first-run upload before
        // identity is set), attempt upload without auth header.
        let auth_header: Option<String> =
            match crate::api::identity::get_active_keys().await {
                Err(e) => {
                    log::debug!("[blossom] no active keys for upload {sha256}: {e}");
                    None
                }
                Ok(keys) => {
                    let event = EventBuilder::new(
                        Kind::Custom(24242),
                        format!("Upload {sha256}"),
                    )
                    .tag(Tag::parse(["t", "upload"])?)
                    .tag(Tag::parse(["x", sha256])?)
                    .tag(Tag::parse(["expiration", &expiration.to_string()])?)
                    .sign_with_keys(&keys)?;

                    let event_json = event.as_json();
                    Some(format!("Nostr {}", STANDARD.encode(event_json)))
                }
            };

        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_secs(60))
            .build()
            .map_err(|e| anyhow!("HTTP client build failed: {e}"))?;

        let url = format!("{server}/{sha256}");
        let mut request = client
            .put(&url)
            .header("Content-Type", mime_type)
            .header("Content-Length", bytes.len().to_string())
            .body(bytes.to_vec());

        if let Some(auth) = auth_header {
            request = request.header("Authorization", auth);
        }

        let response = request
            .send()
            .await
            .map_err(|e| anyhow!("PUT {url} failed: {e}"))?;

        if response.status().is_success() {
            Ok(format!("{server}/{sha256}"))
        } else {
            Err(anyhow!(
                "server returned {} for PUT {url}",
                response.status()
            ))
        }
    }

    #[cfg(target_arch = "wasm32")]
    {
        let _ = (server, sha256, bytes, mime_type);
        Err(anyhow!("NotImplemented: Blossom upload on WASM"))
    }
}
