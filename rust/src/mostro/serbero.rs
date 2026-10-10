//! Serbero, a node's dispute assistant (app#637, mostro#1009).
//!
//! A node that runs Serbero announces its pubkey in the info event (kind
//! 38385) as `["serbero", "<hex>"]`, and registers it as a read-only solver:
//! it takes a dispute first and hands it to a person when needed, who takes
//! it over with a new `admin-took-dispute`. The app trusts the node it
//! already trusts, so a solver is shown as the assistant only when the
//! dispute's own node announces its key — never on the solver's own say-so,
//! and never on another node's: a key one node runs as its Serbero can be a
//! person's on another.
//!
//! Two sources for that node, the cached one first:
//! - every registry node's kind 38385 cached by `node_stats`, which keeps
//!   the newest revision by NIP-01's order (and which the capability fetch
//!   writes before anything reads it), so a dispute of a node the user
//!   switched away from keeps its label;
//! - the active node's announcement from its capability fetch, kept here per
//!   node, for a node the cache does not hold (no store yet).
//!
//! The cache outranks the live answer on purpose: a fetch can end empty
//! (every relay slow at startup) or carry a stale copy from a relay that is
//! behind, and neither is the node taking its Serbero back. A retraction is
//! a newer event without the tag, which supersedes the cached one.
//!
//! Read at display time, not when a message arrives: a history replay can
//! land before the capability fetch, and the label then corrects itself.

use std::collections::{HashMap, HashSet};
use std::sync::RwLock;

use nostr_sdk::prelude::PublicKey;

/// The tag a node announces its Serbero in.
const SERBERO_TAG: &str = "serbero";

/// Per node (hex), what its last capability fetch announced.
static LIVE: RwLock<Option<HashMap<String, Option<String>>>> = RwLock::new(None);

/// The Serbero pubkey an info event's tags announce, as lowercase hex, or
/// `None` without the tag or with a value that is not a public key.
pub(crate) fn parse_tag(tags: &[Vec<String>]) -> Option<String> {
    let value = tags
        .iter()
        .find(|tag| tag.first().map(String::as_str) == Some(SERBERO_TAG))?
        .get(1)?
        .trim()
        .to_lowercase();
    is_pubkey(&value).then_some(value)
}

/// Record what `node`'s capability fetch announced: its Serbero, or none.
pub(crate) fn set_from_tags(node: &str, tags: &[Vec<String>]) {
    LIVE.write()
        .unwrap_or_else(|e| e.into_inner())
        .get_or_insert_with(HashMap::new)
        .insert(node.to_lowercase(), parse_tag(tags));
}

/// Whether `pubkey` is the Serbero `node` announces. Its `cached` info event
/// (the newest revision seen) decides; its `live` answer only when nothing
/// is cached. A node not in `known` (removed from the registry) vouches for
/// nobody, although its live answer stays in memory.
fn is_assistant_in(
    pubkey: &str,
    node: &str,
    live: &HashMap<String, Option<String>>,
    cached: &HashMap<String, Vec<Vec<String>>>,
    known: &HashSet<String>,
) -> bool {
    let node = node.trim().to_lowercase();
    if !known.contains(&node) {
        return false;
    }
    let announced = cached
        .iter()
        .find(|(cached_node, _)| cached_node.to_lowercase() == node)
        .map(|(_, tags)| parse_tag(tags))
        .or_else(|| live.get(&node).cloned())
        .flatten();
    announced.is_some_and(|serbero| serbero == pubkey.trim().to_lowercase())
}

/// Whether the solver `pubkey` (hex) is the Serbero `node` (hex) announces,
/// by that node's live announcement or its cached info event.
pub(crate) async fn is_assistant(node: &str, pubkey: &str) -> bool {
    let live = LIVE
        .read()
        .unwrap_or_else(|e| e.into_inner())
        .clone()
        .unwrap_or_default();
    let cached = crate::api::node_stats::cached_info_tags().await;
    is_assistant_in(pubkey, node, &live, &cached, &known_nodes().await)
}

/// The registry's nodes and the active one (lowercase hex). A node removed
/// from the registry drops out, although its live answer stays in memory.
async fn known_nodes() -> HashSet<String> {
    let mut known: HashSet<String> = match crate::api::nodes::list_mostro_nodes().await {
        Ok(nodes) => nodes.into_iter().map(|n| n.pubkey.to_lowercase()).collect(),
        Err(e) => {
            log::warn!("[serbero] node registry unreadable: {e}");
            HashSet::new()
        }
    };
    known.insert(crate::config::active_mostro_pubkey().to_lowercase());
    known
}

