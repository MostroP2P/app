//! `mostro:` order links: reading one, and finding the order it points at.
//!
//! A node publishes every pending order with a `source` tag that points back
//! to it (mostro `src/nip33.rs`, `create_source_tag`):
//!
//! ```text
//! mostro:<order-id>?relays=<relay>,<relay>&mostro=<node pubkey>
//! ```
//!
//! Nostr clients that render NIP-69 orders show it as a link, and the OS
//! hands it to this app. `mostro=` came later (mostro#678): a link without it
//! belongs to the active node, as it did in v1.
//!
//! Nothing in a link is taken on its word. The order is the newest revision
//! of the Kind 38383 event that the node signed for exactly that order id,
//! and the relays the link names are asked through a client of their own
//! that lives for one lookup: they never join the pool, so a link can
//! neither add relays to the user's list nor get the long-lived
//! subscriptions (`nostr::live_subs`) issued on them.

use anyhow::{anyhow, bail, Result};
use futures_util::future::join;
use futures_util::{stream, StreamExt};
use nostr_sdk::prelude::*;

use crate::nostr::first_answer::{newest_answer, replaceable_rank};
use crate::nostr::order_events::{trade_order_filter, KIND_ORDER};
use crate::nostr::relay_list::normalize_relay_url;
use crate::rt::time::Duration;

/// The scheme of an order link.
pub const ORDER_LINK_SCHEME: &str = "mostro";

/// Relays read from one link at most. A node lists the handful it publishes
/// to; the cap bounds the connections a hostile link can make us open.
pub const MAX_LINK_RELAYS: usize = 8;

/// How long the relays get to answer, the same budget as the other one-shot
/// reads of a node's events (`fetch_mostro_instance_tags`).
pub const LOOKUP_TIMEOUT: Duration = Duration::from_secs(10);

/// How long the lookup keeps listening after the first copy, in case that
/// relay held an older revision. Relays that answer at all answer within a
/// few hundred milliseconds of each other.
const ANSWER_GRACE: Duration = Duration::from_millis(750);

/// What a `mostro:` link says, checked for shape. Nothing here is known to
/// exist until [`find_order_event`] finds it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct OrderLink {
    /// The daemon's order UUID, in its canonical lower-case hyphenated form.
    pub order_id: String,
    /// The link's relays that may be asked ([`is_public_relay`]), normalized,
    /// de-duplicated, at most [`MAX_LINK_RELAYS`].
    pub relays: Vec<String>,
    /// The node that published the order, when the link names it.
    pub node: Option<PublicKey>,
}

impl OrderLink {
    /// Reads `raw` as an order link.
    ///
    /// Lenient about what clients do to a link on its way here — case, a
    /// `//` after the scheme, a trailing slash, percent-encoding, a relay
    /// that is not a public `wss://` URL (dropped) — and strict about what decides
    /// which order is shown: the order id must be a UUID and a `mostro=` that
    /// is present must be a public key. A link whose node cannot be read is
    /// broken, not a link to the active node.
    ///
    /// **Errors**: `InvalidOrderLink` with the reason.
    pub fn parse(raw: &str) -> Result<Self> {
        let url = Url::parse(raw.trim()).map_err(|e| anyhow!("InvalidOrderLink: {e}"))?;
        if url.scheme() != ORDER_LINK_SCHEME {
            bail!("InvalidOrderLink: scheme is {:?}", url.scheme());
        }
        // `mostro:<id>` keeps the id in the path; `mostro://<id>` in the host.
        let id = match url.host_str() {
            Some(host) => format!("{host}{}", url.path()),
            None => url.path().to_string(),
        };
        let order_id = uuid::Uuid::parse_str(id.trim_matches('/'))
            .map_err(|_| anyhow!("InvalidOrderLink: order id {id:?} is not a UUID"))?
            .hyphenated()
            .to_string();

        let mut relays: Vec<String> = Vec::new();
        let mut node = None;
        for (key, value) in url.query_pairs() {
            match key.as_ref() {
                "relays" => {
                    let public = value
                        .split(',')
                        .filter_map(normalize_relay_url)
                        .filter(|relay| is_public_relay(relay));
                    for relay in public {
                        if relays.len() < MAX_LINK_RELAYS && !relays.contains(&relay) {
                            relays.push(relay);
                        }
                    }
                }
                "mostro" => {
                    let key = parse_node(&value).ok_or_else(|| {
                        anyhow!("InvalidOrderLink: node {value:?} is not a public key")
                    })?;
                    node = Some(key);
                }
                _ => {}
            }
        }

        Ok(Self {
            order_id,
            relays,
            node,
        })
    }

