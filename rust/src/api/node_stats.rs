/// Per-node decision data for the Mostro node selector.
///
/// The selector redesign (`design_handoff_selector_nodo`, 9a/9b) asks each
/// node card to answer "does this node serve me?" before "do I trust it?":
/// accepted fiat currencies, open orders right now (counted by the app from
/// the node's kind 38383 events, never declared by the node), fee, sats range
/// per trade, escrow backend and anti-abuse bond.
///
/// Everything here is derived from two relay queries over the candidate
/// pubkeys — the nodes' kind 38385 instance events and their `pending`
/// kind 38383 orders — folded by pure helpers so the logic is unit-tested
/// without a relay pool. Nothing is persisted and the active-node order book
/// (`orders::ORDER_BOOK`, deliberately single-node) is never touched.
use std::collections::{BTreeMap, HashMap};

use anyhow::Result;
use nostr_sdk::prelude::{Event, Filter, Kind, PublicKey, SingleLetterTag};
use serde::{Deserialize, Serialize};

use crate::api::types::{OrderInfo, OrderStatus};
use crate::mostro::escrow_mode;
use crate::nostr::order_events::{parse_order_event, KIND_ORDER};

/// Kind 38385 — Mostro instance status (NIP-33 addressable, `d` = pubkey).
const KIND_INSTANCE: u16 = 38385;

/// Relay round-trip budget for each of the two queries.
const FETCH_TIMEOUT_SECS: u64 = 10;

/// Open orders of one fiat currency on one node.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FiatOrderCount {
    /// ISO 4217 code as published in the `f` tag, upper-cased.
    pub fiat_code: String,
    pub count: u32,
}

/// What the selector shows for one node. Every field is optional on purpose:
/// a missing tag renders as `—` in the UI, never as an invented value.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct MostroNodeStats {
    /// Node pubkey, 64-char lowercase hex.
    pub pubkey: String,
    /// `created_at` of the node's kind 38385 event, `None` when none was
    /// found. The daemon republishes it periodically, so it doubles as a
    /// liveness signal.
    pub info_seen_at: Option<i64>,
    /// `created_at` of the newest pending order, `None` when there are none.
    pub latest_order_at: Option<i64>,
    /// Fee the node charges, **in percent** (`0.6` = 0.6 %). The wire `fee`
    /// tag is a fraction (`0.006`); converted here so Dart never divides.
    pub fee_pct: Option<f64>,
    pub min_order_amount: Option<u64>,
    pub max_order_amount: Option<u64>,
    /// `fiat_currencies_accepted`, split on commas, trimmed, upper-cased,
    /// deduplicated, in the node's order. Empty when the tag is absent.
    pub accepted_currencies: Vec<String>,
    /// Stable marker: `unknown` / `lightning` / `cashu`
    /// (see [`escrow_mode::EscrowMode::as_marker`]).
    pub escrow_mode: String,
    /// Mint the node pins for Cashu escrow; only set when the mode is Cashu.
    pub cashu_mint_url: Option<String>,
    /// `bond_enabled` tag: `Some(true)` when the node requires a bond,
    /// `Some(false)` when it explicitly does not, `None` when the daemon
    /// predates bonds. This client cannot post a bond, so `Some(true)` makes
    /// the node non-selectable.
    pub bond_required: Option<bool>,
    /// `bond_amount_pct`, **in percent**; only set when `bond_required` is
    /// `Some(true)`.
    pub bond_pct: Option<f64>,
    /// Pending orders per fiat currency, sorted by code.
    pub orders_by_fiat: Vec<FiatOrderCount>,
    /// Sum of [`Self::orders_by_fiat`].
    pub total_orders: u32,
}

impl MostroNodeStats {
    fn empty(pubkey: &str) -> Self {
        Self {
            pubkey: pubkey.to_string(),
            info_seen_at: None,
            latest_order_at: None,
            fee_pct: None,
            min_order_amount: None,
            max_order_amount: None,
            accepted_currencies: Vec::new(),
            escrow_mode: escrow_mode::EscrowMode::Unknown.as_marker().to_string(),
            cashu_mint_url: None,
            bond_required: None,
            bond_pct: None,
            orders_by_fiat: Vec::new(),
            total_orders: 0,
        }
    }
}

