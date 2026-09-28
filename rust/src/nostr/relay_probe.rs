//! Asking a `Connected` relay whether it is still there.
//!
//! Every recovery path in this client is keyed on an **observed** change:
//! a relay transitioning to `Disconnected`, the pool going `Online`, a relay
//! sending `CLOSED`, or the app resuming. A connection that keeps answering
//! the protocol while delivering nothing produces none of those, so nothing
//! wakes [`crate::nostr::live_subs`] — and `repair_relay` would report zero
//! anyway, since the SDK's registry still lists the subscription as present.
//!
//! Measured against a live daemon (issue #291): with the relay frozen so it
//! could not answer the WebSocket PONG, the SDK's own ping caught it in 56 s
//! and `live_subs` re-issued every subscription 15 s after it came back. With
//! a proxy answering the pings while swallowing the relay's frames, the app
//! was deaf for **6 minutes without logging a single line**, and the five
//! events it missed were never requested again. That second shape is what
//! this module detects. It is also the shape of a REQ refused over a relay's
//! per-connection cap (`req_census`): the subscription never existed, and the
//! `NOTICE` names none, so nothing can repair it.
//!
//! **Traffic proves life; silence proves nothing.** That asymmetry is the
//! whole design. Recent traffic from a relay is taken as proof it is healthy
//! and skips the probe — but a quiet relay is never *concluded* dead, only
//! asked. PR #324 measured 240 s of silence on a perfectly healthy relay and
//! would have reconnected it, so a silence timer cannot be the signal.

use std::collections::HashMap;
use std::time::Duration;

use nostr_sdk::prelude::{Client, EventId, Filter, Relay, RelayStatus};

/// How long a relay may stay quiet before it is asked whether it is alive.
pub(crate) const PROBE_INTERVAL: Duration = Duration::from_secs(120);

/// How long the relay has to answer the probe's EOSE. Generous next to the
/// measured round trips (20 ms on a local nostr-rs-relay, 820 ms on nos.lol)
/// so a slow relay is never mistaken for a dead one.
pub(crate) const PROBE_TIMEOUT: Duration = Duration::from_secs(15);

/// Traffic newer than this makes a probe pointless: something arrived, so the
/// socket delivers.
pub(crate) const FRESH_TRAFFIC_WINDOW: Duration = Duration::from_secs(120);

/// How long [`force_reconnect`] leaves between dropping a socket and asking
/// for it back.
///
/// It cannot be keyed on the status: `disconnect_relay` reports `Terminated`
/// immediately while the teardown is still in flight, so waiting for the
/// status to move returns at once and achieves nothing. Measured against a
/// MockRelay — reconnecting with no grace leaves the relay stuck in
/// `Disconnected`/`Connecting` past five seconds; 250 ms of grace has it
/// `Connected` again. (#324 carried a 200 ms sleep here for the same reason,
/// undocumented.)
const RECONNECT_GRACE: Duration = Duration::from_millis(250);

/// The probe's filter: one event id of 32 zero bytes, which nothing can match,
/// so a healthy relay answers EOSE with no events at all.
///
/// **Not** `limit(0)`, the obvious candidate: measured, strfry (nos.lol)
/// answers it with EOSE in 0.8 s but nostr-rs-relay never answers it at all,
/// which would have made every such relay look dead. An id filter that cannot
/// match is answered by both — 0.02 s and 0.82 s respectively.
pub(crate) fn probe_filter() -> Filter {
    Filter::new().id(EventId::from_byte_array([0u8; 32]))
}

/// When each relay was last heard from, and last asked.
///
/// Keyed by relay URL so one relay's traffic never vouches for another's
/// socket — the flaw ermeme caught in #324's first round, where a pool-wide
/// timestamp meant a live relay masked a dead one.
#[derive(Debug, Default)]
pub(crate) struct RelayLiveness {
    seen: HashMap<String, i64>,
    probed: HashMap<String, i64>,
}

impl RelayLiveness {
    /// Something arrived from `url`: an event, or any relay message.
    pub(crate) fn record_traffic(&mut self, url: &str, at: i64) {
        self.seen.insert(url.to_string(), at);
    }