    /// The link's relays that `pool_relays` does not already hold, compared
    /// in normalized form.
    pub fn relays_outside(&self, pool_relays: &[String]) -> Vec<String> {
        let in_pool: Vec<String> = pool_relays
            .iter()
            .filter_map(|url| normalize_relay_url(url))
            .collect();
        self.relays
            .iter()
            .filter(|relay| !in_pool.contains(relay))
            .cloned()
            .collect()
    }
}

/// Whether a link may make us connect to `relay`: TLS, to a host on the public
/// internet. A link is anyone's to write, and it is looked up before the user
/// has said anything, so a relay on the user's own machine or network would
/// make a link a way to knock on it. A node publishes on public relays; one
/// on a private network (a test setup) is still reached through the pool.
fn is_public_relay(relay: &str) -> bool {
    use nostr::types::url::Host;
    use std::net::Ipv4Addr;

    fn public_v4(ip: Ipv4Addr) -> bool {
        let [a, b, ..] = ip.octets();
        let shared = a == 100 && (64..128).contains(&b); // RFC 6598
        !(ip.is_private()
            || ip.is_loopback()
            || ip.is_link_local()
            || ip.is_unspecified()
            || ip.is_broadcast()
            || ip.is_documentation()
            || shared)
    }

    let Ok(url) = Url::parse(relay) else {
        return false;
    };
    if url.scheme() != "wss" {
        return false;
    }
    match url.host() {
        Some(Host::Domain(domain)) => {
            let domain = domain.trim_end_matches('.').to_ascii_lowercase();
            domain.contains('.')
                && !domain.ends_with(".localhost")
                && !domain.ends_with(".local")
                && !domain.ends_with(".internal")
        }
        Some(Host::Ipv4(ip)) => public_v4(ip),
        Some(Host::Ipv6(ip)) => match ip.to_ipv4_mapped() {
            Some(v4) => public_v4(v4),
            None => {
                !(ip.is_loopback()
                    || ip.is_unspecified()
                    || ip.is_unique_local()
                    || ip.is_unicast_link_local())
            }
        },
        None => false,
    }
}

/// A node's public key as a link writes it: 64 hex characters, as the daemon
/// does, or an `npub`. Stricter than `PublicKey::parse`, which also reads a
/// key with bytes trailing it.
fn parse_node(value: &str) -> Option<PublicKey> {
    let value = value.trim();
    if value.len() == 64 && value.bytes().all(|b| b.is_ascii_hexdigit()) {
        PublicKey::from_hex(value).ok()
    } else if value.starts_with("npub1") {
        PublicKey::from_bech32(value).ok()
    } else {
        None
    }
}

/// The newest revision of `order_id`'s Kind 38383 event that `node` signed.
///
/// Asks `pool` — the app's client, when it has one — and `extra_relays`,
/// through a short-lived client of their own, at once. A relay is not
/// trusted to honour the filter: author, kind and `d` tag are checked again
/// here (nostr-sdk has already checked the signature). Returns on the first
/// copy plus [`ANSWER_GRACE`], or `None` once every relay finished, or
/// [`LOOKUP_TIMEOUT`] passed, without one.
///
/// `extra_relays` must not hold the pool's own relays: those would be asked
/// twice, over a second connection ([`OrderLink::relays_outside`]).
pub async fn find_order_event(
    pool: Option<&Client>,
    extra_relays: &[String],
    node: &PublicKey,
    order_id: &str,
) -> Option<Event> {
    let filter = trade_order_filter(node, order_id);

    // Both sent at once: neither waits on the other's relays.
    let ask_pool = async {
        match pool {
            Some(client) => events_from(client, filter.clone()).await,
            None => stream::empty().boxed(),
        }
    };
    let ask_link = async {
        let client = lookup_client(extra_relays).await;
        let events = match &client {
            Some(client) => events_from(client, filter.clone()).await,
            None => stream::empty().boxed(),
        };
        (client, events)
    };
    let (from_pool, (lookup_client, from_link)) = join(ask_pool, ask_link).await;

    let answers = stream::select(from_pool, from_link)
        .filter(|event| std::future::ready(is_revision_of(event, node, order_id)));
    let newest = newest_answer(Box::pin(answers), ANSWER_GRACE, replaceable_rank).await;

    if let Some(client) = lookup_client {
        client.shutdown().await;
    }
    newest
}

