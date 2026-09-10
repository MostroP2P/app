/// NIP-13 Proof of Work difficulties required by the connected Mostro.
///
/// Both are published in the daemon's Kind 38385 event and set when the relay
/// pool goes online:
///
/// * `pow` — required of **every** event the client sends.
/// * `pow_first_contact` — required when the visible sender is a trade key the
///   node does not yet associate with an active order or dispute: creating an
///   order, taking one, or a restore under a fresh trade key. Never lower than
///   `pow`, typically higher.
///
/// An under-powered event is dropped before the daemon decrypts anything, with
/// no `cant-do` and no error of any kind — mining against `pow` when the node
/// charges `pow_first_contact` makes order creation silently do nothing
/// (issue #177, <https://mostro.network/protocol/transport_migration.html>).
///
/// **An absent `pow_first_contact` tag means unknown, not zero and not `pow`.**
/// Daemons that enforce a first-contact difficulty but predate the tag exist,
/// so the tag parses to `None` rather than a number and
/// [`first_contact_pow_for`] falls back to at least `pow`.
use std::sync::LazyLock;

use anyhow::{anyhow, Result};
use tokio::sync::watch;

use crate::rt::time::Duration;

/// How long a first-contact wrap waits for the destination node's capability
/// fetch before failing closed. The fetch itself is bounded by a 10s relay
/// query, so a snapshot that has not arrived by then is not coming.
const CAPABILITY_WAIT: Duration = Duration::from_secs(10);

/// One capability generation: both difficulties plus the node (hex pubkey)
/// they were fetched from. Published as a single value so a reader can never
/// observe `pow` from one refresh and `pow_first_contact` from another — and,
/// as important, so a reader can tell *whose* difficulties these are: at
/// startup nothing has been fetched yet, and right after a node switch the
/// stored generation still belongs to the previous node.
#[derive(Clone, Debug, PartialEq)]
struct Capabilities {
    node: String,
    pow: u8,
    first_contact: Option<u8>,
}

/// `None` until the first successful capability fetch. A `watch` channel so a
/// first-contact wrap can await the generation it needs instead of reading
/// whatever happens to be stored.
static CAPS: LazyLock<watch::Sender<Option<Capabilities>>> =
    LazyLock::new(|| watch::channel(None).0);

/// Store both PoW difficulties fetched from `node` (hex pubkey) as one
/// snapshot: `pow` for every outgoing event, and `pow_first_contact` (`None`
/// when the node published no such tag). A single setter on purpose —
/// publishing the values separately would let a concurrent wrap mine against
/// one fresh and one stale value.
pub fn set_pows(node: &str, pow: u8, first_contact: Option<u8>) {
    CAPS.send_replace(Some(Capabilities {
        node: node.to_string(),
        pow,
        first_contact,
    }));
    match first_contact {
        Some(d) => log::info!("[pow] node {node}: difficulty set to {pow}, first-contact to {d}"),
        None => log::info!(
            "[pow] node {node}: difficulty set to {pow}; no pow_first_contact published — \
             first-contact difficulty unknown"
        ),
    }
}

/// Current PoW difficulty.  Returns 0 when no PoW is required.
///
/// Deliberately node-agnostic, unlike [`first_contact_pow_for`]: the events
/// mined at this difficulty act on orders the daemon already knows, which can
/// only exist after at least one successful capability fetch, and blocking
/// every mid-trade send on a re-fetch would hurt more than a briefly stale
/// difficulty does.
pub fn get_pow() -> u8 {
    CAPS.borrow().as_ref().map_or(0, |c| c.pow)
}

/// Difficulty to mine a first-contact event for `node` (hex pubkey) at,
/// resolved per [`resolve_first_contact`] — but only from a capability
/// snapshot that was actually fetched *from that node*.
///
/// Until such a snapshot exists this waits (capability fetches run
/// asynchronously when the relay pool comes online and after a node switch),
/// and after [`CAPABILITY_WAIT`] it fails closed with a `PowUnknown` error
/// rather than guess: at startup the store holds nothing, and right after a
/// node switch it still holds the previous node's — possibly lower —
/// difficulties, and an under-mined first-contact event is dropped silently
/// (issue #177), which is strictly worse than an explicit error the user can
/// retry.
pub async fn first_contact_pow_for(node: &str) -> Result<u8> {
    first_contact_pow_within(node, CAPABILITY_WAIT).await
}

