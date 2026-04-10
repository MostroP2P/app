/// Nostr relay management API exposed to Flutter via flutter_rust_bridge.
///
/// Thin facade over `RelayPool` — keeps all async/relay logic in the pool
/// while exposing a flat function interface for the Dart side.
use anyhow::Result;
use nostr_sdk::Event;
use std::sync::Arc;
use tokio::sync::OnceCell;

use crate::api::types::{ConnectionState, RelayInfo};
use crate::nostr::relay_pool::RelayPool;
use crate::queue::outbox;

/// Global relay pool singleton, initialised once by `initialize()`.
static POOL: OnceCell<Arc<RelayPool>> = OnceCell::const_new();

fn pool() -> Result<&'static Arc<RelayPool>> {
    POOL.get().ok_or_else(|| anyhow::anyhow!("NotInitialized"))
}

/// Initialize the Nostr client with a relay list.
///
/// If `relays` is empty or `None`, uses preconfigured defaults.
pub async fn initialize(relays: Option<Vec<String>>) -> Result<()> {
    if POOL.get().is_some() {
        return Err(anyhow::anyhow!("AlreadyInitialized"));
    }

    let urls: Vec<String> = relays
        .unwrap_or_default()
        .into_iter()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect();

    let urls = if urls.is_empty() { default_relays() } else { urls };

    // get_or_try_init is atomic — only one caller creates the pool even if
    // two race past the is_some() guard above.
    POOL.get_or_try_init(|| async { RelayPool::new(urls).await })
        .await?;

    // Spawn a background task that flushes the outbox whenever the relay pool
    // transitions to Online.  The task exits when the broadcast channel closes.
    let pool_ref = POOL.get().unwrap().clone();
    tokio::spawn(async move {
        let mut rx = pool_ref.subscribe_connection_state();
        log::info!("[nostr] connection state watcher started");
        loop {
            match rx.recv().await {
                Ok(ConnectionState::Online) => {
                    log::info!("[nostr] relay pool ONLINE — fetching PoW, flushing queue, subscribing orders");
                    // Fetch PoW first so queued messages are wrapped with the
                    // correct difficulty before being flushed.
                    fetch_and_set_pow().await;
                    let _ = flush_message_queue().await;
                    // Start (or re-start) Kind 38383 order book subscription.
                    crate::api::orders::subscribe_orders().await;
                }
                Ok(state) => {
                    log::info!("[nostr] connection state changed: {state:?}");
                }
                Err(_) => {
                    log::warn!("[nostr] connection state channel closed");
                    break;
                }
            }
        }
    });

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
///
/// Iterates the in-memory outbox, publishes each pending event via the relay
/// pool, and applies exponential backoff on failure.  Events are pruned once
/// sent or after [`MAX_RETRIES`] failures.
///
/// Returns the count of messages successfully published in this pass.
pub async fn flush_message_queue() -> Result<u32> {
    let client = pool()?.client();
    let sent = outbox::outbox()
        .flush(|event_json| {
            let client = client.clone();
            async move {
                let event: Event = serde_json::from_str(&event_json)?;
                client
                    .send_event(&event)
                    .await
                    .map_err(|e| anyhow::anyhow!("{e}"))?;
                Ok(())
            }
        })
        .await;
    Ok(sent)
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
        loop {
            match self.rx.recv().await {
                Ok(state) => return Some(state),
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

/// Wrapper so flutter_rust_bridge can generate a Dart Stream.
pub struct RelayStatusStream {
    rx: tokio::sync::broadcast::Receiver<RelayInfo>,
}

impl RelayStatusStream {
    pub async fn next(&mut self) -> Option<RelayInfo> {
        loop {
            match self.rx.recv().await {
                Ok(info) => return Some(info),
                Err(tokio::sync::broadcast::error::RecvError::Lagged(_)) => continue,
                Err(tokio::sync::broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

/// Fetch the Mostro daemon's Kind 38385 (instance status) tags.
///
/// Queries the relay pool for a Kind 38385 event published by `mostro_pubkey_hex`.
/// Returns the raw tag list as `Vec<Vec<String>>` so the Dart layer can parse
/// each tag into the `MostroInstance` model.
///
/// Returns `None` if no matching event arrives within 10 seconds (relay
/// not reachable, or daemon has never published a Kind 38385 event).
pub async fn fetch_mostro_instance_tags(
    mostro_pubkey_hex: String,
) -> Result<Option<Vec<Vec<String>>>> {
    use nostr_sdk::prelude::*;
    use std::time::Duration;

    let client = pool()?.client();

    let pubkey = nostr_sdk::PublicKey::from_hex(&mostro_pubkey_hex)
        .map_err(|e| anyhow::anyhow!("invalid pubkey hex: {e}"))?;

    // Kind 38385 is a NIP-33 addressable event; the `d` tag uniquely identifies
    // the Mostro instance and equals the daemon's pubkey (hex). Adding the
    // d-tag constraint prevents the relay from returning a stale or unrelated
    // event from the same author.
    let filter = Filter::new()
        .kind(Kind::from(38385u16))
        .author(pubkey)
        .custom_tag(SingleLetterTag::lowercase(Alphabet::D), &mostro_pubkey_hex)
        .limit(1);

    let events = client
        .fetch_events(filter, Duration::from_secs(10))
        .await
        .map_err(|e| anyhow::anyhow!("fetch_events failed: {e}"))?;

    if let Some(event) = events.first() {
        let tags = event
            .tags
            .iter()
            .map(|t| t.as_slice().to_vec())
            .collect::<Vec<Vec<String>>>();
        Ok(Some(tags))
    } else {
        Ok(None)
    }
}

/// Fetch the Mostro daemon's PoW requirement from its Kind 38385 event
/// and store it globally.  Called each time the relay pool goes Online so
/// the value stays current if the daemon updates its configuration.
async fn fetch_and_set_pow() {
    let mostro_pubkey_hex = crate::config::active_mostro_pubkey();
    match fetch_mostro_instance_tags(mostro_pubkey_hex).await {
        Ok(Some(tags)) => {
            let pow_tag = tags
                .iter()
                .find(|t| t.first().map(|s| s.as_str()) == Some("pow"));
            let difficulty = match pow_tag.and_then(|t| t.get(1)) {
                Some(v) => match v.parse::<u8>() {
                    Ok(d) => d,
                    Err(_) => {
                        log::warn!("[nostr] malformed pow tag value: {v:?} — defaulting to 0");
                        0
                    }
                },
                None => 0,
            };
            crate::mostro::pow::set_pow(difficulty);
        }
        Ok(None) => {
            log::warn!("[nostr] no Kind 38385 event found — PoW defaults to 0");
            crate::mostro::pow::set_pow(0);
        }
        Err(e) => {
            log::warn!("[nostr] failed to fetch Kind 38385 for PoW: {e}");
        }
    }
}

// ── Internals ───────────────────────────────────────────────────────────────

fn default_relays() -> Vec<String> {
    crate::config::DEFAULT_RELAYS
        .iter()
        .map(|s| s.to_string())
        .collect()
}

/// Provide access to the global pool for other Rust modules (e.g. orders API).
#[allow(dead_code)]
pub(crate) fn get_pool() -> Result<&'static Arc<RelayPool>> {
    pool()
}