/// Whether `event` is a revision of `order_id` as `node` publishes it.
fn is_revision_of(event: &Event, node: &PublicKey, order_id: &str) -> bool {
    event.pubkey == *node
        && event.kind.as_u16() == KIND_ORDER
        && event.tags.identifier().as_deref() == Some(order_id)
}

/// The events `client` streams for `filter`, errors logged and dropped. An
/// empty stream when the request cannot even be made (no relay to ask).
async fn events_from(client: &Client, filter: Filter) -> stream::BoxStream<'static, Event> {
    match client.stream_events(filter).timeout(LOOKUP_TIMEOUT).await {
        Ok(events) => events
            .filter_map(|(relay, item)| async move {
                item.inspect_err(|e| log::debug!("[order-link] {relay}: {e}"))
                    .ok()
            })
            .boxed(),
        Err(e) => {
            log::debug!("[order-link] lookup not sent: {e}");
            stream::empty().boxed()
        }
    }
}

/// A client on `relays` alone, connecting in the background — a request sent
/// before a relay is up waits for it. `None` when there is nothing to ask.
async fn lookup_client(relays: &[String]) -> Option<Client> {
    let client = Client::new();
    let mut added = 0;
    for relay in relays {
        match client.add_relay(relay.as_str()).await {
            Ok(_) => added += 1,
            Err(e) => log::debug!("[order-link] relay {relay} skipped: {e}"),
        }
    }
    if added == 0 {
        return None;
    }
    client.connect().await;
    Some(client)
}

#[cfg(test)]
mod tests {
    use super::*;

    const ORDER_ID: &str = "e215c07e-b1f9-45b0-9640-0295067ee99a";
    const NODE_HEX: &str = "82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390";

    fn node() -> PublicKey {
        PublicKey::from_hex(NODE_HEX).unwrap()
    }

    fn invalid(raw: &str) -> String {
        OrderLink::parse(raw).unwrap_err().to_string()
    }

    // ── Reading a link ───────────────────────────────────────────────────────

    /// The example of mostro's `docs/SOURCE_TAG_PUBKEY.md`, as the daemon
    /// writes it into the `source` tag.
    #[test]
    fn reads_the_link_a_node_publishes() {
        let link = OrderLink::parse(&format!(
            "mostro:{ORDER_ID}?relays=wss://relay.mostro.network,wss://nos.lol&mostro={NODE_HEX}"
        ))
        .unwrap();

        assert_eq!(
            link,
            OrderLink {
                order_id: ORDER_ID.to_string(),
                relays: vec![
                    "wss://relay.mostro.network".to_string(),
                    "wss://nos.lol".to_string()
                ],
                node: Some(node()),
            }
        );
    }

    /// Daemons before mostro#678 wrote no `mostro=`: the link names no node,
    /// and the caller falls back to the active one.
    #[test]
    fn a_link_from_an_older_daemon_names_no_node() {
        let link = OrderLink::parse(&format!("mostro:{ORDER_ID}?relays=wss://nos.lol")).unwrap();

        assert_eq!(link.node, None);
        assert_eq!(link.relays, vec!["wss://nos.lol"]);
    }

    #[test]
    fn a_link_without_relays_is_still_a_link() {
        let link = OrderLink::parse(&format!("mostro:{ORDER_ID}?mostro={NODE_HEX}")).unwrap();

        assert!(link.relays.is_empty());
        assert_eq!(link.node, Some(node()));
    }

