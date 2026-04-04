/// Orders API — read path for the public order book.
///
/// Subscribes to Kind 38383 events from the relay pool, caches locally,
/// applies filters, and exposes a stream for UI updates.
use anyhow::Result;
use std::collections::HashMap;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
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
        log::warn!(
            "[orders] resolve_maker_order: no pending entry for pubkey={trade_pubkey_hex}"
        );
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
    fn default() -> Self { Self::new() }
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
        result.sort_by(|a, b| {
            match (a.expires_at, b.expires_at) {
                (Some(ea), Some(eb)) => ea.cmp(&eb),
                (Some(_), None) => std::cmp::Ordering::Less,
                (None, Some(_)) => std::cmp::Ordering::Greater,
                (None, None) => b.created_at.cmp(&a.created_at),
            }
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

    let order = OrderInfo {
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

    // Subscribe to gift-wrap (Kind 1059) responses from the daemon addressed to
    // this trade key. This gives us the daemon-assigned order UUID faster and
    // more reliably than waiting for the Kind 38383 content-fingerprint match.
    subscribe_gift_wraps(sender_keys.public_key(), trade_index).await;

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
    store_trade_key_index(&ck, trade_index).await;       // content fingerprint
    store_pending_maker_key(&sender_keys.public_key().to_hex(), trade_index);
    store_pending_local_id(&ck, &order.id);
    order_book().upsert_order(order.clone()).await;

    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;
    let event_json =
        actions::new_order(&sender_keys, &mostro_pubkey, &params_for_dispatch, trade_index)
            .await?;
    publish_event_json(&event_json).await?;

    log::info!(
        "[orders] create_order dispatched id={} trade_index={trade_index} ck={ck}",
        order.id
    );

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
                    let ln_address: Option<String> =
                        crate::api::settings::get_settings()
                            .await
                            .ok()
                            .and_then(|s| s.default_lightning_address);
                    let ln_address_ref = ln_address.as_deref();

                    let action_result = match dispatch_role {
                        TradeRole::Buyer => {
                            actions::take_sell(
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
                                    if ln_address_ref.is_some() { "present" } else { "none" }
                                );
                                // Subscribe to d-tag K38383 updates for this specific order so we
                                // receive status changes (pending → in-progress → waiting-payment …).
                                subscribe_single_order(&order_id).await;
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

    let trade_index = get_trade_key_index(&order_id).await
        .ok_or_else(|| anyhow::anyhow!("no persisted trade key for order {order_id}"))?;
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;
    let event_json = actions::add_invoice(
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
    let trade_index = get_trade_key_index(&order_id).await
        .ok_or_else(|| anyhow::anyhow!("no persisted trade key for order {order_id}"))?;
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;
    let event_json = actions::fiat_sent(&sender_keys, &mostro_pubkey, &order_id, trade_index).await?;
    publish_event_json(&event_json).await?;
    log::info!("[orders] fiat_sent published for order={order_id} trade_index={trade_index}");
    Ok(())
}

/// Seller confirms fiat received and releases escrowed sats.
///
/// Sends a `Release` MostroMessage to the Mostro daemon signed with the trade
/// key that was used when taking the order.
pub async fn release_order(order_id: String) -> Result<()> {
    let trade_index = get_trade_key_index(&order_id).await
        .ok_or_else(|| anyhow::anyhow!("no persisted trade key for order {order_id}"))?;
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;
    let event_json = actions::release(&sender_keys, &mostro_pubkey, &order_id, trade_index).await?;
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
    let trade_index = get_trade_key_index(&order_id).await
        .ok_or_else(|| anyhow::anyhow!("no persisted trade key for order {order_id}"))?;
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;
    let event_json = actions::cancel(&sender_keys, &mostro_pubkey, &order_id, trade_index).await?;
    publish_event_json(&event_json).await?;
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
pub(crate) async fn subscribe_gift_wraps(
    trade_pubkey: nostr_sdk::PublicKey,
    trade_index: u32,
) {
    tokio::spawn(async move {
        // Fetch keys first — if this fails there is no point subscribing and
        // we avoid leaving an orphan relay subscription with no decryption path.
        let recipient_keys =
            match crate::api::identity::get_active_trade_keys(trade_index).await {
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
        log::info!("[orders] gift-wrap subscription active for trade_pubkey={trade_pubkey_hex}");

        use nostr_sdk::RelayPoolNotification;
        use tokio::time::{timeout, Duration};

        const IDLE_TIMEOUT_SECS: u64 = 30 * 60;
        let mut last_activity = tokio::time::Instant::now();

        loop {
            let remaining = Duration::from_secs(IDLE_TIMEOUT_SECS)
                .saturating_sub(last_activity.elapsed());
            if remaining.is_zero() {
                log::debug!(
                    "[orders] gift-wrap idle timeout for trade={trade_pubkey_hex}"
                );
                break;
            }

            match timeout(remaining, rx.recv()).await {
                Ok(Ok(RelayPoolNotification::Event { event, .. })) => {
                    if event.kind != nostr_sdk::Kind::from(1059u16) {
                        continue;
                    }
                    // Only process events addressed to our trade pubkey.
                    let is_for_us = event.tags.iter().any(|t| {
                        let s = t.as_slice();
                        s.first().map(|v| v.as_str()) == Some("p")
                            && s.get(1).map(|v| v.as_str()) == Some(trade_pubkey_hex.as_str())
                    });
                    if !is_for_us {
                        continue;
                    }

                    let event_json = match serde_json::to_string(&*event) {
                        Ok(j) => j,
                        Err(e) => {
                            log::warn!("[orders] gift-wrap event serialize failed: {e}");
                            continue;
                        }
                    };
                    match crate::nostr::gift_wrap::unwrap(&recipient_keys, &event_json).await {
                        Ok(rumor_json) => {
                            process_gift_wrap_rumor(&rumor_json, &trade_pubkey_hex).await;
                            last_activity = tokio::time::Instant::now();
                        }
                        Err(e) => log::warn!("[orders] gift-wrap decrypt failed: {e}"),
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

        log::debug!(
            "[orders] gift-wrap subscription exiting for trade={trade_pubkey_hex}"
        );
    });
}

/// Parse the inner rumor JSON from a decrypted gift-wrap and dispatch by action.
async fn process_gift_wrap_rumor(rumor_json: &str, trade_pubkey_hex: &str) {
    use mostro_core::message::{Action, Message};

    // The rumor is a serialised UnsignedEvent; extract its content string.
    let content = match serde_json::from_str::<serde_json::Value>(rumor_json) {
        Ok(v) => match v.get("content").and_then(|c| c.as_str()) {
            Some(s) => s.to_string(),
            None => {
                log::warn!("[orders] gift-wrap rumor has no content field");
                return;
            }
        },
        Err(e) => {
            log::warn!("[orders] gift-wrap rumor JSON parse failed: {e}");
            return;
        }
    };

    // Mostro wire format: [message, null_or_peer]
    let (msg, _peer): (Message, Option<mostro_core::message::Peer>) =
        match serde_json::from_str(&content) {
            Ok(p) => p,
            Err(e) => {
                log::warn!("[orders] gift-wrap content deserialize failed: {e}");
                return;
            }
        };

    let kind = msg.get_inner_message_kind();

    log::info!(
        "[orders] gift-wrap action={:?} order_id={:?} trade_pubkey={}",
        kind.action,
        kind.id,
        trade_pubkey_hex
    );

    match &kind.action {
        Action::NewOrder => {
            if let Some(order_id) = &kind.id {
                let order_id_str = order_id.to_string();
                resolve_maker_order(&order_id_str, trade_pubkey_hex).await;
                log::info!(
                    "[orders] gift-wrap NewOrder: daemon order={order_id_str} confirmed"
                );
            } else {
                log::warn!("[orders] gift-wrap NewOrder has no order id");
            }
        }
        Action::Canceled => {
            log::info!("[orders] gift-wrap Canceled for trade={trade_pubkey_hex}");
            if let Some(order_id) = &kind.id {
                order_book().remove_order(&order_id.to_string()).await;
            }
        }
        action => {
            log::debug!(
                "[orders] gift-wrap unhandled action={action:?} (Phase 7+)"
            );
        }
    }
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
        let filter =
            crate::nostr::order_events::trade_order_filter(&mostro_pubkey, &order_id);
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
            let remaining = Duration::from_secs(IDLE_TIMEOUT_SECS)
                .saturating_sub(last_activity.elapsed());
            if remaining.is_zero() {
                log::debug!("[orders] subscribe_single_order idle timeout for order={order_id}");
                break;
            }

            match timeout(remaining, rx.recv()).await {
                Ok(Ok(RelayPoolNotification::Event { event, .. })) => {
                    if let Some(order) = crate::nostr::order_events::parse_order_event(&event, None) {
                        if order.id == order_id {
                            log::info!(
                                "[orders] d-tag update: order={} status={:?}",
                                order_id,
                                order.status
                            );
                            last_activity = tokio::time::Instant::now();
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
    let pool = crate::api::nostr::get_pool()
        .map_err(|_| anyhow::anyhow!("RelayPoolNotInitialized"))?;
    let event: nostr_sdk::Event = serde_json::from_str(event_json)
        .map_err(|e| anyhow::anyhow!("invalid event JSON: {e}"))?;
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

async fn _run_order_subscription() {
    let Ok(pool) = crate::api::nostr::get_pool() else {
        log::error!("[orders] subscription failed: relay pool not initialized");
        return;
    };
    let client = pool.client();

    // The Mostro daemon is the author of all Kind 38383 events.
    // Use the compiled-in default pubkey (mirrors config.rs / settings screen).
    let mostro_pubkey = match nostr_sdk::PublicKey::from_hex(&crate::config::active_mostro_pubkey()) {
        Ok(pk) => pk,
        Err(e) => {
            log::error!("[orders] invalid mostro pubkey: {e}");
            return;
        }
    };
    log::info!("[orders] subscribing to Kind 38383 from mostro={}", mostro_pubkey.to_hex());

    // Get notifications receiver before subscribing to avoid missing
    // events that arrive between the subscribe call and receiver creation.
    let mut rx = client.notifications();

    // Subscribe to ALL orders (no status restriction) so we receive status-change
    // events (e.g. pending → canceled) and can remove them from the order book.
    // Display-level filtering (show only pending) is handled in the Dart layer.
    let filter = crate::nostr::order_events::all_orders_filter(&mostro_pubkey);
    if let Err(e) = client.subscribe(filter, None).await {
        log::error!("[orders] subscribe failed: {e}");
        return;
    }
    log::info!("[orders] Kind 38383 subscription active — waiting for events");

    use nostr_sdk::RelayPoolNotification;

    loop {
        match rx.recv().await {
            Ok(RelayPoolNotification::Event { event, .. }) => {
                log::info!("[orders] event kind={} author={}", event.kind, &event.pubkey.to_hex()[..8]);
                match parse_order_event(&event, None) {
                    Some(mut info) => {
                        log::info!("[orders] parsed order id={} kind={:?} status={:?}", info.id, info.kind, info.status);
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
                        order_book().upsert_order(info).await;
                    }
                    None => {
                        log::warn!("[orders] event kind={} rejected by parser (tags: {:?})",
                            event.kind,
                            event.tags.iter().take(6).map(|t| t.as_slice().first().map(|s| s.as_str()).unwrap_or("?")).collect::<Vec<_>>()
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
pub(crate) async fn process_order_event(event: &nostr_sdk::Event, my_pubkey: Option<&nostr_sdk::PublicKey>) {
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
pub async fn get_trade_role(
    order_id: String,
) -> Result<Option<crate::api::types::TradeRole>> {
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
