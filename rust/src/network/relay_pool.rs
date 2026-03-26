/// Relay pool — manages connections to Nostr relays.
///
/// Wraps nostr-sdk's Client with Mostro-specific concerns:
/// preconfigured defaults, ConnectionState tracking, and event subscriptions
/// for Kind 38383 (orders) and Kind 1059 (Gift Wrap messages).
///
/// per research R1.
use anyhow::{Context, Result};
use nostr_sdk::{Client, Event, Filter, Keys, Kind, PublicKey, RelayPoolNotification, RelayStatus};
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};

use crate::api::types::{ConnectionState, RelayInfo, RelaySource};
use crate::api::types::RelayStatus as AppRelayStatus;

/// Default relays for new installations.
pub const DEFAULT_RELAYS: &[&str] = &[
    "wss://relay.mostro.network",
    "wss://relay.damus.io",
    "wss://nos.lol",
];

/// Kind 38383 — public Mostro order listings.
pub const KIND_ORDER: u16 = 38383;
/// Kind 1059 — NIP-59 Gift Wrap for all private Mostro communication.
pub const KIND_GIFT_WRAP: u16 = 1059;

struct PoolState {
    connection: ConnectionState,
    relays: Vec<RelayInfo>,
}

pub struct RelayPool {
    client: Client,
    state: Arc<RwLock<PoolState>>,
    event_tx: broadcast::Sender<Event>,
}

impl RelayPool {
    /// Create a new RelayPool, add relays, and initiate connections.
    pub async fn new(keys: Keys, relay_urls: Option<Vec<String>>) -> Result<Self> {
        let client = Client::new(keys);
        let urls = relay_urls
            .unwrap_or_else(|| DEFAULT_RELAYS.iter().map(|s| s.to_string()).collect());

        for url in &urls {
            client
                .add_relay(url.as_str())
                .await
                .context(format!("add relay {}", url))?;
        }

        client.connect().await;

        let (event_tx, _) = broadcast::channel(1024);
        let relay_infos: Vec<RelayInfo> = urls
            .iter()
            .map(|url| RelayInfo {
                url: url.clone(),
                is_active: true,
                is_default: DEFAULT_RELAYS.contains(&url.as_str()),
                source: RelaySource::Default,
                is_blacklisted: false,
                status: AppRelayStatus::Connecting,
                last_connected_at: None,
                last_error: None,
            })
            .collect();

        let state = Arc::new(RwLock::new(PoolState {
            connection: ConnectionState::Reconnecting,
            relays: relay_infos,
        }));

        Ok(Self {
            client,
            state,
            event_tx,
        })
    }

    /// Subscribe to public order listings (Kind 38383).
    pub async fn subscribe_orders(&self) -> Result<broadcast::Receiver<Event>> {
        let filter = Filter::new().kind(Kind::from(KIND_ORDER));
        self.client
            .subscribe(filter, None)
            .await
            .context("subscribe to orders")?;
        Ok(self.event_tx.subscribe())
    }

    /// Subscribe to Gift Wrap events (Kind 1059) for our pubkey.
    pub async fn subscribe_gift_wraps(
        &self,
        recipient_pubkey: &PublicKey,
    ) -> Result<broadcast::Receiver<Event>> {
        let filter = Filter::new()
            .kind(Kind::from(KIND_GIFT_WRAP))
            .pubkey(*recipient_pubkey);
        self.client
            .subscribe(filter, None)
            .await
            .context("subscribe to gift wraps")?;
        Ok(self.event_tx.subscribe())
    }

    /// Publish a signed event to all connected relays.
    pub async fn publish(&self, event: Event) -> Result<()> {
        self.client
            .send_event(&event)
            .await
            .context("send event to relay pool")?;
        Ok(())
    }

    /// Add a relay URL to the pool and connect.
    pub async fn add_relay(&self, url: &str) -> Result<()> {
        self.client
            .add_relay(url)
            .await
            .context(format!("add relay {}", url))?;
        self.client
            .connect_relay(url)
            .await
            .context("connect relay")?;
        Ok(())
    }

    /// Remove a relay from the pool.
    pub async fn remove_relay(&self, url: &str) -> Result<()> {
        self.client
            .remove_relay(url)
            .await
            .context(format!("remove relay {}", url))?;
        Ok(())
    }

    /// Get the current aggregate connection state.
    pub async fn connection_state(&self) -> ConnectionState {
        self.state.read().await.connection
    }

    /// Get a snapshot of all relay info.
    pub async fn relay_infos(&self) -> Vec<RelayInfo> {
        self.state.read().await.relays.clone()
    }

    /// Spawn a background task that pumps relay notifications into the event channel.
    pub fn start_notification_pump(self: Arc<Self>) {
        let mut notifications = self.client.notifications();
        let event_tx = self.event_tx.clone();
        let state = Arc::clone(&self.state);

        tokio::spawn(async move {
            while let Ok(notification) = notifications.recv().await {
                match notification {
                    RelayPoolNotification::Event { event, .. } => {
                        let _ = event_tx.send(*event);
                    }
                    RelayPoolNotification::Shutdown => {
                        let mut s = state.write().await;
                        s.connection = ConnectionState::Offline;
                        for relay in &mut s.relays {
                            relay.status = AppRelayStatus::Disconnected;
                        }
                        break;
                    }
                    _ => {}
                }
            }
        });

        // Poll relay statuses every 5 seconds to update ConnectionState.
        let state = Arc::clone(&self.state);
        let client = self.client.clone();
        tokio::spawn(async move {
            let mut interval = tokio::time::interval(std::time::Duration::from_secs(5));
            loop {
                interval.tick().await;
                let relays = client.relays().await;
                let mut s = state.write().await;
                for relay_info in &mut s.relays {
                    if let Ok(url) = relay_info.url.parse() {
                        if let Some(r) = relays.get(&url) {
                            relay_info.status = sdk_status_to_app(r.status());
                        }
                    }
                }
                let any_connected = s
                    .relays
                    .iter()
                    .any(|r| r.status == AppRelayStatus::Connected);
                let all_offline = s.relays.iter().all(|r| {
                    matches!(r.status, AppRelayStatus::Disconnected | AppRelayStatus::Error)
                });
                s.connection = if any_connected {
                    ConnectionState::Online
                } else if all_offline {
                    ConnectionState::Offline
                } else {
                    ConnectionState::Reconnecting
                };
            }
        });
    }

    /// Gracefully disconnect from all relays.
    pub async fn disconnect(&self) {
        self.client.disconnect().await;
    }
}

fn sdk_status_to_app(status: RelayStatus) -> AppRelayStatus {
    match status {
        RelayStatus::Connected => AppRelayStatus::Connected,
        RelayStatus::Connecting => AppRelayStatus::Connecting,
        RelayStatus::Disconnected | RelayStatus::Initialized | RelayStatus::Pending => {
            AppRelayStatus::Disconnected
        }
        RelayStatus::Terminated => AppRelayStatus::Error,
        _ => AppRelayStatus::Error,
    }
}
