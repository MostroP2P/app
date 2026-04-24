/// Orders API — read path for the public order book.
///
/// Subscribes to Kind 38383 events from the relay pool, caches locally,
/// applies filters, and exposes a stream for UI updates.
use anyhow::Result;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};

use crate::api::types::{NewOrderParams, OrderInfo, OrderKind, OrderStatus};
use crate::config::active_mostro_pubkey;
use crate::db::Storage;
use crate::mostro::actions;
use crate::nostr::order_events::parse_order_event;

// ── Per-trade key index map ───────────────────────────────────────────────────

/// Maps `order_id` → `trade_key_index` for trades initiated in this session.
/// Allows subsequent actions (add-invoice, fiat-sent, release) to sign with the
/// same trade key that was used when taking the order.
use std::sync::OnceLock;

static TRADE_KEY_MAP: OnceLock<std::sync::RwLock<HashMap<String, u32>>> = OnceLock::new();

fn trade_key_map() -> &'static std::sync::RwLock<HashMap<String, u32>> {
    TRADE_KEY_MAP.get_or_init(|| std::sync::RwLock::new(HashMap::new()))
}

/// Maps `trade_pubkey_hex` → `trade_key_index` for newly created maker orders.
///
/// The daemon assigns its own UUID to a new order and publishes it as a Kind
/// 38383 event signed by the daemon (not the maker), so there is no way to
/// derive the real order ID from the Kind 38383 event itself.  Instead we keep
/// a short-lived entry keyed by the trade public key and call
/// `resolve_maker_order` once the daemon's gift-wrapped acknowledgement arrives
/// and the real order ID is known.
static PENDING_MAKER_KEYS: OnceLock<std::sync::RwLock<HashMap<String, u32>>> = OnceLock::new();

fn pending_maker_keys() -> &'static std::sync::RwLock<HashMap<String, u32>> {
    PENDING_MAKER_KEYS.get_or_init(|| std::sync::RwLock::new(HashMap::new()))
}

fn store_pending_maker_key(trade_pubkey_hex: &str, index: u32) {
    if let Ok(mut map) = pending_maker_keys().write() {
        map.insert(trade_pubkey_hex.to_string(), index);
    }
}

// ── Daemon confirmation channel for create_order ─────────────────────────────

/// Result sent by the gift-wrap handler to the waiting `create_order` call.
enum DaemonConfirmation {
    /// Daemon accepted the order and assigned a UUID.
    Confirmed { daemon_id: String },
    /// Daemon rejected the order with a CantDo reason.
    Rejected { reason: String, message: String },
}

/// Maps `trade_pubkey_hex` → oneshot sender for the pending `create_order` call.
static PENDING_CONFIRMATIONS: OnceLock<std::sync::Mutex<HashMap<String, tokio::sync::oneshot::Sender<DaemonConfirmation>>>> = OnceLock::new();

fn pending_confirmations() -> &'static std::sync::Mutex<HashMap<String, tokio::sync::oneshot::Sender<DaemonConfirmation>>> {
    PENDING_CONFIRMATIONS.get_or_init(|| std::sync::Mutex::new(HashMap::new()))
}

/// Maps `content_key` → `local_uuid` for newly created maker orders.
///
/// At create time the order is added to the order book with a locally-generated
/// UUID.  When the daemon later publishes its own Kind 38383 event (with a
/// daemon-assigned UUID), the subscription loop uses this map to remove the
/// stale local entry so there is only one entry in the book — keyed by the
/// daemon's UUID — and `cancel_order` sends the correct ID.
static PENDING_LOCAL_IDS: OnceLock<std::sync::RwLock<HashMap<String, String>>> = OnceLock::new();

fn pending_local_ids() -> &'static std::sync::RwLock<HashMap<String, String>> {
    PENDING_LOCAL_IDS.get_or_init(|| std::sync::RwLock::new(HashMap::new()))
}

fn store_pending_local_id(content_key: &str, local_uuid: &str) {
    if let Ok(mut map) = pending_local_ids().write() {
        map.insert(content_key.to_string(), local_uuid.to_string());
    }
}

fn take_pending_local_id(content_key: &str) -> Option<String> {
    pending_local_ids()
        .write()
        .ok()
        .and_then(|mut m| m.remove(content_key))
}

/// Resolve a pending maker order once the daemon's gift-wrapped acknowledgement
/// is processed and the real order ID becomes known.
///
/// Moves the entry from `PENDING_MAKER_KEYS` into the regular `TRADE_KEY_MAP`
/// so that subsequent maker actions (e.g. cancel) can find the trade key via
/// `get_trade_key_index(real_order_id)`.
pub async fn resolve_maker_order(order_id: &str, trade_pubkey_hex: &str) {
    let index = pending_maker_keys()
        .read()
        .ok()
        .and_then(|m| m.get(trade_pubkey_hex).copied());
    if let Some(idx) = index {
        if let Ok(mut map) = pending_maker_keys().write() {
            map.remove(trade_pubkey_hex);
        }
        store_trade_key_index(order_id, idx).await;
        log::info!("[orders] resolved maker order={order_id} trade_index={idx}");
    } else {
        log::warn!("[orders] resolve_maker_order: no pending entry for pubkey={trade_pubkey_hex}");
    }
}

/// Build a stable content key for a maker order.
///
/// The key is stored in `TRADE_KEY_MAP` at creation time (prefixed with
/// `"content:"` so it never collides with real UUIDs).  On cold start the
/// relay subscription can compute the same key from an incoming Kind 38383
/// event and look up the trade index, restoring `is_mine = true` without
/// needing the daemon's gift-wrap acknowledgement.
fn order_content_key(
    kind: &crate::api::types::OrderKind,
    fiat_code: &str,
    fiat_amount: Option<f64>,
    fiat_amount_min: Option<f64>,
    fiat_amount_max: Option<f64>,
    payment_method: &str,
) -> String {
    let amount = match (fiat_amount, fiat_amount_min, fiat_amount_max) {
        (Some(a), _, _) => format!("f{}", a as i64),
        (_, Some(mn), Some(mx)) => format!("r{}:{}", mn as i64, mx as i64),
        _ => "?".to_string(),
    };
    let k = match kind {
        crate::api::types::OrderKind::Buy => "buy",
        crate::api::types::OrderKind::Sell => "sell",
    };
    format!("content:{k}:{fiat_code}:{amount}:{payment_method}")
}

/// Persist `index` for `order_id` in both the in-memory cache and the DB.
///
/// The in-memory write is synchronous and always succeeds.  The DB write is
/// best-effort — a failure is logged but does not prevent the trade from
/// proceeding (the in-memory value is still available for the remainder of
/// this session).
async fn store_trade_key_index(order_id: &str, index: u32) {
    if let Ok(mut map) = trade_key_map().write() {
        map.insert(order_id.to_string(), index);
    }
    if let Some(db) = crate::db::app_db::db() {
        if let Err(e) = db.save_trade_key(order_id, index).await {
            log::warn!("[orders] failed to persist trade key for order={order_id}: {e}");
        }
    }
}

/// Return the BIP-32 index for `order_id`, or `None` if not found.
///
/// Lookup order:
/// 1. In-memory cache (always up-to-date for the current session).
/// 2. Persistent DB (covers trades taken in a previous session).
///
/// Returns `None` when neither source has a record for the order.
/// Callers must treat `None` as an error rather than silently using index 0,
/// which would cause signature verification failures on the daemon side.
async fn get_trade_key_index(order_id: &str) -> Option<u32> {
    // Fast path: in-memory cache.
    if let Some(idx) = trade_key_map()
        .read()
        .ok()
        .and_then(|m| m.get(order_id).copied())
    {
        return Some(idx);
    }
    // Slow path: DB (populates cache on hit for subsequent calls).
    if let Some(db) = crate::db::app_db::db() {
        match db.get_trade_key(order_id).await {
            Ok(Some(idx)) => {
                if let Ok(mut map) = trade_key_map().write() {
                    map.insert(order_id.to_string(), idx);
                }
                return Some(idx);
            }
            Ok(None) => {}
            Err(e) => log::warn!("[orders] DB trade key lookup failed for order={order_id}: {e}"),
        }
    }
    log::warn!("[orders] trade key not found for order={order_id}");
    None
}

/// Expose trade key lookup for inter-module use (e.g. reputation rating).
pub(crate) async fn trade_key_for_order(order_id: &str) -> Option<u32> {
    get_trade_key_index(order_id).await
}

/// Expose event publishing for inter-module use.
pub(crate) async fn publish_event(event_json: &str) -> Result<()> {
    publish_event_json(event_json).await
}

/// Filter parameters for the order list.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct OrderFilters {
    pub kind: Option<OrderKind>,
    pub fiat_code: Option<String>,
    pub payment_method: Option<String>,
}

/// Shared order cache + broadcast channel for UI updates.
pub struct OrderBook {
    orders: Arc<RwLock<Vec<OrderInfo>>>,
    tx: broadcast::Sender<Vec<OrderInfo>>,
}

impl Default for OrderBook {
    fn default() -> Self {
        Self::new()
    }
}

impl OrderBook {
    pub fn new() -> Self {
        let (tx, _) = broadcast::channel(16);
        Self {
            orders: Arc::new(RwLock::new(Vec::new())),
            tx,
        }
    }

    /// Replace the cached order list and notify listeners.
    pub async fn set_orders(&self, orders: Vec<OrderInfo>) {
        *self.orders.write().await = orders.clone();
        let _ = self.tx.send(orders);
    }

    /// Insert or update a single order and notify listeners.
    pub async fn upsert_order(&self, order: OrderInfo) {
        let mut orders = self.orders.write().await;
        if let Some(existing) = orders.iter_mut().find(|o| o.id == order.id) {
            *existing = order;
        } else {
            orders.push(order);
        }
        let snapshot = orders.clone();
        drop(orders);
        let _ = self.tx.send(snapshot);
    }

    /// Update the status of an existing cached order and notify listeners.
    ///
    /// No-op when the order is not in the cache (e.g. already removed).
    pub async fn update_order_status(&self, order_id: &str, status: OrderStatus) {
        let mut orders = self.orders.write().await;
        if let Some(existing) = orders.iter_mut().find(|o| o.id == order_id) {
            existing.status = status;
            let snapshot = orders.clone();
            drop(orders);
            let _ = self.tx.send(snapshot);
        }
    }

