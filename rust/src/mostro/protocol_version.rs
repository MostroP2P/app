/// Wire protocol the connected Mostro speaks, from the `protocol_version` tag
/// of its Kind 38385 event.
///
/// A node speaks exactly **one** transport
/// (<https://mostro.network/protocol/transport_migration.html>):
///
/// * `"1"` → NIP-59 gift wrap, Kind 1059 — DEPRECATED and **not supported by
///   this app**. mostrod 0.19.0 drops it; mostro-core has the variant marked
///   for removal (mostro#786).
/// * `"2"` → NIP-44 direct, signed Kind 14 — what this app sends.
/// * **no tag** → a daemon predating the tag, which per the migration guide
///   speaks v1 — also unsupported. Absence is not neutral: the guide states
///   clients must read it as legacy, and only an explicit `"2"` proves a node
///   can decrypt what this v2-native client sends.
///
/// This module exists to make a mismatch legible. The gate is invisible on the
/// wire: a v1 node never decrypts a Kind 14 event, so it does not answer and
/// does not complain, and the client used to surface that as a plain timeout.
/// Reading the tag lets the app say which node it is talking to and why nothing
/// will happen, instead of leaving the user to guess.
///
/// Like `mostro::pow`, the state is one snapshot per capability fetch, tagged
/// with the node it came from: at startup nothing has been fetched, and right
/// after a node switch the store still describes the previous node, and a
/// verdict for one node must never be applied to another.
use std::sync::LazyLock;

use anyhow::{anyhow, Result};
use tokio::sync::watch;

use crate::rt::time::Duration;

/// The only protocol this app speaks.
pub const SUPPORTED_VERSION: u8 = 2;

/// How long [`ensure_supported`] waits for the destination node's capability
/// fetch before failing closed. Mirrors `mostro::pow`: the fetch is bounded by
/// a 10s relay query, so a snapshot that has not arrived by then is not coming.
const CAPABILITY_WAIT: Duration = Duration::from_secs(10);

/// One fetched verdict: the node (hex pubkey) and the `protocol_version` it
/// advertised — `None` when its Kind 38385 event carries no such tag, which
/// means a pre-tag daemon speaking legacy v1, *not* "anything goes".
#[derive(Clone, Debug, PartialEq)]
struct Advertised {
    node: String,
    version: Option<u8>,
}

/// `None` until the first successful capability fetch. A `watch` channel so a
/// wrap can await the generation it needs instead of trusting whatever node's
/// verdict happens to be stored.
static ADVERTISED: LazyLock<watch::Sender<Option<Advertised>>> =
    LazyLock::new(|| watch::channel(None).0);

/// Store the protocol version advertised by `node` (hex pubkey), or `None`
/// when its Kind 38385 event published no `protocol_version` tag. Only called
/// after a *successful* tag fetch — a failed or empty fetch must leave the
/// store alone so "not fetched" stays distinct from "fetched, no tag".
pub fn set_protocol_version(node: &str, version: Option<u8>) {
    ADVERTISED.send_replace(Some(Advertised {
        node: node.to_string(),
        version,
    }));
    match version {
        Some(SUPPORTED_VERSION) => {
            log::info!("[protocol] node {node} speaks v2 (signed kind 14)")
        }
        Some(v) => log::warn!(
            "[protocol] node {node} advertises protocol version {v}, which this app does not \
             speak — messages to it will not be read"
        ),
        None => log::warn!(
            "[protocol] node {node} published no protocol_version — a pre-tag daemon speaks \
             legacy v1, which this app does not"
        ),
    }
}

/// Whether an advertised `protocol_version` is one this app speaks.
///
/// Only an explicit [`SUPPORTED_VERSION`] qualifies. An **absent** tag means a
/// daemon predating it, which the migration guide defines as speaking v1 —
/// treating that as compatible would send Kind 14 events to exactly the nodes
/// that can never read them, recreating the silent timeout this module exists
/// to diagnose. (Malformed values also parse to absent and land here.)
pub fn is_supported(version: Option<u8>) -> bool {
    version == Some(SUPPORTED_VERSION)
}

/// Fail unless `node` (hex pubkey) advertised a protocol this app speaks.
///
/// Resolves only against a capability snapshot fetched *from that node*:
/// until one exists this waits (fetches run when the relay pool comes online
/// and after a node switch), and after [`CAPABILITY_WAIT`] it fails closed
/// with a retryable `NodeCapabilitiesUnknown` marker rather than guess —
/// at startup nothing has been fetched, and right after a node switch the
/// store still holds the previous node's verdict, which must not leak onto
/// the new node in either direction.
///
/// A known-incompatible node fails with `UnsupportedNodeProtocol:{advertised}`
/// (`1` for a tagless pre-tag daemon) — a stable marker Dart localizes.
pub async fn ensure_supported(node: &str) -> Result<()> {
    ensure_supported_within(node, CAPABILITY_WAIT).await
}

