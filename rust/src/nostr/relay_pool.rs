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
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};

use crate::api::types::{ConnectionState, RelayInfo, RelaySource, RelayStatus};
use crate::nostr::order_events::pending_orders_filter;

const KIND_GIFT_WRAP: u16 = 1059;

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
        relays.remove(pos);
        drop(relays);
        self.client
            .remove_relay(url)
            .await
            .map_err(|e| anyhow!("remove relay failed: {e}"))?;
        Ok(())
    }

    pub async fn get_relays(&self) -> Vec<RelayInfo> {
        self.relays.read().await.clone()
    }

    pub async fn connection_state(&self) -> ConnectionState {
        let relays = self.relays.read().await;
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

    pub fn subscribe_connection_state(&self) -> broadcast::Receiver<ConnectionState> {
        self.conn_tx.subscribe()
    }

    pub fn subscribe_relay_status(&self) -> broadcast::Receiver<RelayInfo> {
        self.relay_tx.subscribe()
    }

    /// Subscribe to Kind 38383 (public orders) and Kind 1059 (gift wraps) separately.
    pub async fn subscribe_order_and_dm_feeds(&self, trade_pubkeys: Vec<PublicKey>) -> Result<()> {
        let order_filter = pending_orders_filter();
        self.client
            .subscribe(order_filter, None)
            .await
            .map_err(|e| anyhow!("order subscribe failed: {e}"))?;

        let dm_filter = Filter::new()
            .kind(Kind::from(KIND_GIFT_WRAP))
            .pubkeys(trade_pubkeys);
        self.client
            .subscribe(dm_filter, None)
            .await
            .map_err(|e| anyhow!("dm subscribe failed: {e}"))?;

        Ok(())
    }

    pub fn client(&self) -> Arc<Client> {
        self.client.clone()
    }
}