    /// Get all cached orders, optionally filtered.
    pub async fn get_orders(&self, filters: Option<OrderFilters>) -> Vec<OrderInfo> {
        // Clone + filter under the read lock, then drop it before sorting.
        let mut result: Vec<OrderInfo> = {
            let orders = self.orders.read().await;
            orders
                .iter()
                .filter(|o| matches!(o.status, OrderStatus::Pending))
                .filter(|o| {
                    let Some(ref f) = filters else { return true };
                    if let Some(ref kind) = f.kind {
                        if &o.kind != kind {
                            return false;
                        }
                    }
                    if let Some(ref code) = f.fiat_code {
                        if !code.is_empty() && o.fiat_code != *code {
                            return false;
                        }
                    }
                    if let Some(ref pm) = f.payment_method {
                        if !pm.is_empty()
                            && !o.payment_method.to_lowercase().contains(&pm.to_lowercase())
                        {
                            return false;
                        }
                    }
                    true
                })
                .cloned()
                .collect()
        }; // read lock dropped here

        // Sort by ascending expiration (soonest-expiring first), then by
        // descending created_at for orders without expiration.
        result.sort_by(|a, b| match (a.expires_at, b.expires_at) {
            (Some(ea), Some(eb)) => ea.cmp(&eb),
            (Some(_), None) => std::cmp::Ordering::Less,
            (None, Some(_)) => std::cmp::Ordering::Greater,
            (None, None) => b.created_at.cmp(&a.created_at),
        });

        result
    }

    /// Get a single order by ID.
    pub async fn get_order(&self, order_id: &str) -> Option<OrderInfo> {
        self.orders
            .read()
            .await
            .iter()
            .find(|o| o.id == order_id)
            .cloned()
    }

    /// Remove the order with the given ID from the cache and notify listeners.
    /// No-op if the ID is not present.
    pub async fn remove_order(&self, order_id: &str) {
        let mut orders = self.orders.write().await;
        let before = orders.len();
        orders.retain(|o| o.id != order_id);
        if orders.len() != before {
            let snapshot = orders.clone();
            drop(orders);
            let _ = self.tx.send(snapshot);
        }
    }

    pub(crate) fn subscribe(&self) -> broadcast::Receiver<Vec<OrderInfo>> {
        self.tx.subscribe()
    }
}

// ── Global singleton ────────────────────────────────────────────────────────

use tokio::sync::OnceCell;

// ── Gift-wrap deduplication ──────────────────────────────────────────────────

/// Tracks recently processed gift-wrap event IDs to avoid duplicate processing
/// when both the per-trade and global subscriptions receive the same event.
static PROCESSED_GW: OnceLock<std::sync::Mutex<std::collections::VecDeque<String>>> = OnceLock::new();

/// Returns `true` if this event ID was already processed (duplicate).
/// Otherwise records it and returns `false`.
fn is_duplicate_gift_wrap(event_id: &str) -> bool {
    const MAX_ENTRIES: usize = 128;
    let deque = PROCESSED_GW.get_or_init(|| std::sync::Mutex::new(std::collections::VecDeque::new()));
    let mut guard = match deque.lock() {
        Ok(g) => g,
        Err(_) => return false,
    };
    if guard.iter().any(|id| id == event_id) {
        return true;
    }
    guard.push_back(event_id.to_string());
    if guard.len() > MAX_ENTRIES {
        guard.pop_front();
    }
    false
}

static ORDER_BOOK: OnceCell<OrderBook> = OnceCell::const_new();

fn order_book() -> &'static OrderBook {
    // Eagerly initialize on first access. The init closure is sync-compatible
    // because OrderBook::new() does no async work.
    if ORDER_BOOK.get().is_none() {
        // Safe to ignore the result — concurrent calls will race harmlessly
        // and OnceCell ensures only one value is stored.
        let _ = ORDER_BOOK.set(OrderBook::new());
    }
    ORDER_BOOK.get().expect("OrderBook not initialized")
}

/// Public API: get filtered orders.
pub async fn get_orders(filters: Option<OrderFilters>) -> Result<Vec<OrderInfo>> {
    Ok(order_book().get_orders(filters).await)
}

/// Public API: get a single order by ID.
pub async fn get_order(order_id: String) -> Result<Option<OrderInfo>> {
    Ok(order_book().get_order(&order_id).await)
}

/// Create a new order on the Mostro network.
///
/// Validates params, builds the MostroMessage, wraps via NIP-59, and
/// publishes to relays. Queues if offline.
///
pub async fn create_order(params: NewOrderParams) -> Result<OrderInfo> {
    // Validate: fiat_amount XOR range
    let has_fixed = params.fiat_amount.is_some();
    let has_range = params.fiat_amount_min.is_some() && params.fiat_amount_max.is_some();
    if has_fixed == has_range {
        return Err(anyhow::anyhow!(
            "Must provide either fiat_amount or both fiat_amount_min and fiat_amount_max"
        ));
    }
    if has_fixed {
        let amount = params.fiat_amount.unwrap();
        if amount <= 0.0 || !amount.is_finite() {
            return Err(anyhow::anyhow!("fiat_amount must be > 0"));
        }
    }
    if has_range {
        let min = params.fiat_amount_min.unwrap();
        let max = params.fiat_amount_max.unwrap();
        if !min.is_finite() || !max.is_finite() {
            return Err(anyhow::anyhow!(
                "fiat_amount_min and fiat_amount_max must be finite"
            ));
        }
        if min <= 0.0 || min >= max {
            return Err(anyhow::anyhow!(
                "fiat_amount_min must be > 0 and < fiat_amount_max"
            ));
        }
    }
    if params.fiat_code.trim().is_empty() {
        return Err(anyhow::anyhow!("fiat_code must not be empty"));
    }
    if params.payment_method.trim().is_empty() {
        return Err(anyhow::anyhow!("payment_method must not be empty"));
    }

    // Build a local OrderInfo representing the newly created order.
    // In Phase 7, this will be replaced by the actual Mostro response
    // after the NIP-59 message is published and acknowledged.
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;

    // Clone params before the struct takes ownership of its fields.
    let params_for_dispatch = params.clone();

    let mut order = OrderInfo {
        id: uuid::Uuid::new_v4().to_string(),
        kind: params.kind,
        status: OrderStatus::Pending,
        amount_sats: params.amount_sats,
        fiat_amount: params.fiat_amount,
        fiat_amount_min: params.fiat_amount_min,
        fiat_amount_max: params.fiat_amount_max,
        fiat_code: params.fiat_code,
        payment_method: params.payment_method,
        premium: params.premium,
        creator_pubkey: String::new(),
        created_at: now,
        expires_at: Some(now + 24 * 3600),
        is_mine: true,
    };

    // Derive a fresh trade key — each order must use a unique derived key index
    // so the daemon can verify the trade index in the message.
    let trade_key_info = crate::api::identity::derive_trade_key().await?;
    let trade_index = trade_key_info.index;
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;

    // Build the content fingerprint key BEFORE publishing so the subscription
    // loop never races against an empty TRADE_KEY_MAP when the daemon replies
    // faster than our post-publish bookkeeping runs.
    let ck = order_content_key(
        &params_for_dispatch.kind,
        &params_for_dispatch.fiat_code,
        params_for_dispatch.fiat_amount,
        params_for_dispatch.fiat_amount_min,
        params_for_dispatch.fiat_amount_max,
        &params_for_dispatch.payment_method,
    );

    // Register all bookkeeping entries before publishing the event.
    // The daemon can respond with a Kind 38383 event within milliseconds; if
    // we stored these after publish the subscription loop could arrive before
    // the keys are written and miss the fingerprint match entirely.
    store_trade_key_index(&order.id, trade_index).await; // local UUID fallback
    store_trade_key_index(&ck, trade_index).await; // content fingerprint
    let trade_pk_hex = sender_keys.public_key().to_hex();
    store_pending_maker_key(&trade_pk_hex, trade_index);
    store_pending_local_id(&ck, &order.id);

    // DO NOT add to order book or DB yet — wait for daemon confirmation first.
    // This avoids a phantom "pending" order when the daemon rejects (CantDo).

    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;
    let identity_keys =
        crate::api::identity::get_transport_identity_keys(&sender_keys).await?;
    let event_json = actions::new_order(
        &identity_keys,
        &sender_keys,
        &mostro_pubkey,
        &params_for_dispatch,
        trade_index,
    )
    .await?;

    // Set up the confirmation channel AFTER building the event but BEFORE
    // publishing, so the entry is in the map before any response can arrive.
    let (conf_tx, conf_rx) = tokio::sync::oneshot::channel::<DaemonConfirmation>();
    if let Ok(mut map) = pending_confirmations().lock() {
        map.insert(trade_pk_hex.clone(), conf_tx);
    }

    // Subscribe to gift-wrap responses AFTER registering the confirmation
    // channel so that any events (including stale ones replayed by relays)
    // find the entry and notify us instead of being silently discarded.
    subscribe_gift_wraps(sender_keys.public_key(), trade_index).await;

    if let Err(e) = publish_event_json(&event_json).await {
        // Rollback all in-memory bookkeeping on publish failure.
        if let Ok(mut m) = trade_key_map().write() { m.remove(&order.id); m.remove(&ck); }
        if let Ok(mut m) = pending_maker_keys().write() { m.remove(&trade_pk_hex); }
        if let Ok(mut m) = pending_local_ids().write() { m.remove(&ck); }
        if let Ok(mut m) = pending_confirmations().lock() { m.remove(&trade_pk_hex); }
        return Err(e.into());
    }

    crate::api::logging::blog_info("orders", format!(
        "create_order published id={} trade_index={trade_index} — waiting for daemon",
        order.id
    ));

    // Wait for daemon confirmation. The daemon typically responds within 1s.
    // The 5s timeout is a safety net for network issues.
    let confirmation = tokio::time::timeout(
        std::time::Duration::from_secs(5),
        conf_rx,
    ).await;

    // Clean up the pending entry regardless of outcome.
    if let Ok(mut map) = pending_confirmations().lock() {
        map.remove(&trade_pk_hex);
    }

    // Determine the final order ID (daemon UUID or local fallback).
    let final_order_id = match confirmation {
        Ok(Ok(DaemonConfirmation::Confirmed { daemon_id })) => {
            crate::api::logging::blog_info("orders", format!(
                "create_order confirmed by daemon: {daemon_id}"
            ));
            daemon_id
        }
        Ok(Ok(DaemonConfirmation::Rejected { reason, message })) => {
            crate::api::logging::blog_warn("orders", format!(
                "create_order rejected: {reason} — {message}"
            ));
            return Err(anyhow::anyhow!("{message}"));
        }
        _ => {
            // Timeout — optimistic: use local UUID and add to book/DB.
            crate::api::logging::blog_info("orders", format!(
                "create_order: no daemon response within 5s, using local id={}", order.id
            ));
            order.id.clone()
        }
    };

    // Order confirmed (or timeout) — now create the local state.
    order.id = final_order_id.clone();
    order_book().upsert_order(order.clone()).await;

    let maker_role = match order.kind {
        OrderKind::Sell => crate::api::types::TradeRole::Seller,
        OrderKind::Buy => crate::api::types::TradeRole::Buyer,
    };
    let maker_step = match maker_role {
        crate::api::types::TradeRole::Seller => {
            crate::api::types::TradeStep::Seller(crate::api::types::SellerStep::OrderPublished)
        }
        crate::api::types::TradeRole::Buyer => {
            crate::api::types::TradeStep::Buyer(crate::api::types::BuyerStep::OrderTaken)
        }
    };
    let trade = crate::api::types::TradeInfo {
        id: order.id.clone(),
        order: order.clone(),
        role: maker_role,
        counterparty_pubkey: String::new(),
        current_step: maker_step,
        hold_invoice: None,
        buyer_invoice: None,
        trade_key_index: trade_index,
        cooperative_cancel_state: None,
        timeout_at: None,
        started_at: now,
        completed_at: None,
        outcome: None,
    };
    if let Some(db) = crate::db::app_db::db() {
        if let Err(e) = db.save_trade(&trade).await {
            log::warn!("[orders] failed to persist maker trade: {e}");
        }
    }

    Ok(order)
}

