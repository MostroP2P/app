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

// ── Pending daemon-request bookkeeping ───────────────────────────────────────

/// Result sent by the gift-wrap handler to the waiting request caller.
enum DaemonReply {
    /// Daemon accepted the order and assigned a UUID (create flow).
    Confirmed { daemon_id: String },
    /// Daemon accepted the take (take flow). Unlike a create, the take's
    /// first reply varies by role and daemon config (add-invoice,
    /// pay-invoice, a direct progression message, …), so the reply carries
    /// whatever the caller needs to build the trade from real daemon data
    /// instead of optimistic assumptions.
    TakeAccepted {
        action: mostro_core::message::Action,
        /// Order status from the reply payload, when present.
        status: Option<crate::api::types::OrderStatus>,
        /// Sat amount the daemon calculated for the trade, when present.
        amount_sats: Option<u64>,
        /// Hold invoice bolt11 (seller taking a buy order), when present.
        hold_invoice: Option<String>,
    },
    /// Daemon acknowledged an add-invoice. The reply doubles as a status
    /// update processed by the per-action arms; the caller only needs the
    /// unblock, so no data travels with it.
    Acknowledged,
    /// Daemon rejected the request with a CantDo reason.
    Rejected { reason: String, message: String },
}

/// What kind of outgoing request a pending record tracks.
enum PendingRequestKind {
    Create {
        /// Locally-generated UUID the order was created under before the
        /// daemon assigned the real one. Bridged to the daemon UUID on
        /// confirmation.
        local_uuid: String,
        /// Content fingerprint (see `order_content_key`) — lets the Kind
        /// 38383 subscription find this record when the daemon's public
        /// event arrives (that event carries neither our trade pubkey nor a
        /// request_id).
        content_key: String,
    },
    /// A take-buy / take-sell awaiting the daemon's first reply.
    Take,
    /// A buyer's add-invoice awaiting the daemon's acknowledgement.
    AddInvoice,
}

/// Everything one outgoing daemon request needs tracked until its reply is
/// consumed.
///
/// `request_id` is the correlation nonce sent in the outgoing message; the
/// daemon echoes it in both the success reply and any `CantDo` rejection.
/// Only a reply carrying the matching nonce may resolve or consume this
/// record — stale events replayed by relays carry a different (or no)
/// `request_id` and must leave every part of it in place for the genuine
/// reply. Keeping the waiter channel, the trade index, and the kind-specific
/// bridging state in one record keyed by the attempt's fresh trade key means
/// an uncorrelated event cannot consume state belonging to a live (or
/// concurrent) request.
struct PendingRequest {
    request_id: u64,
    trade_index: u32,
    kind: PendingRequestKind,
    /// `Some` while the caller is blocked waiting. The 10s timeout detaches
    /// only this sender and leaves the rest of the record, so a genuine late
    /// reply still reconciles trade-key and id bindings instead of being
    /// indistinguishable from a stale replay.
    tx: Option<tokio::sync::oneshot::Sender<DaemonReply>>,
}

/// Maps `trade_pubkey_hex` → the pending daemon request for that trade key.
///
/// Each request derives a fresh trade key, so one entry per key suffices;
/// sequential requests on the same key (e.g. a take followed by add-invoice)
/// work because the previous record is consumed by its reply. For creates:
/// the daemon assigns its own UUID to a new order and publishes it as a Kind
/// 38383 event signed by the daemon (not the maker), so the real order ID is
/// only learnable from the gift-wrapped acknowledgement; the record carries
/// the correlation state needed to consume that acknowledgement safely.
static PENDING_REQUESTS: OnceLock<std::sync::Mutex<HashMap<String, PendingRequest>>> = OnceLock::new();

fn pending_requests() -> &'static std::sync::Mutex<HashMap<String, PendingRequest>> {
    PENDING_REQUESTS.get_or_init(|| std::sync::Mutex::new(HashMap::new()))
}

/// True when a daemon reply carrying `got` may resolve a waiter that expects
/// `expected`. Replies must echo the exact nonce — `None` (stale replays,
/// unsolicited events) never matches.
fn request_id_matches(expected: u64, got: Option<u64>) -> bool {
    got == Some(expected)
}

/// Remove and return the pending request for `trade_pubkey_hex` **only** when
/// `got` echoes its `request_id`. A mismatched or absent id leaves the record
/// in place: relays can replay historical events, and a stale reply must not
/// confirm, reject, or reconcile a live request — the genuine reply (carrying
/// the nonce) arrives later and finds the record.
fn take_matching_request(trade_pubkey_hex: &str, got: Option<u64>) -> Option<PendingRequest> {
    let mut map = pending_requests().lock().ok()?;
    match map.get(trade_pubkey_hex) {
        Some(p) if request_id_matches(p.request_id, got) => map.remove(trade_pubkey_hex),
        Some(_) => {
            crate::api::logging::blog_debug("gift-wrap", format!(
                "request_id {got:?} does not match pending request for trade={} — \
                 leaving record for the genuine reply",
                &trade_pubkey_hex[..8]
            ));
            None
        }
        None => None,
    }
}

/// Remove and return the pending create whose content fingerprint equals
/// `content_key` — used by the Kind 38383 subscription to bridge the local
/// UUID once the daemon's public event arrives. Records with a live waiter
/// (`tx` is `Some`) are left alone: the in-flight `create_order` call owns
/// the reconciliation and must still find its record when the kind-14
/// acknowledgement lands.
fn take_pending_create_by_content_key(content_key: &str) -> Option<PendingRequest> {
    let mut map = pending_requests().lock().ok()?;
    let key = map
        .iter()
        .find(|(_, p)| {
            p.tx.is_none()
                && matches!(
                    &p.kind,
                    PendingRequestKind::Create { content_key: ck, .. } if ck == content_key
                )
        })
        .map(|(k, _)| k.clone())?;
    map.remove(&key)
}

/// Detach the waiter channel from the pending request for `trade_pubkey_hex`,
/// leaving the record itself in place — but only when `request_id` still
/// identifies this caller's own attempt. Called on the 10s timeout: the
/// caller stops waiting, but the record must survive so a genuine late reply
/// still reconciles (and a stale replay still cannot).
///
/// The nonce gate matters for same-key overlaps: `send_invoice` reuses the
/// take's trade key, so a newer attempt may have overwritten this record —
/// a timed-out older attempt must not detach the newer attempt's live waiter.
fn detach_request_waiter(trade_pubkey_hex: &str, request_id: u64) {
    if let Ok(mut m) = pending_requests().lock() {
        if let Some(p) = m.get_mut(trade_pubkey_hex) {
            if p.request_id == request_id {
                p.tx = None;
            }
        }
    }
}

/// Drop the pending request for `trade_pubkey_hex` — but only when
/// `request_id` still identifies this caller's own attempt (publish failure
/// rollback). Same same-key overlap rationale as [`detach_request_waiter`].
fn remove_pending_request(trade_pubkey_hex: &str, request_id: u64) {
    if let Ok(mut m) = pending_requests().lock() {
        if m.get(trade_pubkey_hex).is_some_and(|p| p.request_id == request_id) {
            m.remove(trade_pubkey_hex);
        }
    }
}

/// Drop whatever pending request remains for `trade_pubkey_hex`,
/// unconditionally. Only for the end of the per-trade subscription's
/// lifetime, when no reply can be delivered to any attempt on this key.
fn purge_pending_request(trade_pubkey_hex: &str) {
    if let Ok(mut m) = pending_requests().lock() {
        m.remove(trade_pubkey_hex);
    }
}

/// Local UUID of the pending create for `trade_pubkey_hex`, if any — a
/// read-only peek used to decide whether a stored order id is ours to rebind.
fn pending_local_uuid_for(trade_pubkey_hex: &str) -> Option<String> {
    pending_requests()
        .lock()
        .ok()?
        .get(trade_pubkey_hex)
        .and_then(|p| match &p.kind {
            PendingRequestKind::Create { local_uuid, .. } => Some(local_uuid.clone()),
            _ => None,
        })
}

/// Remove and return the pending request for `trade_pubkey_hex` only when it
/// is a `Take` and `got` echoes its nonce. Creates are left in place for the
/// `NewOrder` arm — a create's only success reply is `NewOrder`, while a
/// take's first reply varies, so takes are resolved before the per-action
/// arms (see `dispatch_mostro_message`).
fn take_matching_take(trade_pubkey_hex: &str, got: Option<u64>) -> Option<PendingRequest> {
    let mut map = pending_requests().lock().ok()?;
    match map.get(trade_pubkey_hex) {
        Some(p)
            if request_id_matches(p.request_id, got)
                && matches!(p.kind, PendingRequestKind::Take) =>
        {
            map.remove(trade_pubkey_hex)
        }
        _ => None,
    }
}

/// Remove and return the pending request for `trade_pubkey_hex` only when it
/// is an `AddInvoice` and `got` echoes its nonce. Unlike takes, the consumed
/// message still flows through the per-action arms — an add-invoice reply is
/// also a status update (see `dispatch_mostro_message`).
fn take_matching_add_invoice(trade_pubkey_hex: &str, got: Option<u64>) -> Option<PendingRequest> {
    let mut map = pending_requests().lock().ok()?;
    match map.get(trade_pubkey_hex) {
        Some(p)
            if request_id_matches(p.request_id, got)
                && matches!(p.kind, PendingRequestKind::AddInvoice) =>
        {
            map.remove(trade_pubkey_hex)
        }
        _ => None,
    }
}

