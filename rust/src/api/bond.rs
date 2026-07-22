//! Anti-abuse bond client handling.
//!
//! Currently covers the `bond-slashed` forfeiture notice: a best-effort,
//! informational message the daemon sends when the local user's bond is
//! slashed. The notice is broadcast to the Dart notification layer; the tracked
//! order is never mutated (the slashed amount must not overwrite the order's
//! real amount).

use anyhow::{bail, Result};
use tokio::sync::broadcast;
use tokio::sync::broadcast::error::RecvError;

use crate::api::types::{BondSlashedEvent, OrderStatus, SlashCause};

/// Buffered slash notices; a slash is rare, so a small buffer is ample.
const CHANNEL_CAPACITY: usize = 64;

struct BondStore {
    /// Broadcast channel; payload = incoming bond-slashed notice.
    event_tx: broadcast::Sender<BondSlashedEvent>,
}

static BOND_STORE: std::sync::OnceLock<BondStore> = std::sync::OnceLock::new();

fn bond_store() -> &'static BondStore {
    BOND_STORE.get_or_init(|| {
        let (event_tx, _rx) = broadcast::channel(CHANNEL_CAPACITY);
        BondStore { event_tx }
    })
}

/// Infers the slash cause from the tracked order's current status.
///
/// The daemon sends the resolution message first — `canceled` for a timeout,
/// `admin-settled` / `admin-canceled` for a dispute — and only then the
/// trailing `bond-slashed`. So by the time the notice arrives, the tracked
/// status already reflects the cause. Any dispute/admin state means a
/// dispute-directed slash; everything else (including an unknown status)
/// defaults to a timeout slash.
pub(crate) fn infer_slash_cause(status: Option<&OrderStatus>) -> SlashCause {
    match status {
        Some(
            OrderStatus::Dispute
            | OrderStatus::CanceledByAdmin
            | OrderStatus::SettledByAdmin
            | OrderStatus::CompletedByAdmin,
        ) => SlashCause::Dispute,
        _ => SlashCause::Timeout,
    }
}

/// Broadcasts a `bond-slashed` notice to any active [`BondSlashedStream`].
pub(crate) fn emit_bond_slashed(event: BondSlashedEvent) {
    let _ = bond_store().event_tx.send(event);
}

/// A stream that emits incoming [`BondSlashedEvent`]s for the Dart layer.
pub struct BondSlashedStream {
    rx: broadcast::Receiver<BondSlashedEvent>,
}

impl BondSlashedStream {
    /// Poll for the next incoming bond-slashed notice.
    ///
    /// `RecvError::Lagged` is skipped gracefully rather than ending the stream.
    pub async fn next(&mut self) -> Result<BondSlashedEvent> {
        loop {
            match self.rx.recv().await {
                Ok(event) => return Ok(event),
                Err(RecvError::Lagged(_)) => continue,
                Err(RecvError::Closed) => bail!("BondSlashedStream closed: sender dropped"),
            }
        }
    }
}

/// Subscribe to incoming `bond-slashed` notices.
pub fn on_bond_slashed() -> BondSlashedStream {
    BondSlashedStream {
        rx: bond_store().event_tx.subscribe(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dispute_and_admin_states_infer_dispute() {
        for status in [
            OrderStatus::Dispute,
            OrderStatus::CanceledByAdmin,
            OrderStatus::SettledByAdmin,
            OrderStatus::CompletedByAdmin,
        ] {
            assert_eq!(infer_slash_cause(Some(&status)), SlashCause::Dispute);
        }
    }

    #[test]
    fn canceled_and_other_states_infer_timeout() {
        for status in [
            OrderStatus::Canceled,
            OrderStatus::InProgress,
            OrderStatus::WaitingPayment,
            OrderStatus::WaitingBuyerInvoice,
            OrderStatus::Active,
        ] {
            assert_eq!(infer_slash_cause(Some(&status)), SlashCause::Timeout);
        }
    }

    #[test]
    fn unknown_status_defaults_to_timeout() {
        assert_eq!(infer_slash_cause(None), SlashCause::Timeout);
    }
}