/// [`ensure_supported`] with an explicit wait bound, so tests can cover the
/// fail-closed path without a 10-second stall.
async fn ensure_supported_within(node: &str, wait: Duration) -> Result<()> {
    let mut rx = ADVERTISED.subscribe();
    let version = crate::rt::time::timeout(wait, async {
        loop {
            // Scoped so the watch borrow is released before awaiting.
            let fetched = rx
                .borrow_and_update()
                .as_ref()
                .filter(|a| a.node == node)
                .map(|a| a.version);
            if let Some(version) = fetched {
                return version;
            }
            if rx.changed().await.is_err() {
                // The sender is a static and never drops; park until the
                // timeout fires rather than spin.
                std::future::pending::<()>().await;
            }
        }
    })
    .await
    .map_err(|_| anyhow!("NodeCapabilitiesUnknown: capabilities for node {node} not fetched yet"))?;

    if is_supported(version) {
        return Ok(());
    }
    // A tagless daemon predates the tag and speaks v1 (migration guide).
    let advertised = version.map_or_else(|| "1".to_string(), |v| v.to_string());
    Err(anyhow!("UnsupportedNodeProtocol:{advertised}"))
}

/// Read `protocol_version` out of a Kind 38385 tag list. A malformed value is
/// reported and treated as absent.
pub fn parse_protocol_version(tags: &[Vec<String>]) -> Option<u8> {
    let value = tags
        .iter()
        .find(|t| t.first().map(|s| s.as_str()) == Some("protocol_version"))?
        .get(1)?;

    match value.parse::<u8>() {
        Ok(v) => Some(v),
        Err(_) => {
            log::warn!("[protocol] malformed protocol_version tag: {value:?} — treating as absent");
            None
        }
    }
}

/// Reset to "nothing fetched". Only for tests, via
/// `pow::test_support::lock_pow`, which serializes every test touching the
/// process-global node-capability state and calls this on drop.
#[cfg(test)]
pub(crate) fn clear_for_test() {
    ADVERTISED.send_replace(None);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mostro::pow::test_support::lock_pow;

    const SHORT: Duration = Duration::from_millis(50);

    fn tag(name: &str, value: &str) -> Vec<String> {
        vec![name.to_string(), value.to_string()]
    }

    #[test]
    fn only_an_explicit_v2_is_supported() {
        assert!(is_supported(Some(2)));
        // Gift wrap is being removed, not implemented: a v1 node cannot read
        // what this app sends, and saying so beats a silent timeout.
        assert!(!is_supported(Some(1)));
        assert!(!is_supported(Some(3)));
        // Explicit 0 and 255 must not collapse into any sentinel (PR #252
        // review): they are versions this app does not speak, full stop.
        assert!(!is_supported(Some(0)));
        assert!(!is_supported(Some(255)));
        // Absent means a pre-tag daemon, which the migration guide defines as
        // speaking v1 — not "assume compatible".
        assert!(!is_supported(None));
    }

    #[tokio::test]
    async fn a_v2_advertisement_opens_the_gate_for_that_node_only() {
        let _guard = lock_pow();

        set_protocol_version("node-a", Some(2));
        assert!(ensure_supported_within("node-a", SHORT).await.is_ok());

        // The previous node's verdict must never serve the new node — in
        // either direction (PR #252 review, stale-generation window).
        let err = ensure_supported_within("node-b", SHORT).await.unwrap_err();
        assert!(
            err.to_string().starts_with("NodeCapabilitiesUnknown"),
            "got: {err}"
        );
    }

    #[tokio::test]
    async fn explicit_incompatible_versions_fail_with_the_marker() {
        let _guard = lock_pow();

        for (version, marker) in [
            (Some(1), "UnsupportedNodeProtocol:1"),
            (Some(0), "UnsupportedNodeProtocol:0"),
            (Some(255), "UnsupportedNodeProtocol:255"),
            // Tagless = pre-tag daemon = v1 per the migration guide.
            (None, "UnsupportedNodeProtocol:1"),
        ] {
            set_protocol_version("node-a", version);
            let err = ensure_supported_within("node-a", SHORT).await.unwrap_err();
            assert_eq!(err.to_string(), marker);
        }
    }

    #[tokio::test]
    async fn before_any_fetch_the_gate_fails_closed() {
        let _guard = lock_pow();

        let err = ensure_supported_within("node-a", SHORT).await.unwrap_err();
        assert!(
            err.to_string().starts_with("NodeCapabilitiesUnknown"),
            "got: {err}"
        );
    }

    #[tokio::test]
    async fn a_delayed_capability_fetch_unblocks_the_gate() {
        let _guard = lock_pow();

        crate::rt::spawn(async {
            crate::rt::time::sleep(Duration::from_millis(20)).await;
            set_protocol_version("node-a", Some(2));
        });

        ensure_supported_within("node-a", Duration::from_secs(5))
            .await
            .expect("gate must open once the fetch lands");
    }

    #[test]
    fn the_version_is_read_from_the_tag_list() {
        // The shape the reference node (mostro 0.18.0) publishes today.
        let tags = vec![
            tag("mostro_version", "0.18.0"),
            tag("pow", "6"),
            tag("protocol_version", "1"),
        ];

        assert_eq!(parse_protocol_version(&tags), Some(1));
    }

    #[test]
    fn a_node_without_the_tag_reads_as_absent() {
        assert_eq!(parse_protocol_version(&[tag("pow", "6")]), None);
    }

    #[test]
    fn malformed_and_valueless_tags_read_as_absent() {
        assert_eq!(
            parse_protocol_version(&[tag("protocol_version", "two")]),
            None
        );
        assert_eq!(
            parse_protocol_version(&[vec!["protocol_version".to_string()]]),
            None
        );
    }
}
