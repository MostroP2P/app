//! Bitcoin/fiat exchange rates published by the active Mostro node
//! (kind 30078, NIP-33, `d` tag `mostro-rates`).
//!
//! The rate exists for one reason: a market-price order carries no sats
//! amount, so nothing on this side can tell whether it lands inside the
//! node's `min_order_amount`/`max_order_amount` until the daemon prices it
//! and answers `OutOfRangeSatsAmount` (#337).
//!
//! The node's own event is the right source, not a third-party API. The
//! daemon prices such an order as `fiat_amount / price * 1E8` from the very
//! aggregate it publishes here (`mostro/src/app/order.rs`), so this is the
//! same number its range check will use; any other quote would be a different
//! price, and asking for it would tell a stranger which currency the user is
//! about to trade.
//!
//! Node-scoped like [`crate::mostro::pow`] and [`crate::mostro::escrow_mode`]:
//! a snapshot is only ever served back to the node it was fetched from, so a
//! node switch can never price an order at the previous node's rate.
//!
//! Nothing here blocks anything. A missing, stale or unparseable rate simply
//! yields `None`, and the caller then submits unchecked with the daemon as the
//! backstop — the same fail-open choice PR #302 made for fixed-sats orders.

use std::collections::HashMap;
use std::sync::RwLock;

/// Kind of the rates event (NIP-33 addressable).
pub const RATES_KIND: u16 = 30078;

/// NIP-33 `d` tag identifying it.
pub const RATES_D_TAG: &str = "mostro-rates";

/// Lifetime assumed for an event published without a NIP-40 `expiration` tag,
/// and the ceiling clamped onto one that carries an implausibly distant value.
///
/// It is the daemon's own ceiling: it stamps `min(update_interval * 2, 3600)`
/// seconds (`mostro/src/price/manager.rs`). Clamping costs at most one refetch
/// per hour and stops a misconfigured node from pinning the app to a price
/// that stopped being true long ago.
const MAX_LIFETIME_SECS: i64 = 3600;

/// One fetched rate table plus the node it came from and the instant it stops
/// being usable. Stored whole so a reader can never mix a currency from one
/// refresh with the expiry of another.
struct Snapshot {
    node: String,
    rates: HashMap<String, f64>,
    expires_at: i64,
}

/// `None` until the first successful fetch.
static SNAPSHOT: RwLock<Option<Snapshot>> = RwLock::new(None);

/// Read the BTC rate table out of a rates event's content.
///
/// The payload is Yadio-shaped — `{"BTC": {"USD": 50000.0, ...}}` — and is
/// parsed leniently: a currency whose value is not a usable positive number is
/// dropped rather than failing the whole table, since one bad entry says
/// nothing about the rest. `None` means nothing usable was found at all.
///
/// Codes are upper-cased so a lookup never misses on capitalisation alone.
pub fn parse_rates_content(content: &str) -> Option<HashMap<String, f64>> {
    let value: serde_json::Value = serde_json::from_str(content).ok()?;
    let table = value.get("BTC")?.as_object()?;

    let rates: HashMap<String, f64> = table
        .iter()
        .filter(|(code, _)| code.as_str() != "BTC")
        .filter_map(|(code, price)| {
            let price = price.as_f64()?;
            (price.is_finite() && price > 0.0).then(|| (code.to_uppercase(), price))
        })
        .collect();

    (!rates.is_empty()).then_some(rates)
}

/// When a rates event published at `created_at` stops being usable, from its
/// NIP-40 `expiration` tag when it carries one. See [`MAX_LIFETIME_SECS`] for
/// both the fallback and the clamp.
pub fn expires_at(created_at: i64, expiration_tag: Option<i64>) -> i64 {
    let ceiling = created_at.saturating_add(MAX_LIFETIME_SECS);
    expiration_tag.map_or(ceiling, |tag| tag.min(ceiling))
}

/// Record the rates `node` (hex pubkey) published, valid until `expires_at`.
///
/// A poisoned lock is recovered from rather than propagated, as in
/// `escrow_mode`: this is a cache of what a node said, and refusing to refresh
/// it after an unrelated panic would only serve older prices.
pub fn store(node: &str, rates: HashMap<String, f64>, expires_at: i64) {
    let count = rates.len();
    *SNAPSHOT.write().unwrap_or_else(|e| e.into_inner()) = Some(Snapshot {
        node: node.to_string(),
        rates,
        expires_at,
    });
    log::info!("[rates] node {node}: cached {count} rates until {expires_at}");
}

/// The cached price of one BTC in `fiat_code`, or `None` when there is nothing
/// usable to answer with: no fetch yet, a snapshot belonging to another node,
/// one that has expired by `now`, or a currency this node does not quote.
pub fn cached_rate(node: &str, fiat_code: &str, now: i64) -> Option<f64> {
    let guard = SNAPSHOT.read().unwrap_or_else(|e| e.into_inner());
    let snapshot = guard.as_ref()?;
    if snapshot.node != node || now >= snapshot.expires_at {
        return None;
    }
    snapshot.rates.get(&fiat_code.to_uppercase()).copied()
}