// ── Pure helpers (unit-tested) ───────────────────────────────────────────────

fn tag_value<'a>(tags: &'a [Vec<String>], name: &str) -> Option<&'a str> {
    tags.iter()
        .find(|t| t.first().map(String::as_str) == Some(name))
        .and_then(|t| t.get(1))
        .map(String::as_str)
        .map(str::trim)
        .filter(|v| !v.is_empty())
}

/// `fiat_currencies_accepted` → normalized code list. The daemon publishes
/// one comma-separated value; tolerate whitespace, case and duplicates.
fn parse_accepted_currencies(raw: Option<&str>) -> Vec<String> {
    let mut out: Vec<String> = Vec::new();
    for code in raw.unwrap_or_default().split(',') {
        let code = code.trim().to_ascii_uppercase();
        if !code.is_empty() && !out.contains(&code) {
            out.push(code);
        }
    }
    out
}

/// A wire fraction (`0.006`) as a percentage (`0.6`). Negative or
/// non-numeric values are dropped rather than shown.
fn fraction_to_pct(raw: Option<&str>) -> Option<f64> {
    raw?.parse::<f64>()
        .ok()
        .filter(|v| v.is_finite() && *v >= 0.0)
        .map(|v| v * 100.0)
}

fn parse_u64(raw: Option<&str>) -> Option<u64> {
    raw?.parse().ok()
}

/// Fold a kind 38385 tag list (plus the event's `created_at`) into `stats`.
///
/// Mirrors the gating the About screen already applies in Dart
/// (`MostroInstance.fromTags`): bond params surface only when
/// `bond_enabled == true`; the mint only when the mode is Cashu.
fn apply_info_tags(stats: &mut MostroNodeStats, tags: &[Vec<String>], seen_at: i64) {
    stats.info_seen_at = Some(seen_at);
    stats.fee_pct = fraction_to_pct(tag_value(tags, "fee"));
    stats.min_order_amount = parse_u64(tag_value(tags, "min_order_amount"));
    stats.max_order_amount = parse_u64(tag_value(tags, "max_order_amount"));
    stats.accepted_currencies =
        parse_accepted_currencies(tag_value(tags, "fiat_currencies_accepted"));

    let (mode, cashu) = escrow_mode::parse_tags(tags);
    stats.escrow_mode = mode.as_marker().to_string();
    stats.cashu_mint_url = if mode.is_cashu() {
        cashu.mint_url
    } else {
        None
    };

    stats.bond_required = tag_value(tags, "bond_enabled").map(|v| v.eq_ignore_ascii_case("true"));
    stats.bond_pct = if stats.bond_required == Some(true) {
        fraction_to_pct(tag_value(tags, "bond_amount_pct"))
    } else {
        None
    };
}

/// Keep only the newest version of each addressable order (`author` + `d`).
///
/// Relays may hand back several versions of the same kind 38383 `d` tag
/// (one per status transition); counting all of them would inflate liquidity.
fn dedup_latest(orders: Vec<OrderInfo>) -> Vec<OrderInfo> {
    let mut latest: HashMap<(String, String), OrderInfo> = HashMap::new();
    for order in orders {
        let key = (order.creator_pubkey.clone(), order.id.clone());
        match latest.get(&key) {
            Some(existing) if existing.created_at >= order.created_at => {}
            _ => {
                latest.insert(key, order);
            }
        }
    }
    latest.into_values().collect()
}

/// Is this order open right now? `pending` and not past its `expiration`.
fn is_open(order: &OrderInfo, now: i64) -> bool {
    order.status == OrderStatus::Pending && order.expires_at.is_none_or(|exp| exp > now)
}

/// Per-node fold of [`count_open_orders`]: orders per fiat code plus the
/// newest `created_at`.
type NodeLiquidity = (BTreeMap<String, u32>, Option<i64>);