    /// What a chat app or the OS may do to a link before it arrives.
    #[test]
    fn tolerates_what_a_link_goes_through_on_its_way() {
        let upper = ORDER_ID.to_uppercase();
        let encoded = "relays=wss%3A%2F%2Fnos.lol%2Cwss%3A%2F%2Frelay.mostro.network";
        for raw in [
            format!(" MOSTRO:{upper}?{encoded} "),
            format!("mostro://{ORDER_ID}?{encoded}"),
            format!("mostro:{ORDER_ID}/?{encoded}"),
        ] {
            let link = OrderLink::parse(&raw).unwrap_or_else(|e| panic!("{raw}: {e}"));
            assert_eq!(link.order_id, ORDER_ID, "{raw}");
            assert_eq!(
                link.relays,
                vec!["wss://nos.lol", "wss://relay.mostro.network"],
                "{raw}"
            );
        }
    }

    #[test]
    fn a_node_may_be_named_by_its_npub() {
        let npub = node().to_bech32().unwrap();

        let link = OrderLink::parse(&format!("mostro:{ORDER_ID}?mostro={npub}")).unwrap();

        assert_eq!(link.node, Some(node()));
    }

    #[test]
    fn keeps_websocket_relays_once_each_and_no_more_than_the_cap() {
        let many: Vec<String> = (0..MAX_LINK_RELAYS + 3)
            .map(|i| format!("wss://relay{i}.example.com"))
            .collect();
        let raw = format!(
            "mostro:{ORDER_ID}?relays=https://not.a.relay,WSS://NOS.LOL/,wss://nos.lol,{}",
            many.join(",")
        );

        let link = OrderLink::parse(&raw).unwrap();

        assert_eq!(link.relays.len(), MAX_LINK_RELAYS);
        assert_eq!(link.relays[0], "wss://nos.lol");
        assert!(!link.relays.iter().any(|r| r.starts_with("https")));
    }

    /// Looked up before the user is asked anything: a link must not turn the
    /// app into a way to reach the user's own machine or network.
    #[test]
    fn asks_only_public_relays_over_tls() {
        let raw = format!(
            "mostro:{ORDER_ID}?relays={}",
            [
                "ws://plain.example.com",
                "wss://localhost:7777",
                "wss://relay.localhost",
                "wss://printer.local",
                "wss://router",
                "wss://127.0.0.1",
                "wss://10.0.0.2",
                "wss://172.16.5.4",
                "wss://192.168.1.1:8080",
                "wss://169.254.10.10",
                "wss://100.64.0.1",
                "wss://[::1]",
                "wss://[fd00::1]",
                "wss://[fe80::1]",
                "wss://[::ffff:192.168.1.1]",
                "wss://nos.lol",
                "wss://203.0.114.7",
            ]
            .join(",")
        );

        let link = OrderLink::parse(&raw).unwrap();

        assert_eq!(link.relays, vec!["wss://nos.lol", "wss://203.0.114.7"]);
    }

    #[test]
    fn refuses_what_is_not_an_order_link() {
        for raw in [
            format!("nostr:{ORDER_ID}"),
            format!("https://mostro.network/{ORDER_ID}"),
            "mostro:".to_string(),
            "mostro:not-an-order?relays=wss://nos.lol".to_string(),
            "not a link at all".to_string(),
        ] {
            assert!(invalid(&raw).starts_with("InvalidOrderLink"), "{raw}");
        }
    }

    /// The node decides whose orders are shown: one that cannot be read must
    /// not quietly become the active node.
    #[test]
    fn refuses_a_link_whose_node_cannot_be_read() {
        for node in ["82fa8cb9", "zz", &format!("{NODE_HEX}00")] {
            let raw = format!("mostro:{ORDER_ID}?mostro={node}");
            assert!(invalid(&raw).starts_with("InvalidOrderLink"), "{raw}");
        }
    }

    #[test]
    fn asks_only_the_link_relays_the_pool_does_not_hold() {
        let link = OrderLink::parse(&format!(
            "mostro:{ORDER_ID}?relays=wss://relay.mostro.network,wss://nos.lol,wss://extra.example.com"
        ))
        .unwrap();

        let outside = link.relays_outside(&[
            "wss://Relay.Mostro.Network/".to_string(),
            "wss://nos.lol".to_string(),
        ]);

        assert_eq!(outside, vec!["wss://extra.example.com"]);
    }

    // ── Finding the order ────────────────────────────────────────────────────