/// Take an existing order, starting a trade.
///
/// Sends a `take-buy` or `take-sell` MostroMessage via NIP-59 using a freshly
/// derived trade key.  Automatically includes the user's default Lightning
/// Address in the payload when taking a sell order (take-sell-ln-address flow).
/// Returns a `TradeInfo` with the initial trade state.
pub async fn take_order(
    order_id: String,
    role: crate::api::types::TradeRole,
    fiat_amount: Option<f64>,
) -> Result<crate::api::types::TradeInfo> {
    let order = order_book()
        .get_order(&order_id)
        .await
        .ok_or_else(|| anyhow::anyhow!("OrderNotFound"))?;

    if order.is_mine {
        return Err(anyhow::anyhow!("CannotTakeOwnOrder"));
    }

    if order.status != OrderStatus::Pending {
        return Err(anyhow::anyhow!("OrderAlreadyTaken"));
    }

    // Validate range amount when order has a range.
    let is_range = order.fiat_amount_min.is_some() && order.fiat_amount_max.is_some();
    if is_range {
        let amt = fiat_amount.ok_or_else(|| anyhow::anyhow!("FiatAmountRequired"))?;
        if !amt.is_finite() || amt <= 0.0 {
            return Err(anyhow::anyhow!("fiat_amount must be positive and finite"));
        }
        let min = order.fiat_amount_min.unwrap();
        let max = order.fiat_amount_max.unwrap();
        if amt < min || amt > max {
            return Err(anyhow::anyhow!("OutOfRange"));
        }
    }

    use crate::api::types::*;

    // Role must match order kind: buyers take sell orders; sellers take buy orders.
    let expected_role = match order.kind {
        OrderKind::Buy => TradeRole::Seller,
        OrderKind::Sell => TradeRole::Buyer,
    };
    if role != expected_role {
        return Err(anyhow::anyhow!("InvalidRole"));
    }

    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;

    let dispatch_role = role.clone();
    let initial_step = match role {
        TradeRole::Buyer => TradeStep::Buyer(BuyerStep::OrderTaken),
        TradeRole::Seller => TradeStep::Seller(SellerStep::TakerFound),
    };

    // Derive a fresh trade key so each take uses a unique Nostr identity.
    let trade_key_info = crate::api::identity::derive_trade_key().await?;
    let trade_index = trade_key_info.index;
    // Do NOT persist the mapping here — store only after the take event is
    // successfully published so a publish failure doesn't leave a stale entry.

    let trade = TradeInfo {
        id: uuid::Uuid::new_v4().to_string(),
        order: order.clone(),
        role,
        counterparty_pubkey: order.creator_pubkey.clone(),
        current_step: initial_step,
        hold_invoice: None,
        buyer_invoice: None,
        trade_key_index: trade_index,
        cooperative_cancel_state: None,
        timeout_at: Some(now + 900),
        started_at: now,
        completed_at: None,
        outcome: None,
    };

    // Dispatch the take action to Mostro using the trade key for signing.
    match crate::api::identity::get_active_trade_keys(trade_index).await {
        Ok(sender_keys) => {
            match nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey()) {
                Ok(mostro_pubkey) => {
                    // Read default LN address from settings (take-sell-ln-address flow).
                    let ln_address: Option<String> = crate::api::settings::get_settings()
                        .await
                        .ok()
                        .and_then(|s| s.default_lightning_address);
                    let ln_address_ref = ln_address.as_deref();

                    let identity_keys = match crate::api::identity::get_transport_identity_keys(
                        &sender_keys,
                    )
                    .await
                    {
                        Ok(k) => k,
                        Err(e) => {
                            log::error!(
                                "[orders] take_order: could not resolve identity keys: {e}"
                            );
                            return Ok(trade);
                        }
                    };
                    let action_result = match dispatch_role {
                        TradeRole::Buyer => {
                            actions::take_sell(
                                &identity_keys,
                                &sender_keys,
                                &mostro_pubkey,
                                &order_id,
                                trade_index,
                                fiat_amount,
                                ln_address_ref,
                            )
                            .await
                        }
                        TradeRole::Seller => {
                            actions::take_buy(
                                &identity_keys,
                                &sender_keys,
                                &mostro_pubkey,
                                &order_id,
                                trade_index,
                                fiat_amount,
                            )
                            .await
                        }
                    };

                    match action_result {
                        Ok(event_json) => {
                            if let Err(e) = publish_event_json(&event_json).await {
                                log::warn!("[orders] take_order publish failed: {e}");
                            } else {
                                // Persist trade-key mapping and trade record only after a
                                // successful publish so failures leave no stale state.
                                store_trade_key_index(&order_id, trade_index).await;
                                if let Some(db) = crate::db::app_db::db() {
                                    if let Err(e) = db.save_trade(&trade).await {
                                        log::warn!("[orders] failed to persist trade: {e}");
                                    }
                                }
                                log::info!(
                                    "[orders] take_order dispatched order={order_id} \
                                     trade_index={trade_index} ln_address={}",
                                    if ln_address_ref.is_some() {
                                        "present"
                                    } else {
                                        "none"
                                    }
                                );
                                // Subscribe to d-tag K38383 updates for this specific order so we
                                // receive status changes (pending → in-progress → waiting-payment …).
                                subscribe_single_order(&order_id).await;
                                // Subscribe to NIP-59 gift-wrap daemon responses addressed to
                                // this trade key so we can receive BuyerTookOrder /
                                // HoldInvoicePaymentAccepted and unlock the P2P chat.
                                subscribe_gift_wraps(sender_keys.public_key(), trade_index).await;
                                // Create a session so the chat API can look up keys immediately.
                                let _ = crate::mostro::session::session_manager()
                                    .create_session(
                                        order_id.clone(),
                                        trade.role.clone(),
                                        trade_index,
                                        trade.order.clone(),
                                    )
                                    .await;
                            }
                        }
                        Err(e) => log::warn!("[orders] take_order action build failed: {e}"),
                    }
                }
                Err(e) => log::error!("[orders] take_order: invalid mostro pubkey: {e}"),
            }
        }
        Err(e) => log::warn!("[orders] take_order: could not get trade keys: {e}"),
    }

    Ok(trade)
}

/// Submit buyer's Lightning invoice for a trade.
///
/// Sends an `AddInvoice` MostroMessage to the daemon signed with the trade key
/// that was used when taking the order.
pub async fn send_invoice(
    order_id: String,
    invoice_or_address: String,
    amount_sats: u64,
) -> Result<()> {
    if invoice_or_address.trim().is_empty() {
        return Err(anyhow::anyhow!("Invoice or address must not be empty"));
    }

    // For bolt11 invoices the amount is encoded in the invoice; pass None.
    // For Lightning Addresses Mostro needs the amount to resolve the address.
    let amount_opt = if invoice_or_address.contains('@') && amount_sats > 0 {
        Some(amount_sats)
    } else {
        None
    };

    let trade_index = get_trade_key_index(&order_id)
        .await
        .ok_or_else(|| anyhow::anyhow!("no persisted trade key for order {order_id}"))?;
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    let identity_keys =
        crate::api::identity::get_transport_identity_keys(&sender_keys).await?;
    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;
    let event_json = actions::add_invoice(
        &identity_keys,
        &sender_keys,
        &mostro_pubkey,
        &order_id,
        trade_index,
        &invoice_or_address,
        amount_opt,
    )
    .await?;
    publish_event_json(&event_json).await?;
    log::info!(
        "[orders] add_invoice published for order={order_id} trade_index={trade_index} \
         ln_address={} amount={:?}",
        invoice_or_address.contains('@'),
        amount_opt
    );
    Ok(())
}

/// Mark fiat payment as sent by the buyer.
///
/// Sends a `FiatSent` MostroMessage to the Mostro daemon signed with the trade
/// key that was used when taking the order.
pub async fn send_fiat_sent(order_id: String) -> Result<()> {
    let trade_index = get_trade_key_index(&order_id)
        .await
        .ok_or_else(|| anyhow::anyhow!("no persisted trade key for order {order_id}"))?;
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    let identity_keys =
        crate::api::identity::get_transport_identity_keys(&sender_keys).await?;
    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;
    let event_json = actions::fiat_sent(
        &identity_keys,
        &sender_keys,
        &mostro_pubkey,
        &order_id,
        trade_index,
    )
    .await?;
    publish_event_json(&event_json).await?;
    log::info!("[orders] fiat_sent published for order={order_id} trade_index={trade_index}");
    Ok(())
}