/// Drop the snapshot. Called when a fetch finds no usable event, so an
/// unreachable or de-configured price source stops answering from the last
/// good one.
pub fn clear() {
    *SNAPSHOT.write().unwrap_or_else(|e| e.into_inner()) = None;
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::{Mutex, MutexGuard, PoisonError};

    /// Serializes the tests that touch the process-global snapshot and drops
    /// it afterwards, so none of them leaks a rate into another.
    struct Guard(#[allow(dead_code)] MutexGuard<'static, ()>);

    impl Drop for Guard {
        fn drop(&mut self) {
            clear();
        }
    }

    fn lock() -> Guard {
        static LOCK: Mutex<()> = Mutex::new(());
        Guard(LOCK.lock().unwrap_or_else(PoisonError::into_inner))
    }

    #[test]
    fn a_yadio_shaped_payload_parses() {
        let rates = parse_rates_content(r#"{"BTC":{"USD":50000.0,"EUR":45000.5}}"#).unwrap();

        assert_eq!(rates.get("USD"), Some(&50000.0));
        assert_eq!(rates.get("EUR"), Some(&45000.5));
    }

    #[test]
    fn the_btc_self_rate_is_dropped() {
        let rates = parse_rates_content(r#"{"BTC":{"BTC":1,"USD":50000.0}}"#).unwrap();

        assert_eq!(rates.len(), 1);
        assert!(!rates.contains_key("BTC"));
    }

    #[test]
    fn codes_are_upper_cased() {
        let rates = parse_rates_content(r#"{"BTC":{"usd":50000.0}}"#).unwrap();

        assert_eq!(rates.get("USD"), Some(&50000.0));
    }

    #[test]
    fn unusable_entries_are_dropped_without_failing_the_table() {
        // Zero and negative prices would divide into absurd sats amounts, and
        // a string is not a price at all — but USD still is.
        let rates =
            parse_rates_content(r#"{"BTC":{"ARS":0,"VES":-1,"GBP":"nope","USD":50000.0}}"#)
                .unwrap();

        assert_eq!(rates.len(), 1);
        assert_eq!(rates.get("USD"), Some(&50000.0));
    }

    #[test]
    fn a_payload_with_nothing_usable_is_none() {
        assert!(parse_rates_content(r#"{"BTC":{}}"#).is_none());
        assert!(parse_rates_content(r#"{"BTC":{"USD":0}}"#).is_none());
    }

    #[test]
    fn a_payload_that_is_not_a_rate_table_is_none() {
        assert!(parse_rates_content("").is_none());
        assert!(parse_rates_content("not json").is_none());
        assert!(parse_rates_content(r#"{"USD":50000.0}"#).is_none());
        assert!(parse_rates_content(r#"{"BTC":"50000"}"#).is_none());
    }

    #[test]
    fn an_expiration_tag_bounds_the_snapshot() {
        assert_eq!(expires_at(1_000, Some(1_600)), 1_600);
    }

    #[test]
    fn an_event_without_an_expiration_tag_gets_the_default_lifetime() {
        assert_eq!(expires_at(1_000, None), 1_000 + MAX_LIFETIME_SECS);
    }

    #[test]
    fn an_implausible_expiration_is_clamped_to_the_ceiling() {
        // A node claiming its price is good for a year does not get to pin the
        // app to it.
        assert_eq!(
            expires_at(1_000, Some(1_000 + 365 * 24 * 3600)),
            1_000 + MAX_LIFETIME_SECS
        );
    }

    fn usd(price: f64) -> HashMap<String, f64> {
        HashMap::from([("USD".to_string(), price)])
    }

    #[test]
    fn a_stored_rate_is_served_back_to_its_node() {
        let _guard = lock();
        store("node-a", usd(50_000.0), 1_000);

        assert_eq!(cached_rate("node-a", "USD", 999), Some(50_000.0));
        assert_eq!(cached_rate("node-a", "usd", 999), Some(50_000.0));
    }

    #[test]
    fn another_nodes_snapshot_is_never_served() {
        // Same reason as `pow`: after a node switch the store still describes
        // the previous node, whose price is not the one this order will be
        // quoted at.
        let _guard = lock();
        store("node-a", usd(50_000.0), 1_000);

        assert_eq!(cached_rate("node-b", "USD", 999), None);
    }

    #[test]
    fn an_expired_snapshot_is_not_served() {
        let _guard = lock();
        store("node-a", usd(50_000.0), 1_000);

        assert_eq!(cached_rate("node-a", "USD", 1_000), None);
        assert_eq!(cached_rate("node-a", "USD", 1_001), None);
    }

    #[test]
    fn a_currency_the_node_does_not_quote_is_none() {
        let _guard = lock();
        store("node-a", usd(50_000.0), 1_000);

        assert_eq!(cached_rate("node-a", "CLP", 999), None);
    }

    #[test]
    fn nothing_is_served_before_a_fetch_or_after_a_clear() {
        let _guard = lock();
        assert_eq!(cached_rate("node-a", "USD", 999), None);

        store("node-a", usd(50_000.0), 1_000);
        clear();

        assert_eq!(cached_rate("node-a", "USD", 999), None);
    }
}