/// Fold parsed orders into per-node liquidity. `now` is injected so the
/// expiry rule is testable.
fn count_open_orders(orders: Vec<OrderInfo>, now: i64) -> HashMap<String, NodeLiquidity> {
    let mut per_node: HashMap<String, NodeLiquidity> = HashMap::new();
    for order in dedup_latest(orders) {
        if !is_open(&order, now) {
            continue;
        }
        let (by_fiat, latest) = per_node.entry(order.creator_pubkey.clone()).or_default();
        *by_fiat
            .entry(order.fiat_code.to_ascii_uppercase())
            .or_default() += 1;
        *latest = Some(latest.map_or(order.created_at, |l| l.max(order.created_at)));
    }
    per_node
}

fn apply_order_counts(stats: &mut MostroNodeStats, liquidity: NodeLiquidity) {
    let (by_fiat, latest) = liquidity;
    stats.total_orders = by_fiat.values().sum();
    stats.orders_by_fiat = by_fiat
        .into_iter()
        .map(|(fiat_code, count)| FiatOrderCount { fiat_code, count })
        .collect();
    stats.latest_order_at = latest;
}

/// Build the stats rows from the raw events, one row per requested pubkey in
/// request order. Nodes with no event at all get an empty row (the UI shows
/// them as unreachable), never a missing one.
fn summarize(
    pubkeys: &[String],
    info_events: &[Event],
    order_events: &[Event],
    now: i64,
) -> Vec<MostroNodeStats> {
    let mut rows: Vec<MostroNodeStats> =
        pubkeys.iter().map(|p| MostroNodeStats::empty(p)).collect();
    let index: HashMap<&str, usize> = pubkeys
        .iter()
        .enumerate()
        .map(|(i, p)| (p.as_str(), i))
        .collect();

    // Newest 38385 per author wins; the `d` tag must be the author itself,
    // as in `fetch_mostro_instance_tags`.
    let mut seen_info: HashMap<String, i64> = HashMap::new();
    for event in info_events {
        let author = event.pubkey.to_hex();
        let Some(&i) = index.get(author.as_str()) else {
            continue;
        };
        let tags: Vec<Vec<String>> = event.tags.iter().map(|t| t.as_slice().to_vec()).collect();
        if tag_value(&tags, "d") != Some(author.as_str()) {
            continue;
        }
        let created = event.created_at.as_secs() as i64;
        if seen_info.get(&author).is_some_and(|&prev| prev >= created) {
            continue;
        }
        seen_info.insert(author.clone(), created);
        apply_info_tags(&mut rows[i], &tags, created);
    }

    let orders: Vec<OrderInfo> = order_events
        .iter()
        .filter_map(|e| parse_order_event(e, None))
        .collect();
    for (pubkey, liquidity) in count_open_orders(orders, now) {
        if let Some(&i) = index.get(pubkey.as_str()) {
            apply_order_counts(&mut rows[i], liquidity);
        }
    }
    rows
}

// ── Public API ───────────────────────────────────────────────────────────────

/// Fetch decision data for every node in `pubkeys` (64-char hex) with two
/// relay queries — their kind 38385 instance events and their `pending`
/// kind 38383 orders — and return one [`MostroNodeStats`] per requested
/// pubkey, in request order.
///
/// Best-effort like `refresh_mostro_node_metadata`: whatever arrives within
/// the window is used, a node that answered nothing comes back as an empty
/// row (no `info_seen_at`, zero orders). Only an outright query failure or an
/// invalid pubkey is an error.
pub async fn fetch_mostro_node_stats(pubkeys: Vec<String>) -> Result<Vec<MostroNodeStats>> {
    use std::time::Duration;

    let pubkeys: Vec<String> = pubkeys
        .into_iter()
        .map(|p| p.trim().to_lowercase())
        .collect();
    if pubkeys.is_empty() {
        return Ok(Vec::new());
    }
    let authors: Vec<PublicKey> = pubkeys
        .iter()
        .map(|p| PublicKey::from_hex(p).map_err(|e| anyhow::anyhow!("InvalidPubkey: {e}")))
        .collect::<Result<_>>()?;

    let client = crate::api::nostr::get_pool()?.client();
    let timeout = Duration::from_secs(FETCH_TIMEOUT_SECS);

    let info_filter = Filter::new()
        .kind(Kind::from(KIND_INSTANCE))
        .authors(authors.clone());
    let orders_filter = Filter::new()
        .kind(Kind::from(KIND_ORDER))
        .authors(authors)
        .custom_tag(SingleLetterTag::LOWERCASE_S, "pending");

    let (info, orders) = tokio::join!(
        client.fetch_events(info_filter).timeout(timeout),
        client.fetch_events(orders_filter).timeout(timeout),
    );
    let info = info.map_err(|e| anyhow::anyhow!("fetch_events (38385) failed: {e}"))?;
    let orders = orders.map_err(|e| anyhow::anyhow!("fetch_events (38383) failed: {e}"))?;

    let info: Vec<Event> = info.into_iter().collect();
    let orders: Vec<Event> = orders.into_iter().collect();
    Ok(summarize(&pubkeys, &info, &orders, crate::rt::unix_now()))
}