/// Seller confirms fiat received and releases escrowed sats.
///
/// Sends a `Release` MostroMessage to the Mostro daemon signed with the trade
/// key that was used when taking the order.
pub async fn release_order(order_id: String) -> Result<()> {
    let trade_index = get_trade_key_index(&order_id)
        .await
        .ok_or_else(|| anyhow::anyhow!("no persisted trade key for order {order_id}"))?;
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    let identity_keys =
        crate::api::identity::get_transport_identity_keys(&sender_keys).await?;
    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;
    let event_json = actions::release(
        &identity_keys,
        &sender_keys,
        &mostro_pubkey,
        &order_id,
        trade_index,
    )
    .await?;
    publish_event_json(&event_json).await?;
    log::info!("[orders] release published for order={order_id} trade_index={trade_index}");
    Ok(())
}

/// Cancel an active trade cooperatively.
///
/// Sends a `Cancel` MostroMessage signed with the trade key used when the order
/// was taken.  Both parties must cancel for it to take effect; the Mostro daemon
/// handles the cooperative-cancel state machine.
pub async fn cancel_order(order_id: String) -> Result<()> {
    let trade_index = get_trade_key_index(&order_id)
        .await
        .ok_or_else(|| anyhow::anyhow!("no persisted trade key for order {order_id}"))?;
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    let identity_keys =
        crate::api::identity::get_transport_identity_keys(&sender_keys).await?;
    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;
    let event_json = actions::cancel(
        &identity_keys,
        &sender_keys,
        &mostro_pubkey,
        &order_id,
        trade_index,
    )
    .await?;
    publish_event_json(&event_json).await?;

    // Optimistic update: mark the trade as Canceled in the local DB immediately
    // so the UI reflects the change without waiting for the daemon's gift-wrap
    // response. Also remove the order from the in-memory order book.
    order_book().remove_order(&order_id).await;
    if let Some(db) = crate::db::app_db::db() {
        if let Err(e) = db
            .update_trade_fields(
                &order_id,
                Some(crate::api::types::OrderStatus::Canceled),
                None,
                None,
            )
            .await
        {
            log::warn!("[orders] failed to optimistically update cancel status for {order_id}: {e}");
        }
    }

    log::info!("[orders] cancel published for order={order_id} trade_index={trade_index}");
    Ok(())
}

// ── Gift-wrap (Kind 1059) subscription ───────────────────────────────────────

/// Subscribe to NIP-59 Gift Wrap (Kind 1059) events addressed to a maker's
/// trade key, spawning a background task that decrypts daemon responses.
///
/// Called immediately after creating a new maker order. Handles:
/// - `Action::NewOrder` — daemon confirmed the order; bridges daemon UUID into
///   `TRADE_KEY_MAP` via `resolve_maker_order`.
/// - All other actions are logged (full trade-session routing is Phase 7+).
///
/// The relay subscription is established synchronously (awaited) before returning,
/// then the event loop is spawned as a background task. This guarantees the
/// subscription is active before the caller publishes the order event.
pub(crate) async fn subscribe_gift_wraps(trade_pubkey: nostr_sdk::PublicKey, trade_index: u32) {
    // ── Synchronous setup: awaited by the caller ──
    let recipient_keys = match crate::api::identity::get_active_trade_keys(trade_index).await {
        Ok(k) => k,
        Err(e) => {
            log::error!("[orders] subscribe_gift_wraps: no trade keys: {e}");
            return;
        }
    };

    let Ok(pool) = crate::api::nostr::get_pool() else {
        log::warn!("[orders] subscribe_gift_wraps: relay pool not initialized");
        return;
    };
    let client = pool.client();

    // Obtain the notifications receiver BEFORE subscribing to avoid a
    // window where daemon responses arrive but aren't captured.
    let mut rx = client.notifications();

    let filter = nostr_sdk::Filter::new()
        .kind(nostr_sdk::Kind::from(1059u16))
        .pubkey(trade_pubkey);
    if let Err(e) = client.subscribe(filter, None).await {
        log::warn!("[orders] subscribe_gift_wraps subscribe failed: {e}");
        return;
    }

    let trade_pubkey_hex = trade_pubkey.to_hex();
    crate::api::logging::blog_info("orders", format!(
        "gift-wrap subscription active for trade={}",
        &trade_pubkey_hex[..8]
    ));

    // ── Event loop: spawned as a background task ──
    tokio::spawn(async move {
        use nostr_sdk::RelayPoolNotification;
        use tokio::time::{timeout, Duration};

        const IDLE_TIMEOUT_SECS: u64 = 30 * 60;
        let mut last_activity = tokio::time::Instant::now();

        loop {
            let remaining =
                Duration::from_secs(IDLE_TIMEOUT_SECS).saturating_sub(last_activity.elapsed());
            if remaining.is_zero() {
                break;
            }

            match timeout(remaining, rx.recv()).await {
                Ok(Ok(RelayPoolNotification::Event { event, .. })) => {
                    if event.kind != nostr_sdk::Kind::from(1059u16) {
                        continue;
                    }
                    let is_for_us = event.tags.iter().any(|t| {
                        let s = t.as_slice();
                        s.first().map(|v| v.as_str()) == Some("p")
                            && s.get(1).map(|v| v.as_str()) == Some(trade_pubkey_hex.as_str())
                    });
                    if !is_for_us {
                        continue;
                    }

                    let eid = event.id.to_hex();
                    if is_duplicate_gift_wrap(&eid) {
                        continue;
                    }
                    crate::api::logging::blog_info("gift-wrap", format!(
                        "Kind 1059 received (per-trade) for trade={} from={} event_id={}",
                        &trade_pubkey_hex[..8],
                        &event.pubkey.to_hex()[..8],
                        &eid[..16],
                    ));
                    match crate::nostr::gift_wrap::unwrap_mostro_message(&recipient_keys, &event).await {
                        Ok(Some(unwrapped)) => {
                            dispatch_mostro_message(unwrapped, &trade_pubkey_hex, trade_index).await;
                            last_activity = tokio::time::Instant::now();
                        }
                        Ok(None) => {
                            // The per-trade filter already narrowed by p-tag, so this
                            // only fires if a relay delivers a wrap whose outer NIP-44
                            // layer doesn't decrypt under our key — not actionable, and
                            // cheap for a hostile relay to spam. Keep it at debug.
                            crate::api::logging::blog_debug("gift-wrap", format!(
                                "decrypt returned None for trade={}", &trade_pubkey_hex[..8]
                            ));
                        }
                        Err(e) => crate::api::logging::blog_warn("gift-wrap", format!(
                            "decrypt failed for trade={}: {e}", &trade_pubkey_hex[..8]
                        )),
                    }
                }
                Ok(Ok(RelayPoolNotification::Shutdown)) => break,
                Ok(Err(broadcast::error::RecvError::Lagged(n))) => {
                    log::warn!("[orders] gift-wrap lagged by {n} messages");
                    continue;
                }
                Ok(Err(broadcast::error::RecvError::Closed)) => break,
                Err(_) => break, // idle timeout
                Ok(Ok(_)) => continue,
            }
        }
    });
}

