//! Publishing to several relays without waiting for the slowest one.
//!
//! nostr-sdk's `Client::send_event` resolves only once **every** relay has
//! answered `OK` or run into its 10 s timeout, so a single sluggish relay
//! holds the caller — and the screen behind it — for seconds after the event
//! already reached the daemon through the healthy ones. The SDK's
//! `FirstSuccess` ack policy is still commented out upstream (0.45), hence
//! this.

use std::future::Future;

use anyhow::Result;
use tokio::sync::mpsc;

use crate::rt::MaybeSend;

/// Outcome of one relay's send: `Err` carries the relay's reason.
pub(crate) type SendOutcome = std::result::Result<(), String>;

/// Runs every send concurrently and resolves on the **first** relay that
/// accepts the event. The remaining sends keep running detached, and
/// `on_outcome` still hears each of them, so the per-relay delivery log stays
/// complete.
///
/// Fails with the stable `NoRelayAccepted` marker (Dart maps it to a
/// localized message) only after every relay refused or timed out — and at
/// once when `sends` is empty.
pub(crate) async fn first_accepted<Fut, L>(sends: Vec<(String, Fut)>, on_outcome: L) -> Result<()>
where
    Fut: Future<Output = SendOutcome> + MaybeSend + 'static,
    L: Fn(&str, &SendOutcome) + Clone + MaybeSend + 'static,
{
    // One detached task per relay, so a send outlives this call. Each reports
    // its outcome itself: once the receiver is gone nobody is left to do it.
    let (tx, mut rx) = mpsc::unbounded_channel::<bool>();
    for (relay, send) in sends {
        let tx = tx.clone();
        let on_outcome = on_outcome.clone();
        crate::rt::spawn(async move {
            let outcome = send.await;
            on_outcome(&relay, &outcome);
            // Fails only after an earlier acceptance ended the wait.
            let _ = tx.send(outcome.is_ok());
        });
    }
    // Only the tasks hold senders now: the channel closing means all of them
    // reported.
    drop(tx);

    while let Some(accepted) = rx.recv().await {
        if accepted {
            return Ok(());
        }
    }
    anyhow::bail!("NoRelayAccepted")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Arc, Mutex};
    use std::time::{Duration, Instant};

    type Log = Arc<Mutex<Vec<(String, bool)>>>;

    fn recorder() -> (Log, impl Fn(&str, &SendOutcome) + Clone + Send + 'static) {
        let log: Log = Arc::default();
        let sink = log.clone();
        (log, move |relay: &str, outcome: &SendOutcome| {
            sink.lock().unwrap().push((relay.to_string(), outcome.is_ok()));
        })
    }

    async fn after(delay_ms: u64, outcome: SendOutcome) -> SendOutcome {
        tokio::time::sleep(Duration::from_millis(delay_ms)).await;
        outcome
    }

    #[tokio::test]
    async fn resolves_on_the_first_acceptance_without_waiting_for_a_slow_relay() {
        // Arrange
        let (_, on_outcome) = recorder();
        let sends = vec![
            ("slow".to_string(), after(2_000, Ok(()))),
            ("fast".to_string(), after(10, Ok(()))),
        ];

        // Act
        let started = Instant::now();
        let result = first_accepted(sends, on_outcome).await;

        // Assert
        assert!(result.is_ok());
        assert!(
            started.elapsed() < Duration::from_millis(1_000),
            "held for {:?} by the slow relay",
            started.elapsed()
        );
    }

    #[tokio::test]
    async fn a_relay_answering_after_the_return_is_still_reported() {
        // Arrange
        let (log, on_outcome) = recorder();
        let sends = vec![
            ("fast".to_string(), after(10, Ok(()))),
            ("late".to_string(), after(150, Err("timeout".to_string()))),
        ];

        // Act
        first_accepted(sends, on_outcome).await.unwrap();
        tokio::time::sleep(Duration::from_millis(400)).await;

        // Assert
        let mut seen = log.lock().unwrap().clone();
        seen.sort();
        assert_eq!(
            seen,
            vec![("fast".to_string(), true), ("late".to_string(), false)]
        );
    }

    #[tokio::test]
    async fn a_refusal_does_not_end_the_wait_for_a_later_acceptance() {
        // Arrange
        let (_, on_outcome) = recorder();
        let sends = vec![
            ("refuses".to_string(), after(10, Err("blocked".to_string()))),
            ("accepts".to_string(), after(80, Ok(()))),
        ];

        // Act
        let result = first_accepted(sends, on_outcome).await;

        // Assert
        assert!(result.is_ok());
    }

    #[tokio::test]
    async fn fails_with_the_marker_once_every_relay_refused() {
        // Arrange
        let (log, on_outcome) = recorder();
        let sends = vec![
            ("a".to_string(), after(10, Err("blocked".to_string()))),
            ("b".to_string(), after(60, Err("timeout".to_string()))),
        ];

        // Act
        let err = first_accepted(sends, on_outcome).await.unwrap_err();

        // Assert
        assert_eq!(err.to_string(), "NoRelayAccepted");
        assert_eq!(log.lock().unwrap().len(), 2, "both outcomes precede the verdict");
    }

    #[tokio::test]
    async fn fails_at_once_with_no_relay_to_send_to() {
        // Arrange
        let (_, on_outcome) = recorder();
        let sends: Vec<(String, std::future::Ready<SendOutcome>)> = Vec::new();

        // Act
        let err = first_accepted(sends, on_outcome).await.unwrap_err();

        // Assert
        assert_eq!(err.to_string(), "NoRelayAccepted");
    }
}
