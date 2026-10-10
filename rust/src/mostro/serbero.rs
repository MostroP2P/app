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
//! Two sources for that node's info event, and the newest revision by
//! NIP-01's order decides, whichever source holds it:
//! - every registry node's kind 38385 cached by `node_stats`, so a dispute
//!   of a node the user switched away from keeps its label;
//! - the event the node's last capability fetch brought, kept here per node.
//!   The cache write is best effort, so a fetch the store could not keep is
//!   still the newest word; and a node the store never saw has only this.
//!
//! Neither source retracts the other by being read later: a fetch can end
//! empty (every relay slow at startup) or carry a stale copy from a relay
//! that is behind, and neither is the node taking its Serbero back. A
//! retraction is a newer event without the tag.
//!
//! Read at display time, not when a message arrives: a history replay can
//! land before the capability fetch, and the label then corrects itself.

use std::collections::{HashMap, HashSet};
use std::sync::RwLock;

use nostr_sdk::prelude::{Event, PublicKey};

use crate::api::node_stats::CachedNodeInfo;

/// The tag a node announces its Serbero in.
const SERBERO_TAG: &str = "serbero";

/// Per node (hex), the info event its last capability fetch brought.
static LIVE: RwLock<Option<HashMap<String, CachedNodeInfo>>> = RwLock::new(None);

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

/// Record the info `event` a capability fetch brought for its author.
pub(crate) fn set_from_event(event: &Event) {
    set_live(
        &event.pubkey.to_hex(),
        CachedNodeInfo {
            created_at: event.created_at.as_secs() as i64,
            event_id: Some(event.id.to_hex()),
            tags: event.tags.iter().map(|t| t.as_slice().to_vec()).collect(),
        },
    );
}

/// Record what `node` announces now, as a revision dated this instant with
/// no id: newer than anything cached, older than any later fetch.
#[cfg(test)]
pub(crate) fn set_from_tags(node: &str, tags: &[Vec<String>]) {
    set_live(
        node,
        CachedNodeInfo {
            created_at: crate::rt::unix_now(),
            event_id: None,
            tags: tags.to_vec(),
        },
    );
}

fn set_live(node: &str, info: CachedNodeInfo) {
    LIVE.write()
        .unwrap_or_else(|e| e.into_inner())
        .get_or_insert_with(HashMap::new)
        .insert(node.to_lowercase(), info);
}

/// Whether `pubkey` is the Serbero `node` announces, by the newest revision
/// of its info event among `live` and `cached` (NIP-01's order). A node not
/// in `known` (removed from the registry) vouches for nobody, although its
/// live answer stays in memory.
fn is_assistant_in(
    pubkey: &str,
    node: &str,
    live: &HashMap<String, CachedNodeInfo>,
    cached: &HashMap<String, CachedNodeInfo>,
    known: &HashSet<String>,
) -> bool {
    let node = node.trim().to_lowercase();
    if !known.contains(&node) {
        return false;
    }
    let of = |source: &HashMap<String, CachedNodeInfo>| {
        source
            .iter()
            .find(|(source_node, _)| source_node.to_lowercase() == node)
            .map(|(_, info)| info.clone())
    };
    let newest = match (of(live), of(cached)) {
        (Some(live), Some(cached)) if live.supersedes(&cached) => Some(live),
        (_, Some(cached)) => Some(cached),
        (live, None) => live,
    };
    newest
        .and_then(|info| parse_tag(&info.tags))
        .is_some_and(|serbero| serbero == pubkey.trim().to_lowercase())
}

/// Whether the solver `pubkey` (hex) is the Serbero `node` (hex) announces,
/// by the newest revision of its info event this app holds.
pub(crate) async fn is_assistant(node: &str, pubkey: &str) -> bool {
    let live = LIVE
        .read()
        .unwrap_or_else(|e| e.into_inner())
        .clone()
        .unwrap_or_default();
    let cached = crate::api::node_stats::cached_info().await;
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

    /// A revision of a node's info event, dated `created_at`.
    fn revision(created_at: i64, pairs: &[(&str, &str)]) -> CachedNodeInfo {
        CachedNodeInfo {
            created_at,
            event_id: Some(format!("{created_at:064x}")),
            tags: tags(pairs),
        }
    }

    fn one(node: &str, info: CachedNodeInfo) -> HashMap<String, CachedNodeInfo> {
        HashMap::from([(node.to_string(), info)])
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
            (NODE.to_string(), revision(100, &[("pow", "0")])),
            (
                OTHER_NODE.to_string(),
                revision(100, &[("serbero", SERBERO)]),
            ),
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
        let live = one(OTHER_NODE, revision(100, &[("serbero", SERBERO)]));

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
    fn the_newest_revision_decides_whichever_source_holds_it() {
        // Arrange: the cache holds the node's newest signed event, with the
        // tag; the last live fetch brought a stale copy from a relay that is
        // behind, or nothing at all (every relay slow at startup).
        let cached = one(NODE, revision(200, &[("serbero", SERBERO)]));
        let stale = one(NODE, revision(100, &[("pow", "0")]));
        let registry = known(&[NODE, OTHER_NODE]);

        // Act + Assert: neither takes the announcement back.
        assert!(is_assistant_in(SERBERO, NODE, &stale, &cached, &registry));
        assert!(is_assistant_in(
            SERBERO,
            NODE,
            &HashMap::new(),
            &cached,
            &registry
        ));

        // The cache write failed (best effort) and the live fetch holds the
        // newer event: the live one decides, both ways.
        let old_without = one(NODE, revision(100, &[("pow", "0")]));
        let new_with = one(NODE, revision(200, &[("serbero", SERBERO)]));
        assert!(is_assistant_in(
            SERBERO,
            NODE,
            &new_with,
            &old_without,
            &registry
        ));
        let old_with = one(NODE, revision(100, &[("serbero", SERBERO)]));
        let new_without = one(NODE, revision(200, &[("pow", "0")]));
        assert!(!is_assistant_in(
            SERBERO,
            NODE,
            &new_without,
            &old_with,
            &registry
        ));
    }

    #[test]
    fn a_retraction_is_a_newer_event_without_the_tag() {
        // Arrange: the operator removed the tag; the newer event superseded
        // the cached one.
        let retracted = one(NODE, revision(200, &[("pow", "0")]));
        let registry = known(&[NODE, OTHER_NODE]);

        // Act + Assert
        assert!(!is_assistant_in(
            SERBERO,
            NODE,
            &HashMap::new(),
            &retracted,
            &registry
        ));
        // Without a cache entry (no store yet), the live answer decides.
        let announced = one(NODE, revision(100, &[("serbero", SERBERO)]));
        assert!(is_assistant_in(
            SERBERO,
            NODE,
            &announced,
            &HashMap::new(),
            &registry
        ));
    }
}