    /// A probe was issued to `url`, whatever its outcome. Recording it on the
    /// attempt, not on success, is what keeps a still-silent relay from being
    /// probed again on the very next tick.
    pub(crate) fn record_probe(&mut self, url: &str, at: i64) {
        self.probed.insert(url.to_string(), at);
    }

    /// Drop everything known about `url` — it left the pool.
    pub(crate) fn forget(&mut self, url: &str) {
        self.seen.remove(url);
        self.probed.remove(url);
    }

    pub(crate) fn last_seen(&self, url: &str) -> Option<i64> {
        self.seen.get(url).copied()
    }

    pub(crate) fn last_probe(&self, url: &str) -> Option<i64> {
        self.probed.get(url).copied()
    }
}

/// Whether `url` should be asked, now.
///
/// A relay with no traffic on record is a candidate rather than an exemption:
/// the one thing a connection that has never delivered anything deserves is a
/// question. #324 took the opposite reading — a missing baseline disabled its
/// recovery for good — and needed a review round to seed one at connect time.
/// Asking costs a REQ and an EOSE, and a healthy relay answers, so the
/// pessimistic default is the safe one here.
pub(crate) fn should_probe(
    status: RelayStatus,
    last_seen: Option<i64>,
    last_probe: Option<i64>,
    now: i64,
) -> bool {
    // A relay the SDK already knows is down is the SDK's to reconnect; only
    // one that still claims to be Connected can be silently dead.
    if status != RelayStatus::Connected {
        return false;
    }
    if within(last_seen, now, FRESH_TRAFFIC_WINDOW) {
        return false;
    }
    !within(last_probe, now, PROBE_INTERVAL)
}

/// Whether `stamp` is set and newer than `window` ago.
fn within(stamp: Option<i64>, now: i64, window: Duration) -> bool {
    stamp.is_some_and(|at| now.saturating_sub(at) < window.as_secs() as i64)
}

/// Ask `relay` whether it is still delivering, and wait [`PROBE_TIMEOUT`]
/// for the answer. `true` means it answered.
///
/// A one-shot fetch, not a long-lived subscription: it opens its own REQ,
/// exits on EOSE and is gone, so it stays out of [`crate::nostr::live_subs`]
/// and costs a relay's per-connection cap only for as long as it runs.
pub(crate) async fn probe_once(relay: &Relay) -> bool {
    probe_within(relay, PROBE_TIMEOUT).await
}

/// [`probe_once`] with the deadline spelled out, so a test can use one short
/// enough to wait for.
///
/// Two layers have to be `Ok`, and each one is a way to read this wrong:
///
/// - The deadline is **ours**, not `FetchEvents::timeout`: measured, the SDK's
///   own timeout is not a failure but the end of collection, so a fetch against
///   a relay that answered nothing at all still returns `Ok` with an empty set.
/// - The fetch itself returns a `Result` too, and an `Err` from it — a
///   transport failure, a relay gone from the pool — is evidence of trouble,
///   not of an answer. Only the outer layer completing *with* an inner `Ok`
///   means the relay replied.
///
/// Either misreading leaves the probe unable to detect the thing it exists to
/// detect. The first one is the shape the live runs exercise: a half-dead
/// socket does not error, it simply never answers.
async fn probe_within(relay: &Relay, limit: Duration) -> bool {
    crate::rt::time::timeout(
        limit,
        std::future::IntoFuture::into_future(relay.fetch_events(probe_filter())),
    )
    .await
    .is_ok_and(|fetched| fetched.is_ok())
}

