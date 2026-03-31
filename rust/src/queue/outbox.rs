use std::sync::{Mutex, OnceLock};
use std::time::{SystemTime, UNIX_EPOCH};

use anyhow::Result;
use serde::{Deserialize, Serialize};

use crate::api::types::QueuedMessageStatus;

// ── QueuedMessage ─────────────────────────────────────────────────────────────

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
    /// Unix-seconds timestamp before which the message must not be retried.
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

    /// Backoff in seconds: 30s × 2^retry_count, capped at 3 600s.
    pub fn next_retry_delay_secs(&self) -> i64 {
        let base: i64 = 30;
        let delay = base * (1i64 << self.retry_count.min(7));
        delay.min(3600)
    }
}

// ── MessageOutbox (in-memory) ─────────────────────────────────────────────────

/// Max retry attempts before a message is considered permanently failed.
const MAX_RETRIES: u32 = 10;

/// In-memory message outbox.
///
/// Persistence to SQLite is wired in Phase 18+ (requires DB initialisation
/// to be threaded through to this module).  Until then messages survive only
/// for the current app session.
pub struct MessageOutbox {
    queue: Mutex<Vec<QueuedMessage>>,
}

impl MessageOutbox {
    fn new() -> Self {
        Self {
            queue: Mutex::new(Vec::new()),
        }
    }

    /// Add an event to the outbox.
    pub fn enqueue(&self, event_json: String) {
        let now = unix_now();
        let msg = QueuedMessage::new(event_json, now);
        self.queue.lock().unwrap().push(msg);
    }

    /// Attempt to publish all pending messages.
    ///
    /// For each `Pending` message whose `next_retry_at` has elapsed:
    /// - Calls `publish_fn` with the serialised event JSON.
    /// - On success → marks `Sent`.
    /// - On failure → increments `retry_count`, schedules next retry with
    ///   exponential backoff.  After [`MAX_RETRIES`] failures → marks `Failed`.
    ///
    /// After flushing, prunes all `Sent` messages and `Failed` messages older
    /// than 24 hours.
    ///
    /// Returns the count of successfully published messages in this pass.
    pub async fn flush<F, Fut>(&self, publish_fn: F) -> u32
    where
        F: Fn(String) -> Fut,
        Fut: std::future::Future<Output = Result<()>>,
    {
        let now = unix_now();

        // Snapshot messages that are due for a retry attempt.
        let pending: Vec<QueuedMessage> = {
            let q = self.queue.lock().unwrap();
            q.iter()
                .filter(|m| {
                    m.status == QueuedMessageStatus::Pending
                        && m.next_retry_at.is_none_or(|t| now >= t)
                })
                .cloned()
                .collect()
        };

        let mut sent = 0u32;

        for mut msg in pending {
            match publish_fn(msg.event_json.clone()).await {
                Ok(()) => {
                    msg.status = QueuedMessageStatus::Sent;
                    sent += 1;
                }
                Err(_) => {
                    msg.retry_count += 1;
                    if msg.retry_count >= MAX_RETRIES {
                        msg.status = QueuedMessageStatus::Failed;
                    } else {
                        msg.next_retry_at = Some(now + msg.next_retry_delay_secs());
                    }
                }
            }

            // Write back the updated entry.
            let mut q = self.queue.lock().unwrap();
            if let Some(entry) = q.iter_mut().find(|m| m.id == msg.id) {
                *entry = msg;
            }
        }

        // Prune: sent items always; failed items after 24 hours.
        let cutoff = now - 86_400;
        self.queue.lock().unwrap().retain(|m| {
            m.status == QueuedMessageStatus::Pending
                || (m.status == QueuedMessageStatus::Failed && m.created_at > cutoff)
        });

        sent
    }

    /// Count of messages currently in the queue (all statuses).
    pub fn len(&self) -> usize {
        self.queue.lock().unwrap().len()
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

// ── Global singleton ──────────────────────────────────────────────────────────

static OUTBOX: OnceLock<MessageOutbox> = OnceLock::new();

pub fn outbox() -> &'static MessageOutbox {
    OUTBOX.get_or_init(MessageOutbox::new)
}

/// Add a serialised Nostr event to the persistent outbox for deferred delivery.
pub fn queue_message(event_json: String) {
    outbox().enqueue(event_json);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

fn unix_now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;

    fn fresh_outbox() -> MessageOutbox {
        MessageOutbox::new()
    }

    #[tokio::test]
    async fn enqueue_and_flush_success() {
        let ob = fresh_outbox();
        ob.enqueue("{}".to_string());
        assert_eq!(ob.len(), 1);

        let sent = ob.flush(|_| async { Ok(()) }).await;
        assert_eq!(sent, 1);
        // Sent items are pruned.
        assert_eq!(ob.len(), 0);
    }

    #[tokio::test]
    async fn flush_failure_increments_retry_count() {
        let ob = fresh_outbox();
        ob.enqueue("{}".to_string());

        let sent = ob
            .flush(|_| async { Err(anyhow::anyhow!("connection refused")) })
            .await;
        assert_eq!(sent, 0);
        let q = ob.queue.lock().unwrap();
        assert_eq!(q[0].retry_count, 1);
        assert_eq!(q[0].status, QueuedMessageStatus::Pending);
    }

    #[tokio::test]
    async fn message_marked_failed_after_max_retries() {
        let ob = fresh_outbox();
        ob.enqueue("{}".to_string());
        // Force retry_count to MAX_RETRIES - 1 so the next failure tips it over.
        {
            let mut q = ob.queue.lock().unwrap();
            q[0].retry_count = MAX_RETRIES - 1;
        }

        ob.flush(|_| async { Err(anyhow::anyhow!("fail")) })
            .await;

        let q = ob.queue.lock().unwrap();
        assert_eq!(q[0].status, QueuedMessageStatus::Failed);
    }

    #[tokio::test]
    async fn backoff_delay_is_applied() {
        let ob = fresh_outbox();
        ob.enqueue("{}".to_string());

        // First failure → retry_count = 1, next_retry_at set in the future.
        ob.flush(|_| async { Err(anyhow::anyhow!("fail")) })
            .await;

        let q = ob.queue.lock().unwrap();
        let msg = &q[0];
        assert!(msg.next_retry_at.is_some());
        // With retry_count 1 the delay should be 60 s (30 × 2^1).
        assert_eq!(msg.next_retry_delay_secs(), 60);
    }
}