// ── Tests ────────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::OrderKind;

    const NODE_A: &str = "82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390";
    const NODE_B: &str = "0000000000000000000000000000000000000000000000000000000000000001";

    fn tags(pairs: &[(&str, &str)]) -> Vec<Vec<String>> {
        pairs
            .iter()
            .map(|(k, v)| vec![k.to_string(), v.to_string()])
            .collect()
    }

    fn order(node: &str, id: &str, fiat: &str, status: OrderStatus, created_at: i64) -> OrderInfo {
        OrderInfo {
            id: id.into(),
            kind: OrderKind::Sell,
            status,
            amount_sats: None,
            fiat_amount: Some(100.0),
            fiat_amount_min: None,
            fiat_amount_max: None,
            fiat_code: fiat.into(),
            payment_method: String::new(),
            premium: 0.0,
            creator_pubkey: node.into(),
            created_at,
            expires_at: None,
            is_mine: false,
            rating: 0.0,
            total_reviews: 0,
            days_active: 0,
        }
    }

    #[test]
    fn accepted_currencies_are_split_trimmed_uppercased_and_deduped() {
        assert_eq!(
            parse_accepted_currencies(Some(" ars, ves ,BRL,ars,, eur")),
            vec!["ARS", "VES", "BRL", "EUR"]
        );
        assert!(parse_accepted_currencies(None).is_empty());
        assert!(parse_accepted_currencies(Some("")).is_empty());
    }

    #[test]
    fn fee_and_bond_are_converted_to_percent() {
        assert_eq!(fraction_to_pct(Some("0.006")), Some(0.6));
        assert_eq!(fraction_to_pct(Some("0")), Some(0.0));
        assert_eq!(fraction_to_pct(Some("-1")), None);
        assert_eq!(fraction_to_pct(Some("abc")), None);
        assert_eq!(fraction_to_pct(None), None);
    }

    #[test]
    fn info_tags_fill_every_field() {
        let mut s = MostroNodeStats::empty(NODE_A);
        apply_info_tags(
            &mut s,
            &tags(&[
                ("d", NODE_A),
                ("fee", "0.006"),
                ("min_order_amount", "5000"),
                ("max_order_amount", "2000000"),
                ("fiat_currencies_accepted", "ARS,VES,BRL"),
                ("escrow_mode", "cashu"),
                ("cashu_mint_url", "https://mint.cashu.space"),
                ("bond_enabled", "true"),
                ("bond_amount_pct", "0.02"),
            ]),
            1_700_000_000,
        );
        assert_eq!(s.info_seen_at, Some(1_700_000_000));
        assert_eq!(s.fee_pct, Some(0.6));
        assert_eq!(s.min_order_amount, Some(5000));
        assert_eq!(s.max_order_amount, Some(2_000_000));
        assert_eq!(s.accepted_currencies, vec!["ARS", "VES", "BRL"]);
        assert_eq!(s.escrow_mode, "cashu");
        assert_eq!(
            s.cashu_mint_url.as_deref(),
            Some("https://mint.cashu.space")
        );
        assert_eq!(s.bond_required, Some(true));
        assert_eq!(s.bond_pct, Some(2.0));
    }

    #[test]
    fn missing_tags_stay_none_and_bond_params_are_gated() {
        let mut s = MostroNodeStats::empty(NODE_A);
        apply_info_tags(
            &mut s,
            &tags(&[
                ("d", NODE_A),
                ("bond_enabled", "false"),
                ("bond_amount_pct", "0.02"),
                ("cashu_mint_url", "https://mint.example"),
            ]),
            1,
        );
        assert_eq!(s.fee_pct, None);
        assert_eq!(s.min_order_amount, None);
        assert!(s.accepted_currencies.is_empty());
        // No escrow_mode tag → unknown, and the mint is not surfaced.
        assert_eq!(s.escrow_mode, "unknown");
        assert_eq!(s.cashu_mint_url, None);
        // Bond explicitly disabled → the pct is not surfaced either.
        assert_eq!(s.bond_required, Some(false));
        assert_eq!(s.bond_pct, None);

        let mut old = MostroNodeStats::empty(NODE_A);
        apply_info_tags(&mut old, &tags(&[("d", NODE_A)]), 1);
        assert_eq!(
            old.bond_required, None,
            "a daemon without bonds says nothing"
        );
    }

    #[test]
    fn open_orders_are_counted_per_node_and_fiat() {
        let now = 1_000;
        let orders = vec![
            order(NODE_A, "o1", "ARS", OrderStatus::Pending, 10),
            order(NODE_A, "o2", "ars", OrderStatus::Pending, 20),
            order(NODE_A, "o3", "VES", OrderStatus::Pending, 30),
            order(NODE_A, "o4", "ARS", OrderStatus::Canceled, 40),
            order(NODE_B, "o5", "COP", OrderStatus::Pending, 50),
        ];
        let per_node = count_open_orders(orders, now);
        let (a, latest_a) = &per_node[NODE_A];
        assert_eq!(a["ARS"], 2);
        assert_eq!(a["VES"], 1);
        assert_eq!(a.get("COP"), None);
        assert_eq!(*latest_a, Some(30));
        let (b, _) = &per_node[NODE_B];
        assert_eq!(b["COP"], 1);
    }

    #[test]
    fn only_the_newest_version_of_an_order_counts() {
        // Same `d` tag twice: the older one is pending, the newer canceled.
        let orders = vec![
            order(NODE_A, "o1", "ARS", OrderStatus::Pending, 10),
            order(NODE_A, "o1", "ARS", OrderStatus::Canceled, 20),
            // And the reverse arrival order must give the same answer.
            order(NODE_A, "o2", "ARS", OrderStatus::Canceled, 20),
            order(NODE_A, "o2", "ARS", OrderStatus::Pending, 10),
        ];
        let per_node = count_open_orders(orders, 1_000);
        assert!(!per_node.contains_key(NODE_A), "both orders are canceled");
    }

    #[test]
    fn expired_pending_orders_are_not_open() {
        let mut o = order(NODE_A, "o1", "ARS", OrderStatus::Pending, 10);
        o.expires_at = Some(500);
        assert!(is_open(&o, 499));
        assert!(!is_open(&o, 500));
        let never = order(NODE_A, "o2", "ARS", OrderStatus::Pending, 10);
        assert!(is_open(&never, i64::MAX));
    }

    #[test]
    fn summarize_returns_one_row_per_requested_pubkey_in_order() {
        let rows = summarize(&[NODE_A.into(), NODE_B.into()], &[], &[], 0);
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].pubkey, NODE_A);
        assert_eq!(rows[1].pubkey, NODE_B);
        assert_eq!(rows[0].info_seen_at, None);
        assert_eq!(rows[0].total_orders, 0);
        assert_eq!(rows[0].escrow_mode, "unknown");
    }

    #[test]
    fn apply_order_counts_sorts_by_code_and_totals() {
        let mut s = MostroNodeStats::empty(NODE_A);
        let mut by_fiat = BTreeMap::new();
        by_fiat.insert("VES".to_string(), 3u32);
        by_fiat.insert("ARS".to_string(), 12u32);
        apply_order_counts(&mut s, (by_fiat, Some(99)));
        assert_eq!(s.total_orders, 15);
        assert_eq!(s.orders_by_fiat[0].fiat_code, "ARS");
        assert_eq!(s.orders_by_fiat[1].fiat_code, "VES");
        assert_eq!(s.latest_order_at, Some(99));
    }
}
