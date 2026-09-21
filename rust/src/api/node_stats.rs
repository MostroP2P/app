/// Per-node decision data for the Mostro node selector.
///
/// The selector redesign (`design_handoff_selector_nodo`, 9a/9b) asks each
/// node card to answer "does this node serve me?" before "do I trust it?":
/// accepted fiat currencies, open orders right now (counted by the app from
/// the node's kind 38383 events, never declared by the node), fee, sats range
/// per trade, escrow backend and anti-abuse bond.
///
/// Everything here is derived from relay queries over the candidate
/// pubkeys — the nodes' kind 38385 instance events and their `pending`
/// kind 38383 orders — folded by pure helpers so the logic is unit-tested
/// without a relay pool. The active-node order book (`orders::ORDER_BOOK`,
/// deliberately single-node) is never touched.
///
/// A node's settings rarely change, so the newest kind 38385 event of each
/// node is **cached** (`settings_keys::MOSTRO_NODE_INFO`): warmed at startup
/// by [`refresh_mostro_node_info_cache`], served by
/// [`cached_mostro_node_stats`] the moment the selector opens, and rewritten
/// by every [`fetch_mostro_node_stats`]. Order counts are never cached — a
/// stale count would be an invented one.
use std::collections::{BTreeMap, HashMap};

use anyhow::Result;
use nostr_sdk::prelude::{Event, Filter, Kind, PublicKey, SingleLetterTag, Timestamp};
use serde::{Deserialize, Serialize};

use crate::api::types::{BondPolicy, BondPolicyInfo, OrderInfo, OrderStatus};
use crate::db::{settings_keys, Storage};
use crate::mostro::{bond_policy, escrow_mode};
use crate::nostr::order_events::{parse_order_event, KIND_ORDER, RECENT_ORDERS_WINDOW_SECS};

/// Kind 38385 — Mostro instance status (NIP-33 addressable, `d` = pubkey).
const KIND_INSTANCE: u16 = 38385;

/// Relay round-trip budget for each query.
const FETCH_TIMEOUT_SECS: u64 = 10;

/// How long the startup warm-up waits for the relay handshakes it races with.
const WARM_UP_CONNECT_WAIT_SECS: u64 = 5;

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
    /// The node's full anti-abuse bond policy (`docs/ANTI_ABUSE_BOND.md`
    /// §3.4): three-state, with every parameter gated on `Enabled`.
    pub bond: BondPolicyInfo,
    /// `bond_enabled` tag: `Some(true)` when the node requires a bond,
    /// `Some(false)` when it explicitly does not, `None` when the daemon
    /// predates bonds. Derived from [`Self::bond`] for the node card.
    pub bond_required: Option<bool>,
    /// `bond_amount_pct`, **in percent**; only set when `bond_required` is
    /// `Some(true)`. Derived from [`Self::bond`] for the node card.
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
            bond: BondPolicyInfo::default(),
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

    stats.bond = bond_policy::parse_tags(tags);
    stats.bond_required = match stats.bond.policy {
        BondPolicy::Unsupported => None,
        BondPolicy::Disabled => Some(false),
        BondPolicy::Enabled => Some(true),
    };
    stats.bond_pct = stats.bond.amount_pct.map(|f| f * 100.0);
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

/// A node's newest kind 38385 event as persisted under
/// [`settings_keys::MOSTRO_NODE_INFO`]. The raw tags are kept, not the parsed
/// row, so a cached event is read by the same [`apply_info_tags`] as a live
/// one and a tag this client learns to parse later needs no migration.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct CachedNodeInfo {
    pub created_at: i64,
    /// Hex id of the event, which orders two revisions of the same second
    /// (see [`CachedNodeInfo::supersedes`]). `None` for an entry cached before
    /// the id was kept.
    #[serde(default)]
    pub event_id: Option<String>,
    pub tags: Vec<Vec<String>>,
}

impl CachedNodeInfo {
    /// Whether this revision replaces `held`, the way NIP-01 orders revisions
    /// of a replaceable event: the newer `created_at` wins, and within one
    /// second the **lowest** id — the one relays retain. Without the id a tie
    /// went to whichever relay answered first, so two devices could cache
    /// different settings for the same node. Same rule as the relay list's
    /// `generation_is_newer`.
    ///
    /// An entry without an id cannot claim to be the lowest: it yields a tie
    /// to a known id and never wins one.
    fn supersedes(&self, held: &Self) -> bool {
        match self.created_at.cmp(&held.created_at) {
            std::cmp::Ordering::Greater => true,
            std::cmp::Ordering::Less => false,
            // Ids are lowercase hex of equal length: string order is byte order.
            std::cmp::Ordering::Equal => match (&self.event_id, &held.event_id) {
                (Some(id), Some(held_id)) => id < held_id,
                (Some(_), None) => true,
                (None, _) => false,
            },
        }
    }
}