/// [`first_contact_pow_for`] with an explicit wait bound, so tests can cover
/// the fail-closed path without a 10-second stall.
async fn first_contact_pow_within(node: &str, wait: Duration) -> Result<u8> {
    let mut rx = CAPS.subscribe();
    crate::rt::time::timeout(wait, async {
        loop {
            // Scoped so the watch borrow is released before awaiting.
            let ready = rx
                .borrow_and_update()
                .as_ref()
                .filter(|c| c.node == node)
                .map(|c| resolve_first_contact(c.pow, c.first_contact));
            if let Some(pow) = ready {
                return pow;
            }
            if rx.changed().await.is_err() {
                // The sender is a static and never drops; park until the
                // timeout fires rather than spin.
                std::future::pending::<()>().await;
            }
        }
    })
    .await
    .map_err(|_| {
        anyhow!("PowUnknown: capabilities for node {node} not fetched yet — refusing to mine a first-contact event at a difficulty that may be too low")
    })
}

/// The first-contact difficulty implied by [`pow`](get_pow) and an optional
/// `pow_first_contact`:
///
/// * published → that value, but never below `pow` (the protocol states it is
///   never lower; a node advertising otherwise is clamped rather than trusted).
/// * absent → `pow`, the documented floor for an unknown first-contact
///   difficulty. That may still be too low, which no client can detect from the
///   event alone: silence is the gate's only feedback.
pub fn resolve_first_contact(pow: u8, first_contact: Option<u8>) -> u8 {
    match first_contact {
        Some(d) => d.max(pow),
        None => pow,
    }
}

/// Read both PoW difficulties out of a Kind 38385 tag list.
///
/// A malformed value is reported and treated as if the tag were absent, which
/// for `pow` means 0 and for `pow_first_contact` means unknown.
pub fn parse_pow_tags(tags: &[Vec<String>]) -> (u8, Option<u8>) {
    (
        parse_difficulty(tags, "pow").unwrap_or(0),
        parse_difficulty(tags, "pow_first_contact"),
    )
}

fn parse_difficulty(tags: &[Vec<String>], name: &str) -> Option<u8> {
    let value = tags
        .iter()
        .find(|t| t.first().map(|s| s.as_str()) == Some(name))?
        .get(1)?;

    match value.parse::<u8>() {
        Ok(d) => Some(d),
        Err(_) => {
            log::warn!("[pow] malformed {name} tag value: {value:?} — treating as absent");
            None
        }
    }
}

/// Serializes tests that touch the process-global PoW snapshot — they live in
/// this module and in `mostro::actions` — and restores the "nothing
/// advertised" default on drop so no test leaks a difficulty into another.
#[cfg(test)]
pub(crate) mod test_support {
    use std::sync::{Mutex, MutexGuard, PoisonError};

    static LOCK: Mutex<()> = Mutex::new(());