fn is_pubkey(hex: &str) -> bool {
    hex.len() == 64 && PublicKey::from_hex(hex).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    const SERBERO: &str = "000005ee0a1a2b3033d2908bb2fc7e29de803d5ac55a249cdebc11d50fca7fc0";
    const HUMAN: &str = "00000f13a1a2b3033d2908bb2fc7e29de803d5ac55a249cdebc11d50fca7fc00";
    const NODE: &str = "dbe0b1be7aafd3cfba92d7463edbd4e33b2969f61bd554d37ac56f032e13355a";
    const OTHER_NODE: &str = "82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390";

    fn known(nodes: &[&str]) -> HashSet<String> {
        nodes.iter().map(|n| n.to_string()).collect()
    }

    fn tags(pairs: &[(&str, &str)]) -> Vec<Vec<String>> {
        pairs
            .iter()
            .map(|(k, v)| vec![k.to_string(), v.to_string()])
            .collect()
    }

    #[test]
    fn the_serbero_tag_is_read_as_lowercase_hex() {
        assert_eq!(
            parse_tag(&tags(&[("pow", "0"), ("serbero", SERBERO)])).as_deref(),
            Some(SERBERO)
        );
        assert_eq!(
            parse_tag(&tags(&[(
                "serbero",
                &format!(" {} ", SERBERO.to_uppercase())
            )]))
            .as_deref(),
            Some(SERBERO)
        );
    }

    #[test]
    fn a_missing_or_malformed_serbero_tag_announces_nobody() {
        assert_eq!(parse_tag(&tags(&[("pow", "0")])), None);
        assert_eq!(parse_tag(&tags(&[("serbero", "")])), None);
        assert_eq!(parse_tag(&tags(&[("serbero", "npub1notakey")])), None);
        assert_eq!(parse_tag(&tags(&[("serbero", &SERBERO[..63])])), None);
        assert_eq!(parse_tag(&[vec!["serbero".to_string()]]), None);
    }

    #[test]
    fn a_solver_is_the_assistant_only_when_the_disputes_node_announces_it() {
        // Arrange: only OTHER_NODE's cached info event announces the Serbero.
        let live = HashMap::new();
        let cached = HashMap::from([
            (NODE.to_string(), tags(&[("pow", "0")])),
            (OTHER_NODE.to_string(), tags(&[("serbero", SERBERO)])),
        ]);
        let registry = known(&[NODE, OTHER_NODE]);

        // Act + Assert
        assert!(is_assistant_in(
            SERBERO, OTHER_NODE, &live, &cached, &registry
        ));
        assert!(is_assistant_in(
            &SERBERO.to_uppercase(),
            &OTHER_NODE.to_uppercase(),
            &live,
            &cached,
            &registry
        ));
        assert!(
            !is_assistant_in(SERBERO, NODE, &live, &cached, &registry),
            "another node's Serbero is a person on this node's dispute"
        );
        assert!(!is_assistant_in(
            HUMAN, OTHER_NODE, &live, &cached, &registry
        ));
        assert!(!is_assistant_in(
            SERBERO,
            OTHER_NODE,
            &live,
            &HashMap::new(),
            &registry
        ));
    }

    #[test]
    fn a_live_announcement_of_a_node_no_longer_known_is_ignored() {
        // Arrange: the user visited a custom node, then removed it from the
        // registry; its live answer outlives the removal in memory.
        let live = HashMap::from([(OTHER_NODE.to_string(), Some(SERBERO.to_string()))]);

        // Act + Assert
        let none = HashMap::new();
        assert!(!is_assistant_in(
            SERBERO,
            OTHER_NODE,
            &live,
            &none,
            &known(&[NODE])
        ));
        assert!(is_assistant_in(
            SERBERO,
            OTHER_NODE,
            &live,
            &none,
            &known(&[OTHER_NODE])
        ));
    }

    #[test]
    fn the_cached_announcement_outranks_a_live_answer() {
        // Arrange: the cache holds the node's newest signed event, with the
        // tag; the last live fetch came back empty (every relay slow at
        // startup) or with a stale copy from a relay that is behind.
        let cached = HashMap::from([(NODE.to_string(), tags(&[("serbero", SERBERO)]))]);
        let empty_fetch = HashMap::from([(NODE.to_string(), None)]);
        let registry = known(&[NODE, OTHER_NODE]);

        // Act + Assert: neither takes the announcement back.
        assert!(is_assistant_in(
            SERBERO,
            NODE,
            &empty_fetch,
            &cached,
            &registry
        ));
        assert!(is_assistant_in(
            SERBERO,
            NODE,
            &HashMap::new(),
            &cached,
            &registry
        ));
    }

    #[test]
    fn a_retraction_reaches_the_label_through_the_cache() {
        // Arrange: the operator removed the tag; the newer event without it
        // superseded the cached one, while the live map still says otherwise.
        let retracted = HashMap::from([(NODE.to_string(), tags(&[("pow", "0")]))]);
        let announced = HashMap::from([(NODE.to_string(), Some(SERBERO.to_string()))]);
        let registry = known(&[NODE, OTHER_NODE]);

        // Act + Assert
        assert!(!is_assistant_in(
            SERBERO, NODE, &announced, &retracted, &registry
        ));
        // Without a cache entry (no store yet), the live answer decides.
        assert!(is_assistant_in(
            SERBERO,
            NODE,
            &announced,
            &HashMap::new(),
            &registry
        ));
    }
}
