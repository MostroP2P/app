//! What a relay was holding when it refused a REQ for being over its cap.
//!
//! strfry-based relays (nos.lol among them) answer a REQ past
//! `maxSubsPerConnection` with `NOTICE "ERROR: too many concurrent REQs"`.
//! Unlike a `CLOSED`, the notice names no subscription, so nothing can be
//! repaired from it — but a census of the connection's REQs, grouped by
//! family, says which of ours filled the cap.

use std::collections::{BTreeMap, HashMap};
use std::sync::{Mutex, OnceLock, PoisonError};

use nostr_sdk::prelude::{Client, SubscriptionId};

/// Id families, longest prefix first so `mostro-chat-dispute-<id>` is not
/// counted as a peer chat.
const FAMILIES: [&str; 3] = ["mostro-chat-dispute-", "mostro-chat-", "mostro-daemon-"];

/// How often one relay's census is logged: a refused burst sends one notice
/// per REQ, and one census describes them all.
const CENSUS_INTERVAL: std::time::Duration = std::time::Duration::from_secs(60);

/// Whether a relay notice reports its per-connection REQ cap.
pub(crate) fn is_req_cap_notice(msg: &str) -> bool {
    msg.to_ascii_lowercase().contains("too many concurrent")
}

/// The family an id belongs to: a per-trade prefix with a `*`, `fetch` for
/// the SDK's random ids (one-shot `fetch_events`), otherwise the id itself.
fn family(id: &str) -> String {
    if let Some(prefix) = FAMILIES.iter().find(|prefix| id.starts_with(*prefix)) {
        return format!("{prefix}*");
    }
    if !id.is_empty() && id.chars().all(|c| c.is_ascii_hexdigit()) {
        return "fetch".to_string();
    }
    id.to_string()
}

/// `"<total> REQs: <family>×<n>, …"`, families sorted by name.
pub(crate) fn census<'a>(ids: impl IntoIterator<Item = &'a SubscriptionId>) -> String {
    let mut counts: BTreeMap<String, usize> = BTreeMap::new();
    for id in ids {
        *counts.entry(family(&id.to_string())).or_insert(0) += 1;
    }
    let total: usize = counts.values().sum();
    let parts: Vec<String> = counts
        .iter()
        .map(|(family, n)| format!("{family}×{n}"))
        .collect();
    format!("{total} REQs: {}", parts.join(", "))
}

/// Whether `url` is due a census now; records it when it is.
fn due(last: &mut HashMap<String, crate::rt::time::Instant>, url: &str) -> bool {
    let now = crate::rt::time::Instant::now();
    match last.get(url) {
        Some(at) if now.duration_since(*at) < CENSUS_INTERVAL => false,
        _ => {
            last.insert(url.to_string(), now);
            true
        }
    }
}

/// Log what `url` holds, at most once per [`CENSUS_INTERVAL`].
pub(crate) async fn report_req_cap(client: &Client, url: &str) {
    static LAST: OnceLock<Mutex<HashMap<String, crate::rt::time::Instant>>> = OnceLock::new();
    let is_due = due(
        &mut LAST
            .get_or_init(Default::default)
            .lock()
            .unwrap_or_else(PoisonError::into_inner),
        url,
    );
    if !is_due {
        return;
    }
    let Ok(Some(relay)) = client.relay(url).await else {
        return;
    };
    let held = relay.subscriptions().await;
    crate::api::logging::blog_warn(
        "relay",
        format!(
            "REQ cap reached relay={} — this connection holds {}",
            crate::api::logging::display_relay(url),
            census(held.keys()),
        ),
    );
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    use super::*;

    #[test]
    fn recognizes_the_strfry_req_cap_notice_only() {
        assert!(is_req_cap_notice("ERROR: too many concurrent REQs"));
        assert!(!is_req_cap_notice("ERROR: bad msg: invalid filter"));
    }

    #[test]
    fn census_groups_per_trade_ids_by_family_and_counts_them() {
        // Arrange
        let ids: Vec<SubscriptionId> = [
            "mostro-orders",
            "mostro-orders-recent",
            "mostro-dm",
            "mostro-orders-watched",
            "mostro-daemon-0123456789abcdef0123456789abcdef",
            "mostro-chat-7c3e1a2b-0000-4000-8000-000000000001",
            "mostro-chat-dispute-7c3e1a2b-0000-4000-8000-000000000001",
            "a1b2c3d4e5f60718",
        ]
        .into_iter()
        .map(SubscriptionId::new)
        .collect();

        // Act
        let line = census(&ids);

        // Assert
        assert_eq!(
            line,
            "8 REQs: fetch×1, mostro-chat-*×1, mostro-chat-dispute-*×1, \
             mostro-daemon-*×1, mostro-dm×1, mostro-orders×1, mostro-orders-recent×1, \
             mostro-orders-watched×1"
        );
    }

    #[test]
    fn a_relay_gets_one_census_per_interval() {
        let mut last = HashMap::new();
        assert!(due(&mut last, "wss://nos.lol"));
        assert!(
            !due(&mut last, "wss://nos.lol"),
            "the rest of the burst is quiet"
        );
        assert!(
            due(&mut last, "wss://relay.mostro.network"),
            "each relay has its own"
        );
    }
}
