/// Relay pool — manages connections to Nostr relays.
///
/// Subscribes to:
///   - Kind 38383 (public order book, `s=Pending` tag)
///   - Kind 1059 (NIP-59 Gift Wrap, p-tagged to our trade keys)
///
/// Connection state is derived: Online if ≥1 relay connected,
/// Reconnecting if attempting, Offline otherwise.
use anyhow::{anyhow, Result};
use nostr_sdk::prelude::*;
// The SDK re-exports its own `RelayStatus` via the prelude. Alias it to avoid
// conflicting with our internal `RelayStatus` from `crate::api::types`.
use nostr_sdk::RelayStatus as SdkRelayStatus;
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tokio::sync::{broadcast, RwLock};

use crate::api::types::{ConnectionState, RelayInfo, RelaySource, RelayStatus};
use crate::nostr::order_events::pending_orders_filter;

const KIND_GIFT_WRAP: u16 = 1059;
/// How often the background task polls each relay's SDK status (seconds).
const STATUS_POLL_INTERVAL_SECS: u64 = 2;

/// Shared relay pool state.
pub struct RelayPool {
    client: Arc<Client>,
    relays: Arc<RwLock<Vec<RelayInfo>>>,
    conn_tx: broadcast::Sender<ConnectionState>,
    relay_tx: broadcast::Sender<RelayInfo>,
}

impl RelayPool {
    /// Create a new pool with the given relay URLs.
    pub async fn new(relay_urls: Vec<String>) -> Result<Arc<Self>> {
        let ephemeral_keys = Keys::generate();
        let client = Arc::new(Client::new(ephemeral_keys));

        let (conn_tx, _) = broadcast::channel(16);
        let (relay_tx, _) = broadcast::channel(64);

        let pool = Arc::new(Self {
            client: client.clone(),
            relays: Arc::new(RwLock::new(Vec::new())),
            conn_tx,
            relay_tx,
        });

        for url in relay_urls {
            pool.add_relay_internal(&url, RelaySource::Default).await?;
        }

        client.connect().await;

        // Give the SDK a moment to initiate WebSocket handshakes before the
        // first status poll.  Without this the initial broadcast is always
        // Reconnecting (every relay is still in Pending/Connecting state).
        tokio::time::sleep(Duration::from_millis(500)).await;

        // Broadcast initial connection state after all relays are wired up.
        pool.broadcast_connection_state().await;

        pool.spawn_status_monitor();
        Ok(pool)
    }

    async fn add_relay_internal(&self, url: &str, source: RelaySource) -> Result<RelayInfo> {
        self.client
            .add_relay(url)
            .await
            .map_err(|e| anyhow!("add relay failed: {e}"))?;

        let info = RelayInfo {
            url: url.to_string(),
            is_active: true,
            is_default: matches!(source, RelaySource::Default),
            source,
            is_blacklisted: false,
            status: RelayStatus::Connecting,
            last_connected_at: None,
            last_error: None,
        };

        self.relays.write().await.push(info.clone());
        let _ = self.relay_tx.send(info.clone());
        self.broadcast_connection_state().await;
        Ok(info)
    }

    /// Add a relay and connect to it.
    pub async fn add_relay(&self, url: &str) -> Result<RelayInfo> {
        let relays = self.relays.read().await;
        if relays.iter().any(|r| r.url == url) {
            return Err(anyhow!("RelayAlreadyExists"));
        }
        drop(relays);
        self.add_relay_internal(url, RelaySource::UserAdded).await
    }

    /// Remove a relay and disconnect.
    pub async fn remove_relay(&self, url: &str) -> Result<()> {
        let mut relays = self.relays.write().await;
        let active_count = relays.iter().filter(|r| r.is_active).count();
        if active_count <= 1 {
            return Err(anyhow!("LastRelay"));
        }
        let pos = relays
            .iter()
            .position(|r| r.url == url)
            .ok_or_else(|| anyhow!("RelayNotFound"))?;
        let mut removed = relays.remove(pos);
        removed.status = RelayStatus::Disconnected;
        drop(relays);

        self.client
            .remove_relay(url)
            .await
            .map_err(|e| anyhow!("remove relay failed: {e}"))?;

        let _ = self.relay_tx.send(removed);
        self.broadcast_connection_state().await;
        Ok(())
    }

    pub async fn get_relays(&self) -> Vec<RelayInfo> {
        self.relays.read().await.clone()
    }

    pub async fn connection_state(&self) -> ConnectionState {
        derive_connection_state(&self.relays.read().await)
    }

    pub fn subscribe_connection_state(&self) -> broadcast::Receiver<ConnectionState> {
        self.conn_tx.subscribe()
    }

    pub fn subscribe_relay_status(&self) -> broadcast::Receiver<RelayInfo> {
        self.relay_tx.subscribe()
    }