/// Bounce `url`'s connection so the reconnect re-issues its subscriptions.
///
/// The recovery is deliberately indirect: dropping and restoring the socket
/// is what produces the `→Connected` transition that `live_subs::repair_relay`
/// already listens for, and that repair is what re-REQs — which is what
/// actually replays the backlog. Merely noticing would leave the client where
/// the measurement found it: deaf, with the missed events never asked for
/// again. It is the one part of #324 that was right.
pub(crate) async fn force_reconnect(client: &Client, url: &str) {
    if let Err(e) = client.disconnect_relay(url).await {
        crate::api::logging::blog_warn(
            "relay",
            format!(
                "liveness probe: disconnect of {} failed: {}",
                crate::api::logging::display_relay(url),
                crate::api::logging::sanitize_relay_text(&e.to_string()),
            ),
        );
    }
    crate::rt::time::sleep(RECONNECT_GRACE).await;
    if let Err(e) = client.connect_relay(url).await {
        crate::api::logging::blog_warn(
            "relay",
            format!(
                "liveness probe: reconnect of {} not started: {}",
                crate::api::logging::display_relay(url),
                crate::api::logging::sanitize_relay_text(&e.to_string()),
            ),
        );
    }
}

/// Reconnect now every relay the SDK holds as `Disconnected`, and say how
/// many there were.
///
/// For the resume path. While the app is in the background the OS cuts every
/// socket, and each relay's connection task then sleeps its retry interval —
/// 10 s, growing to 60 s after repeated failures — before it tries again.
/// `Client::connect` cannot shorten that: it only starts relays that have no
/// connection task (initialized, terminated, sleeping-when-idle). So a daemon
/// message sent while the user paid a bond in their wallet used to wait out
/// that interval after they were back. Bouncing the relay ([`force_reconnect`])
/// replaces the sleeping task with one that connects now; relays connected or
/// already connecting are left alone. All at once: each bounce waits its own
/// grace, and one slow relay must not hold the others.
pub(crate) async fn reconnect_disconnected_now(client: &Client) -> usize {
    let stale: Vec<String> = client
        .relays()
        .await
        .iter()
        .filter(|(_, relay)| relay.status() == RelayStatus::Disconnected)
        .map(|(url, _)| url.to_string())
        .collect();
    futures_util::future::join_all(stale.iter().map(|url| force_reconnect(client, url))).await;
    stale.len()
}

#[cfg(test)]
mod tests {
    use super::*;
    use nostr_sdk::prelude::MockRelay;

    const NOW: i64 = 1_800_000_000;

    /// The property #324 could not hold: a healthy relay must never be
    /// reconnected, however quiet it is. Asking a real relay is what makes
    /// that safe — it answers whether or not it has anything to send.
    /// A relay that drops its first connection right after the handshake —
    /// what the OS does to every socket while the app is in the background —
    /// and keeps every later one open.
    async fn relay_that_drops_the_first_connection() -> String {
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("ws://{}", listener.local_addr().unwrap());
        tokio::spawn(async move {
            let mut first = true;
            while let Ok((stream, _)) = listener.accept().await {
                let drop_it = std::mem::replace(&mut first, false);
                tokio::spawn(async move {
                    if let Ok(mut ws) = tokio_tungstenite::accept_async(stream).await {
                        if drop_it {
                            return;
                        }
                        use futures_util::StreamExt;
                        while ws.next().await.is_some() {}
                    }
                });
            }
        });
        url
    }

