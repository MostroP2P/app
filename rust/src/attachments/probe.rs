//! The attachment round trip the web smoke test runs (#589 phase 4).
//!
//! On the web the transfer rides the browser's `fetch` from a cross-origin
//! isolated page and the cache is IndexedDB. Neither is exercised by the
//! native suite, and a page that dies there still passes every static check.
//! So the smoke test serves a Blossom endpoint on another origin and asks the
//! release bundle to run this: the real encryption, upload, verified download
//! and cache, against that server instead of the production list.
use anyhow::{anyhow, bail, Result};
use rand::RngCore;

use crate::crypto::file_enc;
use crate::db::Storage;
use crate::nostr::blossom;

/// Bytes sent: enough for more than one chunk on the way back.
const PROBE_BYTES: usize = 256 * 1024;

/// Encrypt random bytes, upload them to `server`, download them back through
/// the hash check, cache the blob, read it back from the cache and decrypt
/// it. Fails with what went wrong at the first step that did.
pub(crate) async fn roundtrip<S: Storage>(storage: &S, server: &str) -> Result<()> {
    let mut plaintext = vec![0u8; PROBE_BYTES];
    rand::rngs::OsRng.fill_bytes(&mut plaintext);
    let mut key = [0u8; 32];
    rand::rngs::OsRng.fill_bytes(&mut key);

    let blob = file_enc::encrypt_file(&plaintext, &key)?;
    let uploaded = blossom::upload_to(&[server], blob.clone()).await?;
    let downloaded = blossom::fetch_verified(&uploaded.url, |_| {}).await?;
    if downloaded != blob {
        bail!("probe: the downloaded blob differs from the uploaded one");
    }

    storage.save_attachment_blob(&uploaded.sha256, &downloaded).await?;
    let cached = storage
        .get_attachment_blob(&uploaded.sha256)
        .await?
        .ok_or_else(|| anyhow!("probe: the cache lost the blob"))?;
    if file_enc::decrypt_file(&cached, &key)? != plaintext {
        bail!("probe: the cached blob does not decrypt to what was sent");
    }
    Ok(())
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;
    use crate::db::sqlite::SqliteStorage;
    use crate::nostr::blossom::test_server::serve_with;
    use std::sync::{Arc, Mutex};

    /// A Blossom server that keeps what was PUT and serves it on GET.
    async fn blossom_server() -> String {
        let stored: Arc<Mutex<Vec<u8>>> = Arc::default();
        let (base, _) = serve_with(move |request| {
            if request.method == "PUT" {
                *stored.lock().unwrap() = request.body.clone();
                (200, Vec::new())
            } else {
                (200, stored.lock().unwrap().clone())
            }
        })
        .await;
        base
    }

    #[tokio::test]
    async fn a_blob_survives_upload_download_and_the_cache() {
        // Arrange
        let path = std::env::temp_dir().join(format!("probe-{}.db", rand::random::<u64>()));
        let storage = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();
        let server = blossom_server().await;

        // Act
        let result = roundtrip(&storage, &server).await;

        // Assert
        assert!(result.is_ok(), "{result:?}");
        drop(storage);
        let _ = std::fs::remove_file(&path);
    }

    #[tokio::test]
    async fn a_server_that_serves_other_bytes_fails_the_probe() {
        let path = std::env::temp_dir().join(format!("probe-{}.db", rand::random::<u64>()));
        let storage = SqliteStorage::open(path.to_str().unwrap()).await.unwrap();
        let (server, _) = serve_with(|_| (200, b"not the blob".to_vec())).await;

        let err = roundtrip(&storage, &server).await.unwrap_err();

        assert!(err.to_string().contains("does not match its hash"), "{err}");
        drop(storage);
        let _ = std::fs::remove_file(&path);
    }
}