/// Newest valid kind 38385 per requested author; the `d` tag must be the
/// author itself, as in `fetch_mostro_instance_tags`.
fn newest_info(pubkeys: &[String], info_events: &[Event]) -> HashMap<String, CachedNodeInfo> {
    let mut newest: HashMap<String, CachedNodeInfo> = HashMap::new();
    for event in info_events {
        let author = event.pubkey.to_hex();
        if !pubkeys.contains(&author) {
            continue;
        }
        let tags: Vec<Vec<String>> = event.tags.iter().map(|t| t.as_slice().to_vec()).collect();
        if tag_value(&tags, "d") != Some(author.as_str()) {
            continue;
        }
        let info = CachedNodeInfo {
            created_at: event.created_at.as_secs() as i64,
            event_id: Some(event.id.to_hex()),
            tags,
        };
        if newest.get(&author).is_some_and(|prev| !info.supersedes(prev)) {
            continue;
        }
        newest.insert(author, info);
    }
    newest
}

/// Fold `fresh` into `cache`, the newest revision per node winning
/// ([`CachedNodeInfo::supersedes`]), and say whether anything changed — an unchanged cache is not rewritten.
fn merge_info(
    cache: &mut HashMap<String, CachedNodeInfo>,
    fresh: HashMap<String, CachedNodeInfo>,
) -> bool {
    let mut changed = false;
    for (pubkey, info) in fresh {
        match cache.get(&pubkey) {
            Some(prev) if !info.supersedes(prev) => {}
            _ => {
                cache.insert(pubkey, info);
                changed = true;
            }
        }
    }
    changed
}