/// Dispatch a Mostro `Message` recovered from a gift-wrap.
///
/// Authenticates the sender against the active Mostro pubkey, runs the
/// centralized `validate_response` check (catches `CantDo` responses and
/// malformed `request_id` fields), then routes by action.
async fn dispatch_mostro_message(
    unwrapped: mostro_core::nip59::UnwrappedMessage,
    trade_pubkey_hex: &str,
    trade_index: u32,
) {
    use mostro_core::message::Action;

    // mostro-core 0.10 adds `identity` (seal signer, long-lived) alongside
    // `sender` (rumor author, per-trade). A Mostro node that opts out of the
    // identity/trade split — the current daemon — reuses the same key for
    // both, so `identity == sender`. We keep the existing sender-based
    // authentication check below; the extra `identity` field is deliberately
    // ignored here.
    let mostro_core::nip59::UnwrappedMessage {
        message: msg,
        sender,
        identity: _,
        signature: _,
        created_at: _,
    } = unwrapped;

    // Daemon authentication: the active Mostro pubkey is the only legitimate
    // sender for protocol responses. Reject anything else loudly — previously
    // we trusted whatever decrypted under our trade key.
    match nostr_sdk::PublicKey::from_hex(&crate::config::active_mostro_pubkey()) {
        Ok(expected) if expected == sender => {}
        Ok(expected) => {
            crate::api::logging::blog_warn("gift-wrap", format!(
                "rejecting gift-wrap: sender={} != active mostro={} (trade={})",
                &sender.to_hex()[..8],
                &expected.to_hex()[..8],
                &trade_pubkey_hex[..8],
            ));
            return;
        }
        Err(e) => {
            crate::api::logging::blog_warn("gift-wrap", format!(
                "active mostro pubkey is invalid: {e} — cannot authenticate gift-wrap"
            ));
            return;
        }
    }

    // Centralized response validation: catches malformed `request_id` fields
    // and flags `CantDo` responses. We pass `None` because the app does not
    // yet track outstanding request_ids per action (see issue #101 §5).
    //
    // `MostroCantDo` is NOT a reason to drop the message — the `Action::CantDo`
    // arm below is what unblocks `create_order` callers waiting on a
    // `pending_confirmations` oneshot. Without propagating it, rejected orders
    // time out and fall back to the optimistic local-ID path, leaving phantom
    // pending orders in the book.
    match mostro_core::nip59::validate_response(&msg, None) {
        Ok(()) => {}
        Err(mostro_core::prelude::MostroError::MostroCantDo(_)) => {
            // Fall through to dispatch so the Action::CantDo arm can resolve
            // any waiting `create_order` confirmation.
        }
        Err(e) => {
            crate::api::logging::blog_warn("gift-wrap", format!(
                "validate_response rejected message for trade={}: {e:?}",
                &trade_pubkey_hex[..8]
            ));
            return;
        }
    }

    let kind = msg.get_inner_message_kind();

    let payload_desc = match &kind.payload {
        Some(mostro_core::message::Payload::Order(o)) => format!(
            "Order(status={:?}, amount={}, buyer_pk={}, seller_pk={})",
            o.status,
            o.amount,
            o.buyer_trade_pubkey.as_deref().unwrap_or("-"),
            o.seller_trade_pubkey.as_deref().unwrap_or("-"),
        ),
        Some(mostro_core::message::Payload::PaymentRequest(id, pr, amt)) => format!(
            "PaymentRequest(id={id:?}, invoice_len={}, amount={amt:?})",
            pr.len()
        ),
        Some(other) => format!("{other:?}"),
        None => "None".to_string(),
    };
    crate::api::logging::blog_info("gift-wrap", format!(
        "action={:?} order_id={:?} trade_index={:?} trade_pubkey={} payload={}",
        kind.action, kind.id, kind.trade_index, &trade_pubkey_hex[..8], payload_desc
    ));

    // Reconcile local UUID → daemon UUID if needed.  Gift wrap actions
    // arrive with the daemon's order ID, but if create_order timed out the
    // order book and DB still use the local UUID.  Reconcile before any
    // status update so that update_order_status / update_trade_fields find
    // the order by the daemon ID.
    if let Some(daemon_id) = &kind.id {
        let did = daemon_id.to_string();
        if order_book().get_order(&did).await.is_none() {
            if let Some(db) = crate::db::app_db::db() {
                if let Ok(Some(local_id)) = db.get_order_id_by_trade_index(trade_index).await {
                    if local_id != did {
                        log::info!(
                            "[orders] reconciling order ID: local={local_id} → daemon={did}"
                        );
                        if let Some(mut info) = order_book().get_order(&local_id).await {
                            order_book().remove_order(&local_id).await;
                            info.id = did.clone();
                            order_book().upsert_order(info).await;
                        }
                        let _ = db.update_trade_order_id(&local_id, &did).await;
                        // Replace the stale local_id → trade_index mapping
                        // with daemon_id → trade_index in both DB and memory.
                        let _ = db.delete_trade_key(&local_id).await;
                        let _ = db.save_trade_key(&did, trade_index).await;
                        if let Ok(mut map) = trade_key_map().write() {
                            map.remove(&local_id);
                        }
                        store_trade_key_index(&did, trade_index).await;
                    }
                }
            }
        }
    }

    match &kind.action {
        Action::NewOrder => {
            if let Some(order_id) = &kind.id {
                let daemon_id = order_id.to_string();
                resolve_maker_order(&daemon_id, trade_pubkey_hex).await;

                // If create_order is waiting for confirmation, notify it.
                // The caller handles UUID replacement. Otherwise (cold-start /
                // reconnect), do the replacement here.
                let conf_tx = pending_confirmations()
                    .lock()
                    .ok()
                    .and_then(|mut m| m.remove(trade_pubkey_hex));
                if let Some(tx) = conf_tx {
                    let _ = tx.send(DaemonConfirmation::Confirmed {
                        daemon_id: daemon_id.clone(),
                    });
                    crate::api::logging::blog_info("gift-wrap", format!(
                        "NewOrder: notified waiting create_order daemon={daemon_id}"
                    ));
                } else {
                    // No waiting caller — either cold start, reconnect, or
                    // create_order timed out. Reconcile the local UUID with
                    // the daemon UUID if the order was persisted under a local ID.
                    let local_id = pending_local_ids()
                        .write()
                        .ok()
                        .and_then(|mut m| {
                            // Find the entry whose local_uuid is in the order book.
                            let key = m.iter()
                                .find(|(_, uuid)| uuid.as_str() != daemon_id)
                                .map(|(k, _)| k.clone());
                            key.and_then(|k| m.remove(&k))
                        });
                    if let Some(local_id) = local_id {
                        if order_book().get_order(&local_id).await.is_some() {
                            let mut info = order_book().get_order(&local_id).await.unwrap();
                            order_book().remove_order(&local_id).await;
                            info.id = daemon_id.clone();
                            order_book().upsert_order(info).await;
                            if let Some(db) = crate::db::app_db::db() {
                                let _ = db.update_trade_order_id(&local_id, &daemon_id).await;
                            }
                            crate::api::logging::blog_info("gift-wrap", format!(
                                "NewOrder: late reconciliation local={local_id} → daemon={daemon_id}"
                            ));
                        }
                    } else {
                        crate::api::logging::blog_info("gift-wrap", format!(
                            "NewOrder: daemon order={daemon_id} confirmed (no local order to reconcile)"
                        ));
                    }
                }
            } else {
                log::warn!("[orders] gift-wrap NewOrder has no order id");
            }
        }
        Action::Canceled => {
            log::info!("[orders] gift-wrap Canceled for trade={trade_pubkey_hex}");
            if let Some(order_id) = &kind.id {
                let oid = order_id.to_string();
                order_book().remove_order(&oid).await;
                // Sync the Canceled status into the trade DB so My Trades
                // reflects the cancellation immediately.
                if let Some(db) = crate::db::app_db::db() {
                    if let Err(e) = db
                        .update_trade_fields(
                            &oid,
                            Some(crate::api::types::OrderStatus::Canceled),
                            None,
                            None,
                        )
                        .await
                    {
                        log::warn!("[orders] failed to sync Canceled status for {oid}: {e}");
                    }
                }
            }
        }
        // Seller receives BuyerTookOrder → peer is buyer_trade_pubkey.
        // Buyer receives HoldInvoicePaymentAccepted → peer is seller_trade_pubkey.
        // Both carry the counterpart pubkey in SmallOrder.{buyer,seller}_trade_pubkey.
        Action::BuyerTookOrder | Action::HoldInvoicePaymentAccepted => {
            let order_id = match &kind.id {
                Some(id) => id.to_string(),
                None => {
                    log::warn!("[orders] gift-wrap {:?} has no order id", kind.action);
                    return;
                }
            };
            let small_order = match &kind.payload {
                Some(mostro_core::message::Payload::Order(o)) => o.clone(),
                _ => {
                    log::warn!(
                        "[orders] gift-wrap {:?} payload is not an Order",
                        kind.action
                    );
                    return;
                }
            };
            // Determine which pubkey is the peer based on action:
            // - BuyerTookOrder  → we are the seller, peer is the buyer
            // - HoldInvoicePaymentAccepted → we are the buyer, peer is the seller
            // Determine the peer pubkey from the order payload.
            //   BuyerTookOrder          → we are the seller, peer is the buyer.
            //   HoldInvoicePaymentAccepted → we are the buyer, peer is the seller.
            // Both are the only arms that reach this branch (see outer match guard).
            let peer_pubkey_hex = match kind.action {
                Action::BuyerTookOrder => small_order.buyer_trade_pubkey.clone(),
                Action::HoldInvoicePaymentAccepted => small_order.seller_trade_pubkey.clone(),
                // Safety: unreachable — outer match only routes these two variants here.
                _ => unreachable!("unexpected action in peer-pubkey resolution"),
            };
            let peer_pubkey_hex = match peer_pubkey_hex {
                Some(pk) if !pk.is_empty() => pk,
                _ => {
                    log::warn!(
                        "[orders] gift-wrap {:?}: missing peer pubkey in payload",
                        kind.action
                    );
                    return;
                }
            };
            log::info!(
                "[orders] gift-wrap {:?}: order={order_id} peer={peer_pubkey_hex}",
                kind.action
            );
            // Derive the ECDH shared key and store in session so the chat API
            // can encrypt/decrypt P2P messages and subscribe to the right p-tag.
            on_peer_pubkey_received(&order_id, trade_pubkey_hex, &peer_pubkey_hex).await;

            // Sync the order status from the payload so the trade doesn't stay
            // stuck at Pending in the DB and in-memory order book.
            if let Some(new_status) = small_order.status.and_then(map_core_status) {
                log::info!(
                    "[orders] gift-wrap {:?}: syncing order={order_id} status={:?}",
                    kind.action,
                    new_status
                );
                order_book().update_order_status(&order_id, new_status.clone()).await;
                if let Some(db) = crate::db::app_db::db() {
                    if let Err(e) = db
                        .update_trade_fields(&order_id, Some(new_status), None, None)
                        .await
                    {
                        log::warn!(
                            "[orders] failed to sync status for order={order_id}: {e}"
                        );
                    }
                }
            }
        }
        // Mostro sends PayInvoice to the seller with the hold invoice bolt11
        // when a buyer takes a sell order (or a seller takes a buy order).
        Action::PayInvoice => {
            let order_id = match &kind.id {
                Some(id) => id.to_string(),
                None => {
                    log::warn!("[orders] gift-wrap PayInvoice has no order id");
                    return;
                }
            };
            let (bolt11, amount) = match &kind.payload {
                Some(mostro_core::message::Payload::PaymentRequest(small_order, pr, amt)) => {
                    let sats = amt.and_then(|a| {
                        u64::try_from(a).ok().or_else(|| {
                            log::warn!(
                                "[orders] gift-wrap PayInvoice: negative amount {a}, ignoring"
                            );
                            None
                        })
                    }).or_else(|| {
                        // Fallback: extract amount from the SmallOrder when the
                        // third PaymentRequest field is None.
                        small_order.as_ref().and_then(|so| {
                            let a = so.amount;
                            if a > 0 { Some(a as u64) } else { None }
                        })
                    });
                    (pr.clone(), sats)
                }
                _ => {
                    log::warn!(
                        "[orders] gift-wrap PayInvoice payload is not a PaymentRequest"
                    );
                    return;
                }
            };
            log::info!(
                "[orders] gift-wrap PayInvoice: order={order_id} invoice_len={} amount={:?}",
                bolt11.len(),
                amount
            );
            // Save the hold invoice and update status to WaitingPayment.
            order_book().update_order_status(&order_id, crate::api::types::OrderStatus::WaitingPayment).await;
            if let Some(db) = crate::db::app_db::db() {
                if let Err(e) = db
                    .update_trade_fields(
                        &order_id,
                        Some(crate::api::types::OrderStatus::WaitingPayment),
                        Some(bolt11),
                        amount,
                    )
                    .await
                {
                    log::warn!(
                        "[orders] failed to save hold invoice for order={order_id}: {e}"
                    );
                }
            }
        }
        // Handle remaining status-update actions from the daemon by syncing
        // the trade status in the DB so My Trades reflects the current state.
        Action::WaitingSellerToPay
        | Action::WaitingBuyerInvoice
        | Action::BuyerInvoiceAccepted
        | Action::FiatSentOk
        | Action::HoldInvoicePaymentSettled
        | Action::HoldInvoicePaymentCanceled
        | Action::Released
        | Action::PurchaseCompleted
        | Action::CooperativeCancelAccepted
        | Action::CooperativeCancelInitiatedByPeer
        | Action::CooperativeCancelInitiatedByYou
        | Action::DisputeInitiatedByYou
        | Action::DisputeInitiatedByPeer
        | Action::AdminSettled
        | Action::AdminCanceled
        // Rate/RateReceived/PaymentFailed do not change order status but are
        // handled explicitly so they don't fall through to the catch-all.
        | Action::Rate
        | Action::RateUser
        | Action::RateReceived
        | Action::PaymentFailed => {
            let order_id = match &kind.id {
                Some(id) => id.to_string(),
                None => {
                    log::debug!("[orders] gift-wrap {:?} has no order id", kind.action);
                    return;
                }
            };
            // Map action → OrderStatus for DB sync.
            let new_status = match kind.action {
                Action::WaitingSellerToPay => Some(crate::api::types::OrderStatus::WaitingPayment),
                Action::WaitingBuyerInvoice => {
                    Some(crate::api::types::OrderStatus::WaitingBuyerInvoice)
                }
                Action::BuyerInvoiceAccepted => {
                    Some(crate::api::types::OrderStatus::Active)
                }
                Action::FiatSentOk => {
                    Some(crate::api::types::OrderStatus::FiatSent)
                }
                Action::HoldInvoicePaymentSettled | Action::Released | Action::PurchaseCompleted => {
                    Some(crate::api::types::OrderStatus::SettledHoldInvoice)
                }
                Action::HoldInvoicePaymentCanceled => {
                    Some(crate::api::types::OrderStatus::Canceled)
                }
                Action::CooperativeCancelAccepted => {
                    Some(crate::api::types::OrderStatus::CooperativelyCanceled)
                }
                Action::CooperativeCancelInitiatedByPeer
                | Action::CooperativeCancelInitiatedByYou => None, // status doesn't change yet
                Action::Rate | Action::RateUser | Action::RateReceived => None,
                Action::PaymentFailed => None, // order stays at SettledHoldInvoice
                Action::DisputeInitiatedByYou | Action::DisputeInitiatedByPeer => {
                    Some(crate::api::types::OrderStatus::Dispute)
                }
                Action::AdminSettled => Some(crate::api::types::OrderStatus::SettledByAdmin),
                Action::AdminCanceled => Some(crate::api::types::OrderStatus::CanceledByAdmin),
                _ => None,
            };
            if let Some(status) = new_status {
                log::info!(
                    "[orders] gift-wrap {:?}: syncing order={order_id} status={:?}",
                    kind.action,
                    status
                );
                order_book().update_order_status(&order_id, status.clone()).await;
                if let Some(db) = crate::db::app_db::db() {
                    if let Err(e) = db
                        .update_trade_fields(&order_id, Some(status), None, None)
                        .await
                    {
                        log::warn!(
                            "[orders] failed to sync trade status for order={order_id}: {e}"
                        );
                    }
                }
            } else {
                log::debug!(
                    "[orders] gift-wrap {:?}: order={order_id} (no status change)",
                    kind.action
                );
            }
        }
        Action::CantDo => {
            let reason = match &kind.payload {
                Some(mostro_core::message::Payload::CantDo(Some(r))) => format!("{r:?}"),
                Some(mostro_core::message::Payload::CantDo(None)) => "unknown".to_string(),
                _ => "unknown".to_string(),
            };
            let message = match reason.as_str() {
                "OutOfRangeSatsAmount" => "Order rejected: sats amount is out of the allowed range.".to_string(),
                "OutOfRangeFiatAmount" => "Order rejected: fiat amount is out of the allowed range.".to_string(),
                "InvalidAmount" => "Order rejected: invalid amount.".to_string(),
                "InvalidInvoice" => "Order rejected: invalid Lightning invoice.".to_string(),
                "IsNotYourOrder" => "Order rejected: this order does not belong to you.".to_string(),
                "NotAllowedByStatus" => "Action rejected: not allowed in the current order status.".to_string(),
                "OrderAlreadyCanceled" => "Order is already canceled.".to_string(),
                other => format!("Order rejected by Mostro: {other}"),
            };

            // If create_order is waiting, notify it — the caller handles
            // cleanup and returns an error to Dart. Otherwise ignore stale events.
            let conf_tx = pending_confirmations()
                .lock()
                .ok()
                .and_then(|mut m| m.remove(trade_pubkey_hex));
            if let Some(tx) = conf_tx {
                crate::api::logging::blog_warn("gift-wrap", format!(
                    "CantDo: reason={reason} — notifying waiting create_order"
                ));
                let _ = tx.send(DaemonConfirmation::Rejected { reason, message });
            } else {
                crate::api::logging::blog_debug("gift-wrap", format!(
                    "CantDo: reason={reason} — no waiting caller, ignoring stale event"
                ));
            }
        }
        action => {
            log::debug!("[orders] gift-wrap unhandled action={action:?}");
        }
    }
}

