//! Publishing to several relays without waiting for the slowest one.
//!
//! nostr-sdk's `Client::send_event` resolves only once **every** relay has
//! answered `OK` or run into its 10 s timeout, so a single sluggish relay
//! holds the caller — and the screen behind it — for seconds after the event
//! already reached the daemon through the healthy ones. The SDK's
//! `FirstSuccess` ack policy is still commented out upstream (0.45), hence
//! this. Daemon messages and the peer and dispute chats all publish through
//! [`publish_event`]: a chat message used to wait for the slowest relay too,
//! and showed up in its own conversation 10 s late.

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

/// Publish a signed event through `client`'s write relays, resolving on the
/// **first** that accepts it (see [`first_accepted`]). Each relay's outcome is
/// logged as it answers, including those that answer after the return — with
/// one relay habitually down, knowing where each event landed is what makes
/// delivery issues diagnosable. Envelope metadata only: no content is logged.
///
/// Fails with `NoRelayAccepted` when no relay took it.
pub(crate) async fn publish_event(
    client: &nostr_sdk::prelude::Client,
    event: &nostr_sdk::prelude::Event,
) -> Result<()> {
    use nostr_sdk::prelude::RelayCapabilities;

    let kind = event.kind.as_u16();
    let eid = event.id.to_hex();

    // What `Client::send_event` does before fanning out. Verified first, so an
    // inconsistent event fails here rather than in the store or on a relay;
    // then saved: with the event in the SDK's store, a relay echoing it back
    // on one of our subscriptions is not notified as new.
    event
        .verify()
        .map_err(|e| anyhow::anyhow!("invalid event: {e}"))?;
    if let Err(e) = client.database().save_event(event).await {
        log::warn!("[publish] ev={eid} not saved to the local store: {e}");
    }

    let sends = client
        .relays()
        .with_capabilities(RelayCapabilities::WRITE)
        .await
        .into_iter()
        .map(|(url, relay)| {
            let event = event.clone();
            let send = async move {
                relay
                    .send_event(&event)
                    .await
                    .map(|_| ())
                    .map_err(|e| e.to_string())
            };
            (url.to_string(), send)
        })
        .collect();

    let report = move |relay: &str, outcome: &SendOutcome| {
        let ev = crate::api::logging::short_id(&eid);
        let relay = crate::api::logging::display_relay(relay);
        match outcome {
            Ok(()) => crate::api::logging::blog_info(
                "publish",
                format!("ev={ev} kind={kind} relay={relay} OK"),
            ),
            Err(err) => crate::api::logging::blog_warn(
                "publish",
                format!(
                    "ev={ev} kind={kind} relay={relay} FAIL: {}",
                    crate::api::logging::sanitize_relay_text(err),
                ),
            ),
        }
    };

    // An `OK false` is a relay error here, so "accepted" means accepted.
    first_accepted(sends, report).await
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

    /// A relay that completes the websocket handshake and then never answers:
    /// connected, but no `OK` ever comes back — what a stuck relay looks like.
    async fn silent_relay() -> String {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("ws://{}", listener.local_addr().unwrap());
        tokio::spawn(async move {
            while let Ok((stream, _)) = listener.accept().await {
                tokio::spawn(async move {
                    if let Ok(mut ws) = tokio_tungstenite::accept_async(stream).await {
                        use futures_util::StreamExt;
                        while ws.next().await.is_some() {}
                    }
                });
            }
        });
        url
    }

    /// The chat delay of a stuck relay: one relay accepts at once, the other
    /// never answers. The publish is back with the first, not after the
    /// other's 10 s `OK` timeout, as `Client::send_event` would be.
    #[tokio::test]
    async fn a_relay_that_never_answers_does_not_hold_the_publish() {
        use nostr_sdk::local_relay::MockRelay;
        use nostr_sdk::prelude::*;

        // Arrange
        let healthy = MockRelay::run().await.expect("mock relay");
        let healthy_url = healthy.url().await;
        let silent_url = silent_relay().await;
        let client = Client::new();
        for url in [healthy_url.to_string(), silent_url] {
            client.add_relay(&url).await.expect("add relay");
            client
                .try_connect_relay(&url, Duration::from_secs(3))
                .await
                .expect("connected");
        }
        let event = EventBuilder::new(Kind::TextNote, "hello")
            .finalize(&Keys::generate())
            .unwrap();

        // Act
        let started = Instant::now();
        let result = publish_event(&client, &event).await;

        // Assert
        assert!(result.is_ok(), "{result:?}");
        assert!(
            started.elapsed() < Duration::from_secs(3),
            "held for {:?} by the silent relay",
            started.elapsed()
        );
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
