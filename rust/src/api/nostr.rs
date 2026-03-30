/// Nostr relay management API exposed to Flutter via flutter_rust_bridge.
///
/// Thin facade over `RelayPool` — keeps all async/relay logic in the pool
/// while exposing a flat function interface for the Dart side.
use anyhow::Result;
use std::sync::Arc;
use tokio::sync::OnceCell;

use crate::api::types::{ConnectionState, RelayInfo};
use crate::nostr::relay_pool::RelayPool;

/// Global relay pool singleton, initialised once by `initialize()`.
static POOL: OnceCell<Arc<RelayPool>> = OnceCell::const_new();

fn pool() -> Result<&'static Arc<RelayPool>> {
    POOL.get().ok_or_else(|| anyhow::anyhow!("NotInitialized"))
}

/// Initialize the Nostr client with a relay list.
///
/// If `relays` is empty or `None`, uses preconfigured defaults.
pub async fn initialize(relays: Option<Vec<String>>) -> Result<()> {
    let urls = relays
        .filter(|v| !v.is_empty())
        .unwrap_or_else(default_relays);

    if POOL.get().is_some() {
        return Err(anyhow::anyhow!("AlreadyInitialized"));
    }

    let p = RelayPool::new(urls).await?;
    POOL.set(p)
        .map_err(|_| anyhow::anyhow!("AlreadyInitialized"))?;
    Ok(())
}

/// Add a new relay and connect to it.
pub async fn add_relay(url: String) -> Result<RelayInfo> {
    pool()?.add_relay(&url).await
}

/// Remove a relay and disconnect.
pub async fn remove_relay(url: String) -> Result<()> {
    pool()?.remove_relay(&url).await
}

/// Get all configured relays with current status.
pub async fn get_relays() -> Result<Vec<RelayInfo>> {
    Ok(pool()?.get_relays().await)
}

/// Get overall connection state.
pub async fn get_connection_state() -> Result<ConnectionState> {
    Ok(pool()?.connection_state().await)
}

/// Attempt to send all queued offline messages.
/// Returns count of successfully flushed messages.
///
/// TODO: Wire to outbox queue in Phase 7 when message queue persistence
/// is implemented.
pub async fn flush_message_queue() -> Result<u32> {
    let _pool = pool()?;
    // Placeholder — actual flush implementation requires the persistence
    // layer from Phase 7.
    Ok(0)
}

// ── Streams ─────────────────────────────────────────────────────────────────

/// Stream that emits when overall connection state changes.
pub async fn on_connection_state_changed() -> Result<ConnectionStateStream> {
    let rx = pool()?.subscribe_connection_state();
    Ok(ConnectionStateStream { rx })
}

/// Stream that emits when any individual relay's status changes.
pub async fn on_relay_status_changed() -> Result<RelayStatusStream> {
    let rx = pool()?.subscribe_relay_status();
    Ok(RelayStatusStream { rx })
}

/// Wrapper so flutter_rust_bridge can generate a Dart Stream.
pub struct ConnectionStateStream {
    rx: tokio::sync::broadcast::Receiver<ConnectionState>,
}

impl ConnectionStateStream {
    pub async fn next(&mut self) -> Option<ConnectionState> {
        self.rx.recv().await.ok()
    }
}

/// Wrapper so flutter_rust_bridge can generate a Dart Stream.
pub struct RelayStatusStream {
    rx: tokio::sync::broadcast::Receiver<RelayInfo>,
}

impl RelayStatusStream {
    pub async fn next(&mut self) -> Option<RelayInfo> {
        self.rx.recv().await.ok()
    }
}

// ── Internals ───────────────────────────────────────────────────────────────

fn default_relays() -> Vec<String> {
    vec![
        "wss://relay.mostro.network".to_string(),
        "wss://relay.damus.io".to_string(),
    ]
}

/// Provide access to the global pool for other Rust modules (e.g. orders API).
pub(crate) fn get_pool() -> Result<&'static Arc<RelayPool>> {
    pool()
}