/// Maps a `mostro_core::order::Status` to the local [`OrderStatus`] enum.
fn map_core_status(s: mostro_core::order::Status) -> Option<OrderStatus> {
    use mostro_core::order::Status as S;
    Some(match s {
        S::Pending => OrderStatus::Pending,
        S::WaitingBuyerInvoice => OrderStatus::WaitingBuyerInvoice,
        S::WaitingPayment => OrderStatus::WaitingPayment,
        S::Active => OrderStatus::Active,
        S::InProgress => OrderStatus::InProgress,
        S::FiatSent => OrderStatus::FiatSent,
        S::SettledHoldInvoice => OrderStatus::SettledHoldInvoice,
        S::Success => OrderStatus::Success,
        S::Canceled => OrderStatus::Canceled,
        S::CooperativelyCanceled => OrderStatus::CooperativelyCanceled,
        S::Expired => OrderStatus::Expired,
        S::CanceledByAdmin => OrderStatus::CanceledByAdmin,
        S::SettledByAdmin => OrderStatus::SettledByAdmin,
        S::CompletedByAdmin => OrderStatus::CompletedByAdmin,
        S::Dispute => OrderStatus::Dispute,
    })
}

// ── Peer-pubkey resolution ────────────────────────────────────────────────────

/// Called when the daemon sends `BuyerTookOrder` or `HoldInvoicePaymentAccepted`.
///
/// Derives the ECDH shared key from `(our_trade_key, peer_trade_pubkey)`,
/// stores it in the session, and spawns an incoming-chat subscription on the
/// shared-key pubkey so we receive peer messages from the moment the trade
/// goes active.
async fn on_peer_pubkey_received(order_id: &str, trade_pubkey_hex: &str, peer_pubkey_hex: &str) {
    // Resolve trade key index from order_id.
    let trade_index = match get_trade_key_index(order_id).await {
        Some(idx) => idx,
        None => {
            log::warn!("[orders] on_peer_pubkey_received: no trade key for order={order_id}");
            return;
        }
    };
    let trade_keys = match crate::api::identity::get_active_trade_keys(trade_index).await {
        Ok(k) => k,
        Err(e) => {
            log::error!("[orders] on_peer_pubkey_received: key load failed: {e}");
            return;
        }
    };
    let peer_pubkey = match nostr_sdk::PublicKey::from_hex(peer_pubkey_hex) {
        Ok(pk) => pk,
        Err(e) => {
            log::error!("[orders] on_peer_pubkey_received: invalid peer pubkey: {e}");
            return;
        }
    };
    // Derive the 32-byte ECDH shared secret.
    let shared_key_bytes =
        match crate::crypto::ecdh::derive_nip04_shared_key(&trade_keys, &peer_pubkey) {
            Ok(k) => k,
            Err(e) => {
                log::error!("[orders] on_peer_pubkey_received: ECDH failed: {e}");
                return;
            }
        };
    // Derive the shared-key *pubkey* (the p-tag subscribed by chat listeners).
    // The shared secret is used as a private scalar to derive the corresponding
    // public key — this is the convention used by v1 and the chat protocol spec.
    let shared_pubkey = match nostr_sdk::SecretKey::from_slice(&shared_key_bytes) {
        Ok(sk) => nostr_sdk::Keys::new(sk).public_key(),
        Err(e) => {
            log::error!("[orders] on_peer_pubkey_received: shared key→pubkey failed: {e}");
            return;
        }
    };
    log::info!(
        "[orders] on_peer_pubkey_received: order={order_id}          peer={peer_pubkey_hex} shared_pubkey={}",
        shared_pubkey.to_hex()
    );
    // Update or create the session with peer + shared key.
    let mgr = crate::mostro::session::session_manager();
    if let Some(mut session) = mgr.get_session(order_id).await {
        session.peer_pubkey = Some(peer_pubkey_hex.to_string());
        session.shared_key = Some(shared_key_bytes);
        if let Err(e) = mgr.update_session(order_id, session).await {
            log::warn!("[orders] on_peer_pubkey_received: session update failed: {e}");
        }
    } else {
        // Session may not exist if we received the event after a restart but
        // before create_session ran (rare race). Create it now best-effort.
        log::warn!(
            "[orders] on_peer_pubkey_received: session not found for order={order_id}, skipping session update — incoming subscription still spawned"
        );
    }
    // Spawn incoming-chat subscription on shared-key pubkey.
    let order_id_owned = order_id.to_string();
    let trade_pubkey_hex_owned = trade_pubkey_hex.to_string();
    tokio::spawn(async move {
        crate::api::messages::subscribe_incoming_chat(
            order_id_owned,
            trade_pubkey_hex_owned,
            shared_pubkey,
            trade_keys,
        )
        .await;
    });
}

// ── Single-order subscription ─────────────────────────────────────────────────