/// Classify the daemon's first reply to a take into a [`DaemonReply`].
///
/// A take's success reply varies by role, order shape and daemon config —
/// `add-invoice` (buyer, with the calculated sats in an `Order` payload),
/// `pay-invoice` (seller, hold invoice in a `PaymentRequest` payload),
/// `pay-bond-invoice` (bond-requiring node, anti-abuse bond hold invoice in a
/// `PaymentRequest` payload), or a direct progression message when an invoice
/// was pre-attached — so classification goes by payload shape rather than by
/// enumerating actions (the pattern MostriX uses). `pay-bond-invoice` shares
/// the `PaymentRequest` shape with `pay-invoice`, so its bond bolt11 rides in
/// the same `hold_invoice` slot; Dart discriminates the bond by the
/// `WaitingTakerBond` status (set via `status_for_action`) and routes the
/// taker to the bond payment screen.
fn classify_take_reply(
    action: &mostro_core::message::Action,
    payload: &Option<mostro_core::message::Payload>,
) -> DaemonReply {
    use mostro_core::message::Payload;

    match payload {
        Some(Payload::PaymentRequest(small_order, invoice, amount)) => {
            let amount_sats = amount
                .and_then(|a| u64::try_from(a).ok())
                .or_else(|| {
                    small_order.as_ref().and_then(|so| {
                        if so.amount > 0 { Some(so.amount as u64) } else { None }
                    })
                });
            DaemonReply::TakeAccepted {
                action: action.clone(),
                status: small_order
                    .as_ref()
                    .and_then(|so| so.status.and_then(map_core_status))
                    .or_else(|| status_for_action(action)),
                amount_sats,
                hold_invoice: Some(invoice.clone()),
            }
        }
        Some(Payload::Order(small_order)) => DaemonReply::TakeAccepted {
            action: action.clone(),
            status: small_order
                .status
                .and_then(map_core_status)
                .or_else(|| status_for_action(action)),
            amount_sats: if small_order.amount > 0 {
                Some(small_order.amount as u64)
            } else {
                None
            },
            hold_invoice: None,
        },
        // Action-only progression reply (payload absent or of another shape):
        // still a genuine acceptance. The take interception consumes the
        // message before the status-sync arms run, so derive the implied
        // status from the action itself — otherwise the trade would persist
        // as Pending even though the daemon already advanced it (e.g.
        // waiting-seller-to-pay after a take-sell with an LN address).
        _ => DaemonReply::TakeAccepted {
            action: action.clone(),
            status: status_for_action(action),
            amount_sats: None,
            hold_invoice: None,
        },
    }
}

