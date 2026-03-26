/// Offline message queue — ensures Nostr events are delivered even when
/// the relay pool is temporarily offline.
///
/// Events are persisted in the DB (via Storage) and flushed when the relay
/// pool reconnects. Failed sends are retried up to MAX_ATTEMPTS times.
/// Sent entries are pruned after PRUNE_AFTER_SECS seconds.
///
/// per data-model.md MessageQueue entity.
use anyhow::{Context, Result};
use nostr_sdk::Event;
use std::sync::Arc;

use crate::network::relay_pool::RelayPool;
use crate::storage::{QueuedMessage, Storage};

/// Maximum delivery attempts before marking as Failed.
pub const MAX_ATTEMPTS: i32 = 10;
/// Prune sent messages older than 24 hours.
pub const PRUNE_AFTER_SECS: i64 = 86_400;

pub struct MessageQueue<S: Storage> {
    storage: Arc<S>,
}

impl<S: Storage> MessageQueue<S> {
    pub fn new(storage: Arc<S>) -> Self {
        Self { storage }
    }

    /// Enqueue an event for delivery to the given relay URLs.
    /// The event is persisted before returning so it survives app crashes.
    pub async fn enqueue(&self, event: &Event, target_relays: Vec<String>) -> Result<()> {
        let id = uuid::Uuid::new_v4().to_string();
        let event_json = serde_json::to_string(event).context("serialize event")?;
        let relays_json = serde_json::to_string(&target_relays).context("serialize relays")?;
        let now = now_secs();

        let record = QueuedMessage {
            id,
            event_json,
            target_relays: relays_json,
            status: "Pending".to_string(),
            attempts: 0,
            created_at: now,
            last_attempt_at: None,
        };

        self.storage
            .enqueue_message(record)
            .await
            .context("persist queued message")
    }

    /// Flush all pending messages through the relay pool.
    /// Called automatically when the pool comes online.
    pub async fn flush(&self, pool: &RelayPool) -> Result<()> {
        let pending = self
            .storage
            .list_pending_messages()
            .await
            .context("list pending messages")?;

        for msg in pending {
            let attempts = msg.attempts + 1;
            match self.send_one(&msg, pool).await {
                Ok(()) => {
                    self.storage
                        .update_message_status(&msg.id, "Sent", attempts)
                        .await
                        .ok();
                }
                Err(_) => {
                    let new_status = if attempts >= MAX_ATTEMPTS {
                        "Failed"
                    } else {
                        "Pending"
                    };
                    self.storage
                        .update_message_status(&msg.id, new_status, attempts)
                        .await
                        .ok();
                }
            }
        }

        // Prune old sent messages
        let cutoff = now_secs() - PRUNE_AFTER_SECS;
        self.storage.prune_sent_messages(cutoff).await.ok();

        Ok(())
    }

    async fn send_one(&self, msg: &QueuedMessage, pool: &RelayPool) -> Result<()> {
        let event: Event = serde_json::from_str(&msg.event_json).context("deserialize event")?;
        pool.publish(event).await
    }
}

fn now_secs() -> i64 {
    #[cfg(not(target_arch = "wasm32"))]
    {
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64
    }
    #[cfg(target_arch = "wasm32")]
    {
        (js_sys::Date::now() / 1000.0) as i64
    }
}
