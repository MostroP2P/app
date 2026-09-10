//! Kind 10002 (NIP-65) relay list published by a Mostro node.
//!
//! The daemon announces the relays it reads from and writes to as `r` tags.
//! Both directions matter to a client — we read its Kind 38383 / Kind 14
//! events where it writes, and it reads our Kind 14 messages where it reads
//! — so every `r` tag is taken regardless of its read/write marker.
//!
//! Reference: <https://github.com/nostr-protocol/nips/blob/master/65.md>
use nostr_sdk::prelude::*;

/// Kind 10002 — NIP-65 relay list metadata.
pub const KIND_RELAY_LIST: u16 = 10002;

/// Filter for the newest relay list of a node. Kind 10002 is replaceable,
/// so a relay holds at most one per author; `limit(1)` only trims the
/// duplicates a multi-relay fetch returns.
pub fn relay_list_filter(mostro_pubkey: &PublicKey) -> Filter {
    Filter::new()
        .kind(Kind::from(KIND_RELAY_LIST))
        .author(*mostro_pubkey)
        .limit(1)
}

/// The relay URLs announced by a Kind 10002 event, normalised and
/// de-duplicated in tag order. Tags that are not `r`, that carry no URL, or
/// whose URL is not a WebSocket URL are skipped.
pub fn parse_relay_list(event: &Event) -> Vec<String> {
    let mut urls: Vec<String> = Vec::new();
    for tag in event.tags.iter() {
        let parts = tag.as_slice();
        if parts.first().map(String::as_str) != Some("r") {
            continue;
        }
        let Some(url) = parts.get(1).and_then(|raw| normalize_relay_url(raw)) else {
            continue;
        };
        if !urls.contains(&url) {
            urls.push(url);
        }
    }
    urls
}

/// Canonical form of a relay URL for equality checks: trimmed, scheme and
/// host lower-cased, no trailing slash. Returns `None` unless the scheme is
/// `ws` or `wss` and a host is present.
pub fn normalize_relay_url(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    let (scheme, rest) = trimmed.split_once("://")?;
    let scheme = scheme.to_ascii_lowercase();
    if scheme != "ws" && scheme != "wss" {
        return None;
    }
    let rest = rest.trim_end_matches('/');
    let (host, path) = match rest.find('/') {
        Some(i) => (&rest[..i], &rest[i..]),
        None => (rest, ""),
    };
    if host.is_empty() {
        return None;
    }
    Some(format!("{scheme}://{}{path}", host.to_ascii_lowercase()))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn relay_list_event(tags: &[&[&str]]) -> Event {
        EventBuilder::new(Kind::from(KIND_RELAY_LIST), "")
            .tags(tags.iter().map(|t| Tag::parse(t.iter().copied()).unwrap()))
            .finalize(&Keys::generate())
            .unwrap()
    }

    #[test]
    fn takes_every_r_tag_regardless_of_marker() {
        let event = relay_list_event(&[
            &["r", "wss://relay.mostro.network"],
            &["r", "wss://nos.lol", "read"],
            &["r", "wss://mostro-p2p.tech", "write"],
        ]);

        let urls = parse_relay_list(&event);

        assert_eq!(
            urls,
            vec!["wss://relay.mostro.network", "wss://nos.lol", "wss://mostro-p2p.tech"]
        );
    }

    #[test]
    fn normalises_and_dedupes_urls_in_tag_order() {
        let event = relay_list_event(&[
            &["r", "WSS://Relay.Mostro.Network/"],
            &["r", "wss://relay.mostro.network"],
            &["r", " wss://nos.lol "],
        ]);

        let urls = parse_relay_list(&event);

        assert_eq!(urls, vec!["wss://relay.mostro.network", "wss://nos.lol"]);
    }

    #[test]
    fn skips_non_r_tags_and_non_websocket_urls() {
        let event = relay_list_event(&[
            &["r", "https://relay.mostro.network"],
            &["r", "relay.mostro.network"],
            &["r", ""],
            &["r"],
            &["p", "wss://not-a-relay-tag.example"],
            &["r", "ws://localhost:7777"],
        ]);

        let urls = parse_relay_list(&event);

        assert_eq!(urls, vec!["ws://localhost:7777"]);
    }

    #[test]
    fn relay_list_filter_is_author_pinned_to_kind_10002() {
        let mostro = Keys::generate().public_key();

        let filter = relay_list_filter(&mostro);

        assert_eq!(filter.kinds, Some([Kind::from(10002)].into_iter().collect()));
        assert_eq!(filter.authors, Some([mostro].into_iter().collect()));
        assert_eq!(filter.limit, Some(1));
    }

    #[test]
    fn normalize_keeps_path_case_and_strips_trailing_slash() {
        assert_eq!(
            normalize_relay_url("wss://Example.com/Path/"),
            Some("wss://example.com/Path".to_string())
        );
        assert_eq!(normalize_relay_url("wss:///"), None);
        assert_eq!(normalize_relay_url("http://example.com"), None);
    }
}