    fn order_event(keys: &Keys, order_id: &str, status: &str, revision_at: u64) -> Event {
        EventBuilder::new(Kind::from(KIND_ORDER), "")
            .tags([
                Tag::parse(["d", order_id]).unwrap(),
                Tag::parse(["k", "sell"]).unwrap(),
                Tag::parse(["s", status]).unwrap(),
                Tag::parse(["f", "USD"]).unwrap(),
                Tag::parse(["fa", "20"]).unwrap(),
                Tag::parse(["z", "order"]).unwrap(),
            ])
            .custom_created_at(Timestamp::from_secs(revision_at))
            .finalize(keys)
            .unwrap()
    }

    #[test]
    fn a_revision_is_the_nodes_order_event_for_that_id_only() {
        let node = Keys::generate();
        let id = uuid::Uuid::new_v4().to_string();

        let own = order_event(&node, &id, "pending", 1_000);
        let other_order = order_event(&node, &uuid::Uuid::new_v4().to_string(), "pending", 1_000);
        let impostor = order_event(&Keys::generate(), &id, "pending", 1_000);

        assert!(is_revision_of(&own, &node.public_key(), &id));
        assert!(!is_revision_of(&other_order, &node.public_key(), &id));
        assert!(!is_revision_of(&impostor, &node.public_key(), &id));
    }

    /// A relay holding the events, and its URL.
    async fn relay_with(events: &[Event]) -> (nostr_sdk::local_relay::MockRelay, String) {
        use nostr_sdk::local_relay::MockRelay;

        let relay = MockRelay::run().await.expect("mock relay");
        let url = relay.url().await.to_string();
        let publisher = Client::new();
        publisher.add_relay(&url).await.expect("add relay");
        publisher
            .try_connect_relay(&url, std::time::Duration::from_secs(3))
            .await
            .expect("connect");
        for event in events {
            publisher.send_event(event).await.expect("publish");
        }
        publisher.shutdown().await;
        (relay, url)
    }

    /// The common case for a link to another node: the order lives on relays
    /// the pool has never heard of.
    #[tokio::test]
    async fn finds_the_order_on_the_relays_the_link_names() {
        let node = Keys::generate();
        let id = uuid::Uuid::new_v4().to_string();
        let (_relay, url) = relay_with(&[order_event(&node, &id, "pending", 1_000)]).await;

        let found = find_order_event(None, &[url], &node.public_key(), &id).await;

        assert_eq!(found.map(|e| e.tags.identifier()), Some(Some(id)));
    }

    #[tokio::test]
    async fn finds_the_order_through_the_pool() {
        let node = Keys::generate();
        let id = uuid::Uuid::new_v4().to_string();
        let (_relay, url) = relay_with(&[order_event(&node, &id, "pending", 1_000)]).await;
        let pool = Client::new();
        pool.add_relay(&url).await.unwrap();
        pool.connect().await;

        let found = find_order_event(Some(&pool), &[], &node.public_key(), &id).await;

        assert!(found.is_some());
    }

    /// A link shared while the order was pending may be opened after it was
    /// taken: what is shown is the order now.
    #[tokio::test]
    async fn the_newest_revision_wins() {
        let node = Keys::generate();
        let id = uuid::Uuid::new_v4().to_string();
        let (_old, old_url) = relay_with(&[order_event(&node, &id, "pending", 1_000)]).await;
        let (_new, new_url) = relay_with(&[order_event(&node, &id, "canceled", 2_000)]).await;

        let found = find_order_event(None, &[old_url, new_url], &node.public_key(), &id)
            .await
            .expect("found");

        assert_eq!(found.created_at, Timestamp::from_secs(2_000));
    }

    /// Anyone can publish a Kind 38383 with any `d` tag: only the node named
    /// by the link speaks for its orders.
    #[tokio::test]
    async fn another_authors_event_for_the_same_order_is_not_the_order() {
        let node = Keys::generate();
        let id = uuid::Uuid::new_v4().to_string();
        let (_relay, url) =
            relay_with(&[order_event(&Keys::generate(), &id, "pending", 1_000)]).await;

        let found = find_order_event(None, &[url], &node.public_key(), &id).await;

        assert!(found.is_none());
    }

    #[tokio::test]
    async fn nothing_to_ask_finds_nothing() {
        let found = find_order_event(None, &[], &node(), ORDER_ID).await;

        assert!(found.is_none());
    }
}
