use crate::api::types::QueuedMessageStatus;
use serde::{Deserialize, Serialize};

/// A Nostr event waiting to be published when connectivity is restored.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QueuedMessage {
    /// UUID v4 identifier.
    pub id: String,
    /// Serialised `nostr_sdk::Event` JSON.
    pub event_json: String,
    pub status: QueuedMessageStatus,
    pub created_at: i64,
    pub retry_count: u32,
    pub next_retry_at: Option<i64>,
}

impl QueuedMessage {
    pub fn new(event_json: String, now: i64) -> Self {
        Self {
            id: uuid::Uuid::new_v4().to_string(),
            event_json,
            status: QueuedMessageStatus::Pending,
            created_at: now,
            retry_count: 0,
            next_retry_at: None,
        }
    }

    /// Backoff in seconds: 30s × 2^retry_count, capped at 3600s.
    pub fn next_retry_delay_secs(&self) -> i64 {
        let base: i64 = 30;
        let delay = base * (1i64 << self.retry_count.min(7));
        delay.min(3600)
    }
}
