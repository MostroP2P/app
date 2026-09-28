//! How far an account restore got, for the restore sheet (design 20a–20d).
//!
//! `recover_trades` answers only once, at the end. The sheet shows the stages
//! as they happen: the request reaching a relay, the node's answer and how
//! many orders it named, and each order's details arriving. Those steps are
//! pushed here as [`RestoreProgress`]; the outcome stays `recover_trades`'
//! result. Subscribe **before** calling it, or the first steps are missed.

use anyhow::Result;
use tokio::sync::broadcast;

use crate::api::types::RestoreProgress;

/// A restore emits a handful of steps plus one per order, and a subscriber
/// that falls behind only loses intermediate counts, never the outcome.
const CAPACITY: usize = 64;

static PROGRESS: std::sync::OnceLock<broadcast::Sender<RestoreProgress>> =
    std::sync::OnceLock::new();

fn sender() -> &'static broadcast::Sender<RestoreProgress> {
    PROGRESS.get_or_init(|| broadcast::channel(CAPACITY).0)
}

/// Report a restore step.
pub(crate) fn emit(step: RestoreProgress) {
    // An error only means nobody is listening.
    let _ = sender().send(step);
}

/// The steps of the node's answer: every order and dispute it returned, and
/// how many of them the restore fetches the details of.
pub(crate) fn found(info: &mostro_core::message::RestoreSessionInfo, to_load: usize) -> RestoreProgress {
    RestoreProgress::Found {
        found: (info.restore_orders.len() + info.restore_disputes.len()) as u32,
        to_load: to_load as u32,
    }
}

/// Stream of restore steps; see the module docs.
pub async fn on_restore_progress() -> Result<RestoreProgressStream> {
    Ok(RestoreProgressStream {
        rx: sender().subscribe(),
    })
}

/// Wrapper for flutter_rust_bridge Dart Stream generation.
pub struct RestoreProgressStream {
    rx: broadcast::Receiver<RestoreProgress>,
}

impl RestoreProgressStream {
    pub async fn next(&mut self) -> Option<RestoreProgress> {
        loop {
            match self.rx.recv().await {
                Ok(step) => return Some(step),
                // Only intermediate counts were lost; the next step is current.
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    log::warn!("[restore-progress] stream lagged, {n} steps dropped");
                }
                Err(broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use mostro_core::message::RestoreSessionInfo;

    /// The channel is process-wide and tests run in parallel, so each test
    /// reads until it sees the step it sent.
    async fn next_matching(stream: &mut RestoreProgressStream, want: &RestoreProgress) {
        loop {
            if &stream.next().await.expect("the sender is a static") == want {
                return;
            }
        }
    }

    #[tokio::test]
    async fn a_step_reaches_a_subscriber() {
        // Arrange
        let mut stream = on_restore_progress().await.unwrap();
        let step = RestoreProgress::Loaded { done: 41, to_load: 97 };

        // Act
        emit(step.clone());

        // Assert
        next_matching(&mut stream, &step).await;
    }

    #[tokio::test]
    async fn a_subscriber_that_fell_behind_still_hears_the_next_step() {
        let mut stream = on_restore_progress().await.unwrap();
        for done in 0..=CAPACITY as u32 {
            emit(RestoreProgress::Loaded { done, to_load: 999 });
        }
        let last = RestoreProgress::Loaded { done: 998, to_load: 999 };

        emit(last.clone());

        next_matching(&mut stream, &last).await;
    }

    #[test]
    fn the_answer_counts_orders_and_disputes_and_what_is_loaded() {
        use mostro_core::message::{RestoredDisputesInfo, RestoredOrdersInfo};
        let order = |status: &str| RestoredOrdersInfo {
            order_id: uuid::Uuid::new_v4(),
            trade_index: 14,
            status: status.to_string(),
            counterparty_trade_pubkey: None,
        };
        let info = RestoreSessionInfo {
            restore_orders: vec![order("active"), order("waiting-maker-bond")],
            restore_disputes: vec![RestoredDisputesInfo {
                dispute_id: uuid::Uuid::new_v4(),
                order_id: uuid::Uuid::new_v4(),
                trade_index: 11,
                status: "in-progress".to_string(),
                initiator: None,
                solver_pubkey: None,
            }],
        };

        assert_eq!(found(&info, 1), RestoreProgress::Found { found: 3, to_load: 1 });
    }
}