/// Rows built from the cache alone, one per requested pubkey in request
/// order. No order counts: `total_orders` is `0` because nothing was counted,
/// not because the node is empty — the caller must not read availability or
/// liquidity off these rows.
fn rows_from_cache(
    pubkeys: &[String],
    cache: &HashMap<String, CachedNodeInfo>,
) -> Vec<MostroNodeStats> {
    pubkeys
        .iter()
        .map(|p| {
            let mut row = MostroNodeStats::empty(p);
            if let Some(info) = cache.get(p) {
                apply_info_tags(&mut row, &info.tags, info.created_at);
            }
            row
        })
        .collect()
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

    for (author, info) in newest_info(pubkeys, info_events) {
        if let Some(&i) = index.get(author.as_str()) {
            apply_info_tags(&mut rows[i], &info.tags, info.created_at);
        }
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

// ── KV persistence ───────────────────────────────────────────────────────────

async fn load_info_cache(db: &impl Storage) -> Result<HashMap<String, CachedNodeInfo>> {
    match db.get_setting(settings_keys::MOSTRO_NODE_INFO).await? {
        // A corrupt blob costs one cold open of the selector, nothing else.
        Some(json) => Ok(serde_json::from_str(&json).unwrap_or_default()),
        None => Ok(HashMap::new()),
    }
}

/// Merge `fresh` into the persisted cache. With `keep`, entries of nodes no
/// longer in it are dropped (a removed custom node). Writes only on a change.
async fn store_info(
    db: &impl Storage,
    fresh: HashMap<String, CachedNodeInfo>,
    keep: Option<&[String]>,
) -> Result<()> {
    // Same lock as the registry blobs: the cache is written as a whole, so
    // two concurrent cycles would drop one side's update. Held only around
    // the KV cycle, never across a relay round trip.
    let _guard = crate::api::nodes::registry_lock().lock().await;
    let mut cache = load_info_cache(db).await?;
    let mut changed = merge_info(&mut cache, fresh);
    if let Some(keep) = keep {
        let before = cache.len();
        cache.retain(|pubkey, _| keep.contains(pubkey));
        changed |= cache.len() != before;
    }
    if changed {
        db.set_setting(
            settings_keys::MOSTRO_NODE_INFO,
            &serde_json::to_string(&cache)?,
        )
        .await?;
    }
    Ok(())
}

/// Best effort: the cache is an optimization, so a failed write is logged and
/// the freshly fetched rows are still returned.
async fn store_info_best_effort(fresh: HashMap<String, CachedNodeInfo>, keep: Option<&[String]>) {
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    if let Err(e) = store_info(db, fresh, keep).await {
        log::warn!("[node_stats] could not persist the kind 38385 cache: {e}");
    }
}

fn parse_authors(pubkeys: &[String]) -> Result<Vec<PublicKey>> {
    pubkeys
        .iter()
        .map(|p| PublicKey::from_hex(p).map_err(|e| anyhow::anyhow!("InvalidPubkey: {e}")))
        .collect()
}

fn normalize_pubkeys(pubkeys: Vec<String>) -> Vec<String> {
    pubkeys
        .into_iter()
        .map(|p| p.trim().to_lowercase())
        .collect()
}

// ── Public API ───────────────────────────────────────────────────────────────

/// What the selector shows the moment it opens: one row per requested pubkey
/// (64-char hex), in request order, built from the persisted kind 38385 cache
/// alone — no relay is asked. A node never seen comes back as an empty row.
///
/// Order counts are **not** part of these rows (`total_orders == 0`,
/// `latest_order_at == None` regardless of the node's real book) and
/// `info_seen_at` is as old as the cache: never derive liquidity or
/// availability from them. [`fetch_mostro_node_stats`] supplies both.
pub async fn cached_mostro_node_stats(pubkeys: Vec<String>) -> Result<Vec<MostroNodeStats>> {
    let pubkeys = normalize_pubkeys(pubkeys);
    let cache = match crate::db::app_db::db() {
        Some(db) => load_info_cache(db).await?,
        None => HashMap::new(),
    };
    Ok(rows_from_cache(&pubkeys, &cache))
}

/// Download the kind 38385 event of every node in the registry (trusted and
/// user-added) and persist the newest per node. Called once at startup, in
/// the background, so the selector has every node's settings before it is
/// first opened. Entries of nodes that left the registry are dropped.
///
/// Best-effort: nodes that did not answer within the window keep their cached
/// event. Only an outright query failure is an error, and then the cache is
/// untouched.
pub async fn refresh_mostro_node_info_cache() -> Result<()> {
    use std::time::Duration;

    let pubkeys: Vec<String> = crate::api::nodes::list_mostro_nodes()
        .await?
        .into_iter()
        .map(|n| n.pubkey)
        .collect();
    let authors = parse_authors(&pubkeys)?;
    let client = crate::api::nostr::get_pool()?.client();
    // Runs right after the pool is created, while the relays are still
    // handshaking: a fetch issued now would reach none of them. A no-op once
    // they are connected.
    client
        .connect()
        .and_wait(Duration::from_secs(WARM_UP_CONNECT_WAIT_SECS))
        .await;
    let filter = Filter::new()
        .kind(Kind::from(KIND_INSTANCE))
        .authors(authors);
    let events = client
        .fetch_events(filter)
        .timeout(Duration::from_secs(FETCH_TIMEOUT_SECS))
        .await
        .map_err(|e| anyhow::anyhow!("fetch_events (38385) failed: {e}"))?;
    let events: Vec<Event> = events.into_iter().collect();
    let fresh = newest_info(&pubkeys, &events);
    // Prune against the registry as it is now, not as it was before the
    // round trip: a node added meanwhile must not lose its cached event.
    let keep: Vec<String> = match crate::api::nodes::list_mostro_nodes().await {
        Ok(nodes) => nodes.into_iter().map(|n| n.pubkey).collect(),
        Err(_) => pubkeys,
    };
    store_info_best_effort(fresh, Some(&keep)).await;
    Ok(())
}

/// Fetch decision data for every node in `pubkeys` (64-char hex) with three
/// relay queries — their kind 38385 instance events, their `pending` kind
/// 38383 orders, and every kind 38383 revision of the last
/// [`RECENT_ORDERS_WINDOW_SECS`] regardless of status — and return one
/// [`MostroNodeStats`] per requested pubkey, in request order.
///
/// The recent status-agnostic query is what keeps the count honest: a
/// relay may still hold an order's older `pending` revision next to its
/// newer `canceled` one, and the `s=pending` filter alone would never
/// return the newer revision, so [`dedup_latest`] could not discard the stale
/// one. Both sets are merged before deduplication.
///
/// Best-effort like `refresh_mostro_node_metadata`: whatever arrives within
/// the window is used, a node that answered nothing comes back as an empty
/// row (no `info_seen_at`, zero orders). Only an outright query failure or an
/// invalid pubkey is an error.
///
/// The kind 38385 events it received refresh the persisted cache behind
/// [`cached_mostro_node_stats`] (best effort, written only on a change).
pub async fn fetch_mostro_node_stats(pubkeys: Vec<String>) -> Result<Vec<MostroNodeStats>> {
    use std::time::Duration;

    let pubkeys = normalize_pubkeys(pubkeys);
    if pubkeys.is_empty() {
        return Ok(Vec::new());
    }
    let authors = parse_authors(&pubkeys)?;

    let client = crate::api::nostr::get_pool()?.client();
    let timeout = Duration::from_secs(FETCH_TIMEOUT_SECS);

    let info_filter = Filter::new()
        .kind(Kind::from(KIND_INSTANCE))
        .authors(authors.clone());
    let now = crate::rt::unix_now();
    let pending_filter = Filter::new()
        .kind(Kind::from(KIND_ORDER))
        .authors(authors.clone())
        .custom_tag(SingleLetterTag::LOWERCASE_S, "pending");
    let since = Timestamp::from_secs((now as u64).saturating_sub(RECENT_ORDERS_WINDOW_SECS));
    let recent_filter = Filter::new()
        .kind(Kind::from(KIND_ORDER))
        .authors(authors)
        .since(since);

    let (info, pending, recent) = tokio::join!(
        client.fetch_events(info_filter).timeout(timeout),
        client.fetch_events(pending_filter).timeout(timeout),
        client.fetch_events(recent_filter).timeout(timeout),
    );
    let info = info.map_err(|e| anyhow::anyhow!("fetch_events (38385) failed: {e}"))?;
    let pending =
        pending.map_err(|e| anyhow::anyhow!("fetch_events (38383 pending) failed: {e}"))?;
    let recent = recent.map_err(|e| anyhow::anyhow!("fetch_events (38383 recent) failed: {e}"))?;

    let info: Vec<Event> = info.into_iter().collect();
    // Merged before `summarize` deduplicates by (author, d): the newer
    // revision wins whichever query returned it.
    let orders: Vec<Event> = pending.into_iter().chain(recent).collect();
    store_info_best_effort(newest_info(&pubkeys, &info), None).await;
    Ok(summarize(&pubkeys, &info, &orders, now))
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
        assert_eq!(s.bond.policy, BondPolicy::Enabled);
        assert_eq!(s.bond.amount_pct, Some(0.02));
    }

    /// The card's `bond_required` / `bond_pct` are views over the full policy,
    /// so the two can never disagree about the same event.
    #[test]
    fn bond_card_fields_are_derived_from_the_policy() {
        let mut s = MostroNodeStats::empty(NODE_A);
        apply_info_tags(
            &mut s,
            &tags(&[
                ("bond_enabled", "true"),
                ("bond_apply_to", "both"),
                ("bond_amount_pct", "0.015"),
                ("bond_base_amount_sats", "2000"),
                ("bond_payout_claim_window_days", "10"),
            ]),
            1,
        );
        assert_eq!(s.bond.apply_to, Some(crate::api::types::BondApplyTo::Both));
        assert_eq!(s.bond.base_amount_sats, Some(2000));
        assert_eq!(s.bond.payout_claim_window_days, Some(10));
        assert_eq!(s.bond_required, Some(true));
        assert_eq!(s.bond_pct, Some(1.5));
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
    fn a_newer_canceled_revision_from_the_recent_query_beats_a_stale_pending_one() {
        // What the two relay queries hand back for the same `d` tag: the
        // `s=pending` query only ever sees the older pending revision; the
        // status-agnostic recent query sees the newer canceled one. Merged
        // (pending first, as in `fetch_mostro_node_stats`), the order must
        // not count as open.
        let pending_query = vec![order(NODE_A, "o1", "ARS", OrderStatus::Pending, 10)];
        let recent_query = vec![order(NODE_A, "o1", "ARS", OrderStatus::Canceled, 20)];
        let merged: Vec<OrderInfo> = pending_query.into_iter().chain(recent_query).collect();
        let per_node = count_open_orders(merged, 1_000);
        assert!(!per_node.contains_key(NODE_A));
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

    fn info_event(keys: &nostr_sdk::prelude::Keys, d: &str, fee: &str, created_at: u64) -> Event {
        use nostr_sdk::prelude::{EventBuilder, FinalizeEvent, Tag};
        EventBuilder::new(Kind::from(KIND_INSTANCE), "")
            .tags([
                Tag::parse(["d", d]).unwrap(),
                Tag::parse(["fee", fee]).unwrap(),
            ])
            .custom_created_at(Timestamp::from_secs(created_at))
            .finalize(keys)
            .unwrap()
    }

    fn cached(created_at: i64, fee: &str) -> CachedNodeInfo {
        CachedNodeInfo {
            created_at,
            event_id: None,
            tags: tags(&[("fee", fee)]),
        }
    }

    fn cached_with_id(created_at: i64, event_id: &str, fee: &str) -> CachedNodeInfo {
        CachedNodeInfo {
            event_id: Some(event_id.to_string()),
            ..cached(created_at, fee)
        }
    }

    async fn temp_store(tag: &str) -> crate::db::sqlite::SqliteStorage {
        let path =
            std::env::temp_dir().join(format!("mostro_node_info_{tag}_{}.db", std::process::id()));
        let _ = std::fs::remove_file(&path);
        crate::db::sqlite::SqliteStorage::open(path.to_str().unwrap())
            .await
            .unwrap()
    }

    #[test]
    fn newest_info_keeps_the_newest_valid_event_of_requested_authors() {
        let node = nostr_sdk::prelude::Keys::generate();
        let stranger = nostr_sdk::prelude::Keys::generate();
        let pk = node.public_key().to_hex();
        let events = vec![
            info_event(&node, &pk, "0.006", 200),
            info_event(&node, &pk, "0.01", 100),
            // `d` is not the author: not this node's instance event.
            info_event(&node, "someone-else", "0.5", 300),
            // Not a requested author.
            info_event(&stranger, &stranger.public_key().to_hex(), "0.9", 400),
        ];
        let newest = newest_info(std::slice::from_ref(&pk), &events);
        assert_eq!(newest.len(), 1);
        assert_eq!(newest[&pk].created_at, 200);
        assert_eq!(tag_value(&newest[&pk].tags, "fee"), Some("0.006"));
    }

    /// NIP-01: of two revisions of a replaceable event created in the same
    /// second, the one with the lowest id is the one relays retain. Which of
    /// them a relay answers with first must not decide what is cached.
    #[test]
    fn newest_info_breaks_a_same_second_tie_by_lowest_id_in_either_order() {
        // Arrange: same second, different fee → different ids.
        let node = nostr_sdk::prelude::Keys::generate();
        let pk = node.public_key().to_hex();
        let (a, b) = (
            info_event(&node, &pk, "0.006", 100),
            info_event(&node, &pk, "0.01", 100),
        );
        let lowest = if a.id.to_hex() < b.id.to_hex() { &a } else { &b };
        let expected_fee = tag_value(
            &lowest.tags.iter().map(|t| t.as_slice().to_vec()).collect::<Vec<_>>(),
            "fee",
        )
        .map(str::to_string);

        // Act
        let forward = newest_info(std::slice::from_ref(&pk), &[a.clone(), b.clone()]);
        let reversed = newest_info(std::slice::from_ref(&pk), &[b.clone(), a.clone()]);

        // Assert
        assert_eq!(forward[&pk].event_id, Some(lowest.id.to_hex()));
        assert_eq!(forward[&pk], reversed[&pk]);
        assert_eq!(
            tag_value(&forward[&pk].tags, "fee").map(str::to_string),
            expected_fee
        );
    }

    #[test]
    fn merge_info_replaces_a_same_second_entry_only_with_a_lower_id() {
        // Arrange
        let mut cache = HashMap::from([(NODE_A.to_string(), cached_with_id(100, "bb", "0.006"))]);

        // Act + Assert: a higher id of the same second loses…
        let higher = HashMap::from([(NODE_A.to_string(), cached_with_id(100, "cc", "0.5"))]);
        assert!(!merge_info(&mut cache, higher));
        assert_eq!(cache[NODE_A], cached_with_id(100, "bb", "0.006"));

        // …a lower one wins…
        let lower = HashMap::from([(NODE_A.to_string(), cached_with_id(100, "aa", "0.01"))]);
        assert!(merge_info(&mut cache, lower));
        assert_eq!(cache[NODE_A], cached_with_id(100, "aa", "0.01"));

        // …and the very same event is not a change.
        let same = HashMap::from([(NODE_A.to_string(), cached_with_id(100, "aa", "0.01"))]);
        assert!(!merge_info(&mut cache, same));
    }

    #[test]
    fn an_entry_cached_without_an_id_yields_a_same_second_tie_to_a_known_id() {
        // Arrange: written before the id was kept.
        let mut cache = HashMap::from([(NODE_A.to_string(), cached(100, "0.006"))]);

        // Act
        let live = HashMap::from([(NODE_A.to_string(), cached_with_id(100, "ff", "0.01"))]);
        let changed = merge_info(&mut cache, live);

        // Assert: the id-less entry cannot claim to be the lowest.
        assert!(changed);
        assert_eq!(cache[NODE_A], cached_with_id(100, "ff", "0.01"));

        // And it never wins one itself.
        let legacy = HashMap::from([(NODE_A.to_string(), cached(100, "0.5"))]);
        assert!(!merge_info(&mut cache, legacy));
    }

    #[test]
    fn a_cache_written_before_the_id_was_kept_still_loads() {
        // Arrange
        let json = r#"{"created_at":100,"tags":[["fee","0.006"]]}"#;

        // Act
        let info: CachedNodeInfo = serde_json::from_str(json).unwrap();

        // Assert
        assert_eq!(info, cached(100, "0.006"));
    }

    #[test]
    fn merge_info_lets_the_newest_event_win_and_reports_changes() {
        let mut cache = HashMap::from([(NODE_A.to_string(), cached(100, "0.006"))]);

        // Older or identical events change nothing — no rewrite.
        let stale = HashMap::from([(NODE_A.to_string(), cached(50, "0.5"))]);
        assert!(!merge_info(&mut cache, stale));
        let same = HashMap::from([(NODE_A.to_string(), cached(100, "0.006"))]);
        assert!(!merge_info(&mut cache, same));
        assert_eq!(cache[NODE_A], cached(100, "0.006"));

        // A newer event replaces the entry; a new node is added.
        let fresh = HashMap::from([
            (NODE_A.to_string(), cached(200, "0.01")),
            (NODE_B.to_string(), cached(10, "0.02")),
        ]);
        assert!(merge_info(&mut cache, fresh));
        assert_eq!(cache[NODE_A], cached(200, "0.01"));
        assert_eq!(cache[NODE_B], cached(10, "0.02"));
    }

    #[test]
    fn cached_rows_carry_the_settings_but_never_an_order_count() {
        let cache = HashMap::from([(NODE_A.to_string(), cached(100, "0.006"))]);
        let rows = rows_from_cache(&[NODE_B.into(), NODE_A.into()], &cache);
        assert_eq!(rows.len(), 2);
        // Request order, and a never-seen node is an empty row.
        assert_eq!(rows[0].pubkey, NODE_B);
        assert_eq!(rows[0].info_seen_at, None);
        assert_eq!(rows[1].pubkey, NODE_A);
        assert_eq!(rows[1].fee_pct, Some(0.6));
        assert_eq!(rows[1].info_seen_at, Some(100));
        assert_eq!(rows[1].total_orders, 0);
        assert!(rows[1].orders_by_fiat.is_empty());
        assert_eq!(rows[1].latest_order_at, None);
    }

    #[tokio::test]
    async fn the_info_cache_survives_a_round_trip_and_prunes_removed_nodes() {
        let db = temp_store("round_trip").await;
        assert!(load_info_cache(&db).await.unwrap().is_empty());

        let fresh = HashMap::from([
            (NODE_A.to_string(), cached(100, "0.006")),
            (NODE_B.to_string(), cached(100, "0.02")),
        ]);
        store_info(&db, fresh, None).await.unwrap();
        let loaded = load_info_cache(&db).await.unwrap();
        assert_eq!(loaded[NODE_A], cached(100, "0.006"));
        assert_eq!(loaded[NODE_B], cached(100, "0.02"));

        // A refresh that heard nothing keeps what it had…
        store_info(&db, HashMap::new(), None).await.unwrap();
        assert_eq!(load_info_cache(&db).await.unwrap().len(), 2);

        // …and one over a registry without NODE_B forgets NODE_B.
        store_info(&db, HashMap::new(), Some(&[NODE_A.to_string()]))
            .await
            .unwrap();
        let pruned = load_info_cache(&db).await.unwrap();
        assert_eq!(pruned.len(), 1);
        assert!(pruned.contains_key(NODE_A));
    }

    #[tokio::test]
    async fn a_corrupt_info_cache_reads_as_empty() {
        let db = temp_store("corrupt").await;
        db.set_setting(settings_keys::MOSTRO_NODE_INFO, "not json")
            .await
            .unwrap();
        assert!(load_info_cache(&db).await.unwrap().is_empty());
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
