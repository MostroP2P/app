//! Read a replaceable event without waiting for the slowest relay.
//!
//! `fetch_events` returns once **every** relay has sent EOSE, so one relay
//! that sits on a REQ holds the answer back for the whole timeout — and at
//! startup the node's Kind 38385 used to cost ten seconds that way while three
//! other relays had answered in a third of one. A replaceable event needs no
//! such quorum: any copy will do, the newest is the right one, and relays that
//! answer at all answer within moments of each other.

use futures_util::{Stream, StreamExt};

use crate::rt::time::{timeout, Duration};

/// The newest of the answers in `answers`: the first one, plus whatever else
/// arrives within `grace` of it. `None` when the stream ends without any.
///
/// `grace` exists for the relay holding a stale copy that answers first; it
/// is counted from the first answer, so a source with nothing to say is
/// bounded by the stream's own timeout, not by this.
/// `rank` orders two answers, greater winning; equal ranks are copies of one
/// event and the first to arrive stays. For a replaceable event that rank is
/// NIP-01's — `created_at`, then the **lowest** id ([`replaceable_rank`]) — so
/// which relay answers first never decides between two revisions of a second.
pub(crate) async fn newest_answer<T, K: Ord>(
    mut answers: impl Stream<Item = T> + Unpin,
    grace: Duration,
    rank: impl Fn(&T) -> K,
) -> Option<T> {
    let mut newest = answers.next().await?;
    // Elapsing is the expected way out: it means a relay is still silent.
    let _ = timeout(grace, async {
        while let Some(answer) = answers.next().await {
            if rank(&answer) > rank(&newest) {
                newest = answer;
            }
        }
    })
    .await;
    Some(newest)
}

/// The rank of a replaceable event among its revisions: newer first, and
/// within one second the lowest id, which is the one relays retain (NIP-01).
pub(crate) fn replaceable_rank(
    event: &nostr_sdk::prelude::Event,
) -> (u64, std::cmp::Reverse<[u8; 32]>) {
    (
        event.created_at.as_secs(),
        std::cmp::Reverse(event.id.to_bytes()),
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::sync::mpsc;
    use tokio::time::Instant;

    const GRACE: Duration = Duration::from_millis(200);

    /// An answer is `(created_at, label)`.
    type Answer = (u64, &'static str);

    fn stream(rx: mpsc::UnboundedReceiver<Answer>) -> impl Stream<Item = Answer> + Unpin {
        Box::pin(futures_util::stream::unfold(rx, |mut rx| async {
            rx.recv().await.map(|answer| (answer, rx))
        }))
    }

    fn stamp(answer: &Answer) -> u64 {
        answer.0
    }

    #[tokio::test(start_paused = true)]
    async fn returns_without_waiting_for_a_source_that_stays_silent() {
        // Arrange: one relay answers, another holds the stream open for 10 s.
        let (tx, rx) = mpsc::unbounded_channel::<Answer>();
        tx.send((100, "fast")).unwrap();
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(10)).await;
            drop(tx);
        });
        let started = Instant::now();

        // Act
        let got = newest_answer(stream(rx), GRACE, stamp).await;

        // Assert
        assert_eq!(got, Some((100, "fast")));
        assert_eq!(started.elapsed(), GRACE);
    }

    #[tokio::test(start_paused = true)]
    async fn a_newer_answer_inside_the_grace_window_wins() {
        // Arrange: the stale copy arrives first.
        let (tx, rx) = mpsc::unbounded_channel::<Answer>();
        tx.send((100, "stale")).unwrap();
        tokio::spawn(async move {
            tokio::time::sleep(GRACE / 2).await;
            tx.send((200, "fresh")).unwrap();
            std::future::pending::<()>().await;
        });

        // Act
        let got = newest_answer(stream(rx), GRACE, stamp).await;

        // Assert
        assert_eq!(got, Some((200, "fresh")));
    }

    #[tokio::test(start_paused = true)]
    async fn an_older_answer_does_not_replace_a_newer_one() {
        // Arrange
        let (tx, rx) = mpsc::unbounded_channel::<Answer>();
        tx.send((200, "fresh")).unwrap();
        tx.send((100, "stale")).unwrap();
        drop(tx);

        // Act
        let got = newest_answer(stream(rx), GRACE, stamp).await;

        // Assert
        assert_eq!(got, Some((200, "fresh")));
    }

    #[tokio::test(start_paused = true)]
    async fn ends_as_soon_as_every_source_has_answered() {
        // Arrange: the stream closes (all EOSE) well inside the window.
        let (tx, rx) = mpsc::unbounded_channel::<Answer>();
        tx.send((100, "only")).unwrap();
        drop(tx);
        let started = Instant::now();

        // Act
        let got = newest_answer(stream(rx), GRACE, stamp).await;

        // Assert
        assert_eq!(got, Some((100, "only")));
        assert_eq!(started.elapsed(), Duration::ZERO);
    }

    #[tokio::test(start_paused = true)]
    async fn no_answer_at_all_is_none() {
        // Arrange
        let (tx, rx) = mpsc::unbounded_channel::<Answer>();
        drop(tx);

        // Act
        let got = newest_answer(stream(rx), GRACE, stamp).await;

        // Assert
        assert_eq!(got, None);
    }

    #[tokio::test(start_paused = true)]
    async fn two_revisions_of_one_second_resolve_to_the_lowest_id_in_either_order() {
        use nostr_sdk::prelude::*;

        // Arrange: same author, same second, different content → different ids.
        let keys = Keys::generate();
        let revision = |content: &str| -> Event {
            EventBuilder::new(Kind::from(38385u16), content)
                .custom_created_at(Timestamp::from_secs(100))
                .finalize(&keys)
                .unwrap()
        };
        let (a, b) = (revision("a"), revision("b"));
        let lowest = if a.id.to_bytes() < b.id.to_bytes() { a.id } else { b.id };

        for arrival in [[a.clone(), b.clone()], [b, a]] {
            // Act
            let answers = Box::pin(futures_util::stream::iter(arrival));
            let got = newest_answer(answers, GRACE, replaceable_rank).await;

            // Assert
            assert_eq!(got.map(|event| event.id), Some(lowest));
        }
    }
}