/// Subscribe to K38383 updates for a single order (by `d`-tag) so that status
/// changes after taking the order are reflected in the local order book.
///
/// Spawns a short-lived background task that watches for Kind 38383 events with
/// `d = order_id` and upserts them.  The task exits when the relay pool shuts
/// down or after a generous idle timeout (no updates for 30 minutes).
async fn subscribe_single_order(order_id: &str) {
    let order_id = order_id.to_string();
    tokio::spawn(async move {
        let Ok(pool) = crate::api::nostr::get_pool() else {
            log::warn!("[orders] subscribe_single_order: relay pool not initialized");
            return;
        };
        let client = pool.client();
        let mostro_pubkey =
            match nostr_sdk::PublicKey::from_hex(&crate::config::active_mostro_pubkey()) {
                Ok(pk) => pk,
                Err(e) => {
                    log::error!("[orders] subscribe_single_order: invalid pubkey: {e}");
                    return;
                }
            };

        let mut rx = client.notifications();
        let filter = crate::nostr::order_events::trade_order_filter(&mostro_pubkey, &order_id);
        if let Err(e) = client.subscribe(filter, None).await {
            log::warn!("[orders] subscribe_single_order subscribe failed: {e}");
            return;
        }
        log::info!("[orders] subscribed to d-tag updates for order={order_id}");

        use nostr_sdk::RelayPoolNotification;
        use tokio::time::{timeout, Duration};

        // Exit after 30 minutes of inactivity (no order updates received).
        // The timer resets on each relevant event so active trades stay subscribed.
        const IDLE_TIMEOUT_SECS: u64 = 30 * 60;
        let mut last_activity = tokio::time::Instant::now();

        loop {
            let remaining =
                Duration::from_secs(IDLE_TIMEOUT_SECS).saturating_sub(last_activity.elapsed());
            if remaining.is_zero() {
                log::debug!("[orders] subscribe_single_order idle timeout for order={order_id}");
                break;
            }

            match timeout(remaining, rx.recv()).await {
                Ok(Ok(RelayPoolNotification::Event { event, .. })) => {
                    if let Some(order) = crate::nostr::order_events::parse_order_event(&event, None)
                    {
                        if order.id == order_id {
                            log::info!(
                                "[orders] d-tag update: order={} status={:?}",
                                order_id,
                                order.status
                            );
                            last_activity = tokio::time::Instant::now();
                            // Sync trade status in DB so My Trades reflects it.
                            if let Some(db) = crate::db::app_db::db() {
                                if let Err(e) = db
                                    .update_trade_fields(
                                        &order.id,
                                        Some(order.status.clone()),
                                        None,
                                        order.amount_sats,
                                    )
                                    .await
                                {
                                    log::warn!(
                                        "[orders] failed to sync d-tag trade status for order={}: {e}",
                                        order.id
                                    );
                                }
                            }
                            order_book().upsert_order(order).await;
                        }
                    }
                }
                Ok(Ok(RelayPoolNotification::Shutdown)) => break,
                Ok(Err(_)) => break,
                Err(_) => break, // idle timeout
                Ok(Ok(_)) => continue,
            }
        }
    });
}

// ── Internal helpers ─────────────────────────────────────────────────────────

/// Parse and publish a serialised Nostr event JSON via the relay pool.
///
/// Returns an error if the pool is not initialised, the JSON is malformed,
/// or the relay client reports a publish error.
async fn publish_event_json(event_json: &str) -> Result<()> {
    let pool =
        crate::api::nostr::get_pool().map_err(|_| anyhow::anyhow!("RelayPoolNotInitialized"))?;
    let event: nostr_sdk::Event =
        serde_json::from_str(event_json).map_err(|e| anyhow::anyhow!("invalid event JSON: {e}"))?;
    pool.client()
        .send_event(&event)
        .await
        .map_err(|e| anyhow::anyhow!("publish failed: {e}"))?;
    Ok(())
}

// ── Kind 38383 subscription ───────────────────────────────────────────────────

/// Guards against spawning duplicate subscription loops.
static SUBSCRIPTION_ACTIVE: AtomicBool = AtomicBool::new(false);

/// Subscribe to Kind 38383 (pending public orders) and populate the order book.
///
/// Idempotent — only one subscription loop runs at a time. Call this whenever
/// the relay pool comes online; subsequent calls are no-ops until the previous
/// loop exits (pool shutdown or channel closed).
///
/// Internally spawns a background Tokio task that:
/// 1. Subscribes to `pending_orders_filter()` via the relay pool client.
/// 2. Loops over `RelayPoolNotification::Event` messages.
/// 3. Parses each Kind 38383 event via `parse_order_event` and upserts it
///    into the order book, which broadcasts the update to all `OrdersStream`
///    subscribers.
/// RAII guard that resets `SUBSCRIPTION_ACTIVE` to `false` when dropped,
/// ensuring the flag is cleared even if the subscription task panics.
struct ResetGuard;

impl Drop for ResetGuard {
    fn drop(&mut self) {
        SUBSCRIPTION_ACTIVE.store(false, Ordering::Release);
    }
}

pub async fn subscribe_orders() {
    // Only one loop at a time — subsequent Online transitions are no-ops.
    if SUBSCRIPTION_ACTIVE
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        log::debug!("[orders] subscribe_orders: already active, skipping");
        return;
    }
    log::info!("[orders] subscribe_orders: spawning subscription loop");

    tokio::spawn(async {
        let _guard = ResetGuard;
        _run_order_subscription().await;
    });
}

/// Force-restart the orders subscription.
///
/// Tears down the existing subscription (if any) by resetting the guard,
/// then spawns a fresh subscription loop. Used by the UI "Refresh" action
/// so users get a real re-subscribe instead of a silent no-op.
pub async fn restart_orders_subscription() {
    // Clear the guard so subscribe_orders can acquire it again.
    SUBSCRIPTION_ACTIVE.store(false, Ordering::Release);
    subscribe_orders().await;
}

/// Build a map of `trade_pubkey_hex → (Keys, trade_index)` for all derived
/// trade keys so the global subscription can decrypt any gift-wrap.
async fn build_trade_key_map() -> HashMap<String, (nostr_sdk::Keys, u32)> {
    let mut map = HashMap::new();
    let max_index = match crate::api::identity::get_identity().await {
        Ok(Some(info)) => info.trade_key_index,
        _ => return map,
    };
    for idx in 1..=max_index {
        match crate::api::identity::get_active_trade_keys(idx).await {
            Ok(keys) => {
                let hex = keys.public_key().to_hex();
                map.insert(hex, (keys, idx));
            }
            Err(e) => log::warn!("[orders] failed to derive trade key {idx}: {e}"),
        }
    }
    map
}

/// Handle a Kind 1059 event received on the global subscription.
///
/// Finds which trade key the event is addressed to (via `p` tag), decrypts
/// via `mostro_core::nip59::unwrap_message`, and dispatches the recovered
/// `Message` through `dispatch_mostro_message`.
async fn handle_global_gift_wrap(
    event: &nostr_sdk::Event,
    trade_key_map: &HashMap<String, (nostr_sdk::Keys, u32)>,
) {
    // Find the p-tag that matches one of our trade keys.
    let (recipient_hex, recipient_keys, trade_idx) = {
        let mut found = None;
        for tag in event.tags.iter() {
            let s = tag.as_slice();
            if s.first().map(|v| v.as_str()) == Some("p") {
                if let Some(pk_hex) = s.get(1).map(|v| v.as_str()) {
                    if let Some((keys, idx)) = trade_key_map.get(pk_hex) {
                        found = Some((pk_hex.to_string(), keys.clone(), *idx));
                        break;
                    }
                }
            }
        }
        match found {
            Some(f) => f,
            None => {
                // Not addressed to any of our known trade keys — skip silently.
                return;
            }
        }
    };

    let eid = event.id.to_hex();
    if is_duplicate_gift_wrap(&eid) {
        return;
    }
    crate::api::logging::blog_info("gift-wrap", format!(
        "Kind 1059 received (global) for trade={} from={} event_id={}",
        &recipient_hex[..8],
        &event.pubkey.to_hex()[..8],
        &eid[..16],
    ));

    match crate::nostr::gift_wrap::unwrap_mostro_message(&recipient_keys, event).await {
        Ok(Some(unwrapped)) => {
            dispatch_mostro_message(unwrapped, &recipient_hex, trade_idx).await;
        }
        Ok(None) => {
            // `Ok(None)` = NIP-44 outer decrypt failed. On the global path
            // this is expected whenever trade_key_map contains multiple
            // entries and the event is addressed to a different key; here
            // the p-tag already matched so it only happens on p-tag collisions.
        }
        Err(e) => crate::api::logging::blog_warn("gift-wrap", format!(
            "decrypt failed for trade={}: {e}", &recipient_hex[..8]
        )),
    }
}