    /// Connect `url` and wait for the server to drop it, leaving the SDK's
    /// connection task asleep in its retry interval.
    async fn dropped_relay(url: &str) -> Client {
        let client = Client::new();
        client.add_relay(url).await.expect("add relay");
        client
            .try_connect_relay(url, Duration::from_secs(5))
            .await
            .expect("connect");
        let relay = client
            .relay(url)
            .await
            .expect("relay")
            .expect("known relay");
        for _ in 0..50 {
            if relay.status() == RelayStatus::Disconnected {
                return client;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        panic!("the relay never dropped: {}", relay.status());
    }

    async fn connected_within(client: &Client, url: &str, limit: Duration) -> bool {
        let relay = client
            .relay(url)
            .await
            .expect("relay")
            .expect("known relay");
        let deadline = tokio::time::Instant::now() + limit;
        while tokio::time::Instant::now() < deadline {
            if relay.status() == RelayStatus::Connected {
                return true;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        false
    }

    /// Pins the SDK behaviour this module works around: `Client::connect`
    /// does nothing for a relay whose connection task is asleep in its retry
    /// interval (10 s and up), which is every relay the OS cut while the app
    /// was in the background.
    #[tokio::test]
    async fn connect_does_not_wake_a_relay_asleep_in_its_retry() {
        // Arrange
        let url = relay_that_drops_the_first_connection().await;
        let client = dropped_relay(&url).await;

        // Act
        client.connect().await;

        // Assert
        assert!(!connected_within(&client, &url, Duration::from_secs(3)).await);
    }

    /// The resume fix: a relay dropped in the background reconnects at once,
    /// not when its retry interval runs out — so a daemon message sent while
    /// the user paid in another app arrives as soon as they are back.
    #[tokio::test]
    async fn a_dropped_relay_reconnects_at_once_on_resume() {
        // Arrange
        let url = relay_that_drops_the_first_connection().await;
        let client = dropped_relay(&url).await;

        // Act
        let woken = reconnect_disconnected_now(&client).await;

        // Assert
        assert_eq!(woken, 1);
        assert!(connected_within(&client, &url, Duration::from_secs(3)).await);
    }

    #[tokio::test]
    async fn a_healthy_relay_answers_the_probe() {
        // Arrange: a relay with no traffic at all, which under a silence
        // timer is exactly the false positive that sank the previous attempt.
        let relay = MockRelay::run().await.expect("mock relay");
        let url = relay.url().await;
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        client
            .try_connect_relay(&url, Duration::from_secs(5))
            .await
            .expect("connect");
        let sdk_relay = client
            .relay(&url)
            .await
            .expect("relay")
            .expect("known relay");

        // Act
        let answered = probe_once(&sdk_relay).await;

        // Assert
        assert!(answered, "a silent but healthy relay still answers EOSE");
    }

    /// The probe must not leave its REQ behind: it is a one-shot fetch, and a
    /// subscription that outlived it would consume the per-connection cap the
    /// app already fights over (`req_census`).
    #[tokio::test]
    async fn the_probe_leaves_no_subscription_behind() {
        // Arrange
        let relay = MockRelay::run().await.expect("mock relay");
        let url = relay.url().await;
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        client
            .try_connect_relay(&url, Duration::from_secs(5))
            .await
            .expect("connect");
        let sdk_relay = client
            .relay(&url)
            .await
            .expect("relay")
            .expect("known relay");

        // Act
        assert!(probe_once(&sdk_relay).await);

        // Assert
        assert!(
            sdk_relay.subscriptions().await.is_empty(),
            "the probe's REQ must be closed by the time it returns"
        );
    }

    /// The detection path, which nothing covered until a measurement showed
    /// the first implementation could not detect anything: a relay that
    /// answers nothing must read as unanswered.
    #[tokio::test]
    async fn a_relay_that_answers_nothing_fails_the_probe() {
        // Arrange: connect, then drop the socket so nothing can reply.
        let relay = MockRelay::run().await.expect("mock relay");
        let url = relay.url().await;
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        client
            .try_connect_relay(&url, Duration::from_secs(5))
            .await
            .expect("connect");
        let sdk_relay = client
            .relay(&url)
            .await
            .expect("relay")
            .expect("known relay");
        client.disconnect_relay(&url).await.expect("disconnect");
        tokio::time::sleep(Duration::from_millis(300)).await;

        // Act
        let answered = probe_within(&sdk_relay, Duration::from_millis(800)).await;

        // Assert
        assert!(
            !answered,
            "an unanswered probe must not read as a healthy relay"
        );
    }

    /// The recovery itself: the connection is dropped and restored, which is
    /// the transition `live_subs::repair_relay` re-issues subscriptions on.
    #[tokio::test]
    async fn forcing_a_reconnect_brings_the_relay_back_connected() {
        // Arrange
        let relay = MockRelay::run().await.expect("mock relay");
        let url = relay.url().await;
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        client
            .try_connect_relay(&url, Duration::from_secs(5))
            .await
            .expect("connect");
        let sdk_relay = client
            .relay(&url)
            .await
            .expect("relay")
            .expect("known relay");
        assert_eq!(sdk_relay.status(), RelayStatus::Connected);

        // Act
        force_reconnect(&client, url.as_str()).await;

        // Assert: `connect_relay` only starts the attempt, so the transition
        // the repair listens for lands shortly after, not inline.
        assert!(
            settles_connected(&sdk_relay, Duration::from_secs(5)).await,
            "the bounce must end with the relay connected again, got {:?}",
            sdk_relay.status()
        );
    }

    /// Wait up to `limit` for the relay to report `Connected`.
    async fn settles_connected(relay: &Relay, limit: Duration) -> bool {
        let deadline = tokio::time::Instant::now() + limit;
        while tokio::time::Instant::now() < deadline {
            if relay.status() == RelayStatus::Connected {
                return true;
            }
            tokio::time::sleep(Duration::from_millis(50)).await;
        }
        false
    }

    #[test]
    fn a_quiet_connected_relay_is_asked() {
        assert!(should_probe(
            RelayStatus::Connected,
            Some(NOW - 300),
            Some(NOW - 300),
            NOW
        ));
    }

    /// The measurement that sank #324: 240 s of silence on a healthy relay.
    /// It is long enough to be asked — and asking is all that happens. Nothing
    /// here concludes the relay is dead, which is why a quiet node no longer
    /// means a reconnect every four minutes.
    #[test]
    fn four_minutes_of_silence_asks_rather_than_concludes() {
        assert!(should_probe(
            RelayStatus::Connected,
            Some(NOW - 240),
            None,
            NOW
        ));
    }

    #[test]
    fn recent_traffic_skips_the_probe() {
        assert!(!should_probe(
            RelayStatus::Connected,
            Some(NOW - 5),
            None,
            NOW
        ));
    }

    #[test]
    fn a_relay_that_is_not_connected_is_never_probed() {
        for status in [
            RelayStatus::Disconnected,
            RelayStatus::Connecting,
            RelayStatus::Terminated,
        ] {
            assert!(
                !should_probe(status, None, None, NOW),
                "{status:?} is the SDK's own reconnect to handle"
            );
        }
    }

    /// Without this the timeout path would re-probe on every tick of a relay
    /// that stays silent — the 30-second reconnect loop CodeRabbit found in
    /// #324, one layer up.
    #[test]
    fn a_relay_asked_recently_is_not_asked_again() {
        assert!(!should_probe(
            RelayStatus::Connected,
            Some(NOW - 600),
            Some(NOW - 10),
            NOW
        ));
    }

    #[test]
    fn a_relay_that_never_delivered_anything_is_asked() {
        assert!(should_probe(RelayStatus::Connected, None, None, NOW));
    }

    #[test]
    fn the_probe_filter_can_match_nothing_and_is_not_a_zero_limit() {
        let filter = probe_filter();
        assert_eq!(
            filter.ids.as_ref().map(|ids| ids.len()),
            Some(1),
            "the probe asks for one impossible id"
        );
        assert!(
            filter.limit.is_none(),
            "limit(0) is unanswered by nostr-rs-relay — see probe_filter"
        );
    }

    #[test]
    fn liveness_is_recorded_per_relay() {
        let mut liveness = RelayLiveness::default();
        liveness.record_traffic("wss://a", NOW);
        liveness.record_traffic("wss://b", NOW - 600);

        // One relay's traffic must not vouch for the other's socket.
        assert!(!should_probe(
            RelayStatus::Connected,
            liveness.last_seen("wss://a"),
            None,
            NOW
        ));
        assert!(should_probe(
            RelayStatus::Connected,
            liveness.last_seen("wss://b"),
            None,
            NOW
        ));
    }

    #[test]
    fn forgetting_a_relay_drops_both_stamps() {
        let mut liveness = RelayLiveness::default();
        liveness.record_traffic("wss://a", NOW);
        liveness.record_probe("wss://a", NOW);

        liveness.forget("wss://a");

        assert_eq!(liveness.last_seen("wss://a"), None);
        assert_eq!(liveness.last_probe("wss://a"), None);
    }
}
