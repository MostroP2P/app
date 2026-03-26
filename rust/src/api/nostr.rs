/// Nostr bootstrap API — Phase 3 subset.
///
/// Initializes the relay pool from the in-session identity key and exposes
/// connection state / relay list queries to Flutter.
///
/// Only the native (non-WASM) variant is implemented here.  WASM uses
/// browser WebSocket APIs directly (Phase 4).
#[cfg(not(target_arch = "wasm32"))]
use anyhow::{bail, Result};
#[cfg(not(target_arch = "wasm32"))]
use std::sync::Arc;

#[cfg(not(target_arch = "wasm32"))]
use crate::api::identity::decrypt_blob;
#[cfg(not(target_arch = "wasm32"))]
use crate::api::runtime::native::runtime_lock;
#[cfg(not(target_arch = "wasm32"))]
use crate::api::types::{ConnectionState, RelayInfo};
#[cfg(not(target_arch = "wasm32"))]
use crate::crypto::keys::{derive_identity_key_from_seed, keys_from_privkey};
#[cfg(not(target_arch = "wasm32"))]
use crate::network::relay_pool::RelayPool;
#[cfg(not(target_arch = "wasm32"))]
use crate::storage::Storage;

/// Initialise the Nostr relay pool for the current unlocked identity.
///
/// Must be called after `identity::initialize` and
/// `identity::unlock_with_master_key` (or after `create_identity` /
/// `import_from_*` which set the master key in-session).
///
/// A second call while the pool is already alive is a no-op (returns `Ok(())`).
///
/// `relay_urls` — override the default relay list.  Pass `None` to use
/// the three preconfigured defaults.
#[cfg(not(target_arch = "wasm32"))]
pub async fn initialize_nostr(relay_urls: Option<Vec<String>>) -> Result<()> {
    let mut guard = runtime_lock().lock().await;
    let rt = match guard.as_mut() {
        Some(r) => r,
        None => bail!("runtime not initialised — call identity::initialize first"),
    };

    // Already connected — nothing to do.
    if rt.relay_pool.is_some() {
        return Ok(());
    }

    let master_key = match rt.master_key {
        Some(k) => k,
        None => bail!("identity is locked — call unlock_with_master_key first"),
    };

    let identity = rt
        .storage
        .get_identity()
        .await
        .map_err(|e| anyhow::anyhow!("{}", e))?
        .ok_or_else(|| anyhow::anyhow!("no identity found in storage"))?;

    // Decrypt the stored blob (seed or nsec privkey, depending on derivation_path).
    let decrypted = decrypt_blob(&identity.encrypted_private_key, &master_key)
        .map_err(|e| anyhow::anyhow!("decrypt identity key: {}", e))?;

    let privkey_bytes: [u8; 32] = if identity.derivation_path == "nsec" {
        // nsec import: blob is the raw 32-byte private key.
        decrypted
            .try_into()
            .map_err(|_| anyhow::anyhow!("nsec blob is not 32 bytes"))?
    } else {
        // BIP-32: blob is the 64-byte BIP-39 seed.
        let seed: [u8; 64] = decrypted
            .try_into()
            .map_err(|_| anyhow::anyhow!("seed blob is not 64 bytes"))?;
        derive_identity_key_from_seed(&seed)
            .map_err(|e| anyhow::anyhow!("derive identity key from seed: {}", e))?
    };

    let keys = keys_from_privkey(&privkey_bytes)?;

    let pool_arc = Arc::new(RelayPool::new(keys, relay_urls).await?);
    // start_notification_pump takes an Arc clone; the original stays in AppRuntime.
    Arc::clone(&pool_arc).start_notification_pump();
    rt.relay_pool = Some(pool_arc);
    Ok(())
}

/// Return the current aggregate relay connection state.
///
/// Returns `ConnectionState::Offline` when no pool has been initialised
/// so the Flutter UI can safely poll this before unlocking.
#[cfg(not(target_arch = "wasm32"))]
pub async fn get_connection_state() -> Result<ConnectionState> {
    let guard = runtime_lock().lock().await;
    let rt = match guard.as_ref() {
        Some(r) => r,
        None => return Ok(ConnectionState::Offline),
    };
    match &rt.relay_pool {
        Some(pool) => Ok(pool.connection_state().await),
        None => Ok(ConnectionState::Offline),
    }
}

/// Return a snapshot of all known relays and their status.
#[cfg(not(target_arch = "wasm32"))]
pub async fn get_relay_infos() -> Result<Vec<RelayInfo>> {
    let guard = runtime_lock().lock().await;
    let rt = match guard.as_ref() {
        Some(r) => r,
        None => return Ok(vec![]),
    };
    match &rt.relay_pool {
        Some(pool) => Ok(pool.relay_infos().await),
        None => Ok(vec![]),
    }
}

/// Gracefully disconnect and drop the relay pool (e.g., on sign-out).
#[cfg(not(target_arch = "wasm32"))]
pub async fn disconnect_nostr() -> Result<()> {
    let mut guard = runtime_lock().lock().await;
    if let Some(rt) = guard.as_mut() {
        if let Some(pool) = rt.relay_pool.take() {
            pool.disconnect().await;
        }
    }
    Ok(())
}