/// True when the order id stored for a trade may be rebound to `incoming_id`.
///
/// Only the locally-generated UUID of this trade key's own pending create is
/// ever ours to rebind (local → daemon). A stored id that is not that UUID is
/// either already the daemon's (nothing to do) or belongs to an earlier life
/// of a reused trade key — rebinding it to whatever id an incoming event
/// carries would let a stale replay corrupt a confirmed order.
fn may_reconcile_stored_id(
    stored_id: &str,
    incoming_id: &str,
    pending_local_uuid: Option<&str>,
) -> bool {
    stored_id != incoming_id && pending_local_uuid == Some(stored_id)
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

    /// Empty the cached order list and notify listeners with an empty book.
    ///
    /// Used on a node switch so orders belonging to the previously-active node
    /// disappear from the UI immediately, before the new node's orders arrive.
    pub async fn clear(&self) {
        self.orders.write().await.clear();
        let _ = self.tx.send(Vec::new());
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
    // Sized for the global feed's history replay on reused keys: a mass
    // replay longer than this window would evict ids that a slower relay
    // may still redeliver within the same session.
    const MAX_ENTRIES: usize = 512;
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

    // Register the trade-key mappings before publishing the event.
    // The daemon can respond with a Kind 38383 event within milliseconds; if
    // we stored these after publish the subscription loop could arrive before
    // the keys are written and miss the fingerprint match entirely.
    store_trade_key_index(&order.id, trade_index).await; // local UUID fallback
    store_trade_key_index(&ck, trade_index).await; // content fingerprint
    let trade_pk_hex = sender_keys.public_key().to_hex();

    // DO NOT add to order book or DB yet — wait for daemon confirmation first.
    // This avoids a phantom "pending" order when the daemon rejects (CantDo).

    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;
    let identity_keys =
        crate::api::identity::get_transport_identity_keys(&sender_keys).await?;

    // Correlation nonce for this create attempt. The daemon echoes it in its
    // reply (NewOrder or CantDo); only a reply carrying it may resolve the
    // confirmation below.
    let request_id: u64 = {
        use rand::RngCore;
        rand::rngs::OsRng.next_u64().max(1) // 0 is indistinguishable from "unset"
    };

    let event_json = actions::new_order(
        &identity_keys,
        &sender_keys,
        &mostro_pubkey,
        &params_for_dispatch,
        trade_index,
        request_id,
    )
    .await?;

    // Register the pending-create record AFTER building the event but BEFORE
    // publishing, so it is in the map before any response can arrive. The
    // record carries everything the dispatcher needs to consume the daemon's
    // reply: the waiter channel, and the correlation/bridging state that must
    // only ever be touched by a reply echoing this attempt's request_id.
    let (conf_tx, conf_rx) = tokio::sync::oneshot::channel::<DaemonReply>();
    if let Ok(mut map) = pending_requests().lock() {
        map.insert(
            trade_pk_hex.clone(),
            PendingRequest {
                request_id,
                trade_index,
                kind: PendingRequestKind::Create {
                    local_uuid: order.id.clone(),
                    content_key: ck.clone(),
                },
                tx: Some(conf_tx),
            },
        );
    }

    // Subscribe to gift-wrap responses AFTER registering the confirmation
    // channel so that any events (including stale ones replayed by relays)
    // find the entry and notify us instead of being silently discarded.
    subscribe_gift_wraps(sender_keys.public_key(), trade_index).await;

    if let Err(e) = publish_event_json(&event_json).await {
        // Rollback all in-memory bookkeeping on publish failure.
        if let Ok(mut m) = trade_key_map().write() { m.remove(&order.id); m.remove(&ck); }
        remove_pending_request(&trade_pk_hex, request_id);
        return Err(e);
    }

    crate::api::logging::blog_info("orders", format!(
        "create_order published id={} trade_index={trade_index} — waiting for daemon",
        order.id
    ));

    // Wait for daemon confirmation. The daemon typically responds within 1s.
    // The 10s timeout is a safety net for network issues; on timeout the order
    // is treated as not created (see below) rather than shown optimistically.
    let confirmation = crate::rt::time::timeout(
        std::time::Duration::from_secs(10),
        conf_rx,
    ).await;

    // On success or rejection the dispatcher already consumed the record
    // (take_matching_request). On timeout, detach only the waiter channel and
    // leave the record in place: a genuine late reply must still be able to
    // reconcile the trade-key and id bindings, and only the echoed nonce can
    // consume what remains — a stale replay still cannot. The record's
    // lifetime is bounded by the per-trade subscription (see
    // subscribe_gift_wraps), which removes it when the subscription ends.
    if !matches!(confirmation, Ok(Ok(_))) {
        detach_request_waiter(&trade_pk_hex, request_id);
    }

    // Resolve the daemon's verdict. The order only exists once the daemon
    // confirms it; a timeout means "no response", not an optimistic success.
    let daemon_id = match confirmation {
        Ok(Ok(DaemonReply::Confirmed { daemon_id })) => {
            crate::api::logging::blog_info("orders", format!(
                "create_order confirmed by daemon: {daemon_id}"
            ));
            daemon_id
        }
        Ok(Ok(DaemonReply::Rejected { reason, message })) => {
            crate::api::logging::blog_warn("orders", format!(
                "create_order rejected: {reason} — {message}"
            ));
            return Err(anyhow::anyhow!("{message}"));
        }
        _ => {
            // No daemon response within the timeout. Do not persist or show the
            // order — it was never published. Surface a stable marker the UI
            // maps to a localized "no response from Mostro" message.
            crate::api::logging::blog_warn("orders", format!(
                "create_order: no daemon response within 10s for id={}", order.id
            ));
            return Err(anyhow::anyhow!("NoDaemonResponse"));
        }
    };

    // Confirmed: adopt the daemon UUID. The order is not inserted into
    // `order_book()` — that public store is fed only by the daemon's Kind 38383
    // events. The maker sees it via My Trades (TradeInfo below) until it arrives.
    order.id = daemon_id;

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

    // Derive a fresh trade key so each take uses a unique Nostr identity.
    let trade_key_info = crate::api::identity::derive_trade_key().await?;
    let trade_index = trade_key_info.index;

    // Key/node/event failures now surface as errors: nothing has been
    // published yet, so pretending the take went through (the old behavior)
    // would show the user a trade that never existed.
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;
    let identity_keys =
        crate::api::identity::get_transport_identity_keys(&sender_keys).await?;

    // Read default LN address from settings (take-sell-ln-address flow).
    let ln_address: Option<String> = crate::api::settings::get_settings()
        .await
        .ok()
        .and_then(|s| s.default_lightning_address);

    // Correlation nonce for this take attempt. The daemon echoes it in its
    // reply (add-invoice / pay-invoice / pay-bond-invoice / CantDo); only a
    // reply carrying it may resolve the confirmation below.
    let request_id: u64 = {
        use rand::RngCore;
        rand::rngs::OsRng.next_u64().max(1) // 0 is indistinguishable from "unset"
    };

    let event_json = match role {
        TradeRole::Buyer => {
            actions::take_sell(
                &identity_keys,
                &sender_keys,
                &mostro_pubkey,
                &order_id,
                trade_index,
                fiat_amount,
                ln_address.as_deref(),
                request_id,
            )
            .await?
        }
        TradeRole::Seller => {
            actions::take_buy(
                &identity_keys,
                &sender_keys,
                &mostro_pubkey,
                &order_id,
                trade_index,
                fiat_amount,
                request_id,
            )
            .await?
        }
    };

    // Register the pending record BEFORE subscribing/publishing (same
    // ordering as create_order) so the reply cannot race the bookkeeping.
    let trade_pk_hex = sender_keys.public_key().to_hex();
    let (conf_tx, conf_rx) = tokio::sync::oneshot::channel::<DaemonReply>();
    if let Ok(mut map) = pending_requests().lock() {
        map.insert(
            trade_pk_hex.clone(),
            PendingRequest {
                request_id,
                trade_index,
                kind: PendingRequestKind::Take,
                tx: Some(conf_tx),
            },
        );
    }

    // Subscribe to gift-wrap responses addressed to this trade key so the
    // daemon's reply (and later BuyerTookOrder / HoldInvoicePaymentAccepted)
    // reaches the dispatcher.
    subscribe_gift_wraps(sender_keys.public_key(), trade_index).await;

    if let Err(e) = publish_event_json(&event_json).await {
        remove_pending_request(&trade_pk_hex, request_id);
        return Err(e);
    }

    crate::api::logging::blog_info("orders", format!(
        "take_order published order={order_id} trade_index={trade_index} — \
         waiting for daemon"
    ));

    // Wait for the daemon's verdict — the trade only exists once the daemon
    // acknowledges the take. On timeout, detach only the waiter and leave the
    // record: a genuine late reply is logged, a stale replay still can't
    // consume it, and the record dies with the per-trade subscription.
    let reply = crate::rt::time::timeout(
        std::time::Duration::from_secs(10),
        conf_rx,
    ).await;
    if !matches!(reply, Ok(Ok(_))) {
        detach_request_waiter(&trade_pk_hex, request_id);
    }

    let (status, amount_sats, hold_invoice) = match reply {
        Ok(Ok(DaemonReply::TakeAccepted {
            action,
            status,
            amount_sats,
            hold_invoice,
        })) => {
            crate::api::logging::blog_info("orders", format!(
                "take_order confirmed by daemon: order={order_id} reply={action:?}"
            ));
            (status, amount_sats, hold_invoice)
        }
        Ok(Ok(DaemonReply::Rejected { reason, message })) => {
            crate::api::logging::blog_warn("orders", format!(
                "take_order rejected: {reason} — {message}"
            ));
            return Err(anyhow::anyhow!("{message}"));
        }
        Ok(Ok(DaemonReply::Confirmed { .. })) => {
            // Only the create flow sends Confirmed; a take record can never
            // receive it. Treat defensively as an acceptance without data.
            log::warn!("[orders] take_order received a create-style confirmation");
            (None, None, None)
        }
        _ => {
            // No daemon response within the timeout. Do not persist or show
            // the trade — as far as the user is concerned the take failed.
            crate::api::logging::blog_warn("orders", format!(
                "take_order: no daemon response within 10s for order={order_id}"
            ));
            return Err(anyhow::anyhow!("NoDaemonResponse"));
        }
    };

    // Accepted: build the trade from the daemon's actual reply instead of
    // optimistic assumptions, then persist and wire up the trade session.
    let now = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;
    let initial_step = match role {
        TradeRole::Buyer => TradeStep::Buyer(BuyerStep::OrderTaken),
        TradeRole::Seller => TradeStep::Seller(SellerStep::TakerFound),
    };

    let mut order_info = order.clone();
    if let Some(s) = status.clone() {
        order_info.status = s;
    }
    if amount_sats.is_some() {
        order_info.amount_sats = amount_sats;
    }

    let trade = TradeInfo {
        id: uuid::Uuid::new_v4().to_string(),
        order: order_info,
        role,
        counterparty_pubkey: order.creator_pubkey.clone(),
        current_step: initial_step,
        hold_invoice,
        buyer_invoice: None,
        trade_key_index: trade_index,
        cooperative_cancel_state: None,
        timeout_at: Some(now + 900),
        started_at: now,
        completed_at: None,
        outcome: None,
    };

    store_trade_key_index(&order_id, trade_index).await;
    if status.is_some() || amount_sats.is_some() {
        // Keep the public order book in sync with the reply so the order
        // doesn't linger as Pending and the calculated sats are visible
        // immediately (tradeAmountProvider polls the book). Mirrors what the
        // per-action arms do for later messages; this first reply was
        // consumed by the waiter.
        if let Some(mut info) = order_book().get_order(&order_id).await {
            if let Some(s) = status {
                info.status = s;
            }
            if amount_sats.is_some() {
                info.amount_sats = amount_sats;
            }
            order_book().upsert_order(info).await;
        }
    }
    if let Some(db) = crate::db::app_db::db() {
        if let Err(e) = db.save_trade(&trade).await {
            log::warn!("[orders] failed to persist trade: {e}");
        }
    }
    // Subscribe to d-tag K38383 updates for this specific order so we
    // receive status changes (pending → in-progress → waiting-payment …).
    subscribe_single_order(&order_id).await;
    // Create a session so the chat API can look up keys immediately.
    let _ = crate::mostro::session::session_manager()
        .create_session(
            order_id.clone(),
            trade.role.clone(),
            trade_index,
            trade.order.clone(),
        )
        .await;

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

    let trade_index = get_trade_key_index(&order_id).await.ok_or_else(|| {
        log::warn!("[orders] send_invoice: no persisted trade key for order {order_id}");
        anyhow::anyhow!("TradeNotFound")
    })?;
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    let identity_keys =
        crate::api::identity::get_transport_identity_keys(&sender_keys).await?;
    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;

    // Correlation nonce for this submission. The daemon echoes it in its
    // reply (progression message or CantDo, e.g. InvalidInvoice); only a
    // reply carrying it may resolve the acknowledgement below.
    let request_id: u64 = {
        use rand::RngCore;
        rand::rngs::OsRng.next_u64().max(1) // 0 is indistinguishable from "unset"
    };

    let event_json = actions::add_invoice(
        &identity_keys,
        &sender_keys,
        &mostro_pubkey,
        &order_id,
        trade_index,
        &invoice_or_address,
        amount_opt,
        request_id,
    )
    .await?;

    // Register the pending record BEFORE publishing so the reply cannot race
    // the bookkeeping. The trade key already has an active subscription from
    // the take (and the global feed covers cold starts), so no new
    // subscription is needed here.
    let trade_pk_hex = sender_keys.public_key().to_hex();
    let (conf_tx, conf_rx) = tokio::sync::oneshot::channel::<DaemonReply>();
    if let Ok(mut map) = pending_requests().lock() {
        map.insert(
            trade_pk_hex.clone(),
            PendingRequest {
                request_id,
                trade_index,
                kind: PendingRequestKind::AddInvoice,
                tx: Some(conf_tx),
            },
        );
    }

    if let Err(e) = publish_event_json(&event_json).await {
        remove_pending_request(&trade_pk_hex, request_id);
        return Err(e);
    }
    log::info!(
        "[orders] add_invoice published for order={order_id} trade_index={trade_index} \
         ln_address={} amount={:?} — waiting for daemon",
        invoice_or_address.contains('@'),
        amount_opt
    );

    // Wait for the daemon's verdict: a rejected invoice (e.g. InvalidInvoice)
    // must surface instead of letting the UI advance on a publish that the
    // daemon errored on. Timeout keeps the record for a late reply, which the
    // dispatcher processes as a normal status update.
    let reply = crate::rt::time::timeout(
        std::time::Duration::from_secs(10),
        conf_rx,
    ).await;
    if !matches!(reply, Ok(Ok(_))) {
        detach_request_waiter(&trade_pk_hex, request_id);
    }

    match reply {
        Ok(Ok(DaemonReply::Rejected { reason, message })) => {
            crate::api::logging::blog_warn("orders", format!(
                "add_invoice rejected: {reason} — {message}"
            ));
            Err(anyhow::anyhow!("{message}"))
        }
        Ok(Ok(_)) => {
            crate::api::logging::blog_info("orders", format!(
                "add_invoice acknowledged by daemon for order={order_id}"
            ));
            Ok(())
        }
        _ => {
            crate::api::logging::blog_warn("orders", format!(
                "add_invoice: no daemon response within 10s for order={order_id}"
            ));
            Err(anyhow::anyhow!("NoDaemonResponse"))
        }
    }
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

// ── Mostro reply (Kind 14, protocol v2) subscription ─────────────────────────

/// Subscribe to kind-14 NIP-44 Mostro replies (authored by the node) addressed
/// to a maker's trade key, spawning a background task that decrypts daemon
/// responses.
///
/// Called immediately after creating a new maker order. Handles:
/// - `Action::NewOrder` — daemon confirmed the order; consumes the pending
///   create record and bridges the daemon UUID into `TRADE_KEY_MAP`.
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

    let mostro_pubkey =
        match nostr_sdk::PublicKey::from_hex(&crate::config::active_mostro_pubkey()) {
            Ok(pk) => pk,
            Err(e) => {
                log::error!("[orders] subscribe_gift_wraps: invalid mostro pubkey: {e}");
                return;
            }
        };

    // Obtain the notifications receiver BEFORE subscribing to avoid a
    // window where daemon responses arrive but aren't captured.
    let mut rx = client.notifications();

    // Protocol v2: kind-14 NIP-44 replies authored by Mostro, p-tagged to
    // this trade key.
    //
    // `limit(0)` makes this a live-only subscription: relays return no
    // stored events, only events published after subscribe. In normal
    // operation the key is freshly derived and has no history — the guard
    // protects the cases where key reuse happens anyway: a mnemonic
    // re-imported on another device resets the trade key counter to 0 (no
    // last-trade-index resync yet), re-deriving keys whose full reply
    // history sits on the relays; any future counter regression does the
    // same. Replayed replies from an earlier life of the key are what used
    // to falsely resolve waiting create_order calls.
    // mostro-cli (`wait_for_dm`) and MostriX (waiter subscriptions) use the
    // same pattern for the same purpose. Unlike a `since` cutoff, `limit(0)`
    // never touches live events, so it cannot drop the genuine reply when
    // the client clock runs ahead of the daemon's. Offline catch-up is the
    // global feed's job (see subscribe_node_filters), which replays history.
    let filter = nostr_sdk::Filter::new()
        .kind(nostr_sdk::Kind::PrivateDirectMessage)
        .author(mostro_pubkey)
        .pubkey(trade_pubkey)
        .limit(0);
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
    crate::rt::spawn(async move {
        use nostr_sdk::RelayPoolNotification;
        use crate::rt::time::{timeout, Duration};

        const IDLE_TIMEOUT_SECS: u64 = 30 * 60;
        let mut last_activity = crate::rt::time::Instant::now();

        loop {
            let remaining =
                Duration::from_secs(IDLE_TIMEOUT_SECS).saturating_sub(last_activity.elapsed());
            if remaining.is_zero() {
                break;
            }

            match timeout(remaining, rx.recv()).await {
                Ok(Ok(RelayPoolNotification::Event { event, .. })) => {
                    if event.kind != nostr_sdk::Kind::PrivateDirectMessage {
                        continue;
                    }
                    // Disambiguate Mostro replies from NIP-17 peer chat (also
                    // kind 14): only the node may author a Mostro reply.
                    if event.pubkey != mostro_pubkey {
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
                        "Kind 14 received (per-trade) for trade={} from={} event_id={}",
                        &trade_pubkey_hex[..8],
                        &event.pubkey.to_hex()[..8],
                        &eid[..16],
                    ));
                    match crate::nostr::gift_wrap::unwrap_mostro_message(&recipient_keys, &event).await {
                        Ok(Some(unwrapped)) => {
                            dispatch_mostro_message(unwrapped, &eid, &trade_pubkey_hex, trade_index).await;
                            last_activity = crate::rt::time::Instant::now();
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

        // The subscription bounds the pending record's lifetime: once no
        // reply can be delivered here anymore, a still-unconsumed record
        // (request timed out and no genuine late reply ever arrived) is dead
        // state — drop it, whatever attempt it belongs to.
        purge_pending_request(&trade_pubkey_hex);
    });
}

/// Dispatch a Mostro `Message` recovered from a kind-14 NIP-44 reply.
///
/// The caller recovers the `UnwrappedMessage` via
/// `crate::nostr::gift_wrap::unwrap_mostro_message`, which verifies the kind-14
/// event signature so the `sender` field (the event author) is cryptographically
/// attributable. This function authenticates that `sender` against the active
/// Mostro pubkey (defense-in-depth behind the receive handler's author pin),
/// runs the centralized `validate_response` check (catches `CantDo` responses
/// and malformed `request_id` fields), then routes by action.
async fn dispatch_mostro_message(
    unwrapped: mostro_core::nip59::UnwrappedMessage,
    event_id: &str,
    trade_pubkey_hex: &str,
    trade_index: u32,
) {
    use mostro_core::message::Action;

    // The protocol-v2 unwrap exposes two pubkeys:
    //
    //   * `sender`   — the kind-14 event author, whose signature is verified
    //     inside `unwrap_incoming`. This is the load-bearing, always-stable
    //     origin in v2 and the field we authenticate against.
    //   * `identity` — the proven identity-proof pubkey when a proof is
    //     attached, or the event author when not. Its meaning is conditional,
    //     so it is not the right anchor for the daemon-auth gate.
    //
    // A forger cannot sign a kind-14 event as the node, so `sender == mostro`
    // is the authoritative check.
    let mostro_core::nip59::UnwrappedMessage {
        message: msg,
        sender,
        identity: _,
        signature: _,
        created_at: _,
    } = unwrapped;

    // Daemon authentication: the kind-14 event author (`sender`) must be the
    // active Mostro pubkey. The event signature is verified inside
    // `unwrap_incoming`, so `sender` is the cryptographically authoritative
    // origin.
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
    // and flags `CantDo` responses. We still pass `None` here on purpose:
    // request_id correlation happens at the waiter arms below (via
    // `take_matching_request`) because `validate_response` short-circuits
    // on `CantDo` BEFORE comparing request_ids, so it cannot distinguish a
    // stale replayed rejection from the genuine one.
    //
    // `MostroCantDo` is NOT a reason to drop the message — the `Action::CantDo`
    // arm below is what unblocks `create_order` callers waiting on a
    // pending-create oneshot. Without propagating it, rejected orders
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
    // arrive with the daemon's order ID, but if the create's acknowledgement
    // was missed the trade-key bookkeeping still uses the local UUID.
    // Reconcile before any status update so that update_order_status /
    // update_trade_fields find the order by the daemon ID.
    //
    // Gated by ownership: only the local UUID recorded in this trade key's
    // own pending create may ever be rebound. Without the gate, any event
    // carrying an old order id for a reused trade index (stale replays after
    // a mnemonic re-import) would rebind a confirmed order's id — daemon →
    // daemon — corrupting the order book, the trade row, and the trade-key
    // mapping in one stroke. Cold start loses nothing: the pending map is
    // empty after a restart, and the Kind 38383 fingerprint path owns maker
    // recovery there.
    if let Some(daemon_id) = &kind.id {
        let did = daemon_id.to_string();
        if order_book().get_order(&did).await.is_none() {
            if let Some(db) = crate::db::app_db::db() {
                if let Ok(Some(local_id)) = db.get_order_id_by_trade_index(trade_index).await {
                    let owned = pending_local_uuid_for(trade_pubkey_hex);
                    if may_reconcile_stored_id(&local_id, &did, owned.as_deref()) {
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

    // Resolve a waiting take_order call before the per-action arms. Unlike a
    // create (whose only success reply is NewOrder), a take's first reply
    // varies by role and daemon config (add-invoice, pay-invoice,
    // pay-bond-invoice, a direct progression message, …), so ANY non-CantDo
    // reply echoing the take's nonce belongs to that caller. CantDo stays
    // with its arm below, which rejects any pending request kind through the
    // shared reason mapping. The caller applies the reply's effects itself
    // (status, hold invoice, persistence), so consuming the message here
    // keeps the arms from double-processing it.
    if kind.action != Action::CantDo {
        if let Some(pending) = take_matching_take(trade_pubkey_hex, kind.request_id) {
            let reply = classify_take_reply(&kind.action, &kind.payload);
            if let Some(tx) = pending.tx {
                crate::api::logging::blog_info("gift-wrap", format!(
                    "{:?}: notified waiting take_order for trade={}",
                    kind.action,
                    &trade_pubkey_hex[..8]
                ));
                let _ = tx.send(reply);
            } else {
                // Genuine reply after the 10s timeout: the caller already
                // returned NoDaemonResponse and persisted nothing, so there
                // is nothing to reconcile for a take — just log it.
                crate::api::logging::blog_info("gift-wrap", format!(
                    "{:?}: late reply for timed-out take on trade={} — ignoring",
                    kind.action,
                    &trade_pubkey_hex[..8]
                ));
            }
            return;
        }

        // An add-invoice reply doubles as a status update
        // (waiting-seller-to-pay, buyer-invoice-accepted, …), so only
        // unblock the waiting send_invoice caller and FALL THROUGH — the
        // per-action arms below still persist the message's effects. This
        // asymmetry with takes is deliberate: a take's caller applies the
        // reply itself, an add-invoice's caller only needs success/failure.
        if let Some(pending) = take_matching_add_invoice(trade_pubkey_hex, kind.request_id) {
            if let Some(tx) = pending.tx {
                crate::api::logging::blog_info("gift-wrap", format!(
                    "{:?}: acknowledged waiting send_invoice for trade={}",
                    kind.action,
                    &trade_pubkey_hex[..8]
                ));
                let _ = tx.send(DaemonReply::Acknowledged);
            } else {
                crate::api::logging::blog_info("gift-wrap", format!(
                    "{:?}: late acknowledgement for timed-out add-invoice on trade={}",
                    kind.action,
                    &trade_pubkey_hex[..8]
                ));
            }
        }
    }

    match &kind.action {
        Action::NewOrder => {
            if let Some(order_id) = &kind.id {
                let daemon_id = order_id.to_string();

                // Consume the pending create ONLY when this reply echoes its
                // request_id. Everything the reply is allowed to touch — the
                // trade-key binding, the waiter channel, the local→daemon id
                // bridge — lives in that one record, so a stale replay or a
                // foreign reply (mismatched/absent nonce) touches nothing and
                // the genuine reply still finds the record intact.
                if let Some(pending) = take_matching_request(trade_pubkey_hex, kind.request_id) {
                    // Bind the daemon UUID to this attempt's trade index so
                    // subsequent maker actions (e.g. cancel) can find the key.
                    store_trade_key_index(&daemon_id, pending.trade_index).await;

                    let PendingRequestKind::Create { local_uuid, .. } = pending.kind else {
                        // Unreachable in practice: take records are consumed
                        // by the pre-arm interception for every non-CantDo
                        // action, so only creates can arrive here.
                        log::warn!(
                            "[orders] NewOrder consumed a non-create pending \
                             record for trade={trade_pubkey_hex} — ignoring"
                        );
                        return;
                    };
                    if let Some(tx) = pending.tx {
                        // create_order is still waiting — the caller handles
                        // UUID adoption and persistence.
                        let _ = tx.send(DaemonReply::Confirmed {
                            daemon_id: daemon_id.clone(),
                        });
                        crate::api::logging::blog_info("gift-wrap", format!(
                            "NewOrder: notified waiting create_order daemon={daemon_id}"
                        ));
                    } else {
                        // Genuine reply after the 10s timeout: the caller
                        // already returned NoDaemonResponse and persisted
                        // nothing, so there is no local order to rebind —
                        // the trade-key binding above plus the Kind 38383
                        // fingerprint path restore maker ownership.
                        crate::api::logging::blog_info("gift-wrap", format!(
                            "NewOrder: late confirmation for timed-out create \
                             local={local_uuid} daemon={daemon_id}"
                        ));
                    }
                } else {
                    // Cold start / reconnect (no record — in-memory state is
                    // empty after a restart), or an uncorrelated event that
                    // must not consume anything. The Kind 38383 fingerprint
                    // path owns maker-order recovery in both cases.
                    crate::api::logging::blog_info("gift-wrap", format!(
                        "NewOrder: daemon order={daemon_id} with no matching \
                         pending create — leaving state untouched"
                    ));
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
            // Map action → OrderStatus for DB sync (shared with the take
            // reply classification).
            let new_status = status_for_action(&kind.action);
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

            // Consume the pending request ONLY when this rejection echoes its
            // request_id — a genuine rejection ends the attempt, so the whole
            // record goes with it (whatever its kind). Stale replayed CantDo
            // events (no or foreign request_id) touch nothing and leave the
            // record for the genuine reply.
            if let Some(pending) = take_matching_request(trade_pubkey_hex, kind.request_id) {
                if let Some(tx) = pending.tx {
                    crate::api::logging::blog_warn("gift-wrap", format!(
                        "CantDo: reason={reason} — notifying waiting caller"
                    ));
                    let _ = tx.send(DaemonReply::Rejected { reason, message });
                } else {
                    // Genuine rejection after the 10s timeout: the caller
                    // already returned NoDaemonResponse and persisted nothing,
                    // so dropping the record is the only cleanup needed.
                    crate::api::logging::blog_warn("gift-wrap", format!(
                        "CantDo: reason={reason} — late rejection for timed-out request"
                    ));
                }
            } else {
                crate::api::logging::blog_debug("gift-wrap", format!(
                    "CantDo: reason={reason} — no matching pending request, ignoring event"
                ));
            }
        }
        Action::BondSlashed => {
            let order_id = match &kind.id {
                Some(id) => id.to_string(),
                None => {
                    log::warn!("[orders] gift-wrap BondSlashed has no order id");
                    return;
                }
            };
            let small_order = match &kind.payload {
                Some(mostro_core::message::Payload::Order(so)) => so,
                _ => {
                    log::warn!("[orders] gift-wrap BondSlashed payload is not an Order");
                    return;
                }
            };
            // The payload's amount is the SLASHED BOND amount and its status is
            // null. Never write it back to the tracked order: this notice is
            // informational, and overwriting would corrupt the order's real
            // trade status/amount. We only read the current status to infer the
            // slash cause.
            let amount_sats = match u64::try_from(small_order.amount) {
                Ok(v) => v,
                Err(_) => {
                    log::warn!(
                        "[orders] gift-wrap BondSlashed: invalid amount {} for order={order_id}, ignoring",
                        small_order.amount
                    );
                    return;
                }
            };
            let status = match crate::db::app_db::db() {
                Some(db) => db
                    .get_trade_by_order_id(&order_id)
                    .await
                    .ok()
                    .flatten()
                    .map(|t| t.order.status),
                None => None,
            };
            let cause = crate::api::bond::infer_slash_cause(status.as_ref());
            log::info!(
                "[orders] gift-wrap BondSlashed: order={order_id} amount={amount_sats} cause={cause:?}"
            );
            crate::api::bond::emit_bond_slashed(crate::api::types::BondSlashedEvent {
                event_id: event_id.to_string(),
                order_id,
                amount_sats,
                fiat_code: small_order.fiat_code.clone(),
                fiat_amount: small_order.fiat_amount,
                payment_method: small_order.payment_method.clone(),
                cause,
            });
        }
        action => {
            log::debug!("[orders] gift-wrap unhandled action={action:?}");
        }
    }
}

/// Maps a `mostro_core::order::Status` to the local [`OrderStatus`] enum.
/// Map a daemon action to the order status it implies, for messages that
/// carry no explicit status payload (action-only progression replies).
///
/// Shared by the status-sync arm in `dispatch_mostro_message` and by
/// `classify_take_reply`, so a take whose first reply is action-only (e.g.
/// `waiting-seller-to-pay` after a take-sell with a pre-attached LN address)
/// still persists the status the daemon already advanced to.
fn status_for_action(action: &mostro_core::message::Action) -> Option<OrderStatus> {
    use mostro_core::message::Action;
    match action {
        Action::WaitingSellerToPay => Some(OrderStatus::WaitingPayment),
        Action::WaitingBuyerInvoice => Some(OrderStatus::WaitingBuyerInvoice),
        Action::PayBondInvoice => Some(OrderStatus::WaitingTakerBond),
        Action::BuyerInvoiceAccepted => Some(OrderStatus::Active),
        Action::FiatSentOk => Some(OrderStatus::FiatSent),
        Action::HoldInvoicePaymentSettled | Action::Released | Action::PurchaseCompleted => {
            Some(OrderStatus::SettledHoldInvoice)
        }
        Action::HoldInvoicePaymentCanceled => Some(OrderStatus::Canceled),
        Action::CooperativeCancelAccepted => Some(OrderStatus::CooperativelyCanceled),
        // Status doesn't change yet for cancel initiations; Rate/PaymentFailed
        // don't move the order either.
        Action::CooperativeCancelInitiatedByPeer
        | Action::CooperativeCancelInitiatedByYou
        | Action::Rate
        | Action::RateUser
        | Action::RateReceived
        | Action::PaymentFailed => None,
        Action::DisputeInitiatedByYou | Action::DisputeInitiatedByPeer => {
            Some(OrderStatus::Dispute)
        }
        Action::AdminSettled => Some(OrderStatus::SettledByAdmin),
        Action::AdminCanceled => Some(OrderStatus::CanceledByAdmin),
        _ => None,
    }
}

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
        // Taker anti-abuse bond: the taker must pay a bond hold invoice before
        // the trade progresses.
        S::WaitingTakerBond => OrderStatus::WaitingTakerBond,
        // Maker-side bond is out of scope here (issue #191); it has no local
        // OrderStatus yet. No wildcard, so future Status variants keep forcing
        // this match to be revisited.
        S::WaitingMakerBond => return None,
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
    crate::rt::spawn(async move {
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
    crate::rt::spawn(async move {
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
        use crate::rt::time::{timeout, Duration};

        // Exit after 30 minutes of inactivity (no order updates received).
        // The timer resets on each relevant event so active trades stay subscribed.
        const IDLE_TIMEOUT_SECS: u64 = 30 * 60;
        let mut last_activity = crate::rt::time::Instant::now();

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
                            last_activity = crate::rt::time::Instant::now();
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
/// 1. Subscribes to `all_orders_filter()` via the relay pool client.
/// 2. Loops over `RelayPoolNotification::Event` messages.
/// 3. Parses each Kind 38383 event via `parse_order_event` and upserts it
///    into the order book, which broadcasts the update to all `OrdersStream`
///    subscribers.
///
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

    crate::rt::spawn(async {
        let _guard = ResetGuard;
        _run_order_subscription().await;
    });
}

/// Refresh the order book on demand (UI "Refresh" action).
///
/// Ensures the long-lived subscription loop is running — idempotent: it does
/// NOT clear `SUBSCRIPTION_ACTIVE`, which the previous version did and which
/// spawned a *second* loop while the old one kept consuming notifications.
/// Then it re-pulls the active node's current orders: a plain re-subscribe
/// wouldn't repopulate already-seen orders (nostr-sdk dedups them from the live
/// stream), so the explicit refetch is what actually refreshes the book.
pub async fn restart_orders_subscription() {
    subscribe_orders().await;
    refetch_active_node_orders().await;
}

/// Fetch the active node's current Kind 38383 orders and ingest them.
///
/// The live subscription's notification stream does not redeliver events the
/// session has already seen (nostr-sdk dedups them), so an explicit fetch is
/// needed to (re)populate the book — both on a node switch and on a manual
/// refresh. `fetch_events` collects from the raw relay-message channel, which
/// is not subject to that dedup.
async fn refetch_active_node_orders() {
    let Ok(pool) = crate::api::nostr::get_pool() else {
        log::warn!("[orders] refetch: relay pool not initialized");
        return;
    };
    let mostro_pubkey = match nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey()) {
        Ok(pk) => pk,
        Err(e) => {
            log::error!("[orders] refetch: invalid mostro pubkey: {e}");
            return;
        }
    };
    let order_filter = crate::nostr::order_events::all_orders_filter(&mostro_pubkey);
    match pool
        .client()
        .fetch_events(order_filter, std::time::Duration::from_secs(10))
        .await
    {
        Ok(events) => {
            crate::api::logging::blog_info(
                "orders",
                format!("refetched {} current orders for active node", events.len()),
            );
            for event in events.into_iter() {
                ingest_order_event(&event).await;
            }
        }
        Err(e) => log::warn!("[orders] refetch: fetch current orders failed: {e}"),
    }
}

/// Stable subscription ID for the Kind 38383 order-book feed.
fn orders_subscription_id() -> nostr_sdk::SubscriptionId {
    nostr_sdk::SubscriptionId::new("mostro-orders")
}

/// Stable subscription ID for the Kind 14 Mostro-reply feed.
fn mostro_dm_subscription_id() -> nostr_sdk::SubscriptionId {
    nostr_sdk::SubscriptionId::new("mostro-dm")
}

/// (Re)subscribe the order-book (Kind 38383) and Mostro-reply (Kind 14)
/// filters, author-pinned to `mostro_pubkey`.
///
/// Uses **stable** subscription IDs so that calling this again for a different
/// node REPLACES the existing author-pinned filters in place (the relay pool
/// overwrites the subscription for a known ID) instead of leaking a second
/// subscription that keeps the old node's events flowing.
async fn subscribe_node_filters(
    client: &nostr_sdk::Client,
    mostro_pubkey: nostr_sdk::PublicKey,
    trade_pubkeys: Vec<nostr_sdk::PublicKey>,
) -> Result<()> {
    let order_filter = crate::nostr::order_events::all_orders_filter(&mostro_pubkey);
    client
        .subscribe_with_id(orders_subscription_id(), order_filter, None)
        .await
        .map_err(|e| anyhow::anyhow!("order subscribe failed: {e}"))?;

    // Kind-14 NIP-44 replies authored by Mostro for all known trade pubkeys.
    // The author pin disambiguates from NIP-17 peer chat (also kind 14).
    //
    // Deliberately NO `since` here: this is the offline catch-up channel —
    // after any downtime it must replay the full stored history so status
    // changes and late reconciliations are never lost. Only the ephemeral
    // per-trade subscription (subscribe_gift_wraps) carries a cutoff.
    if !trade_pubkeys.is_empty() {
        let dm_filter = nostr_sdk::Filter::new()
            .kind(nostr_sdk::Kind::PrivateDirectMessage)
            .author(mostro_pubkey)
            .pubkeys(trade_pubkeys);
        client
            .subscribe_with_id(mostro_dm_subscription_id(), dm_filter, None)
            .await
            .map_err(|e| anyhow::anyhow!("dm subscribe failed: {e}"))?;
    }
    Ok(())
}

/// Re-target the live order-book and Mostro-reply subscriptions to the
/// currently-active Mostro node, after the active pubkey has changed.
///
/// Clears the order book (cached orders belong to the previous node),
/// re-subscribes the author-pinned filters with stable IDs (replacing the old
/// ones in place), and refreshes the node's PoW requirement. The long-lived
/// subscription loop keeps running and picks up the new node via its
/// per-event active-pubkey check — no loop restart, so no duplicate loops.
pub(crate) async fn refresh_subscriptions_for_active_node() {
    // Drop stale orders immediately so the UI doesn't show the old node's book.
    order_book().clear().await;

    let Ok(pool) = crate::api::nostr::get_pool() else {
        log::warn!(
            "[orders] node switch: relay pool not initialized; \
             subscriptions will start with the new node once online"
        );
        return;
    };
    let client = pool.client();

    let mostro_pubkey = match nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey()) {
        Ok(pk) => pk,
        Err(e) => {
            log::error!("[orders] node switch: invalid mostro pubkey: {e}");
            return;
        }
    };

    let trade_key_map = build_trade_key_map().await;
    let trade_pubkeys: Vec<nostr_sdk::PublicKey> = trade_key_map
        .keys()
        .filter_map(|hex| nostr_sdk::PublicKey::from_hex(hex).ok())
        .collect();

    if let Err(e) = subscribe_node_filters(&client, mostro_pubkey, trade_pubkeys).await {
        log::error!("[orders] node switch: re-subscribe failed: {e}");
        return;
    }

    // Repopulate the cleared book with the new node's current orders (the live
    // stream won't redeliver already-seen events — see refetch_active_node_orders).
    refetch_active_node_orders().await;

    // Outgoing messages must use the new node's PoW difficulty.
    crate::api::nostr::fetch_and_set_pow().await;

    crate::api::logging::blog_info(
        "orders",
        format!("switched subscriptions to mostro={}", mostro_pubkey.to_hex()),
    );
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

/// Handle a kind-14 Mostro reply received on the global subscription.
///
/// The caller has already pinned the author to the active Mostro pubkey.
/// Finds which trade key the event is addressed to (via `p` tag), decrypts
/// via `mostro_core::transport::unwrap_incoming`, and dispatches the recovered
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
        "Kind 14 received (global) for trade={} from={} event_id={}",
        &recipient_hex[..8],
        &event.pubkey.to_hex()[..8],
        &eid[..16],
    ));

    match crate::nostr::gift_wrap::unwrap_mostro_message(&recipient_keys, event).await {
        Ok(Some(unwrapped)) => {
            dispatch_mostro_message(unwrapped, &eid, &recipient_hex, trade_idx).await;
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

/// Parse a Kind 38383 event and upsert it into the order book, applying
/// maker-order reconciliation (is_mine detection, local→daemon id bridging,
/// trade-status sync).
///
/// Shared by the live subscription loop and the node-switch refetch so both
/// paths populate the book identically.
async fn ingest_order_event(event: &nostr_sdk::Event) {
    log::debug!(
        "[orders] event kind={} author={}",
        event.kind,
        &event.pubkey.to_hex()[..8]
    );
    match parse_order_event(event, None) {
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
                    // The maker order is no longer inserted into the
                    // book optimistically (see `create_order`), so there
                    // is nothing to remove here — just bridge the local
                    // UUID → daemon UUID in the DB so tradeStatusProvider
                    // polls with the real order ID. Only records without a
                    // live waiter are taken: an in-flight create_order owns
                    // its own reconciliation via the kind-14 acknowledgement.
                    if let Some(PendingRequest {
                        kind: PendingRequestKind::Create { local_uuid: local_id, .. },
                        ..
                    }) = take_pending_create_by_content_key(&ck)
                    {
                        if let Some(db) = crate::db::app_db::db() {
                            if let Err(e) =
                                db.update_trade_order_id(&local_id, &info.id).await
                            {
                                log::warn!(
                                    "[orders] failed to update trade order_id \
                                     {local_id} → {}: {e}",
                                    info.id
                                );
                            }
                        }
                        log::info!(
                            "[orders] reconciled local order={local_id} → daemon order={}",
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

    // Build a map of all known trade keys so we can decrypt ANY kind-14
    // Mostro reply, not just those from the current session.
    let trade_key_map = build_trade_key_map().await;
    let trade_pubkeys: Vec<nostr_sdk::PublicKey> = trade_key_map
        .keys()
        .filter_map(|hex| nostr_sdk::PublicKey::from_hex(hex).ok())
        .collect();
    crate::api::logging::blog_info("orders", format!("trade key map: {} keys derived for gift-wrap decryption", trade_pubkeys.len()));

    // Get notifications receiver before subscribing to avoid missing
    // events that arrive between the subscribe call and receiver creation.
    let mut rx = client.notifications();

    // Subscribe to ALL orders (Kind 38383, no status restriction so we receive
    // status changes) and the bulk Kind-14 Mostro-reply feed, both author-pinned
    // to the active node via stable subscription IDs (so a later node switch can
    // replace them in place). Display-level filtering is handled in Dart.
    if let Err(e) = subscribe_node_filters(&client, mostro_pubkey, trade_pubkeys).await {
        log::error!("[orders] subscribe failed: {e}");
        return;
    }

    crate::api::logging::blog_info("orders", "subscriptions active — waiting for events".to_string());

    use nostr_sdk::RelayPoolNotification;

    loop {
        match rx.recv().await {
            Ok(RelayPoolNotification::Event { event, .. }) => {
                // Resolve the *current* active node for each event so a node
                // switch is respected without restarting this loop.
                let Ok(active_mostro) =
                    nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())
                else {
                    continue;
                };

                // ── Kind 14 NIP-44 Mostro reply: decrypt and dispatch ──
                if event.kind == nostr_sdk::Kind::PrivateDirectMessage {
                    // Disambiguate from NIP-17 peer chat (also kind 14): only
                    // the active node may author a Mostro reply.
                    if event.pubkey != active_mostro {
                        continue;
                    }
                    handle_global_gift_wrap(&event, &trade_key_map).await;
                    continue;
                }

                // ── Kind 38383 order book event ──
                // Ignore stale orders from a previously-active node (e.g. events
                // buffered across a node switch); the book only ever holds the
                // active node's orders.
                if event.pubkey != active_mostro {
                    continue;
                }
                ingest_order_event(&event).await;
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
// Currently unused: the subscription loop inlines `parse_order_event` +
// `upsert_order`. Kept as a reusable helper for future event-processing paths.
#[allow(dead_code)]
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
    trades.sort_by_key(|t| std::cmp::Reverse(t.started_at));
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

    // ── request_id correlation ────────────────────────────────────────────────

    #[test]
    fn request_id_only_matches_the_exact_nonce() {
        assert!(request_id_matches(42, Some(42)));
        assert!(!request_id_matches(42, Some(41)));
        // Stale replayed events carry no request_id — they must never match.
        assert!(!request_id_matches(42, None));
    }

    fn insert_pending_create(key: &str, request_id: u64) -> tokio::sync::oneshot::Receiver<DaemonReply> {
        let (tx, rx) = tokio::sync::oneshot::channel::<DaemonReply>();
        pending_requests().lock().unwrap().insert(
            key.to_string(),
            PendingRequest {
                request_id,
                trade_index: 3,
                kind: PendingRequestKind::Create {
                    local_uuid: format!("local-{key}"),
                    content_key: format!("content:{key}"),
                },
                tx: Some(tx),
            },
        );
        rx
    }

    fn local_uuid_of(pending: &PendingRequest) -> &str {
        match &pending.kind {
            PendingRequestKind::Create { local_uuid, .. } => local_uuid,
            _ => panic!("expected a Create record"),
        }
    }

    fn insert_pending_take(key: &str, request_id: u64) -> tokio::sync::oneshot::Receiver<DaemonReply> {
        let (tx, rx) = tokio::sync::oneshot::channel::<DaemonReply>();
        pending_requests().lock().unwrap().insert(
            key.to_string(),
            PendingRequest {
                request_id,
                trade_index: 4,
                kind: PendingRequestKind::Take,
                tx: Some(tx),
            },
        );
        rx
    }

    /// A reply with a foreign or missing request_id must leave the record in
    /// place so the genuine reply can still resolve it; only the echoed nonce
    /// consumes it.
    #[tokio::test]
    async fn take_matching_request_ignores_stale_events() {
        let key = "test-take-matching-request-pubkey";
        let mut rx = insert_pending_create(key, 7);

        // Stale replay (no request_id) and foreign reply: record untouched.
        assert!(take_matching_request(key, None).is_none());
        assert!(take_matching_request(key, Some(99)).is_none());
        assert!(pending_requests().lock().unwrap().contains_key(key));
        assert!(rx.try_recv().is_err()); // nothing sent

        // Genuine reply: record consumed exactly once, waiter still attached.
        let pending = take_matching_request(key, Some(7)).expect("must match");
        let tx = pending.tx.expect("waiter must still be attached");
        let _ = tx.send(DaemonReply::Confirmed {
            daemon_id: "d".to_string(),
        });
        assert!(!pending_requests().lock().unwrap().contains_key(key));
        assert!(take_matching_request(key, Some(7)).is_none());
    }

    /// After the 10s timeout only the waiter channel is detached; the record
    /// survives so the genuine late reply still matches — and stale events
    /// still cannot consume it.
    #[tokio::test]
    async fn late_genuine_reply_matches_after_timeout() {
        let key = "test-late-reply-pubkey";
        let _rx = insert_pending_create(key, 11);

        detach_request_waiter(key, 11);
        assert!(pending_requests().lock().unwrap().contains_key(key));

        // Stale events still bounce off the detached record.
        assert!(take_matching_request(key, None).is_none());
        assert!(take_matching_request(key, Some(99)).is_none());

        // The genuine late reply consumes it: no waiter, but the bridging
        // state (trade index, local uuid) is intact for reconciliation.
        let pending = take_matching_request(key, Some(11)).expect("must match");
        assert!(pending.tx.is_none());
        assert_eq!(pending.trade_index, 3);
        assert_eq!(local_uuid_of(&pending), format!("local-{key}"));
        assert!(!pending_requests().lock().unwrap().contains_key(key));
    }

    /// Concurrent requests each own their record: a reply correlated to one
    /// attempt must never consume state belonging to another.
    #[tokio::test]
    async fn concurrent_requests_do_not_cross_consume() {
        let key_a = "test-concurrent-a-pubkey";
        let key_b = "test-concurrent-b-pubkey";
        let _rx_a = insert_pending_create(key_a, 21);
        let _rx_b = insert_pending_create(key_b, 22);

        // A's nonce only ever matches A's record, under either key.
        assert!(take_matching_request(key_b, Some(21)).is_none());
        let pending = take_matching_request(key_a, Some(21)).expect("must match A");
        assert_eq!(local_uuid_of(&pending), format!("local-{key_a}"));

        // B is untouched and still consumable by its own nonce.
        let pending = take_matching_request(key_b, Some(22)).expect("must match B");
        assert_eq!(local_uuid_of(&pending), format!("local-{key_b}"));
    }

    /// `take_matching_take` must only consume Take records — a matching nonce
    /// on a Create record belongs to the NewOrder arm, and a foreign or
    /// missing nonce consumes nothing at all.
    #[tokio::test]
    async fn take_matching_take_only_consumes_take_records() {
        let create_key = "test-take-kind-create-pubkey";
        let take_key = "test-take-kind-take-pubkey";
        let _rx_c = insert_pending_create(create_key, 41);
        let _rx_t = insert_pending_take(take_key, 42);

        // A Create record is never consumed here, even with its exact nonce.
        assert!(take_matching_take(create_key, Some(41)).is_none());
        assert!(pending_requests().lock().unwrap().contains_key(create_key));

        // A Take record follows the same nonce rules as any request.
        assert!(take_matching_take(take_key, None).is_none());
        assert!(take_matching_take(take_key, Some(99)).is_none());
        assert!(pending_requests().lock().unwrap().contains_key(take_key));
        let pending = take_matching_take(take_key, Some(42)).expect("must match");
        assert!(matches!(pending.kind, PendingRequestKind::Take));
        assert!(!pending_requests().lock().unwrap().contains_key(take_key));

        pending_requests().lock().unwrap().remove(create_key);
    }

    /// `take_matching_add_invoice` mirrors the take rules for its own kind:
    /// only AddInvoice records, only with the exact nonce.
    #[tokio::test]
    async fn take_matching_add_invoice_only_consumes_add_invoice_records() {
        let take_key = "test-ai-take-pubkey";
        let ai_key = "test-ai-addinvoice-pubkey";
        let _rx_t = insert_pending_take(take_key, 51);

        let (tx, _rx) = tokio::sync::oneshot::channel::<DaemonReply>();
        pending_requests().lock().unwrap().insert(
            ai_key.to_string(),
            PendingRequest {
                request_id: 52,
                trade_index: 4,
                kind: PendingRequestKind::AddInvoice,
                tx: Some(tx),
            },
        );

        // A Take record is never consumed here, even with its exact nonce.
        assert!(take_matching_add_invoice(take_key, Some(51)).is_none());
        assert!(pending_requests().lock().unwrap().contains_key(take_key));

        // The AddInvoice record follows the same nonce rules as any request.
        assert!(take_matching_add_invoice(ai_key, None).is_none());
        assert!(take_matching_add_invoice(ai_key, Some(99)).is_none());
        let pending = take_matching_add_invoice(ai_key, Some(52)).expect("must match");
        assert!(matches!(pending.kind, PendingRequestKind::AddInvoice));
        assert!(!pending_requests().lock().unwrap().contains_key(ai_key));

        pending_requests().lock().unwrap().remove(take_key);
    }

    /// Same-key overlap (send_invoice reuses the take's trade key): a newer
    /// attempt overwrites the record, and the older attempt's timeout /
    /// rollback cleanup must not touch the newer attempt's live waiter.
    #[tokio::test]
    async fn overlapping_same_key_attempts_do_not_cross_detach() {
        let key = "test-same-key-overlap-pubkey";

        // Attempt A registers, then attempt B overwrites the record.
        let _rx_a = insert_pending_take(key, 61);
        let _rx_b = insert_pending_take(key, 62);

        // A's timeout fires: it must not detach B's live waiter…
        detach_request_waiter(key, 61);
        assert!(pending_requests()
            .lock()
            .unwrap()
            .get(key)
            .unwrap()
            .tx
            .is_some());

        // …and A's publish-failure rollback must not delete B's record.
        remove_pending_request(key, 61);
        assert!(pending_requests().lock().unwrap().contains_key(key));

        // B's own cleanup still works.
        detach_request_waiter(key, 62);
        assert!(pending_requests()
            .lock()
            .unwrap()
            .get(key)
            .unwrap()
            .tx
            .is_none());
        remove_pending_request(key, 62);
        assert!(!pending_requests().lock().unwrap().contains_key(key));
    }

    /// Action-only progression replies must still carry the status the
    /// action implies — the take interception consumes the message before
    /// the status-sync arms run, so an empty status would persist the trade
    /// as Pending even though the daemon already advanced it.
    #[test]
    fn classify_take_reply_derives_status_from_action_only_replies() {
        use mostro_core::message::Action;

        // take-sell with a pre-attached LN address: daemon skips add-invoice
        // and replies waiting-seller-to-pay with no payload.
        match classify_take_reply(&Action::WaitingSellerToPay, &None) {
            DaemonReply::TakeAccepted { status, .. } => {
                assert_eq!(status, Some(crate::api::types::OrderStatus::WaitingPayment));
            }
            _ => panic!("expected TakeAccepted"),
        }
        match classify_take_reply(&Action::WaitingBuyerInvoice, &None) {
            DaemonReply::TakeAccepted { status, .. } => {
                assert_eq!(
                    status,
                    Some(crate::api::types::OrderStatus::WaitingBuyerInvoice)
                );
            }
            _ => panic!("expected TakeAccepted"),
        }
    }

    fn small_order_with(
        status: mostro_core::order::Status,
        amount: i64,
    ) -> mostro_core::order::SmallOrder {
        mostro_core::order::SmallOrder::new(
            None,
            Some(mostro_core::order::Kind::Sell),
            Some(status),
            amount,
            "USD".to_string(),
            None,
            None,
            100,
            "bank".to_string(),
            0,
            None,
            None,
            None,
            None,
            None,
        )
    }

    /// `classify_take_reply` goes by payload shape: `PaymentRequest` carries
    /// the hold invoice (seller flow) or the anti-abuse bond hold invoice
    /// (`pay-bond-invoice`), `Order` carries the calculated sats (buyer flow),
    /// and action-only replies are still acceptances.
    #[test]
    fn classify_take_reply_maps_payload_shapes() {
        use mostro_core::message::{Action, Payload};
        use mostro_core::order::Status;

        // Seller taking a buy order: pay-invoice with the hold invoice.
        let so = small_order_with(Status::WaitingPayment, 7851);
        match classify_take_reply(
            &Action::PayInvoice,
            &Some(Payload::PaymentRequest(Some(so), "lnbc1invoice".into(), Some(7851))),
        ) {
            DaemonReply::TakeAccepted { status, amount_sats, hold_invoice, .. } => {
                assert_eq!(status, Some(crate::api::types::OrderStatus::WaitingPayment));
                assert_eq!(amount_sats, Some(7851));
                assert_eq!(hold_invoice.as_deref(), Some("lnbc1invoice"));
            }
            _ => panic!("expected TakeAccepted"),
        }

        // Amount falls back to the embedded order when the third field is None.
        let so = small_order_with(Status::WaitingPayment, 500);
        match classify_take_reply(
            &Action::PayInvoice,
            &Some(Payload::PaymentRequest(Some(so), "lnbc1invoice".into(), None)),
        ) {
            DaemonReply::TakeAccepted { amount_sats, .. } => {
                assert_eq!(amount_sats, Some(500));
            }
            _ => panic!("expected TakeAccepted"),
        }

        // Buyer taking a sell order: add-invoice with the calculated sats.
        let so = small_order_with(Status::WaitingBuyerInvoice, 9526);
        match classify_take_reply(&Action::AddInvoice, &Some(Payload::Order(so))) {
            DaemonReply::TakeAccepted { status, amount_sats, hold_invoice, .. } => {
                assert_eq!(
                    status,
                    Some(crate::api::types::OrderStatus::WaitingBuyerInvoice)
                );
                assert_eq!(amount_sats, Some(9526));
                assert!(hold_invoice.is_none());
            }
            _ => panic!("expected TakeAccepted"),
        }

        // Anti-abuse bond: pay-bond-invoice carries the bond hold invoice in a
        // PaymentRequest, surfaced through the same hold_invoice slot and
        // flagged by the WaitingTakerBond status.
        let so = small_order_with(Status::WaitingTakerBond, 1000);
        match classify_take_reply(
            &Action::PayBondInvoice,
            &Some(Payload::PaymentRequest(Some(so), "lnbc1bond".into(), Some(1000))),
        ) {
            DaemonReply::TakeAccepted { status, amount_sats, hold_invoice, .. } => {
                assert_eq!(
                    status,
                    Some(crate::api::types::OrderStatus::WaitingTakerBond)
                );
                assert_eq!(amount_sats, Some(1000));
                assert_eq!(hold_invoice.as_deref(), Some("lnbc1bond"));
            }
            _ => panic!("expected TakeAccepted"),
        }

        // A bond reply with no embedded status still resolves to
        // WaitingTakerBond via status_for_action(PayBondInvoice).
        match classify_take_reply(
            &Action::PayBondInvoice,
            &Some(Payload::PaymentRequest(None, "lnbc1bond".into(), Some(1000))),
        ) {
            DaemonReply::TakeAccepted { status, hold_invoice, .. } => {
                assert_eq!(
                    status,
                    Some(crate::api::types::OrderStatus::WaitingTakerBond)
                );
                assert_eq!(hold_invoice.as_deref(), Some("lnbc1bond"));
            }
            _ => panic!("expected TakeAccepted"),
        }

        // Action-only progression reply: still a genuine acceptance, with
        // the status derived from the action (see
        // classify_take_reply_derives_status_from_action_only_replies).
        match classify_take_reply(&Action::WaitingSellerToPay, &None) {
            DaemonReply::TakeAccepted { status, amount_sats, hold_invoice, .. } => {
                assert_eq!(status, Some(crate::api::types::OrderStatus::WaitingPayment));
                assert!(amount_sats.is_none());
                assert!(hold_invoice.is_none());
            }
            _ => panic!("expected TakeAccepted"),
        }
    }

    /// Only the pending create's own local UUID may be rebound to an incoming
    /// event's order id; a stored id that is already a daemon's (or belongs to
    /// an earlier life of a reused trade key) must never be rebound.
    #[test]
    fn stored_id_reconciles_only_when_owned_by_the_pending_create() {
        // The legitimate case: the stored id is this create's local UUID.
        assert!(may_reconcile_stored_id("local-1", "daemon-1", Some("local-1")));
        // Already the incoming id: nothing to rebind.
        assert!(!may_reconcile_stored_id("daemon-1", "daemon-1", Some("local-1")));
        // Stored id is a confirmed daemon id — a stale replay carrying an old
        // order id for the same (reused) trade index must not rebind it.
        assert!(!may_reconcile_stored_id("daemon-1", "old-daemon-9", Some("local-1")));
        // No pending create for this trade key (cold start / uncorrelated
        // event): never rebind here.
        assert!(!may_reconcile_stored_id("local-1", "daemon-1", None));
    }

    /// The Kind 38383 path matches by content fingerprint, but must leave
    /// records with a live waiter alone — the in-flight create_order call owns
    /// that reconciliation.
    #[tokio::test]
    async fn content_key_lookup_skips_live_waiters() {
        let key = "test-content-key-pubkey";
        let ck = format!("content:{key}");
        let _rx = insert_pending_create(key, 31);

        // Live waiter attached: the 38383 path must not consume the record.
        assert!(take_pending_create_by_content_key(&ck).is_none());

        // After the timeout detaches the waiter, the fingerprint match takes it.
        detach_request_waiter(key, 31);
        let pending = take_pending_create_by_content_key(&ck).expect("must match");
        assert_eq!(local_uuid_of(&pending), format!("local-{key}"));
        assert!(!pending_requests().lock().unwrap().contains_key(key));

        // Unknown fingerprints never match anything.
        assert!(take_pending_create_by_content_key("content:unknown").is_none());
    }

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