async fn _run_order_subscription() {
    let Ok(pool) = crate::api::nostr::get_pool() else {
        log::error!("[orders] subscription failed: relay pool not initialized");
        return;
    };
    let client = pool.client();

    // The Mostro daemon is the author of all Kind 38383 events.
    // Use the compiled-in default pubkey (mirrors config.rs / settings screen).
    let mostro_pubkey = match nostr_sdk::PublicKey::from_hex(&crate::config::active_mostro_pubkey())
    {
        Ok(pk) => pk,
        Err(e) => {
            log::error!("[orders] invalid mostro pubkey: {e}");
            return;
        }
    };
    crate::api::logging::blog_info("orders", format!("subscribing to Kind 38383 from mostro={}", mostro_pubkey.to_hex()));

    // Build a map of all known trade keys so we can decrypt ANY Kind 1059
    // gift-wrap from Mostro, not just those from the current session.
    let trade_key_map = build_trade_key_map().await;
    let trade_pubkeys: Vec<nostr_sdk::PublicKey> = trade_key_map
        .keys()
        .filter_map(|hex| nostr_sdk::PublicKey::from_hex(hex).ok())
        .collect();
    crate::api::logging::blog_info("orders", format!("trade key map: {} keys derived for gift-wrap decryption", trade_pubkeys.len()));

    // Get notifications receiver before subscribing to avoid missing
    // events that arrive between the subscribe call and receiver creation.
    let mut rx = client.notifications();

    // Subscribe to ALL orders (no status restriction) so we receive status-change
    // events (e.g. pending → canceled) and can remove them from the order book.
    // Display-level filtering (show only pending) is handled in the Dart layer.
    let order_filter = crate::nostr::order_events::all_orders_filter(&mostro_pubkey);
    if let Err(e) = client.subscribe(order_filter, None).await {
        log::error!("[orders] subscribe failed: {e}");
        return;
    }

    // Subscribe to Kind 1059 (gift-wrap) for ALL known trade pubkeys so we
    // capture daemon responses even for trades started in previous sessions.
    if !trade_pubkeys.is_empty() {
        let gw_filter = nostr_sdk::Filter::new()
            .kind(nostr_sdk::Kind::from(1059u16))
            .pubkeys(trade_pubkeys);
        if let Err(e) = client.subscribe(gw_filter, None).await {
            crate::api::logging::blog_warn("orders", format!("gift-wrap bulk subscribe failed: {e}"));
        } else {
            crate::api::logging::blog_info("orders", format!("Kind 1059 bulk subscription active for {} trade keys", trade_key_map.len()));
        }
    }

    crate::api::logging::blog_info("orders", format!("subscriptions active — waiting for events"));

    use nostr_sdk::RelayPoolNotification;

    loop {
        match rx.recv().await {
            Ok(RelayPoolNotification::Event { event, .. }) => {
                // ── Kind 1059 gift-wrap: decrypt and dispatch ──
                if event.kind == nostr_sdk::Kind::from(1059u16) {
                    handle_global_gift_wrap(&event, &trade_key_map).await;
                    continue;
                }

                // ── Kind 38383 order book event ──
                log::debug!(
                    "[orders] event kind={} author={}",
                    event.kind,
                    &event.pubkey.to_hex()[..8]
                );
                match parse_order_event(&event, None) {
                    Some(mut info) => {
                        log::info!(
                            "[orders] parsed order id={} kind={:?} status={:?}",
                            info.id,
                            info.kind,
                            info.status
                        );
                        // Restore is_mine=true for maker orders on cold start by
                        // comparing against the content fingerprint stored at creation time.
                        if !info.is_mine {
                            let ck = order_content_key(
                                &info.kind,
                                &info.fiat_code,
                                info.fiat_amount,
                                info.fiat_amount_min,
                                info.fiat_amount_max,
                                &info.payment_method,
                            );
                            log::debug!("[orders] fingerprint check order={} ck={ck}", info.id);
                            if let Some(trade_idx) = get_trade_key_index(&ck).await {
                                info.is_mine = true;
                                // Bridge content fingerprint → daemon UUID so subsequent
                                // actions (cancel) can look up the trade key by real order ID.
                                store_trade_key_index(&info.id, trade_idx).await;
                                // Remove the temporary local-UUID entry that was
                                // added optimistically at create_order time so the
                                // order book only contains the daemon's real UUID.
                                if let Some(local_id) = take_pending_local_id(&ck) {
                                    order_book().remove_order(&local_id).await;
                                    // Update the DB trade record so it references the
                                    // daemon UUID — otherwise tradeStatusProvider polls
                                    // with the stale local UUID and never finds the order.
                                    if let Some(db) = crate::db::app_db::db() {
                                        if let Err(e) = db
                                            .update_trade_order_id(&local_id, &info.id)
                                            .await
                                        {
                                            log::warn!(
                                                "[orders] failed to update trade order_id \
                                                 {local_id} → {}: {e}",
                                                info.id
                                            );
                                        }
                                    }
                                    log::info!(
                                        "[orders] replaced local order={local_id} with daemon order={}",
                                        info.id
                                    );
                                } else {
                                    log::info!(
                                        "[orders] own order={} detected via content match trade_index={trade_idx}",
                                        info.id
                                    );
                                }
                            }
                        }
                        // Sync trade status in DB for own orders so My Trades
                        // reflects status changes even without gift-wrap delivery.
                        if info.is_mine && info.status != crate::api::types::OrderStatus::Pending {
                            if let Some(db) = crate::db::app_db::db() {
                                if let Err(e) = db
                                    .update_trade_fields(
                                        &info.id,
                                        Some(info.status.clone()),
                                        None,
                                        info.amount_sats,
                                    )
                                    .await
                                {
                                    log::warn!(
                                        "[orders] failed to sync trade status for order={}: {e}",
                                        info.id
                                    );
                                }
                            }
                        }
                        order_book().upsert_order(info).await;
                    }
                    None => {
                        log::warn!(
                            "[orders] event kind={} rejected by parser (tags: {:?})",
                            event.kind,
                            event
                                .tags
                                .iter()
                                .take(6)
                                .map(|t| t.as_slice().first().map(|s| s.as_str()).unwrap_or("?"))
                                .collect::<Vec<_>>()
                        );
                    }
                }
            }
            Ok(RelayPoolNotification::Shutdown) => {
                log::info!("[orders] relay pool shutdown — subscription loop exiting");
                break;
            }
            Err(broadcast::error::RecvError::Closed) => {
                log::warn!("[orders] notification channel closed");
                break;
            }
            Err(broadcast::error::RecvError::Lagged(n)) => {
                log::warn!("[orders] lagged by {n} messages");
                continue;
            }
            _ => {}
        }
    }
}

/// Stream that emits whenever the order list changes.
pub async fn on_orders_updated() -> Result<OrdersStream> {
    let rx = order_book().subscribe();
    Ok(OrdersStream { rx })
}

/// Wrapper for flutter_rust_bridge Dart Stream generation.
pub struct OrdersStream {
    rx: broadcast::Receiver<Vec<OrderInfo>>,
}

impl OrdersStream {
    pub async fn next(&mut self) -> Option<Vec<OrderInfo>> {
        loop {
            match self.rx.recv().await {
                Ok(orders) => return Some(orders),
                Err(broadcast::error::RecvError::Lagged(_)) => continue,
                Err(broadcast::error::RecvError::Closed) => return None,
            }
        }
    }
}

/// Called internally to process a raw Nostr event into the order cache.
/// Typically invoked from the relay pool's event processing loop.
pub(crate) async fn process_order_event(
    event: &nostr_sdk::Event,
    my_pubkey: Option<&nostr_sdk::PublicKey>,
) {
    if let Some(order) = parse_order_event(event, my_pubkey) {
        order_book().upsert_order(order).await;
    }
}

/// Return all trades persisted in the local DB, sorted newest-first.
///
/// Returns an empty vec when the DB has not been initialised yet (e.g. during
/// early startup, unit tests, or web builds before IndexedDB is wired).
pub async fn list_trades() -> Result<Vec<crate::api::types::TradeInfo>> {
    let Some(db) = crate::db::app_db::db() else {
        return Ok(vec![]);
    };
    let mut trades = db.list_trades().await?;
    trades.sort_by(|a, b| b.started_at.cmp(&a.started_at));
    Ok(trades)
}

/// Return the persisted [`TradeRole`] for the given `order_id`.
///
/// Returns `Some(role)` when a matching trade record exists in the DB,
/// `None` when the DB has no record for this order (e.g. it was never taken
/// in this installation, or `init_db` has not been called yet).
///
/// Used by the Flutter layer to restore the buyer/seller role after an app
/// restart so the trade-detail screen shows the correct actions.
pub async fn get_trade_role(order_id: String) -> Result<Option<crate::api::types::TradeRole>> {
    let Some(db) = crate::db::app_db::db() else {
        return Ok(None);
    };
    match db.get_trade_by_order_id(&order_id).await {
        Ok(Some(trade)) => Ok(Some(trade.role)),
        Ok(None) => Ok(None),
        Err(e) => {
            log::warn!("[orders] get_trade_role DB error for order={order_id}: {e}");
            Ok(None)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::TradeRole;
    use crate::mostro::session::session_manager;

    // ── Helper ────────────────────────────────────────────────────────────────

    fn dummy_order_info(id: &str) -> crate::api::types::OrderInfo {
        crate::api::types::OrderInfo {
            id: id.to_string(),
            kind: crate::api::types::OrderKind::Buy,
            status: crate::api::types::OrderStatus::Pending,
            fiat_code: "USD".to_string(),
            fiat_amount: Some(100.0),
            fiat_amount_min: None,
            fiat_amount_max: None,
            payment_method: "Bank".to_string(),
            premium: 0.0,
            is_mine: false,
            created_at: 0,
            expires_at: None,
            amount_sats: None,
            creator_pubkey: String::new(),
        }
    }

    // ── Session creation ──────────────────────────────────────────────────────

    /// Creating a session twice for the same order returns SessionAlreadyExists.
    #[tokio::test]
    async fn create_session_is_idempotent() {
        let order_id = uuid::Uuid::new_v4().to_string();
        let order = dummy_order_info(&order_id);

        let mgr = session_manager();
        let first = mgr
            .create_session(order_id.clone(), TradeRole::Buyer, 0, order.clone())
            .await;
        assert!(first.is_ok(), "first create_session must succeed");

        let second = mgr
            .create_session(order_id.clone(), TradeRole::Buyer, 0, order)
            .await;
        assert!(
            second.is_err(),
            "second create_session for same order must fail"
        );
        assert!(second
            .unwrap_err()
            .to_string()
            .contains("SessionAlreadyExists"));
    }

    /// After create_session the session has no peer pubkey or shared key yet.
    #[tokio::test]
    async fn new_session_has_no_peer_keys() {
        let order_id = uuid::Uuid::new_v4().to_string();
        let order = dummy_order_info(&order_id);

        let mgr = session_manager();
        let session = mgr
            .create_session(order_id.clone(), TradeRole::Seller, 1, order)
            .await
            .unwrap();

        assert!(session.peer_pubkey.is_none());
        assert!(session.shared_key.is_none());
    }

    // ── Peer-pubkey resolution ────────────────────────────────────────────────

    /// on_peer_pubkey_received with no session for the order is a graceful no-op.
    #[tokio::test]
    async fn peer_pubkey_with_no_session_does_not_panic() {
        // Use a random order_id that has no session — should log a warning only.
        on_peer_pubkey_received(
            &uuid::Uuid::new_v4().to_string(),
            "aabbccdd", // trade_pubkey_hex (irrelevant, no trade key stored)
            "aabbccdd", // peer_pubkey_hex (also irrelevant)
        )
        .await;
        // If we reach here without panicking the test passes.
    }
}