    pub(crate) struct PowGuard(#[allow(dead_code)] MutexGuard<'static, ()>);

    impl Drop for PowGuard {
        fn drop(&mut self) {
            super::CAPS.send_replace(None);
            crate::mostro::protocol_version::clear_for_test();
        }
    }

    pub(crate) fn lock_pow() -> PowGuard {
        PowGuard(LOCK.lock().unwrap_or_else(PoisonError::into_inner))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tag(name: &str, value: &str) -> Vec<String> {
        vec![name.to_string(), value.to_string()]
    }

    #[test]
    fn an_absent_first_contact_tag_falls_back_to_pow() {
        // Not 0: the tag being absent means the difficulty is unknown, and
        // mining below `pow` would be dropped for certain.
        assert_eq!(resolve_first_contact(6, None), 6);
        assert_eq!(resolve_first_contact(0, None), 0);
    }

    #[test]
    fn a_published_first_contact_difficulty_is_used() {
        assert_eq!(resolve_first_contact(6, Some(12)), 12);
    }

    #[test]
    fn a_first_contact_difficulty_below_pow_is_clamped() {
        // The protocol states it is never lower than `pow`; a node saying
        // otherwise gets clamped rather than trusted, since `pow` applies to
        // every event including this one.
        assert_eq!(resolve_first_contact(6, Some(2)), 6);
    }

    /// Regression for the refresh race (PR #251 review): both difficulties are
    /// published as one snapshot, so the absent → advertised transition can
    /// never be observed half-applied by a first-contact wrap.
    #[tokio::test]
    async fn a_refresh_publishes_both_difficulties_together() {
        let _guard = test_support::lock_pow();

        set_pows("node-a", 6, None);
        assert_eq!(get_pow(), 6);
        assert_eq!(first_contact_pow_within("node-a", SHORT).await.unwrap(), 6);

        set_pows("node-a", 6, Some(12));
        assert_eq!(get_pow(), 6);
        assert_eq!(first_contact_pow_within("node-a", SHORT).await.unwrap(), 12);
    }

    /// A short bound for waits the test expects to succeed immediately or to
    /// fail closed without stalling the suite.
    const SHORT: Duration = Duration::from_millis(50);

    /// Regression for ermeme's P1 on PR #251, startup window: before any
    /// capability fetch has completed there is no snapshot, and a
    /// first-contact wrap must fail closed instead of mining at 0.
    #[tokio::test]
    async fn before_any_fetch_first_contact_fails_closed() {
        let _guard = test_support::lock_pow();

        let err = first_contact_pow_within("node-a", SHORT).await.unwrap_err();
        assert!(err.to_string().starts_with("PowUnknown"), "got: {err}");
    }

    /// Regression for ermeme's P1 on PR #251, node-switch window: the previous
    /// node's snapshot must never satisfy a first-contact wrap for the new
    /// node, no matter how fresh it is.
    #[tokio::test]
    async fn a_previous_nodes_snapshot_never_serves_the_new_node() {
        let _guard = test_support::lock_pow();

        set_pows("node-a", 1, Some(2));
        let err = first_contact_pow_within("node-b", SHORT).await.unwrap_err();
        assert!(err.to_string().starts_with("PowUnknown"), "got: {err}");
    }

    /// The wait side of the gate: a wrap that arrives while the capability
    /// fetch is still in flight blocks until the fetch lands, then mines at
    /// the fetched difficulty — no error, no under-mining.
    #[tokio::test]
    async fn a_delayed_capability_fetch_unblocks_the_wait() {
        let _guard = test_support::lock_pow();

        crate::rt::spawn(async {
            crate::rt::time::sleep(Duration::from_millis(20)).await;
            set_pows("node-a", 6, Some(12));
        });

        let pow = first_contact_pow_within("node-a", Duration::from_secs(5))
            .await
            .unwrap();
        assert_eq!(pow, 12);
    }

    #[test]
    fn both_difficulties_are_read_from_the_tag_list() {
        let tags = vec![
            tag("mostro_version", "0.18.0"),
            tag("pow", "6"),
            tag("pow_first_contact", "12"),
        ];

        assert_eq!(parse_pow_tags(&tags), (6, Some(12)));
    }

    #[test]
    fn a_node_publishing_only_pow_leaves_first_contact_unknown() {
        // What the daemon at 0.18.0 actually advertises today.
        let tags = vec![tag("pow", "6"), tag("protocol_version", "1")];

        assert_eq!(parse_pow_tags(&tags), (6, None));
    }

    #[test]
    fn malformed_values_are_treated_as_absent() {
        let tags = vec![tag("pow", "many"), tag("pow_first_contact", "-1")];

        assert_eq!(parse_pow_tags(&tags), (0, None));
    }

    #[test]
    fn a_valueless_tag_is_treated_as_absent() {
        let tags = vec![
            vec!["pow".to_string()],
            vec!["pow_first_contact".to_string()],
        ];

        assert_eq!(parse_pow_tags(&tags), (0, None));
    }
}