    /// Re-subscribe to Kind 38383 (public orders) and Kind 1059 (gift wraps)
    /// after a reconnect or cold start, respawning per-trade gift-wrap workers.
    ///
    /// `trade_keys` is a list of `(trade_pubkey, trade_index)` pairs gathered
    /// from persisted state (e.g. the trade-key DB table).  For each pair this
    /// method:
    /// 1. Adds the pubkey to the bulk Kind 1059 relay filter so events are
    ///    delivered to this client.
    /// 2. Spawns a `subscribe_gift_wraps` worker (same as `create_order` does)
    ///    so decryption keys are available and daemon responses are routed.
    ///
    /// Kind 38383 processing is handled by `orders::subscribe_orders()`.
    pub async fn subscribe_order_and_dm_feeds(
        &self,
        trade_keys: Vec<(PublicKey, u32)>,
    ) -> Result<()> {
        let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&crate::config::active_mostro_pubkey())
            .map_err(|e| anyhow!("invalid mostro pubkey: {e}"))?;
        let order_filter = pending_orders_filter(&mostro_pubkey);
        self.client
            .subscribe(order_filter, None)
            .await
            .map_err(|e| anyhow!("order subscribe failed: {e}"))?;

        let pubkeys: Vec<PublicKey> = trade_keys.iter().map(|(pk, _)| *pk).collect();
        if !pubkeys.is_empty() {
            let dm_filter = Filter::new()
                .kind(Kind::from(KIND_GIFT_WRAP))
                .pubkeys(pubkeys);
            self.client
                .subscribe(dm_filter, None)
                .await
                .map_err(|e| anyhow!("dm subscribe failed: {e}"))?;

            // Respawn per-trade gift-wrap workers so each trade key's decrypt
            // path is live.  Without this, the relay delivers events but no
            // worker is running to unwrap and route them.
            for (pubkey, trade_index) in trade_keys {
                crate::api::orders::subscribe_gift_wraps(pubkey, trade_index).await;
            }
        }

        Ok(())
    }

    pub fn client(&self) -> Arc<Client> {
        self.client.clone()
    }

    // ── Internal helpers ──────────────────────────────────────────────────────

    async fn broadcast_connection_state(&self) {
        let state = derive_connection_state(&self.relays.read().await);
        let _ = self.conn_tx.send(state);
    }

    /// Spawn a background task that polls each relay's SDK status every
    /// `STATUS_POLL_INTERVAL_SECS` seconds and broadcasts changes on
    /// `relay_tx` / `conn_tx` when a relay transitions between states.
    ///
    /// `RelayPoolNotification` in nostr-sdk 0.44 does not expose relay-level
    /// status transitions, so polling `client.relay(url).status()` is the
    /// available mechanism.
    fn spawn_status_monitor(self: &Arc<Self>) {
        let client = self.client.clone();
        let relays = self.relays.clone();
        let conn_tx = self.conn_tx.clone();
        let relay_tx = self.relay_tx.clone();

        tokio::spawn(async move {
            loop {
                tokio::time::sleep(Duration::from_secs(STATUS_POLL_INTERVAL_SECS)).await;

                let relay_urls: Vec<String> =
                    relays.read().await.iter().map(|r| r.url.clone()).collect();

                let mut any_changed = false;

                for url in relay_urls {
                    let Ok(sdk_relay) = client.relay(&url).await else {
                        continue;
                    };
                    let new_status = map_sdk_status(sdk_relay.status());

                    let mut relays_w = relays.write().await;
                    if let Some(info) = relays_w.iter_mut().find(|r| r.url == url) {
                        if info.status != new_status {
                            info.status = new_status;
                            if matches!(info.status, RelayStatus::Connected) {
                                info.last_connected_at = Some(unix_now());
                            }
                            any_changed = true;
                            let _ = relay_tx.send(info.clone());
                        }
                    }
                    drop(relays_w);
                }

                if any_changed {
                    let state = derive_connection_state(&relays.read().await);
                    let _ = conn_tx.send(state);
                }
            }
        });
    }
}

// ── Pure helpers ──────────────────────────────────────────────────────────────

fn derive_connection_state(relays: &[RelayInfo]) -> ConnectionState {
    let any_connected = relays
        .iter()
        .any(|r| matches!(r.status, RelayStatus::Connected));
    let any_connecting = relays
        .iter()
        .any(|r| matches!(r.status, RelayStatus::Connecting));

    if any_connected {
        ConnectionState::Online
    } else if any_connecting {
        ConnectionState::Reconnecting
    } else {
        ConnectionState::Offline
    }
}

/// Map an SDK `RelayStatus` to our internal `RelayStatus`.
fn map_sdk_status(s: SdkRelayStatus) -> RelayStatus {
    match s {
        SdkRelayStatus::Connected => RelayStatus::Connected,
        SdkRelayStatus::Connecting | SdkRelayStatus::Pending => RelayStatus::Connecting,
        SdkRelayStatus::Disconnected
        | SdkRelayStatus::Terminated
        | SdkRelayStatus::Initialized
        | SdkRelayStatus::Sleeping => RelayStatus::Disconnected,
        SdkRelayStatus::Banned => RelayStatus::Error,
    }
}

fn unix_now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64
}
