//! What a node offers for reputation portability (MostroP2P/protocol
//! reputation_transfer.md, "Discovery"): `reputation_issuer` when it exports,
//! `reputation_import_issuers` when it imports. A client sends
//! `export-reputation` / `import-reputation` only to a node that advertises
//! them: one that predates the actions cannot parse them and never answers.
//!
//! Kept per node from its capability fetch; a fetch without the tags, or no
//! info event at all, retracts an older answer.

use std::collections::HashMap;
use std::sync::RwLock;

const ISSUER_TAG: &str = "reputation_issuer";
const IMPORT_TAG: &str = "reputation_import_issuers";

/// A node's reputation capabilities, from its info event.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct ReputationSupport {
    /// The key the node signs attestations with; `None` when it does not
    /// export.
    pub issuer: Option<String>,
    /// The issuer keys the node imports from; `None` when it does not import,
    /// empty when it imports from nobody yet.
    pub import_issuers: Option<Vec<String>>,
}

static LIVE: RwLock<Option<HashMap<String, ReputationSupport>>> = RwLock::new(None);

fn is_pubkey(value: &str) -> bool {
    value.len() == 64 && value.bytes().all(|b| b.is_ascii_hexdigit())
}

/// The reputation capabilities an info event's tags announce. Values that
/// are not public keys are dropped.
pub(crate) fn parse_tags(tags: &[Vec<String>]) -> ReputationSupport {
    let find = |name: &str| {
        tags.iter()
            .find(|t| t.first().map(String::as_str) == Some(name))
    };
    let issuer = find(ISSUER_TAG)
        .and_then(|t| t.get(1))
        .map(|v| v.trim().to_lowercase())
        .filter(|v| is_pubkey(v));
    let import_issuers = find(IMPORT_TAG).map(|t| {
        t.iter()
            .skip(1)
            .map(|v| v.trim().to_lowercase())
            .filter(|v| is_pubkey(v))
            .collect()
    });
    ReputationSupport {
        issuer,
        import_issuers,
    }
}

/// Record what `node`'s capability fetch announced.
pub(crate) fn set_from_tags(node: &str, tags: &[Vec<String>]) {
    LIVE.write()
        .unwrap_or_else(|e| e.into_inner())
        .get_or_insert_with(HashMap::new)
        .insert(node.to_lowercase(), parse_tags(tags));
}

/// What `node` offers, as of its last capability fetch; nothing when it was
/// never fetched.
pub(crate) fn get(node: &str) -> ReputationSupport {
    LIVE.read()
        .unwrap_or_else(|e| e.into_inner())
        .as_ref()
        .and_then(|live| live.get(&node.to_lowercase()).cloned())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tags(raw: &[&[&str]]) -> Vec<Vec<String>> {
        raw.iter()
            .map(|t| t.iter().map(|v| v.to_string()).collect())
            .collect()
    }

    #[test]
    fn reads_both_tags_and_drops_values_that_are_not_keys() {
        let a = "a".repeat(64);
        let b = "B".repeat(64);
        let support = parse_tags(&tags(&[
            &["reputation_issuer", &a],
            &["reputation_import_issuers", &a, "nope", &b],
        ]));
        assert_eq!(support.issuer, Some(a.clone()));
        assert_eq!(support.import_issuers, Some(vec![a, "b".repeat(64)]));
    }

    #[test]
    fn an_empty_trust_list_still_means_the_node_imports() {
        let support = parse_tags(&tags(&[&["reputation_import_issuers"]]));
        assert_eq!(support.import_issuers, Some(vec![]));
        assert_eq!(support.issuer, None);
    }

    #[test]
    fn a_fetch_without_the_tags_retracts_an_older_answer() {
        let node = "c".repeat(64);
        set_from_tags(&node, &tags(&[&["reputation_issuer", &"d".repeat(64)]]));
        assert!(get(&node).issuer.is_some());
        set_from_tags(&node, &[]);
        assert_eq!(get(&node), ReputationSupport::default());
        assert_eq!(get(&"e".repeat(64)), ReputationSupport::default());
    }
}
