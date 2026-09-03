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
use crate::mostro::pending::{
    classify_take_reply, detach_request_waiter, may_reconcile_stored_id, order_content_key,
    pending_local_uuid_for, pending_requests, purge_pending_request, remove_pending_request,
    take_matching_add_invoice, take_matching_dispute, take_matching_request, take_matching_restore,
    take_matching_take, take_pending_create_by_content_key, DaemonReply, DisputeMatch,
    PendingRequest, PendingRequestKind, Wake,
};
use crate::mostro::status::{
    add_invoice_sync, cancellation_wipes_history, is_hard_terminal, map_core_status,
    peer_reputation, status_for_action, wire_status_applies,
};
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

/// Ids the DB has already been asked about and did not have.
///
/// The ingest path looks up a content fingerprint for every Kind 38383 event,
/// and for every order belonging to somebody else that lookup misses — one
/// storage round trip per event, which on web is an IndexedDB transaction.
///
/// Safe to cache only because absence is stable: `store_trade_key_index` is
/// the sole path from absent to present, and it clears the entry.
static TRADE_KEY_MISSES: OnceLock<std::sync::RwLock<std::collections::HashSet<String>>> =
    OnceLock::new();

/// Ceiling on remembered misses.
const TRADE_KEY_MISS_CAPACITY: usize = 4096;

fn trade_key_misses() -> &'static std::sync::RwLock<std::collections::HashSet<String>> {
    TRADE_KEY_MISSES.get_or_init(|| std::sync::RwLock::new(std::collections::HashSet::new()))
}

/// Record `order_id` as absent, keeping the set within its ceiling.
///
/// Dropping everything when full is deliberate: this is a cache, so the worst
/// an eviction costs is one extra storage read, and that is cheaper than
/// tracking insertion order for entries nobody will ask about twice.
fn record_miss(misses: &mut std::collections::HashSet<String>, order_id: &str) {
    if misses.len() >= TRADE_KEY_MISS_CAPACITY {
        misses.clear();
    }
    misses.insert(order_id.to_string());
}

fn note_trade_key_miss(order_id: &str) {
    if let Ok(mut misses) = trade_key_misses().write() {
        record_miss(&mut misses, order_id);
    }
}

fn forget_trade_key_miss(order_id: &str) {
    if let Ok(mut misses) = trade_key_misses().write() {
        misses.remove(order_id);
    }
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
    // This is the only way an id goes from absent to present, so it is the
    // only place the negative cache has to be invalidated.
    forget_trade_key_miss(order_id);
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
    let found = lookup_trade_key_index(order_id).await;
    if found.is_none() {
        log::warn!("[orders] trade key not found for order={order_id}");
    }
    found
}

/// `get_trade_key_index` without the not-found warning, for callers where a
/// missing binding is an expected state rather than an error (the dispatch
/// generation gate: a create's confirmation arrives before any binding
/// exists for the daemon id).
async fn lookup_trade_key_index(order_id: &str) -> Option<u32> {
    // Fast path: in-memory cache.
    if let Some(idx) = trade_key_map()
        .read()
        .ok()
        .and_then(|m| m.get(order_id).copied())
    {
        return Some(idx);
    }
    // Known absent: skip the round trip.
    if trade_key_misses()
        .read()
        .is_ok_and(|misses| misses.contains(order_id))
    {
        return None;
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
            Ok(None) => note_trade_key_miss(order_id),
            // Deliberately not cached: a failed read is not evidence of
            // absence, and caching it would strand the order as "not ours".
            Err(e) => log::warn!("[orders] DB trade key lookup failed for order={order_id}: {e}"),
        }
    }
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

// ── Per-order dispatch serialization ─────────────────────────────────────────

/// One mutex per `order_id`, guarding the validate-then-mutate sequences that
/// daemon-message dispatch and `take_order` run over the order book, the trade
/// row and the session.
///
/// Those sequences check first (terminal-status gate, local-status lookup) and
/// mutate several `await`s later. Without serialization a delivery that passed
/// the check can be overtaken by a retake of the same order id while it is
/// suspended: the retake persists its own book / DB / session state, then the
/// suspended handler resumes and writes the previous generation's outcome over
/// it (#259).
///
/// The registry is a *synchronous* mutex holding `Arc`s of asynchronous ones,
/// and is never held across an `await`. What callers hold across awaits is the
/// per-order guard, which is a `tokio::sync::Mutex` for exactly that reason.
static ORDER_LOCKS: OnceLock<std::sync::Mutex<HashMap<String, Arc<tokio::sync::Mutex<()>>>>> =
    OnceLock::new();

fn order_locks() -> &'static std::sync::Mutex<HashMap<String, Arc<tokio::sync::Mutex<()>>>> {
    ORDER_LOCKS.get_or_init(|| std::sync::Mutex::new(HashMap::new()))
}

/// Acquire the per-order lock for `order_id`, waiting for any in-flight
/// handler of the same order to finish.
///
/// Entries the registry is the last owner of are dropped while the map is
/// held, so the map tracks orders with live work rather than every order ever
/// dispatched. A poisoned registry falls back to a private lock: losing
/// serialization for one message beats panicking the dispatch task.
///
/// Callers must not hold this guard while waiting on a daemon reply — the
/// reply is delivered by `dispatch_mostro_message`, which takes the same lock.
async fn lock_order(order_id: &str) -> tokio::sync::OwnedMutexGuard<()> {
    let lock = {
        let Ok(mut map) = order_locks().lock() else {
            log::warn!(
                "[orders] order-lock registry poisoned — order={order_id} runs unserialized"
            );
            return Arc::new(tokio::sync::Mutex::new(())).lock_owned().await;
        };
        map.retain(|_, lock| Arc::strong_count(lock) > 1);
        Arc::clone(
            map.entry(order_id.to_string())
                .or_insert_with(|| Arc::new(tokio::sync::Mutex::new(()))),
        )
    };
    lock.lock_owned().await
}

/// Filter parameters for the order list.
#[derive(Debug, Clone, Default, serde::Serialize, serde::Deserialize)]
pub struct OrderFilters {
    pub kind: Option<OrderKind>,
    pub fiat_code: Option<String>,
    pub payment_method: Option<String>,
}

/// How long relay-driven book updates are collected before one snapshot is
/// published.
///
/// Short enough to read as immediate, long enough that a burst of 38383 events
/// costs one emission instead of one each. Only the relay firehose goes
/// through this: daemon-message handlers and user actions publish directly.
const PUBLISH_COALESCE_MS: u64 = 200;

/// Shared order cache + broadcast channel for UI updates.
pub struct OrderBook {
    orders: Arc<RwLock<Vec<OrderInfo>>>,
    tx: broadcast::Sender<Vec<OrderInfo>>,
    /// Set while a coalescing window is armed. Shared with the window's task,
    /// which clears it.
    publish_scheduled: Arc<AtomicBool>,
}

/// Snapshots retained for a subscriber that has fallen behind.
///
/// A cold-start or refetch burst publishes far more updates than the UI reads
/// in the same instant, so this is sized for that burst rather than for steady
/// state. While each message is a full snapshot, overflowing is survivable —
/// the newest snapshot supersedes the dropped ones. That stops being true if
/// this channel ever carries deltas.
const ORDER_STREAM_CAPACITY: usize = 64;

impl Default for OrderBook {
    fn default() -> Self {
        Self::new()
    }
}

impl OrderBook {
    pub fn new() -> Self {
        let (tx, _) = broadcast::channel(ORDER_STREAM_CAPACITY);
        Self {
            orders: Arc::new(RwLock::new(Vec::new())),
            tx,
            publish_scheduled: Arc::new(AtomicBool::new(false)),
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
        Self::apply_upsert(&mut orders, order);
        let snapshot = orders.clone();
        drop(orders);
        let _ = self.tx.send(snapshot);
    }

    /// Insert or update a single order **without** notifying listeners.
    ///
    /// For bulk ingest, where the caller publishes once at the end. Every
    /// message on this channel is a whole-book snapshot, so publishing per
    /// event during a refetch of N orders costs N clones of an N-element
    /// vector and N full payloads across the bridge.
    pub(crate) async fn upsert_order_deferred(&self, order: OrderInfo) {
        let mut orders = self.orders.write().await;
        Self::apply_upsert(&mut orders, order);
    }

    /// Insert or update a single order, publishing at most once per
    /// [`PUBLISH_COALESCE_MS`] window.
    ///
    /// For the relay firehose, where events arrive far faster than anyone can
    /// read them and every emission carries the whole book. The window is
    /// trailing: the burst that opens it is published when it closes, so the
    /// subscriber sees the settled book rather than each intermediate state.
    pub(crate) async fn upsert_order_coalesced(&self, order: OrderInfo) {
        self.upsert_order_deferred(order).await;
        self.schedule_publish();
    }

    /// Arm the coalescing window, unless one is already running.
    fn schedule_publish(&self) {
        if self.publish_scheduled.swap(true, Ordering::AcqRel) {
            return;
        }
        let orders = Arc::clone(&self.orders);
        let scheduled = Arc::clone(&self.publish_scheduled);
        let tx = self.tx.clone();
        crate::rt::spawn(async move {
            crate::rt::time::sleep(std::time::Duration::from_millis(PUBLISH_COALESCE_MS)).await;
            // Released before the snapshot is taken, so an update arriving
            // during the read opens a new window instead of being swallowed.
            scheduled.store(false, Ordering::Release);
            let snapshot = orders.read().await.clone();
            let _ = tx.send(snapshot);
        });
    }

    /// Publish the current book to subscribers.
    pub(crate) async fn publish(&self) {
        let snapshot = self.orders.read().await.clone();
        let _ = self.tx.send(snapshot);
    }

    fn apply_upsert(orders: &mut Vec<OrderInfo>, order: OrderInfo) {
        if let Some(existing) = orders.iter_mut().find(|o| o.id == order.id) {
            *existing = order;
        } else {
            orders.push(order);
        }
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

// ── Daemon-message deduplication ─────────────────────────────────────────────

/// Sized for the global feed's history replay on reused keys: a mass replay
/// longer than this window would evict ids that a slower relay may still
/// redeliver within the same session.
const DEDUP_MAX_ENTRIES: usize = 512;

/// Recently processed daemon-message event IDs, so an event delivered by both
/// the per-trade and the global subscription is only handled once.
///
/// `seen` answers the membership question; `order` exists only to know which
/// id to drop when the window is full. Both hold the same `Arc<str>`, so a new
/// id is allocated once, and `record` is the only thing that writes them —
/// split those two writes across call sites and `seen` grows without bound.
///
/// `frb(ignore)` because this module is part of `crate::api`, which
/// flutter_rust_bridge scans: without it the codegen emits bindings for this
/// private, non-bridgeable type and the wasm build stops compiling.
#[derive(Default)]
#[flutter_rust_bridge::frb(ignore)]
struct DedupWindow {
    seen: std::collections::HashSet<Arc<str>>,
    order: std::collections::VecDeque<Arc<str>>,
}

impl DedupWindow {
    /// Returns `true` if `event_id` is already in the window. Otherwise records
    /// it — evicting the oldest id when the window is full — and returns
    /// `false`.
    fn record(&mut self, event_id: &str) -> bool {
        if self.seen.contains(event_id) {
            return true;
        }
        let id: Arc<str> = Arc::from(event_id);
        self.seen.insert(Arc::clone(&id));
        self.order.push_back(id);
        if self.order.len() > DEDUP_MAX_ENTRIES {
            if let Some(evicted) = self.order.pop_front() {
                self.seen.remove(&evicted);
            }
        }
        false
    }
}

static PROCESSED_GW: OnceLock<std::sync::Mutex<DedupWindow>> = OnceLock::new();

/// Returns `true` if this event ID was already processed (duplicate).
/// Otherwise records it and returns `false`.
fn is_duplicate_daemon_message(event_id: &str) -> bool {
    let window = PROCESSED_GW.get_or_init(|| std::sync::Mutex::new(DedupWindow::default()));
    match window.lock() {
        Ok(mut guard) => guard.record(event_id),
        Err(_) => false,
    }
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
pub async fn create_order(mut params: NewOrderParams) -> Result<OrderInfo> {
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
    // #175: validate the fiat code before publishing, so a stale or tampered
    // saved default is rejected locally with a stable InvalidFiatCode marker
    // (Dart localizes it) instead of going out and coming back as a daemon
    // CantDo. Reuses the settings validator so every caller inherits the check.
    // Format-level (ISO 4217 shape) only. Membership belongs against the
    // daemon's advertised supported_currencies — authoritative and free of
    // bundled-list drift — tracked as a follow-up (#380), not a Rust copy of
    // assets/data/fiat.json.
    //
    // Normalize in place first so validation and publication see the SAME value:
    // otherwise " USD " clears the trimmed check but the padded code is what
    // flows into order.fiat_code and the dispatch clone below (#304 review, B3).
    params.fiat_code = params.fiat_code.trim().to_string();
    crate::api::settings::validate_fiat_code(&params.fiat_code)?;
    if params.payment_method.trim().is_empty() {
        return Err(anyhow::anyhow!("payment_method must not be empty"));
    }

    // Build a local OrderInfo representing the newly created order.
    // In Phase 7, this will be replaced by the actual Mostro response
    // after the NIP-59 message is published and acknowledged.
    let now = crate::rt::unix_now();

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
        // Own new order: the daemon's Kind 38383 confirmation carries the
        // real reputation snapshot; until then there is none to show.
        rating: 0.0,
        total_reviews: 0,
        days_active: 0,
    };

    // Compatibility preflight (PR #252 review): refuse an unsupported node
    // BEFORE deriving or persisting anything. The wrap re-checks as a defense,
    // but by that point the trade-key index and the content fingerprint below
    // are already stored — durably — and a bail there would leave orphaned
    // maker-ownership records that any later public order with the same
    // kind/currency/amount/payment-method fingerprint would match as "mine".
    crate::mostro::protocol_version::ensure_supported(&active_mostro_pubkey()).await?;

    // Derive a fresh trade key — each order must use a unique derived key index
    // so the daemon can verify the trade index in the message.
    let trade_key_info = crate::api::identity::derive_trade_key().await?;
    let trade_index = trade_key_info.index;
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    // Fresh key: join the bulk Kind-14 coverage now, so daemon messages for
    // it (e.g. a late admin-took-dispute) outlive the temporary per-trade
    // receiver (PR #253 review).
    ensure_global_dm_coverage(&sender_keys, trade_index).await;

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
    let identity_keys = crate::api::identity::get_transport_identity_keys(&sender_keys).await?;

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
    let (conf_tx, conf_rx) = tokio::sync::oneshot::channel::<Wake>();
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

    // Subscribe to daemon responses AFTER registering the confirmation
    // channel so that any events (including stale ones replayed by relays)
    // find the entry and notify us instead of being silently discarded.
    subscribe_daemon_messages(sender_keys.public_key(), trade_index).await;

    if let Err(e) = publish_event_json(&event_json).await {
        // Rollback all in-memory bookkeeping on publish failure.
        if let Ok(mut m) = trade_key_map().write() {
            m.remove(&order.id);
            m.remove(&ck);
        }
        remove_pending_request(&trade_pk_hex, request_id);
        return Err(e);
    }

    crate::api::logging::blog_info(
        "orders",
        format!(
            "create_order published id={} trade_index={trade_index} — waiting for daemon",
            order.id
        ),
    );

    // Wait for daemon confirmation. The daemon typically responds within 1s.
    // The 10s timeout is a safety net for network issues; on timeout the order
    // is treated as not created (see below) rather than shown optimistically.
    let confirmation = crate::rt::time::timeout(std::time::Duration::from_secs(10), conf_rx).await;

    // On success or rejection the dispatcher already consumed the record
    // (take_matching_request). On timeout, detach only the waiter channel and
    // leave the record in place: a genuine late reply must still be able to
    // reconcile the trade-key and id bindings, and only the echoed nonce can
    // consume what remains — a stale replay still cannot. The record's
    // lifetime is bounded by the per-trade subscription (see
    // subscribe_daemon_messages), which removes it when the subscription ends.
    if !matches!(confirmation, Ok(Ok(_))) {
        detach_request_waiter(&trade_pk_hex, request_id);
    }

    // Resolve the daemon's verdict. The order only exists once the daemon
    // confirms it; a timeout means "no response", not an optimistic success.
    let daemon_id = match confirmation {
        Ok(Ok(Wake {
            reply: DaemonReply::Confirmed { daemon_id },
            ..
        })) => {
            crate::api::logging::blog_info(
                "orders",
                format!("create_order confirmed by daemon: {daemon_id}"),
            );
            daemon_id
        }
        Ok(Ok(Wake {
            reply: DaemonReply::Rejected { reason, message },
            ..
        })) => {
            crate::api::logging::blog_warn(
                "orders",
                format!("create_order rejected: {reason} — {message}"),
            );
            return Err(anyhow::anyhow!("{message}"));
        }
        _ => {
            // No daemon response within the timeout. Do not persist or show the
            // order — it was never published. Surface a stable marker the UI
            // maps to a localized "no response from Mostro" message.
            crate::api::logging::blog_warn(
                "orders",
                format!(
                    "create_order: no daemon response within 10s for id={}",
                    order.id
                ),
            );
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
        peer_rating: None,
        peer_reviews: None,
        peer_days: None,
        rated_at: None,
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
    if let Ok(keys) = crate::api::identity::get_active_trade_keys(trade_index).await {
        // Fresh key: join the bulk Kind-14 coverage now, so daemon messages
        // for it (e.g. a late admin-took-dispute) outlive the temporary
        // per-trade receiver (PR #253 review).
        ensure_global_dm_coverage(&keys, trade_index).await;
    }

    // Key/node/event failures now surface as errors: nothing has been
    // published yet, so pretending the take went through (the old behavior)
    // would show the user a trade that never existed.
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;
    let identity_keys = crate::api::identity::get_transport_identity_keys(&sender_keys).await?;

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
    let (conf_tx, conf_rx) = tokio::sync::oneshot::channel::<Wake>();
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

    // Subscribe to daemon responses addressed to this trade key so the
    // daemon's reply (and later BuyerTookOrder / HoldInvoicePaymentAccepted)
    // reaches the dispatcher.
    subscribe_daemon_messages(sender_keys.public_key(), trade_index).await;

    if let Err(e) = publish_event_json(&event_json).await {
        remove_pending_request(&trade_pk_hex, request_id);
        return Err(e);
    }

    crate::api::logging::blog_info(
        "orders",
        format!(
            "take_order published order={order_id} trade_index={trade_index} — \
         waiting for daemon"
        ),
    );

    // Wait for the daemon's verdict — the trade only exists once the daemon
    // acknowledges the take. On timeout, detach only the waiter and leave the
    // record: a genuine late reply is logged, a stale replay still can't
    // consume it, and the record dies with the per-trade subscription.
    let reply = crate::rt::time::timeout(std::time::Duration::from_secs(10), conf_rx).await;
    if !matches!(reply, Ok(Ok(_))) {
        detach_request_waiter(&trade_pk_hex, request_id);
    }

    let (status, amount_sats, hold_invoice, handed_guard) = match reply {
        Ok(Ok(Wake {
            reply:
                DaemonReply::TakeAccepted {
                    action,
                    status,
                    amount_sats,
                    hold_invoice,
                },
            order_guard,
        })) => {
            crate::api::logging::blog_info(
                "orders",
                format!("take_order confirmed by daemon: order={order_id} reply={action:?}"),
            );
            (status, amount_sats, hold_invoice, order_guard)
        }
        Ok(Ok(Wake {
            reply: DaemonReply::Rejected { reason, message },
            ..
        })) => {
            crate::api::logging::blog_warn(
                "orders",
                format!("take_order rejected: {reason} — {message}"),
            );
            return Err(anyhow::anyhow!("{message}"));
        }
        Ok(Ok(Wake {
            reply: DaemonReply::Confirmed { .. },
            ..
        })) => {
            // Only the create flow sends Confirmed; a take record can never
            // receive it. Treat defensively as an acceptance without data.
            log::warn!("[orders] take_order received a create-style confirmation");
            (None, None, None, None)
        }
        _ => {
            // No daemon response within the timeout. Do not persist or show
            // the trade — as far as the user is concerned the take failed.
            crate::api::logging::blog_warn(
                "orders",
                format!("take_order: no daemon response within 10s for order={order_id}"),
            );
            return Err(anyhow::anyhow!("NoDaemonResponse"));
        }
    };

    // Accepted: build the trade from the daemon's actual reply instead of
    // optimistic assumptions, then persist and wire up the trade session.
    let now = crate::rt::unix_now();
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
        peer_rating: None,
        peer_reviews: None,
        peer_days: None,
        rated_at: None,
    };

    // The other side of the race guarded in `dispatch_mostro_message`: this
    // block is the "retake is accepted and persists its state" step. Taking the
    // same per-order lock keeps it from landing between a daemon handler's
    // check and its write, and keeps that handler from landing between ours
    // (#259).
    //
    // Normally the guard arrives WITH the reply: the dispatcher that consumed
    // it hands its own guard through the waiter channel, so no other handler
    // of this order can slot in between the reply and this persistence (a
    // queued one would otherwise win the FIFO mutex over this woken task).
    // Acquired here only as the fallback for a reply that carried no guard
    // (no order id on the reply), and never around the wait itself: the reply
    // is delivered by `dispatch_mostro_message`, which takes this very lock —
    // holding it while waiting would deadlock the take.
    let _order_guard = match handed_guard {
        Some(guard) => guard,
        None => lock_order(&order_id).await,
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
    // Subscribe to d-tag K38383 updates for this specific order so we still
    // see the public buckets the daemon does publish (in-progress once taken,
    // success / canceled at the end); the fine-grained states only ever arrive
    // as daemon messages.
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
    let identity_keys = crate::api::identity::get_transport_identity_keys(&sender_keys).await?;
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
    let (conf_tx, conf_rx) = tokio::sync::oneshot::channel::<Wake>();
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
    crate::api::logging::blog_info(
        "orders",
        format!(
            "add_invoice published for order={} trade_index={trade_index} \
             ln_address={} amount={:?} — waiting for daemon",
            crate::api::logging::short_id(&order_id),
            invoice_or_address.contains('@'),
            amount_opt
        ),
    );

    // Wait for the daemon's verdict: a rejected invoice (e.g. InvalidInvoice)
    // must surface instead of letting the UI advance on a publish that the
    // daemon errored on. Timeout keeps the record for a late reply, which the
    // dispatcher processes as a normal status update.
    let reply = crate::rt::time::timeout(std::time::Duration::from_secs(10), conf_rx).await;
    if !matches!(reply, Ok(Ok(_))) {
        detach_request_waiter(&trade_pk_hex, request_id);
    }

    match reply {
        Ok(Ok(Wake {
            reply: DaemonReply::Rejected { reason, message },
            ..
        })) => {
            crate::api::logging::blog_warn(
                "orders",
                format!("add_invoice rejected: {reason} — {message}"),
            );
            Err(anyhow::anyhow!("{message}"))
        }
        Ok(Ok(_)) => {
            crate::api::logging::blog_info(
                "orders",
                format!("add_invoice acknowledged by daemon for order={order_id}"),
            );
            Ok(())
        }
        _ => {
            crate::api::logging::blog_warn(
                "orders",
                format!("add_invoice: no daemon response within 10s for order={order_id}"),
            );
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
    let identity_keys = crate::api::identity::get_transport_identity_keys(&sender_keys).await?;
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
    crate::api::logging::blog_info(
        "orders",
        format!(
            "fiat_sent published for order={} trade_index={trade_index}",
            crate::api::logging::short_id(&order_id),
        ),
    );
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
    let identity_keys = crate::api::identity::get_transport_identity_keys(&sender_keys).await?;
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
    crate::api::logging::blog_info(
        "orders",
        format!(
            "release published for order={} trade_index={trade_index}",
            crate::api::logging::short_id(&order_id),
        ),
    );
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
    let identity_keys = crate::api::identity::get_transport_identity_keys(&sender_keys).await?;
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
    // so the UI reflects the change without waiting for the daemon's
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
            log::warn!(
                "[orders] failed to optimistically update cancel status for {order_id}: {e}"
            );
        }
    }

    crate::api::logging::blog_info(
        "orders",
        format!(
            "cancel published for order={} trade_index={trade_index}",
            crate::api::logging::short_id(&order_id),
        ),
    );
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
pub(crate) async fn subscribe_daemon_messages(
    trade_pubkey: nostr_sdk::PublicKey,
    trade_index: u32,
) {
    // ── Synchronous setup: awaited by the caller ──
    let recipient_keys = match crate::api::identity::get_active_trade_keys(trade_index).await {
        Ok(k) => k,
        Err(e) => {
            log::error!("[orders] subscribe_daemon_messages: no trade keys: {e}");
            return;
        }
    };

    let Ok(pool) = crate::api::nostr::get_pool() else {
        log::warn!("[orders] subscribe_daemon_messages: relay pool not initialized");
        return;
    };
    let client = pool.client();

    let mostro_pubkey = match nostr_sdk::PublicKey::from_hex(&crate::config::active_mostro_pubkey())
    {
        Ok(pk) => pk,
        Err(e) => {
            log::error!("[orders] subscribe_daemon_messages: invalid mostro pubkey: {e}");
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
        log::warn!("[orders] subscribe_daemon_messages subscribe failed: {e}");
        return;
    }

    let trade_pubkey_hex = trade_pubkey.to_hex();
    crate::api::logging::blog_info(
        "orders",
        format!(
            "daemon-message subscription active for trade={}",
            &trade_pubkey_hex[..8]
        ),
    );

    // ── Event loop: spawned as a background task ──
    crate::rt::spawn(async move {
        use crate::rt::time::{timeout, Duration};
        use nostr_sdk::RelayPoolNotification;

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
                    if is_duplicate_daemon_message(&eid) {
                        crate::api::logging::blog_debug(
                            "daemon-msg",
                            format!(
                                "drop ev={} reason=duplicate",
                                crate::api::logging::short_id(&eid)
                            ),
                        );
                        continue;
                    }
                    crate::api::logging::blog_info(
                        "daemon-msg",
                        format!(
                            "Kind 14 received (per-trade) for trade={} from={} event_id={}",
                            &trade_pubkey_hex[..8],
                            &event.pubkey.to_hex()[..8],
                            &eid[..16],
                        ),
                    );
                    match crate::nostr::transport::unwrap_mostro_message(&recipient_keys, &event)
                        .await
                    {
                        Ok(Some(unwrapped)) => {
                            dispatch_mostro_message(
                                unwrapped,
                                &eid,
                                &trade_pubkey_hex,
                                trade_index,
                            )
                            .await;
                            last_activity = crate::rt::time::Instant::now();
                        }
                        Ok(None) => {
                            // The per-trade filter already narrowed by p-tag, so this
                            // only fires if a relay delivers a wrap whose outer NIP-44
                            // layer doesn't decrypt under our key — not actionable, and
                            // cheap for a hostile relay to spam. Keep it at debug.
                            crate::api::logging::blog_debug(
                                "daemon-msg",
                                format!(
                                    "decrypt returned None for trade={}",
                                    &trade_pubkey_hex[..8]
                                ),
                            );
                        }
                        Err(e) => crate::api::logging::blog_warn(
                            "daemon-msg",
                            format!("decrypt failed for trade={}: {e}", &trade_pubkey_hex[..8]),
                        ),
                    }
                }
                Ok(Ok(RelayPoolNotification::Shutdown)) => break,
                Ok(Err(broadcast::error::RecvError::Lagged(n))) => {
                    log::warn!("[orders] daemon-msg lagged by {n} messages");
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
/// `crate::nostr::transport::unwrap_mostro_message`, which verifies the kind-14
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
            crate::api::logging::blog_warn(
                "daemon-msg",
                format!(
                    "rejecting daemon message: sender={} != active mostro={} (trade={})",
                    &sender.to_hex()[..8],
                    &expected.to_hex()[..8],
                    &trade_pubkey_hex[..8],
                ),
            );
            return;
        }
        Err(e) => {
            crate::api::logging::blog_warn(
                "daemon-msg",
                format!("active mostro pubkey is invalid: {e} — cannot authenticate the sender"),
            );
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
            crate::api::logging::blog_warn(
                "daemon-msg",
                format!(
                    "validate_response rejected message for trade={}: {e:?}",
                    &trade_pubkey_hex[..8]
                ),
            );
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
    crate::api::logging::blog_info(
        "daemon-msg",
        format!(
            "action={:?} order_id={:?} trade_index={:?} trade_pubkey={} payload={}",
            kind.action,
            kind.id,
            kind.trade_index,
            &trade_pubkey_hex[..8],
            payload_desc
        ),
    );

    // Everything below is serialized against other handlers of this order id:
    // the reconcile block, the waiter interception and the per-action arms all
    // check local state first and mutate it several `await`s later, so without
    // the guard a retake of the same order can be accepted in between and have
    // the suspended handler write the previous generation's outcome over its
    // book entry, trade row and session (#259).
    //
    // Held until this function returns, and taken here rather than at the top
    // because the order id only exists once the message kind is parsed.
    // Messages with no order id own no order state, so they take no lock.
    let mut order_guard = match &kind.id {
        Some(order_id) => Some(lock_order(&order_id.to_string()).await),
        None => None,
    };

    // Generation gate, read UNDER the lock so it cannot interleave with a
    // retake's rebind: a message addressed to a trade key OLDER than the one
    // currently bound to this order belongs to a superseded attempt — e.g.
    // the trailing Canceled of a take that was replaced — and its writes are
    // stale by definition, lock or no lock. Strictly-older only: a retake's
    // first reply arrives on the NEW key while the binding still holds the
    // old index (`take_order` rebinds after this very reply resolves its
    // waiter), and the identity counter only grows, so a later attempt
    // always carries a higher index. No binding fails open — a create's
    // confirmation precedes any binding for the daemon id, and the nonce
    // gates below own correlation. BondSlashed is exempt: it never writes
    // order state, and a trailing slash notice addressed to the slashed
    // (superseded) generation is by-design delivery (#197).
    if kind.action != Action::BondSlashed {
        if let Some(order_id) = &kind.id {
            let oid = order_id.to_string();
            if let Some(bound) = lookup_trade_key_index(&oid).await {
                if trade_index < bound {
                    crate::api::logging::blog_info(
                        "daemon-msg",
                        format!(
                            "drop {:?} order={}: addressed to superseded trade key \
                         (idx {} < bound {})",
                            kind.action,
                            crate::api::logging::short_id(&oid),
                            trade_index,
                            bound,
                        ),
                    );
                    return;
                }
            }
        }
    }

    // Reconcile local UUID → daemon UUID if needed.  Daemon actions
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
                crate::api::logging::blog_info(
                    "daemon-msg",
                    format!(
                        "{:?}: notified waiting take_order for trade={}",
                        kind.action,
                        &trade_pubkey_hex[..8]
                    ),
                );
                // Hand THIS dispatcher's per-order guard to the woken
                // take_order along with the reply, so its persistence runs in
                // the same critical section that consumed the reply. Released
                // here, a second daemon message already queued on the mutex
                // would beat the woken task to it (tokio's Mutex is FIFO) and
                // run its arm against a trade row and session that do not
                // exist yet. A failed send (the waiter timed out) returns the
                // Wake, dropping the guard right here.
                let _ = tx.send(crate::mostro::pending::Wake {
                    reply,
                    order_guard: order_guard.take(),
                });
            } else {
                // Genuine reply after the 10s timeout: the caller already
                // returned NoDaemonResponse and persisted nothing, so there
                // is nothing to reconcile for a take — just log it.
                crate::api::logging::blog_info(
                    "daemon-msg",
                    format!(
                        "{:?}: late reply for timed-out take on trade={} — ignoring",
                        kind.action,
                        &trade_pubkey_hex[..8]
                    ),
                );
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
                crate::api::logging::blog_info(
                    "daemon-msg",
                    format!(
                        "{:?}: acknowledged waiting send_invoice for trade={}",
                        kind.action,
                        &trade_pubkey_hex[..8]
                    ),
                );
                let _ = tx.send(Wake::from(DaemonReply::Acknowledged));
            } else {
                crate::api::logging::blog_info(
                    "daemon-msg",
                    format!(
                        "{:?}: late acknowledgement for timed-out add-invoice on trade={}",
                        kind.action,
                        &trade_pubkey_hex[..8]
                    ),
                );
            }
        }

        // A dispute's only success reply is DisputeInitiatedByYou, so the arm
        // gates on that action as well as on the nonce — anything else leaves
        // the record for the genuine reply rather than unblocking the caller
        // on a message that is not an acceptance. Falls through like an
        // add-invoice: the reply is also the status update that moves the
        // order to Dispute.
        //
        // DisputeInitiatedByPeer echoes the same nonce but the daemon
        // addresses it to the counterparty's trade key, which has no pending
        // record of ours (mostro src/app/dispute.rs, notify_dispute_to_users).
        if kind.action == Action::DisputeInitiatedByYou {
            match take_matching_dispute(trade_pubkey_hex, kind.request_id) {
                Some(DisputeMatch::Waiting(tx)) => {
                    crate::api::logging::blog_info(
                        "daemon-msg",
                        format!(
                            "DisputeInitiatedByYou: accepted waiting open_dispute for trade={}",
                            &trade_pubkey_hex[..8]
                        ),
                    );
                    let _ = tx.send(Wake::from(DaemonReply::DisputeAccepted {
                        dispute_id: dispute_id_from_payload(kind.payload.as_ref()),
                    }));
                }
                // Genuine acceptance after the 10s timeout — of this attempt or
                // of an earlier one a retry superseded. The caller already
                // returned NoDaemonResponse and persisted no dispute. Record it
                // now: the status arm below moves the trade to Dispute
                // regardless, and a disputed trade with no dispute record has no
                // solver to reach (PR #275 review).
                Some(DisputeMatch::Late) => {
                    crate::api::logging::blog_warn("daemon-msg", format!(
                        "DisputeInitiatedByYou: late acceptance for timed-out open_dispute on trade={}",
                        &trade_pubkey_hex[..8]
                    ));
                    if let Some(order_id) = kind.id.map(|id| id.to_string()) {
                        crate::api::disputes::record_late_acceptance(
                            &order_id,
                            dispute_id_from_payload(kind.payload.as_ref()),
                        )
                        .await;
                    }
                }
                None => {}
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
                        let _ = tx.send(Wake::from(DaemonReply::Confirmed {
                            daemon_id: daemon_id.clone(),
                        }));
                        crate::api::logging::blog_info("daemon-msg", format!(
                            "NewOrder: notified waiting create_order daemon={daemon_id}"
                        ));
                    } else {
                        // Genuine reply after the 10s timeout: the caller
                        // already returned NoDaemonResponse and persisted
                        // nothing, so there is no local order to rebind —
                        // the trade-key binding above plus the Kind 38383
                        // fingerprint path restore maker ownership.
                        crate::api::logging::blog_info("daemon-msg", format!(
                            "NewOrder: late confirmation for timed-out create \
                             local={local_uuid} daemon={daemon_id}"
                        ));
                    }
                } else {
                    // Cold start / reconnect (no record — in-memory state is
                    // empty after a restart), or an uncorrelated event that
                    // must not consume anything. The Kind 38383 fingerprint
                    // path owns maker-order recovery in both cases.
                    crate::api::logging::blog_info("daemon-msg", format!(
                        "NewOrder: daemon order={daemon_id} with no matching \
                         pending create — leaving state untouched"
                    ));
                }
            } else {
                log::warn!("[orders] daemon-msg NewOrder has no order id");
            }
        }
        Action::RestoreSession => {
            // Daemon's restore reply (mostro send_restore_session_response ->
            // Message::new_restore(RestoreData), addressed to the sending trade
            // key). Correlated by trade pubkey only — RestoreSession carries no
            // request_id — so take_matching_restore skips the nonce gate.
            match &kind.payload {
                Some(mostro_core::message::Payload::RestoreData(info)) => {
                    if let Some(pending) = take_matching_restore(trade_pubkey_hex) {
                        if let Some(tx) = pending.tx {
                            let _ = tx.send(Wake::from(DaemonReply::Restored(info.clone())));
                            crate::api::logging::blog_info("daemon-msg", format!(
                                "RestoreData: notified waiting restore_session ({} orders, {} disputes)",
                                info.restore_orders.len(),
                                info.restore_disputes.len()
                            ));
                        } else {
                            // Post-timeout late reply: the caller already
                            // returned NoDaemonResponse and detached its waiter.
                            // Logged for parity with the NewOrder/take/add-invoice arms.
                            crate::api::logging::blog_info("daemon-msg", format!(
                                "RestoreData: late reply for timed-out restore on trade={}",
                                trade_pubkey_hex.get(..8).unwrap_or(trade_pubkey_hex)
                            ));
                        }
                    } else {
                        crate::api::logging::blog_info("daemon-msg", format!(
                            "RestoreData with no waiting caller for trade={}",
                            trade_pubkey_hex.get(..8).unwrap_or(trade_pubkey_hex)
                        ));
                    }
                }
                _ => {
                    log::warn!(
                        "[orders] RestoreSession reply payload is not RestoreData for trade={trade_pubkey_hex}"
                    );
                }
            }
        }
        Action::Canceled => {
            log::info!("[orders] daemon-msg Canceled for trade={trade_pubkey_hex}");
            if let Some(order_id) = &kind.id {
                let oid = order_id.to_string();
                // A stale Canceled replayed over a finished trade — e.g. the
                // taker-timeout cancel of an order that was later re-taken
                // and completed — must not overwrite the terminal outcome.
                // The wipe path below is unaffected: it starts from
                // pending/waiting, which are not terminal.
                if status_sync_blocked_by_terminal(&oid, &kind.action).await {
                    return;
                }
                // Deliberately NOT removed from the order book. The book is
                // fed only by the daemon's Kind 38383 events, and on a
                // taker-responsible timeout mostrod republishes the order as
                // `pending` BEFORE sending this Canceled (scheduler.rs:
                // update_order_event, then notify) — a blind remove here
                // races that republish and leaves the order missing from the
                // book until restart. A genuine cancel arrives as a 38383
                // status update and the UI already filters non-pending.
                if let Some(db) = crate::db::app_db::db() {
                    let local_status = match db.get_trade_by_order_id(&oid).await {
                        Ok(Some(trade)) => Some(trade.order.status),
                        Ok(None) => None,
                        Err(e) => {
                            log::warn!("[orders] Canceled: trade lookup failed for {oid}: {e}");
                            None
                        }
                    };
                    if local_status
                        .as_ref()
                        .is_some_and(cancellation_wipes_history)
                    {
                        // The trade never went active (no peer, no chat, no
                        // exchange — typically a waiting-state timeout):
                        // wipe it instead of keeping a meaningless
                        // Canceled history row. Mirrors v1, which deletes
                        // pending/waiting sessions on cancel.
                        match db.delete_trade_by_order_id(&oid).await {
                            Ok(()) => crate::api::logging::blog_info(
                                "orders",
                                format!(
                                    "Canceled before active — removed trade for order={oid}"
                                ),
                            ),
                            Err(e) => log::warn!(
                                "[orders] failed to remove canceled trade for {oid}: {e}"
                            ),
                        }
                        crate::mostro::session::session_manager()
                            .remove_session(&oid)
                            .await;
                    } else {
                        // Sync the Canceled status into the trade DB so My
                        // Trades reflects the cancellation immediately.
                        crate::api::logging::blog_info(
                            "orders",
                            format!(
                                "status order={} →Canceled src=kind14/Canceled (history kept)",
                                crate::api::logging::short_id(&oid),
                            ),
                        );
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
                // Push the cancellation to Dart: after a wipe there is no DB
                // row left to poll, and after a timeout republish the book
                // reads `pending` — screens need this signal either way.
                emit_trade_update(&oid, crate::api::types::OrderStatus::Canceled);
            }
        }
        // Seller receives BuyerTookOrder → peer is buyer_trade_pubkey.
        // Buyer receives HoldInvoicePaymentAccepted → peer is seller_trade_pubkey.
        // Both carry the counterpart pubkey in SmallOrder.{buyer,seller}_trade_pubkey.
        Action::BuyerTookOrder | Action::HoldInvoicePaymentAccepted => {
            let order_id = match &kind.id {
                Some(id) => id.to_string(),
                None => {
                    log::warn!("[orders] daemon-msg {:?} has no order id", kind.action);
                    return;
                }
            };
            // Before ANY side effect — a stale replay over a finished trade
            // must not re-derive the peer key, recreate session state, or
            // respawn the chat subscription either (the legit re-take of a
            // timeout-canceled order is unaffected: its wiped row leaves the
            // book's `pending` as the local status, which passes).
            if status_sync_blocked_by_terminal(&order_id, &kind.action).await {
                return;
            }
            let small_order = match &kind.payload {
                Some(mostro_core::message::Payload::Order(o)) => o.clone(),
                _ => {
                    log::warn!(
                        "[orders] daemon-msg {:?} payload is not an Order",
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
                        "[orders] daemon-msg {:?}: missing peer pubkey in payload",
                        kind.action
                    );
                    return;
                }
            };
            log::info!(
                "[orders] daemon-msg {:?}: order={order_id} peer={peer_pubkey_hex}",
                kind.action
            );
            // Derive the ECDH shared key and store in session so the chat API
            // can encrypt/decrypt P2P messages and subscribe to the right p-tag.
            on_peer_pubkey_received(&order_id, &peer_pubkey_hex).await;

            // Sync the order status from the payload so the trade doesn't stay
            // stuck at Pending in the DB and in-memory order book. Both actions
            // mean the escrow is locked, so a payload without an explicit
            // status still implies Active.
            if let Some(new_status) = small_order
                .status
                .and_then(map_core_status)
                .or_else(|| status_for_action(&kind.action))
            {
                crate::api::logging::blog_info(
                    "orders",
                    format!(
                        "status order={} →{new_status:?} src=kind14/{:?}",
                        crate::api::logging::short_id(&order_id),
                        kind.action,
                    ),
                );
                order_book().update_order_status(&order_id, new_status.clone()).await;
                if let Some(db) = crate::db::app_db::db() {
                    if let Err(e) = db
                        .update_trade_fields(&order_id, Some(new_status.clone()), None, None)
                        .await
                    {
                        log::warn!(
                            "[orders] failed to sync status for order={order_id}: {e}"
                        );
                    }
                }
                emit_trade_update(&order_id, new_status);
            }
        }
        // Mostro asks the buyer for a Lightning invoice with AddInvoice. A
        // taker's first copy is consumed by the take waiter as the take
        // reply; this arm covers the maker-buyer, whose buy order was taken
        // and the hold invoice paid. The message arrives on the global feed
        // with no trade_index, so the order id is the only usable key.
        Action::AddInvoice => {
            let order_id = match &kind.id {
                Some(id) => id.to_string(),
                None => {
                    log::warn!("[orders] daemon-msg AddInvoice has no order id");
                    return;
                }
            };
            let Some((new_status, amount)) = add_invoice_sync(&kind.payload) else {
                // The daemon follows up with a second AddInvoice carrying a
                // Peer payload: the counterparty's (taker's) reputation
                // snapshot (issue #305). Persist it so the add-invoice screen
                // and trade detail can show who took the order.
                if let Some((rating, reviews, days)) = peer_reputation(&kind.payload) {
                    persist_peer_reputation(&order_id, rating, reviews, days).await;
                } else {
                    log::debug!(
                        "[orders] daemon-msg AddInvoice for order={order_id}: no Order or Peer payload, ignoring"
                    );
                }
                return;
            };
            if status_sync_blocked_by_terminal(&order_id, &kind.action).await {
                return;
            }
            crate::api::logging::blog_info(
                "orders",
                format!(
                    "status order={} →{new_status:?} src=kind14/AddInvoice",
                    crate::api::logging::short_id(&order_id),
                ),
            );
            // Sync the book with status AND calculated sats: the add-invoice
            // screen polls the book for the amount (tradeAmountProvider) and
            // refuses to submit an LN address without it.
            if let Some(mut info) = order_book().get_order(&order_id).await {
                info.status = new_status.clone();
                if amount.is_some() {
                    info.amount_sats = amount;
                }
                order_book().upsert_order(info).await;
            }
            if let Some(db) = crate::db::app_db::db() {
                if let Err(e) = db
                    .update_trade_fields(&order_id, Some(new_status.clone()), None, amount)
                    .await
                {
                    log::warn!(
                        "[orders] failed to sync add-invoice for order={order_id}: {e}"
                    );
                }
            }
            // After the book update and the DB attempt, so a listener that
            // reacts to the push (e.g. auto-opening the add-invoice screen)
            // reads the freshest state available; a logged DB failure does
            // not suppress the notification.
            emit_trade_update(&order_id, new_status);
        }
        // Mostro sends PayInvoice to the seller with the hold invoice bolt11
        // when a buyer takes a sell order (or a seller takes a buy order).
        Action::PayInvoice => {
            let order_id = match &kind.id {
                Some(id) => id.to_string(),
                None => {
                    log::warn!("[orders] daemon-msg PayInvoice has no order id");
                    return;
                }
            };
            let (bolt11, amount) = match &kind.payload {
                Some(mostro_core::message::Payload::PaymentRequest(small_order, pr, amt)) => {
                    let sats = amt.and_then(|a| {
                        u64::try_from(a).ok().or_else(|| {
                            log::warn!(
                                "[orders] daemon-msg PayInvoice: negative amount {a}, ignoring"
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
                    // Like AddInvoice, the daemon follows up with a Peer
                    // payload carrying the counterparty's (taker's) reputation
                    // (issue #305). Persist it for the pay-invoice screen and
                    // trade detail rather than discarding the whole message.
                    if let Some((rating, reviews, days)) = peer_reputation(&kind.payload) {
                        persist_peer_reputation(&order_id, rating, reviews, days).await;
                    } else {
                        log::warn!(
                            "[orders] daemon-msg PayInvoice payload is not a PaymentRequest"
                        );
                    }
                    return;
                }
            };
            log::info!(
                "[orders] daemon-msg PayInvoice: order={order_id} invoice_len={} amount={:?}",
                bolt11.len(),
                amount
            );
            if status_sync_blocked_by_terminal(&order_id, &kind.action).await {
                return;
            }
            // Save the hold invoice and update status to WaitingPayment.
            crate::api::logging::blog_info(
                "orders",
                format!(
                    "status order={} →WaitingPayment src=kind14/PayInvoice",
                    crate::api::logging::short_id(&order_id),
                ),
            );
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
            emit_trade_update(&order_id, crate::api::types::OrderStatus::WaitingPayment);
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
                    log::debug!("[orders] daemon-msg {:?} has no order id", kind.action);
                    return;
                }
            };
            // Map action → OrderStatus for DB sync (shared with the take
            // reply classification).
            let new_status = status_for_action(&kind.action);
            if let Some(status) = new_status {
                if status_sync_blocked_by_terminal(&order_id, &kind.action).await {
                    return;
                }
                crate::api::logging::blog_info(
                    "orders",
                    format!(
                        "status order={} →{status:?} src=kind14/{:?}",
                        crate::api::logging::short_id(&order_id),
                        kind.action,
                    ),
                );
                order_book().update_order_status(&order_id, status.clone()).await;
                if let Some(db) = crate::db::app_db::db() {
                    if let Err(e) = db
                        .update_trade_fields(&order_id, Some(status.clone()), None, None)
                        .await
                    {
                        log::warn!(
                            "[orders] failed to sync trade status for order={order_id}: {e}"
                        );
                    }
                }
                emit_trade_update(&order_id, status);
            } else {
                log::debug!(
                    "[orders] daemon-msg {:?}: order={order_id} (no status change)",
                    kind.action
                );
            }
        }
        // The daemon announces which solver took the dispute, and carries their
        // pubkey in the payload. That pubkey is what both sides ECDH against to
        // establish the dispute-chat keys, so losing this message means there
        // is no way to reach the solver at all — nothing routed it before.
        Action::AdminTookDispute => {
            let Some(order_id) = kind.id.map(|id| id.to_string()) else {
                log::warn!("[orders] admin-took-dispute without an order id");
                return;
            };
            match admin_pubkey_from_payload(kind.payload.as_ref()) {
                Some(admin_pubkey) => {
                    if let Err(e) =
                        crate::api::disputes::handle_admin_took_dispute(order_id, admin_pubkey)
                            .await
                    {
                        log::warn!("[orders] admin-took-dispute not applied: {e}");
                    }
                }
                None => log::warn!(
                    "[orders] admin-took-dispute for order={order_id} carried no peer pubkey"
                ),
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

            // Consume the pending request on a genuine rejection. A restore is
            // nonce-less (RestoreSession carries no request_id), so its record
            // is correlated by trade pubkey via take_matching_restore — try that
            // first. It only matches a Restore record, so order requests keep
            // their nonce gate: a stale replayed CantDo (no or foreign
            // request_id) still touches nothing and leaves the order record for
            // the genuine reply. For non-restore requests the nonce-gated
            // take_matching_request path is unchanged.
            let matched = take_matching_restore(trade_pubkey_hex)
                .or_else(|| take_matching_request(trade_pubkey_hex, kind.request_id));
            if let Some(pending) = matched {
                if let Some(tx) = pending.tx {
                    crate::api::logging::blog_warn("daemon-msg", format!(
                        "CantDo: reason={reason} — notifying waiting caller"
                    ));
                    let _ = tx.send(Wake::from(DaemonReply::Rejected { reason, message }));
                } else {
                    // Genuine rejection after the 10s timeout: the caller
                    // already returned NoDaemonResponse and persisted nothing,
                    // so dropping the record is the only cleanup needed.
                    crate::api::logging::blog_warn("daemon-msg", format!(
                        "CantDo: reason={reason} — late rejection for timed-out request"
                    ));
                }
            } else {
                crate::api::logging::blog_debug("daemon-msg", format!(
                    "CantDo: reason={reason} — no matching pending request, ignoring event"
                ));
            }
        }
        Action::BondSlashed => {
            let order_id = match &kind.id {
                Some(id) => id.to_string(),
                None => {
                    log::warn!("[orders] daemon-msg BondSlashed has no order id");
                    return;
                }
            };
            let small_order = match &kind.payload {
                Some(mostro_core::message::Payload::Order(so)) => so,
                _ => {
                    log::warn!("[orders] daemon-msg BondSlashed payload is not an Order");
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
                        "[orders] daemon-msg BondSlashed: invalid amount {} for order={order_id}, ignoring",
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
                "[orders] daemon-msg BondSlashed: order={order_id} amount={amount_sats} cause={cause:?}"
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
            log::debug!("[orders] daemon-msg unhandled action={action:?}");
        }
    }
}

/// Current locally known status for a trade: the DB row when present
/// (authoritative across restarts), else the in-memory book entry.
async fn current_local_status(order_id: &str) -> Option<OrderStatus> {
    if let Some(db) = crate::db::app_db::db() {
        if let Ok(Some(trade)) = db.get_trade_by_order_id(order_id).await {
            return Some(trade.order.status);
        }
    }
    order_book().get_order(order_id).await.map(|o| o.status)
}

/// True when a Kind 14 status sync must be skipped: the trade already sits
/// in a hard-terminal status. Relays deliver the startup backlog
/// newest-first, so a progression message that would move a finished trade
/// is an out-of-order replay, not a real transition — applying it walks
/// the status backwards and re-emits action requests to the UI.
async fn status_sync_blocked_by_terminal(
    order_id: &str,
    action: &mostro_core::message::Action,
) -> bool {
    let Some(local) = current_local_status(order_id).await else {
        return false;
    };
    if is_hard_terminal(&local) {
        crate::api::logging::blog_debug(
            "orders",
            format!(
                "skip replayed {action:?} order={}: already {local:?}",
                crate::api::logging::short_id(order_id),
            ),
        );
        return true;
    }
    false
}

// ── Public vs private order status ────────────────────────────────────────────

/// Whether a status parsed from a public Kind 38383 event may replace the one
/// already held for that trade.
///
/// The wire status is NIP-69's four-bucket view (`pending`, `in-progress`,
/// `success`, `canceled`): mostrod stops publishing once a trade turns private,
/// so `in-progress` means "taken", never "escrow locked". Letting it overwrite
/// a status learned from a daemon message drags an Active trade back to
/// InProgress and offers actions the daemon then rejects (issue #203).
/// Logs one wire→trade status sync decision. A real transition logs at info;
/// blocked (`applies=false`) and no-op decisions log at debug so relay
/// redelivery churn stays out of a shipped build's log while remaining
/// visible in a debugging session (#277).
fn log_wire_status_sync(
    order_id: &str,
    wire: &OrderStatus,
    local: Option<&OrderStatus>,
    applies: bool,
    src: &str,
) {
    let line = format!(
        "status order={} wire={wire:?} local={} applies={applies} src={src}",
        crate::api::logging::short_id(order_id),
        local.map_or_else(|| "-".to_string(), |s| format!("{s:?}")),
    );
    if applies && local != Some(wire) {
        crate::api::logging::blog_info("orders", line);
    } else {
        crate::api::logging::blog_debug("orders", line);
    }
}

/// Status already held for `order_id`, or `None` when the order is not one of
/// ours. The persisted trade wins over the in-memory book: it is the record fed
/// exclusively by daemon messages.
pub(crate) async fn local_trade_status(order_id: &str) -> Option<OrderStatus> {
    if let Some(db) = crate::db::app_db::db() {
        if let Ok(Some(trade)) = db.get_trade_by_order_id(order_id).await {
            return Some(trade.order.status);
        }
    }
    order_book()
        .get_order(order_id)
        .await
        .map(|info| info.status)
}

// ── Peer-pubkey resolution ────────────────────────────────────────────────────

/// Called when the daemon sends `BuyerTookOrder` or `HoldInvoicePaymentAccepted`.
///
/// Derives the ECDH shared key from `(our_trade_key, peer_trade_pubkey)`,
/// stores it in the session, and spawns an incoming-chat subscription on the
/// shared-key pubkey so we receive peer messages from the moment the trade
/// goes active.
async fn on_peer_pubkey_received(order_id: &str, peer_pubkey_hex: &str) {
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
    // Derive the chat conversation keys (K_conv / K_sign — HKDF split of the
    // trade-key ECDH secret, protocol chat spec) and spawn the incoming-chat
    // subscription pinned to their author key.
    let (conv, sign) = match crate::crypto::chat_keys::derive_chat_keys(&trade_keys, &peer_pubkey) {
        Ok(pair) => pair,
        Err(e) => {
            log::error!("[orders] on_peer_pubkey_received: chat key derivation failed: {e}");
            return;
        }
    };
    let order_id_owned = order_id.to_string();
    crate::rt::spawn(async move {
        crate::api::messages::subscribe_incoming_chat(
            crate::api::messages::ChatChannel::Peer,
            order_id_owned,
            trade_keys,
            peer_pubkey,
            conv,
            sign,
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

        use crate::rt::time::{timeout, Duration};
        use nostr_sdk::RelayPoolNotification;

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
                    if let Some(mut order) =
                        crate::nostr::order_events::parse_order_event(&event, None)
                    {
                        if order.id == order_id {
                            log::info!(
                                "[orders] d-tag update: order={} status={:?}",
                                order_id,
                                order.status
                            );
                            last_activity = crate::rt::time::Instant::now();
                            let local = local_trade_status(&order.id).await;
                            let applies = wire_status_applies(local.as_ref(), &order.status);
                            // This subscription only exists for orders we
                            // created or took, so every decision is ours to log.
                            log_wire_status_sync(
                                &order.id,
                                &order.status,
                                local.as_ref(),
                                applies,
                                "38383/d-tag",
                            );
                            if let Some(db) = crate::db::app_db::db() {
                                if let Err(e) = db
                                    .update_trade_fields(
                                        &order.id,
                                        applies.then(|| order.status.clone()),
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
                            if !applies {
                                if let Some(local) = local {
                                    order.status = local;
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
    let kind = event.kind.as_u16();
    let eid = event.id.to_hex();
    let output = pool
        .client()
        .send_event(&event)
        .await
        .map_err(|e| anyhow::anyhow!("publish failed: {e}"))?;
    // Per-relay outcome: with one relay habitually down, knowing WHERE each
    // event actually landed is what makes delivery issues diagnosable.
    for relay in &output.success {
        crate::api::logging::blog_info(
            "publish",
            format!(
                "ev={} kind={kind} relay={} OK",
                crate::api::logging::short_id(&eid),
                crate::api::logging::display_relay(&relay.to_string()),
            ),
        );
    }
    for (relay, err) in &output.failed {
        crate::api::logging::blog_warn(
            "publish",
            format!(
                "ev={} kind={kind} relay={} FAIL: {}",
                crate::api::logging::short_id(&eid),
                crate::api::logging::display_relay(&relay.to_string()),
                crate::api::logging::sanitize_relay_text(err),
            ),
        );
    }
    // The SDK returns Ok even when every relay rejected the event (verified
    // in nostr-relay-pool 0.44: `send_event_to` has no empty-success guard).
    // Without this, fire-and-forget actions (fiat-sent, release, cancel)
    // would report success having reached zero relays, and correlated ones
    // would wait 10s for a reply that can never arrive. Partial success
    // stays Ok. Stable marker — Dart maps it to a localized message.
    if output.success.is_empty() {
        anyhow::bail!("NoRelayAccepted");
    }
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

    // Reconciles state the daemon-message channel missed (e.g. a waiting-state
    // timeout that fired while the app was closed). Idempotent across
    // re-subscribes — at most one sweep loop per process.
    spawn_stale_sweep();
}

// ── Stale-state sweep ─────────────────────────────────────────────────────────

/// Delay before the first sweep so the initial Kind 38383 fetch can populate
/// the book — the sweep only acts on positive book signals, so it must not
/// run against an empty cache.
const SWEEP_INITIAL_DELAY_SECS: u64 = 60;
/// Cadence mirrors v1's 30-minute cleanup job.
const SWEEP_INTERVAL_SECS: u64 = 30 * 60;
/// Waiting trades younger than this are never touched: the daemon's own
/// waiting window (default `expiration_seconds`) has not elapsed yet.
const SWEEP_MIN_AGE_SECS: i64 = 900;
/// Keyless in-memory sessions older than this are dropped. Any order that
/// can still activate does so long before; a missing session self-heals in
/// the peer-pubkey handler anyway.
const SWEEP_SESSION_TTL_SECS: i64 = 24 * 3600;

static SWEEP_ACTIVE: AtomicBool = AtomicBool::new(false);

/// What the sweep does with one stale waiting trade, given the daemon's
/// current public (Kind 38383) status for that order.
#[derive(Debug, PartialEq)]
enum SweepAction {
    /// The trade never went active and the daemon moved on — republished as
    /// pending (taker side) or canceled outright: wipe row + session, same
    /// as the live `Canceled` daemon-message path.
    Wipe,
    /// Own maker order republished as pending: the order is alive again,
    /// sync the row back so My Trades reflects it.
    SyncPending,
    /// No positive daemon signal — absent from the book, or the ambiguous
    /// `in-progress` public marker: leave untouched.
    Keep,
}

fn sweep_action(
    is_mine: bool,
    book_status: Option<&crate::api::types::OrderStatus>,
) -> SweepAction {
    use crate::api::types::OrderStatus as S;
    match book_status {
        Some(S::Pending) if is_mine => SweepAction::SyncPending,
        Some(S::Pending) => SweepAction::Wipe,
        Some(S::Canceled | S::Expired | S::CanceledByAdmin) => SweepAction::Wipe,
        _ => SweepAction::Keep,
    }
}

fn spawn_stale_sweep() {
    if SWEEP_ACTIVE
        .compare_exchange(false, true, Ordering::AcqRel, Ordering::Acquire)
        .is_err()
    {
        return;
    }
    crate::rt::spawn(async {
        crate::rt::time::sleep(crate::rt::time::Duration::from_secs(
            SWEEP_INITIAL_DELAY_SECS,
        ))
        .await;
        loop {
            run_stale_sweep_once().await;
            crate::rt::time::sleep(crate::rt::time::Duration::from_secs(SWEEP_INTERVAL_SECS)).await;
        }
    });
}

/// Reconcile trades stuck in waiting states with the daemon's public book.
///
/// Covers cancellations whose daemon message the app never received (closed or
/// offline when the daemon's waiting window expired). The clock only
/// *triggers* the check — every decision needs a positive daemon signal
/// (see [`sweep_action`]); the daemon stays the authority on order state.
async fn run_stale_sweep_once() {
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    let trades = match db.list_trades().await {
        Ok(trades) => trades,
        Err(e) => {
            log::warn!("[orders] sweep: list_trades failed: {e}");
            return;
        }
    };
    let now = crate::rt::unix_now();
    let (mut examined, mut wiped, mut resynced) = (0usize, 0usize, 0usize);
    for trade in trades {
        if !matches!(
            trade.order.status,
            crate::api::types::OrderStatus::WaitingBuyerInvoice
                | crate::api::types::OrderStatus::WaitingPayment
        ) {
            continue;
        }
        // Age gate: never race the take/propagation window of a live trade.
        let deadline = trade
            .timeout_at
            .unwrap_or(trade.started_at + SWEEP_MIN_AGE_SECS);
        if now <= deadline {
            continue;
        }
        examined += 1;
        let oid = trade.order.id.clone();
        let book_status = order_book().get_order(&oid).await.map(|o| o.status);
        match sweep_action(trade.order.is_mine, book_status.as_ref()) {
            SweepAction::Wipe => match db.delete_trade_by_order_id(&oid).await {
                Ok(()) => {
                    crate::mostro::session::session_manager()
                        .remove_session(&oid)
                        .await;
                    emit_trade_update(&oid, crate::api::types::OrderStatus::Canceled);
                    log::info!("[orders] sweep: wiped stale waiting trade order={oid}");
                    wiped += 1;
                }
                Err(e) => log::warn!("[orders] sweep: failed to wipe {oid}: {e}"),
            },
            SweepAction::SyncPending => {
                match db
                    .update_trade_fields(
                        &oid,
                        Some(crate::api::types::OrderStatus::Pending),
                        None,
                        None,
                    )
                    .await
                {
                    Ok(()) => {
                        emit_trade_update(&oid, crate::api::types::OrderStatus::Pending);
                        log::info!(
                            "[orders] sweep: resynced republished maker order={oid} to pending"
                        );
                        resynced += 1;
                    }
                    Err(e) => log::warn!("[orders] sweep: failed to resync {oid}: {e}"),
                }
            }
            SweepAction::Keep => {}
        }
    }
    let sessions_dropped = crate::mostro::session::session_manager()
        .cleanup_stale_sessions(SWEEP_SESSION_TTL_SECS)
        .await;
    if examined > 0 || sessions_dropped > 0 {
        crate::api::logging::blog_info(
            "orders",
            format!(
                "stale sweep: examined={examined} wiped={wiped} resynced={resynced} sessions_dropped={sessions_dropped}"
            ),
        );
    }
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
                ingest_order_event_with(&event, Publish::WhenBatchEnds).await;
            }
            // One emission for the batch. Publishing per event made a refetch
            // O(N²): each upsert cloned the whole book and sent it across the
            // bridge, so N orders cost N clones of an N-element vector. This
            // path runs on cold start, on every node switch, and on every
            // pull-to-refresh.
            order_book().publish().await;
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
    crate::api::logging::blog_info(
        "relay",
        format!(
            "sub created id={} kinds=[38383] author={}",
            orders_subscription_id(),
            crate::api::logging::short_id(&mostro_pubkey.to_hex()),
        ),
    );

    // Kind-14 NIP-44 replies authored by Mostro for all known trade pubkeys.
    // The author pin disambiguates from NIP-17 peer chat (also kind 14).
    //
    // Deliberately NO `since` here: this is the offline catch-up channel —
    // after any downtime it must replay the full stored history so status
    // changes and late reconciliations are never lost. Only the ephemeral
    // per-trade subscription (subscribe_daemon_messages) carries a cutoff.
    if !trade_pubkeys.is_empty() {
        let p_count = trade_pubkeys.len();
        let dm_filter = nostr_sdk::Filter::new()
            .kind(nostr_sdk::Kind::PrivateDirectMessage)
            .author(mostro_pubkey)
            .pubkeys(trade_pubkeys);
        client
            .subscribe_with_id(mostro_dm_subscription_id(), dm_filter, None)
            .await
            .map_err(|e| anyhow::anyhow!("dm subscribe failed: {e}"))?;
        crate::api::logging::blog_info(
            "relay",
            format!(
                "sub created id={} kinds=[14] p_count={p_count}",
                mostro_dm_subscription_id(),
            ),
        );
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

    // Same reasoning for the escrow mode, and it matters more: the capability
    // re-fetch below is a network round trip, and until it answers the old
    // node's mode would still be cached. Dropping it first makes that window
    // read as Unknown — which keeps Cashu shut — instead of carrying one
    // node's Cashu mode onto another.
    crate::mostro::escrow_mode::clear();

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

    let trade_pubkeys = seed_global_dm_coverage().await;

    if let Err(e) = subscribe_node_filters(&client, mostro_pubkey, trade_pubkeys).await {
        log::error!("[orders] node switch: re-subscribe failed: {e}");
        return;
    }

    // Repopulate the cleared book with the new node's current orders (the live
    // stream won't redeliver already-seen events — see refetch_active_node_orders).
    refetch_active_node_orders().await;

    // Outgoing messages must use the new node's PoW difficulty, and the
    // escrow mode must reflect the node we just switched to.
    crate::api::nostr::fetch_and_set_node_capabilities().await;

    crate::api::logging::blog_info(
        "orders",
        format!(
            "switched subscriptions to mostro={}",
            mostro_pubkey.to_hex()
        ),
    );
}

/// Build a map of `trade_pubkey_hex → (Keys, trade_index)` for all derived
/// trade keys so the global subscription can decrypt any daemon message.
/// Trade-key decryption coverage for the bulk Kind-14 subscription:
/// pubkey hex → (keys, index). Refreshable on purpose (PR #253 review): the
/// global subscription used to snapshot the map once at startup, so a key
/// derived later — a new order or take — was covered only by the 30-minute
/// per-trade receiver, and a solver assignment arriving after that expired
/// was never decrypted.
///
/// Seeded in full by BOTH subscription entry points — startup and node
/// switch — via [`seed_global_dm_coverage`]; `ensure_global_dm_coverage`
/// adds keys derived mid-session. The event loop decrypts against this map
/// and `resubscribe_global_dm_filter` rebuilds the relay filter from it
/// alone, so an unseeded or shrunk map makes previous sessions' trades
/// undecryptable and silently unsubscribes them.
static GLOBAL_DM_KEYS: std::sync::OnceLock<
    tokio::sync::RwLock<HashMap<String, (nostr_sdk::Keys, u32)>>,
> = std::sync::OnceLock::new();

fn global_dm_keys() -> &'static tokio::sync::RwLock<HashMap<String, (nostr_sdk::Keys, u32)>> {
    GLOBAL_DM_KEYS.get_or_init(|| tokio::sync::RwLock::new(HashMap::new()))
}

/// Add a freshly derived trade key to the global decryption map and refresh
/// the bulk Kind-14 relay filter to include it, so daemon messages for this
/// key (including an admin-took-dispute long after creation) are received
/// for the whole life of the process, not just while the temporary per-trade
/// receiver runs. Idempotent: a key already covered causes no relay churn.
pub(crate) async fn ensure_global_dm_coverage(keys: &nostr_sdk::Keys, trade_index: u32) {
    let hex = keys.public_key().to_hex();
    {
        let mut map = global_dm_keys().write().await;
        if map.contains_key(&hex) {
            return;
        }
        map.insert(hex, (keys.clone(), trade_index));
    }
    resubscribe_global_dm_filter().await;
}

/// Re-issue the bulk Kind-14 subscription with the current coverage set.
/// Same stable id, so the relay replaces the filter in place. No-op before
/// the pool exists — startup seeds the map and subscribes moments later.
async fn resubscribe_global_dm_filter() {
    let Ok(pool) = crate::api::nostr::get_pool() else {
        return;
    };
    let Ok(mostro_pubkey) = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey()) else {
        return;
    };
    let trade_pubkeys: Vec<nostr_sdk::PublicKey> = global_dm_keys()
        .read()
        .await
        .keys()
        .filter_map(|hex| nostr_sdk::PublicKey::from_hex(hex).ok())
        .collect();
    if trade_pubkeys.is_empty() {
        return;
    }
    let p_count = trade_pubkeys.len();
    let dm_filter = nostr_sdk::Filter::new()
        .kind(nostr_sdk::Kind::PrivateDirectMessage)
        .author(mostro_pubkey)
        .pubkeys(trade_pubkeys);
    if let Err(e) = pool
        .client()
        .subscribe_with_id(mostro_dm_subscription_id(), dm_filter, None)
        .await
    {
        log::warn!("[orders] bulk DM filter refresh failed: {e}");
    } else {
        crate::api::logging::blog_info(
            "relay",
            format!(
                "sub replaced id={} kinds=[14] p_count={p_count}",
                mostro_dm_subscription_id(),
            ),
        );
    }
}

/// Derive every known trade key and merge it into the refreshable coverage
/// map, returning the full pubkey set for the relay filter.
///
/// Union, not replace: a session key inserted concurrently (create/take in
/// flight while subscriptions restart) must never be evicted.
async fn seed_global_dm_coverage() -> Vec<nostr_sdk::PublicKey> {
    let derived = build_trade_key_map().await;
    let mut map = global_dm_keys().write().await;
    for (hex, entry) in derived {
        map.entry(hex).or_insert(entry);
    }
    map.keys()
        .filter_map(|hex| nostr_sdk::PublicKey::from_hex(hex).ok())
        .collect()
}

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

/// Find which of our trade keys this kind-14 is addressed to, reading the key
/// map only for the lookup itself.
///
/// The read guard must not be held past this point: handling a message can end
/// up in `ensure_global_dm_coverage`, which takes the same lock for writing.
async fn resolve_dm_recipient(event: &nostr_sdk::Event) -> Option<(String, nostr_sdk::Keys, u32)> {
    let map = global_dm_keys().read().await;
    for tag in event.tags.iter() {
        let s = tag.as_slice();
        if s.first().map(|v| v.as_str()) == Some("p") {
            if let Some(pk_hex) = s.get(1).map(|v| v.as_str()) {
                if let Some((keys, idx)) = map.get(pk_hex) {
                    return Some((pk_hex.to_string(), keys.clone(), *idx));
                }
            }
        }
    }
    // The bulk filter pins author + our own p-tags, so a kind-14 that reaches
    // here without a matching key is an anomaly (stale filter after
    // regenerate? key map gap?) — worth a warn.
    crate::api::logging::blog_warn(
        "daemon-msg",
        format!(
            "drop ev={} reason=no-matching-p-tag map={}",
            crate::api::logging::short_id(&event.id.to_hex()),
            map.len(),
        ),
    );
    None
}

/// Handle a kind-14 Mostro reply received on the global subscription.
///
/// The caller has already pinned the author to the active Mostro pubkey and
/// resolved the addressed trade key via [`resolve_dm_recipient`]. Decrypts
/// via `mostro_core::transport::unwrap_incoming` and dispatches the recovered
/// `Message` through `dispatch_mostro_message`.
async fn handle_global_daemon_message(
    event: &nostr_sdk::Event,
    recipient: (String, nostr_sdk::Keys, u32),
) {
    let (recipient_hex, recipient_keys, trade_idx) = recipient;

    let eid = event.id.to_hex();
    if is_duplicate_daemon_message(&eid) {
        crate::api::logging::blog_debug(
            "daemon-msg",
            format!(
                "drop ev={} reason=duplicate",
                crate::api::logging::short_id(&eid)
            ),
        );
        return;
    }
    crate::api::logging::blog_info(
        "daemon-msg",
        format!(
            "Kind 14 received (global) for trade={} from={} event_id={}",
            &recipient_hex[..8],
            &event.pubkey.to_hex()[..8],
            &eid[..16],
        ),
    );

    match crate::nostr::transport::unwrap_mostro_message(&recipient_keys, event).await {
        Ok(Some(unwrapped)) => {
            dispatch_mostro_message(unwrapped, &eid, &recipient_hex, trade_idx).await;
        }
        Ok(None) => {
            // `Ok(None)` = NIP-44 outer decrypt failed. On the global path
            // this is expected whenever trade_key_map contains multiple
            // entries and the event is addressed to a different key; here
            // the p-tag already matched so it only happens on p-tag collisions.
        }
        Err(e) => crate::api::logging::blog_warn(
            "daemon-msg",
            format!("decrypt failed for trade={}: {e}", &recipient_hex[..8]),
        ),
    }
}

/// The solver's pubkey carried by `admin-took-dispute`, per
/// <https://mostro.network/protocol/dispute_chat.html>: the daemon puts it in a
/// `Peer` payload. Any other payload shape means the message cannot establish
/// the dispute chat, so it is reported rather than guessed at.
fn admin_pubkey_from_payload(payload: Option<&mostro_core::message::Payload>) -> Option<String> {
    use mostro_core::message::Payload;
    match payload {
        Some(Payload::Peer(peer)) => Some(peer.pubkey.clone()),
        _ => None,
    }
}

/// Bind the daemon UUID to the trade-key index recovered from the content
/// fingerprint on cold start — but ONLY when no authoritative mapping exists
/// yet.
///
/// The request_id-correlated create/confirm path (see the `NewOrder` handler)
/// is the source of truth for `daemon_id → index`. The content fingerprint is
/// ambiguous — a taken range order is re-published on the wire as a plain
/// fixed-amount order, and two identical open orders share one fingerprint
/// slot — so it must never overwrite an existing binding, or a subsequent
/// release/cancel/rate gets signed with the wrong trade key and the daemon
/// rejects it (`InvalidPeer`, #326). This mirrors the v1 client, which keys the
/// trade index by daemon UUID and never by order content.
async fn bridge_fingerprint_trade_index(order_id: &str, trade_idx: u32) {
    // "No binding yet" is the case this function exists to handle, so the
    // warning variant would fire on the normal path.
    if lookup_trade_key_index(order_id).await.is_none() {
        store_trade_key_index(order_id, trade_idx).await;
    }
}

/// The daemon's dispute UUID out of a `Dispute` payload.
fn dispute_id_from_payload(payload: Option<&mostro_core::message::Payload>) -> Option<String> {
    use mostro_core::message::Payload;
    match payload {
        Some(Payload::Dispute(id, _)) => Some(id.to_string()),
        _ => None,
    }
}

/// Parse a Kind 38383 event and upsert it into the order book, applying
/// maker-order reconciliation (is_mine detection, local→daemon id bridging,
/// trade-status sync).
///
/// Shared by the live subscription loop and the node-switch refetch so both
/// paths populate the book identically.
/// When an ingested event reaches subscribers.
#[derive(Clone, Copy, PartialEq, Eq)]
enum Publish {
    /// At most one emission per coalescing window — the relay firehose, where
    /// events arrive faster than the UI can consume whole-book snapshots.
    Coalesced,
    /// Bulk ingest: the caller publishes once for the whole batch.
    WhenBatchEnds,
}

async fn ingest_order_event(event: &nostr_sdk::Event) {
    ingest_order_event_with(event, Publish::Coalesced).await;
}

async fn ingest_order_event_with(event: &nostr_sdk::Event, publish: Publish) {
    log::debug!(
        "[orders] event kind={} author={}",
        event.kind,
        &event.pubkey.to_hex()[..8]
    );
    match parse_order_event(event, None) {
        Some(mut info) => {
            log::debug!(
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
                // A miss is the expected case here: every order from another
                // user fails this lookup, so the warning variant would fire
                // once per ingested event.
                if let Some(trade_idx) = lookup_trade_key_index(&ck).await {
                    info.is_mine = true;
                    // Bridge content fingerprint → daemon UUID so subsequent
                    // actions (cancel) can look up the trade key by real order ID.
                    bridge_fingerprint_trade_index(&info.id, trade_idx).await;
                    // The maker order is no longer inserted into the
                    // book optimistically (see `create_order`), so there
                    // is nothing to remove here — just bridge the local
                    // UUID → daemon UUID in the DB so tradeStatusProvider
                    // polls with the real order ID. Only records without a
                    // live waiter are taken: an in-flight create_order owns
                    // its own reconciliation via the kind-14 acknowledgement.
                    if let Some(PendingRequest {
                        kind:
                            PendingRequestKind::Create {
                                local_uuid: local_id,
                                ..
                            },
                        ..
                    }) = take_pending_create_by_content_key(&ck)
                    {
                        if let Some(db) = crate::db::app_db::db() {
                            if let Err(e) = db.update_trade_order_id(&local_id, &info.id).await {
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
            // reflects status changes even without daemon-message delivery.
            if info.status != crate::api::types::OrderStatus::Pending {
                let local = local_trade_status(&info.id).await;
                let applies = wire_status_applies(local.as_ref(), &info.status);
                if info.is_mine {
                    // Only own orders: for stranger book entries `local`
                    // falls back to the book itself and would log every
                    // public update.
                    log_wire_status_sync(
                        &info.id,
                        &info.status,
                        local.as_ref(),
                        applies,
                        "38383/book",
                    );
                    if let Some(db) = crate::db::app_db::db() {
                        if let Err(e) = db
                            .update_trade_fields(
                                &info.id,
                                applies.then(|| info.status.clone()),
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
                if !applies {
                    if let Some(local) = local {
                        info.status = local;
                    }
                }
            }
            match publish {
                Publish::Coalesced => order_book().upsert_order_coalesced(info).await,
                Publish::WhenBatchEnds => order_book().upsert_order_deferred(info).await,
            }
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
    crate::api::logging::blog_info(
        "orders",
        format!(
            "subscribing to Kind 38383 from mostro={}",
            mostro_pubkey.to_hex()
        ),
    );

    // Derive and seed the decryption coverage for ALL known trade keys —
    // the event loop decrypts against global_dm_keys, not a local map, and
    // resubscribe_global_dm_filter rebuilds the relay filter from it alone.
    // Unseeded, every previous session's trade is undecryptable and falls
    // off the filter on the session's first create or take.
    let trade_pubkeys = seed_global_dm_coverage().await;
    crate::api::logging::blog_info(
        "orders",
        format!(
            "trade key map: {} keys derived for daemon-message decryption",
            trade_pubkeys.len()
        ),
    );

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

    crate::api::logging::blog_info(
        "orders",
        "subscriptions active — waiting for events".to_string(),
    );

    use nostr_sdk::RelayPoolNotification;

    loop {
        match rx.recv().await {
            Ok(RelayPoolNotification::Event { event, .. }) => {
                // Resolve the *current* active node for each event so a node
                // switch is respected without restarting this loop.
                let Ok(active_mostro) = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())
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
                    if let Some(recipient) = resolve_dm_recipient(&event).await {
                        handle_global_daemon_message(&event, recipient).await;
                    }
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
            // Raw relay control messages. Observation only — every arm just
            // logs. CLOSED and NOTICE are anomalies (a relay refusing or
            // complaining about a subscription) that were previously
            // swallowed by the catch-all and undiagnosable in the field.
            Ok(RelayPoolNotification::Message { relay_url, message }) => {
                use nostr_sdk::RelayMessage;
                match message {
                    // Ground truth for delivery questions: this fires for
                    // every frame the relay pushes, BEFORE the SDK's
                    // first-time-seen dedup that gates the Event
                    // notification above (#277).
                    RelayMessage::Event {
                        subscription_id,
                        event,
                    } => {
                        let kind = event.kind.as_u16();
                        // Kind 14 only: nothing subscribes to the superseded
                        // gift wrap, so a 1059 frame here would be noise from
                        // somebody else's subscription.
                        if kind == 14 {
                            crate::api::logging::blog_debug(
                                "relay",
                                format!(
                                    "raw ev={} kind={kind} sub={subscription_id} relay={}",
                                    crate::api::logging::short_id(&event.id.to_hex()),
                                    crate::api::logging::display_relay(&relay_url.to_string()),
                                ),
                            );
                        }
                    }
                    RelayMessage::EndOfStoredEvents(sub_id) => {
                        crate::api::logging::blog_debug(
                            "relay",
                            format!(
                                "eose sub={sub_id} relay={}",
                                crate::api::logging::display_relay(&relay_url.to_string()),
                            ),
                        );
                    }
                    RelayMessage::Closed {
                        subscription_id,
                        message,
                    } => {
                        crate::api::logging::blog_warn(
                            "relay",
                            format!(
                                "closed sub={subscription_id} relay={} msg={}",
                                crate::api::logging::display_relay(&relay_url.to_string()),
                                crate::api::logging::sanitize_relay_text(&message),
                            ),
                        );
                    }
                    RelayMessage::Notice(msg) => {
                        crate::api::logging::blog_warn(
                            "relay",
                            format!(
                                "notice relay={} msg={}",
                                crate::api::logging::display_relay(&relay_url.to_string()),
                                crate::api::logging::sanitize_relay_text(&msg),
                            ),
                        );
                    }
                    RelayMessage::Auth { .. } => {
                        crate::api::logging::blog_debug(
                            "relay",
                            format!(
                                "auth-challenge relay={}",
                                crate::api::logging::display_relay(&relay_url.to_string()),
                            ),
                        );
                    }
                    _ => {}
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
        }
    }
}

/// Buffered trade lifecycle updates. Every daemon-driven status sync emits
/// one, but they are per-trade progression steps — a handful per trade over
/// minutes — so a small buffer is still ample.
const TRADE_UPDATES_CAPACITY: usize = 64;

static TRADE_UPDATES: std::sync::OnceLock<broadcast::Sender<crate::api::types::TradeUpdate>> =
    std::sync::OnceLock::new();

fn trade_updates_tx() -> &'static broadcast::Sender<crate::api::types::TradeUpdate> {
    TRADE_UPDATES.get_or_init(|| broadcast::channel(TRADE_UPDATES_CAPACITY).0)
}

/// Persists the counterparty (taker) reputation snapshot from the daemon's
/// follow-up Peer DM and nudges any open screen to re-read the trade so it
/// surfaces who took the order (issue #305).
///
/// The Peer DM carries no status of its own — it rides the same
/// PayInvoice / AddInvoice action as the flow message that already ran — so
/// this re-emits the trade's *current* status (read from the book) purely to
/// wake `tradeInfoStreamProvider`; it never changes state. When the book has
/// no row for the order yet, the persisted snapshot is still read the next
/// time the trade loads, so a missing emission only delays the live update.
async fn persist_peer_reputation(order_id: &str, rating: f64, reviews: u32, days: u32) {
    crate::api::logging::blog_info(
        "orders",
        format!(
            "peer-reputation order={} rating={rating} reviews={reviews} days={days}",
            crate::api::logging::short_id(order_id),
        ),
    );
    if let Some(db) = crate::db::app_db::db() {
        if let Err(e) = db
            .update_trade_peer_reputation(order_id, rating, reviews, days)
            .await
        {
            log::warn!("[orders] failed to persist peer reputation for order={order_id}: {e}");
        }
    }
    if let Some(info) = order_book().get_order(order_id).await {
        emit_trade_update(order_id, info.status);
    }
}

/// Broadcasts a trade lifecycle change to any active [`TradeUpdatesStream`].
pub(crate) fn emit_trade_update(order_id: &str, status: crate::api::types::OrderStatus) {
    let _ = trade_updates_tx().send(crate::api::types::TradeUpdate {
        order_id: order_id.to_string(),
        status,
    });
}

/// Stream of trade lifecycle changes pushed by the daemon-message ingest.
///
/// Every status a Kind 14 dispatch arm syncs is emitted here, after the
/// in-memory book update and the DB persistence attempt. A DB write failure
/// (or a memory-only session with no DB at all) is logged and does not
/// suppress the emission — the stream means "the daemon moved this trade",
/// not "the DB commit succeeded", so listeners must tolerate a trade row
/// that is missing or behind the book. Complements the 2s status polling in
/// two ways: cancellations that polling cannot observe (a wiped
/// never-active trade has no DB row left, and after a timeout republish the
/// book shows `pending` again), and action requests the user must react to
/// promptly (add-invoice / pay-invoice) no matter which screen is open.
pub async fn on_trade_updated() -> Result<TradeUpdatesStream> {
    Ok(TradeUpdatesStream {
        rx: trade_updates_tx().subscribe(),
    })
}

/// Wrapper for flutter_rust_bridge Dart Stream generation.
pub struct TradeUpdatesStream {
    rx: broadcast::Receiver<crate::api::types::TradeUpdate>,
}

impl TradeUpdatesStream {
    pub async fn next(&mut self) -> Option<crate::api::types::TradeUpdate> {
        loop {
            match self.rx.recv().await {
                Ok(update) => return Some(update),
                // Dropped updates degrade, not corrupt: the trades list
                // refetches on any later emission, kept-history trades are
                // covered by the 2s status poll, and the sweep re-emits
                // within 30 min. Log so the (unlikely) case is observable.
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    log::warn!("[orders] trade-updates stream lagged, dropped {n} updates");
                    continue;
                }
                Err(broadcast::error::RecvError::Closed) => return None,
            }
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
                // Each message is a full snapshot, so dropping some is
                // survivable: the next one carries the whole book. Log it
                // anyway — this is the only backpressure signal there is, and
                // it stops being harmless the moment this channel carries
                // deltas instead of snapshots.
                Err(broadcast::error::RecvError::Lagged(n)) => {
                    log::warn!("[orders] order-book stream lagged, dropped {n} snapshots");
                    continue;
                }
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

/// Highest trade-key index across all recovered orders and disputes (#217).
///
/// The counter must be raised to this so the next `derive_trade_key()` cannot
/// hand out an index a recovered trade already owns. Returns `None` when the
/// restore carried no trades (nothing to resync to). Indexes are `i64` on the
/// wire; a value that is negative or beyond `u32::MAX` is not a real trade
/// index, so it is dropped rather than truncated into the counter.
fn recovered_max_trade_index(info: &mostro_core::message::RestoreSessionInfo) -> Option<u32> {
    // A single adapter drops both negatives and any value >= u32::MAX — neither
    // is a real trade index, and truncating one into a small u32 could corrupt
    // the counter this exists to protect. u32::MAX itself is dropped: it is the
    // reserved terminal index, and storing it as the counter would make the next
    // derive_trade_key compute u32::MAX + 1 and overflow (panic in debug, wrap to
    // 0 in release — reissuing index 0, the exact key-reuse this resync prevents).
    // Collapsed into one filter_map so the two conditions can't drift apart.
    let all: Vec<i64> = info
        .restore_orders
        .iter()
        .map(|o| o.trade_index)
        .chain(info.restore_disputes.iter().map(|d| d.trade_index))
        .collect();
    let total = all.len();
    let valid: Vec<u32> = all
        .into_iter()
        .filter_map(|i| u32::try_from(i).ok().filter(|&v| v < u32::MAX))
        .collect();
    // A dropped index is not just an odd value: it means the daemon sent
    // something this client's model does not cover, and a silently-lowered
    // floor produces a later CantDo(InvalidTradeIndex) with no breadcrumb. Warn
    // so the drop is traceable — especially the degenerate all-invalid case,
    // where this returns None, restore_session skips the resync, and the restore
    // reports success with a log as the only evidence anything happened.
    let dropped = total - valid.len();
    if dropped > 0 {
        crate::api::logging::blog_warn(
            "restore",
            format!(
                "recovered_max_trade_index dropped {dropped} of {total} indexes \
                 (negative or out-of-range); resync floor uses the valid remainder"
            ),
        );
    }
    valid.into_iter().max()
}

/// Send a `RestoreSession` to the active daemon and return the user's active
/// trades/disputes. Mirrors create_order's send/await, minus the order payload.
///
/// Correlation: the request is sent from a fresh TRADE key (event.sender) while
/// the Seal carries the IDENTITY key (event.identity). The daemon looks up
/// trades by identity/master key and replies to the trade key
/// (mostro restore_session.rs: master_key = event.identity, reply -> event.sender),
/// so we subscribe on the trade key and correlate the reply by that pubkey.
#[flutter_rust_bridge::frb(ignore)]
pub async fn restore_session() -> Result<mostro_core::message::RestoreSessionInfo> {
    // Fresh trade key -> event.sender (daemon replies here).
    let trade_key_info = crate::api::identity::derive_trade_key().await?;
    let trade_index = trade_key_info.index;
    let sender_keys = crate::api::identity::get_active_trade_keys(trade_index).await?;
    // Fresh key: join the bulk Kind-14 coverage now, so daemon messages for
    // it (e.g. a late admin-took-dispute) outlive the temporary per-trade
    // receiver (PR #253 review).
    ensure_global_dm_coverage(&sender_keys, trade_index).await;
    let trade_pk_hex = sender_keys.public_key().to_hex();

    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey())?;
    // Identity/transport keys sign the Seal -> event.identity (master key).
    let identity_keys = crate::api::identity::get_transport_identity_keys(&sender_keys).await?;

    let event_json = actions::restore_session(&identity_keys, &sender_keys, &mostro_pubkey).await?;

    // Register the pending-restore record BEFORE publishing so the reply can't
    // race the map. Correlated by trade pubkey only (RestoreSession carries no
    // request_id) -> take_matching_restore.
    let (conf_tx, conf_rx) = tokio::sync::oneshot::channel::<Wake>();
    // If the lock is poisoned we can't register the pending record, so the
    // reply could never be correlated — bail rather than publish an event
    // that would strand the caller for the full timeout only to report
    // NoDaemonResponse (a lock bug wearing a network bug's mask).
    {
        let mut map = pending_requests()
            .lock()
            .map_err(|_| anyhow::anyhow!("PendingRequestsLockPoisoned"))?;
        map.insert(
            trade_pk_hex.clone(),
            PendingRequest {
                request_id: 0,
                trade_index,
                kind: PendingRequestKind::Restore,
                tx: Some(conf_tx),
            },
        );
    }

    subscribe_daemon_messages(sender_keys.public_key(), trade_index).await;

    if let Err(e) = publish_event_json(&event_json).await {
        remove_pending_request(&trade_pk_hex, 0);
        return Err(e);
    }
    crate::api::logging::blog_info(
        "restore",
        format!("RestoreSession published trade_index={trade_index} — waiting for daemon"),
    );

    let confirmation = crate::rt::time::timeout(std::time::Duration::from_secs(10), conf_rx).await;

    if !matches!(confirmation, Ok(Ok(_))) {
        detach_request_waiter(&trade_pk_hex, 0);
    }

    match confirmation {
        Ok(Ok(Wake {
            reply: DaemonReply::Restored(info),
            ..
        })) => {
            // #217: raise trade_key_index past every recovered trade before
            // returning, so the next derive_trade_key() can't reuse a key a
            // recovered trade already owns. Monotonic and idempotent. A persist
            // failure fails the restore: an un-resynced counter reopens the
            // key-reuse bug this closes, so silent success would be worse than
            // a surfaced error the caller can retry.
            if let Some(floor) = recovered_max_trade_index(&info) {
                crate::api::identity::ensure_trade_key_index_at_least(floor).await?;
            }
            Ok(info)
        }
        Ok(Ok(Wake {
            reply: DaemonReply::Rejected { reason, message },
            ..
        })) => {
            crate::api::logging::blog_warn(
                "orders",
                format!("restore_session rejected: {reason} — {message}"),
            );
            Err(anyhow::anyhow!("{message}"))
        }
        Ok(Ok(_other)) => Err(anyhow::anyhow!("unexpected restore reply")),
        _ => Err(anyhow::anyhow!("NoDaemonResponse")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::TradeRole;
    use crate::mostro::pending::register_dispute_request;
    use crate::mostro::session::session_manager;

    /// A cached miss that outlived the key being created would make the order
    /// look like somebody else's, and every later action on it would be signed
    /// with the wrong key. Storing a key must clear its recorded miss.
    #[tokio::test]
    async fn storing_a_trade_key_clears_its_recorded_miss() {
        let order_id = format!("neg-cache-{}", uuid::Uuid::new_v4());
        note_trade_key_miss(&order_id);
        assert!(trade_key_misses().read().unwrap().contains(&order_id));

        store_trade_key_index(&order_id, 7).await;

        assert!(
            !trade_key_misses().read().unwrap().contains(&order_id),
            "the miss must not survive the key it denies"
        );
    }

    /// The miss set is a cache, not a record: it must not grow without bound
    /// as strangers' orders stream past.
    #[test]
    fn the_miss_cache_stays_bounded() {
        let mut misses = std::collections::HashSet::new();

        for n in 0..(TRADE_KEY_MISS_CAPACITY * 2) {
            record_miss(&mut misses, &format!("bound-{n}"));
        }

        assert!(
            misses.len() <= TRADE_KEY_MISS_CAPACITY,
            "miss cache grew to {}",
            misses.len()
        );
    }

    /// A refetch replays the node's whole book through ingest. Publishing per
    /// event made that O(N²) in clones and in bridge payload, so the batch
    /// must produce exactly one emission.
    #[tokio::test]
    async fn a_bulk_ingest_publishes_once_for_the_whole_batch() {
        const BATCH: usize = 50;
        let book = OrderBook::new();
        let mut rx = book.subscribe();

        for n in 0..BATCH {
            book.upsert_order_deferred(dummy_order_info(&format!("bulk-{n}")))
                .await;
        }

        assert!(
            matches!(rx.try_recv(), Err(broadcast::error::TryRecvError::Empty)),
            "a deferred upsert must not publish"
        );

        book.publish().await;

        let snapshot = rx.try_recv().expect("the batch publishes one snapshot");
        assert_eq!(snapshot.len(), BATCH, "the snapshot carries the whole book");
        assert!(
            matches!(rx.try_recv(), Err(broadcast::error::TryRecvError::Empty)),
            "the batch must publish exactly once"
        );
    }

    /// Daemon-message handlers and user actions still emit immediately:
    /// both deferring and coalescing are opt-in.
    #[tokio::test]
    async fn a_direct_upsert_still_publishes_immediately() {
        let book = OrderBook::new();
        let mut rx = book.subscribe();

        book.upsert_order(dummy_order_info("live-1")).await;

        let snapshot = rx.try_recv().expect("a direct upsert publishes");
        assert_eq!(snapshot.len(), 1);
    }

    /// A relay firehose delivers many 38383 events back to back. Each one
    /// publishing a whole-book snapshot is what makes a busy book expensive,
    /// so a burst inside one window must collapse to a single emission.
    #[tokio::test]
    async fn live_relay_updates_coalesce_into_one_emission() {
        const BURST: usize = 20;
        let book = OrderBook::new();
        let mut rx = book.subscribe();

        for n in 0..BURST {
            book.upsert_order_coalesced(dummy_order_info(&format!("burst-{n}")))
                .await;
        }

        assert!(
            matches!(rx.try_recv(), Err(broadcast::error::TryRecvError::Empty)),
            "nothing should be published before the window closes"
        );

        crate::rt::time::sleep(std::time::Duration::from_millis(PUBLISH_COALESCE_MS * 4)).await;

        let snapshot = rx.try_recv().expect("the window publishes once");
        assert_eq!(
            snapshot.len(),
            BURST,
            "the snapshot carries the whole burst"
        );
        assert!(
            matches!(rx.try_recv(), Err(broadcast::error::TryRecvError::Empty)),
            "one emission per window, not one per event"
        );
    }

    /// The window must re-arm, or the book would publish once and then go
    /// silent for the rest of the session.
    #[tokio::test]
    async fn a_later_update_opens_a_new_window() {
        let book = OrderBook::new();
        let mut rx = book.subscribe();
        let settle =
            || crate::rt::time::sleep(std::time::Duration::from_millis(PUBLISH_COALESCE_MS * 4));

        book.upsert_order_coalesced(dummy_order_info("first")).await;
        settle().await;
        assert_eq!(rx.try_recv().expect("first window").len(), 1);

        book.upsert_order_coalesced(dummy_order_info("second"))
            .await;
        settle().await;
        assert_eq!(rx.try_recv().expect("second window").len(), 2);
    }

    /// `global_dm_keys()` is a process-global shared by every test in this
    /// binary, and tests run in parallel: the entry is removed before the
    /// assertions so a failure here cannot leave the map grown for whoever
    /// runs next (`a_late_derived_key_joins_the_global_dm_coverage` asserts
    /// on its size).
    #[tokio::test]
    async fn dm_recipient_is_resolved_from_the_p_tag() {
        use nostr_sdk::{EventBuilder, Kind, Tag};

        let mine = nostr_sdk::Keys::generate();
        let mine_hex = mine.public_key().to_hex();
        let stranger = nostr_sdk::Keys::generate();

        let addressed_to_us = EventBuilder::new(Kind::PrivateDirectMessage, "")
            .tags([Tag::parse(["p", &mine_hex]).unwrap()])
            .sign_with_keys(&nostr_sdk::Keys::generate())
            .unwrap();
        // A stranger's key is never inserted, so this one resolves to None
        // whatever else the shared map happens to hold.
        let addressed_elsewhere = EventBuilder::new(Kind::PrivateDirectMessage, "")
            .tags([Tag::parse(["p", &stranger.public_key().to_hex()]).unwrap()])
            .sign_with_keys(&nostr_sdk::Keys::generate())
            .unwrap();

        global_dm_keys()
            .write()
            .await
            .insert(mine_hex.clone(), (mine.clone(), 7));
        let resolved = resolve_dm_recipient(&addressed_to_us).await;
        let unresolved = resolve_dm_recipient(&addressed_elsewhere).await;
        global_dm_keys().write().await.remove(&mine_hex);

        assert!(
            matches!(resolved, Some((ref hex, _, 7)) if *hex == mine_hex),
            "p-tag matching one of our trade keys must resolve to it"
        );
        assert!(unresolved.is_none());
    }

    /// The window must recognize a repeat, and must forget an id once
    /// `DEDUP_MAX_ENTRIES` newer ones have arrived — otherwise it would grow
    /// without bound.
    ///
    /// Driven against a local window rather than `is_duplicate_daemon_message`:
    /// that one shares a process-global static with every other test in this
    /// binary, so asserting on it would both depend on and destroy state the
    /// rest of the suite may touch.
    #[test]
    fn daemon_message_dedup_recognizes_repeats_and_evicts_oldest() {
        let mut window = DedupWindow::default();
        let id = |n: usize| format!("{n:064x}");

        assert!(!window.record(&id(0)));
        assert!(window.record(&id(0)));

        // One more than capacity, so id(0) is pushed out of the window.
        for n in 1..=DEDUP_MAX_ENTRIES {
            window.record(&id(n));
        }

        assert!(
            !window.record(&id(0)),
            "the oldest id should have been evicted once the window filled"
        );
        assert_eq!(
            window.seen.len(),
            window.order.len(),
            "the set and the eviction queue drifted apart"
        );
        assert!(
            window.order.len() <= DEDUP_MAX_ENTRIES,
            "window grew past its bound: {}",
            window.order.len()
        );
    }

    /// A subscriber that falls behind must resume from the retained window
    /// rather than closing, and that window is `ORDER_STREAM_CAPACITY` deep.
    #[tokio::test]
    async fn a_lagged_orders_stream_resumes_from_the_retained_window() {
        const SENT: usize = 100;
        const _: () = assert!(
            SENT > ORDER_STREAM_CAPACITY,
            "the test must overflow the channel"
        );

        let book = OrderBook::new();
        let mut stream = OrdersStream {
            rx: book.subscribe(),
        };

        // Publish without ever reading, so the receiver is forced to lag.
        for n in 0..SENT {
            book.set_orders(vec![dummy_order_info(&format!("order-{n}"))])
                .await;
        }

        let recovered = stream
            .next()
            .await
            .expect("a lagged stream must resume, not close");
        assert_eq!(
            recovered[0].id,
            format!("order-{}", SENT - ORDER_STREAM_CAPACITY),
            "should resume at the oldest snapshot still retained"
        );
    }

    #[test]
    fn the_solver_pubkey_is_read_from_a_peer_payload() {
        use mostro_core::message::{Payload, Peer};

        let pubkey = "0000000000000000000000000000000000000000000000000000000000000001";
        let payload = Payload::Peer(Peer {
            pubkey: pubkey.to_string(),
            reputation: None,
        });

        assert_eq!(
            admin_pubkey_from_payload(Some(&payload)).as_deref(),
            Some(pubkey)
        );
    }

    // ── #217 recovered_max_trade_index ────────────────────────────────────────
    fn restored_order(trade_index: i64) -> mostro_core::message::RestoredOrdersInfo {
        mostro_core::message::RestoredOrdersInfo {
            order_id: uuid::Uuid::new_v4(),
            trade_index,
            status: "active".to_string(),
        }
    }

    fn restored_dispute(trade_index: i64) -> mostro_core::message::RestoredDisputesInfo {
        mostro_core::message::RestoredDisputesInfo {
            dispute_id: uuid::Uuid::new_v4(),
            order_id: uuid::Uuid::new_v4(),
            trade_index,
            status: "initiated".to_string(),
            initiator: None,
            solver_pubkey: None,
        }
    }

    fn restore_info(
        orders: Vec<i64>,
        disputes: Vec<i64>,
    ) -> mostro_core::message::RestoreSessionInfo {
        mostro_core::message::RestoreSessionInfo {
            restore_orders: orders.into_iter().map(restored_order).collect(),
            restore_disputes: disputes.into_iter().map(restored_dispute).collect(),
        }
    }

    #[test]
    fn recovered_max_is_none_when_nothing_was_restored() {
        assert_eq!(
            recovered_max_trade_index(&restore_info(vec![], vec![])),
            None
        );
    }

    #[test]
    fn recovered_max_spans_orders_and_disputes() {
        // Max lives in disputes here — the fn must consider both collections.
        assert_eq!(
            recovered_max_trade_index(&restore_info(vec![3, 7], vec![12, 5])),
            Some(12)
        );
        // ...and the other way round.
        assert_eq!(
            recovered_max_trade_index(&restore_info(vec![40, 9], vec![2])),
            Some(40)
        );
    }

    #[test]
    fn a_dispute_message_without_a_peer_payload_yields_no_solver() {
        use mostro_core::message::Payload;

        // Nothing is guessed: without the pubkey there is no dispute chat, and
        // silently picking some other payload field would derive keys against
        // the wrong party.
        assert_eq!(admin_pubkey_from_payload(None), None);
        assert_eq!(admin_pubkey_from_payload(Some(&Payload::Amount(42))), None);
    }

    #[test]
    fn recovered_max_drops_negative_and_out_of_range_indexes() {
        // A negative index is not a real trade index — dropped, not counted.
        assert_eq!(
            recovered_max_trade_index(&restore_info(vec![-1, 8], vec![-99])),
            Some(8)
        );
        // Beyond u32::MAX: dropped rather than truncated into a small counter.
        let huge = i64::from(u32::MAX) + 1;
        assert_eq!(
            recovered_max_trade_index(&restore_info(vec![huge, 4], vec![])),
            Some(4)
        );
        // u32::MAX itself is dropped — reserved as the terminal index, since
        // storing it would make the next derive_trade_key overflow on +1.
        let terminal = i64::from(u32::MAX);
        assert_eq!(
            recovered_max_trade_index(&restore_info(vec![terminal, 4], vec![])),
            Some(4)
        );
        // Only u32::MAX present -> None (no safe floor to resync to).
        assert_eq!(
            recovered_max_trade_index(&restore_info(vec![terminal], vec![])),
            None
        );
        // All invalid -> None (nothing safe to resync to).
        assert_eq!(
            recovered_max_trade_index(&restore_info(vec![-1], vec![huge])),
            None
        );
    }

    #[test]
    fn the_daemon_dispute_id_is_read_from_a_dispute_payload() {
        use mostro_core::message::Payload;

        let id = uuid::Uuid::new_v4();
        assert_eq!(
            dispute_id_from_payload(Some(&Payload::Dispute(id, None))).as_deref(),
            Some(id.to_string().as_str())
        );

        // An acceptance carrying no dispute payload leaves the id unknown
        // rather than inventing one — the acceptance is malformed and
        // open_dispute fails closed on it.
        assert_eq!(dispute_id_from_payload(None), None);
        assert_eq!(dispute_id_from_payload(Some(&Payload::Amount(42))), None);
    }

    fn insert_pending_create(key: &str, request_id: u64) -> tokio::sync::oneshot::Receiver<Wake> {
        let (tx, rx) = tokio::sync::oneshot::channel::<Wake>();
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

    fn insert_pending_take(key: &str, request_id: u64) -> tokio::sync::oneshot::Receiver<Wake> {
        let (tx, rx) = tokio::sync::oneshot::channel::<Wake>();
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

    /// #215: a restore is nonce-less, so `take_matching_restore` must match its
    /// pending record by trade pubkey alone — that is what lets a `CantDo`
    /// rejecting a restore reach the waiter instead of timing out. It must NOT
    /// match a non-restore record, so order requests keep their nonce gate.
    #[tokio::test]
    async fn take_matching_restore_matches_restore_records_only() {
        let restore_key = "test-restore-pubkey";
        let order_key = "test-order-pubkey";

        // A pending Restore record (request_id 0, nonce-less).
        let (rtx, _rrx) = tokio::sync::oneshot::channel::<Wake>();
        pending_requests().lock().unwrap().insert(
            restore_key.to_string(),
            PendingRequest {
                request_id: 0,
                trade_index: 4,
                kind: PendingRequestKind::Restore,
                tx: Some(rtx),
            },
        );
        // A pending non-restore (Create) record on a different pubkey.
        let _orx = insert_pending_create(order_key, 7);

        // take_matching_restore ignores the order record (wrong kind)...
        assert!(take_matching_restore(order_key).is_none());
        assert!(pending_requests().lock().unwrap().contains_key(order_key));
        // ...and matches the restore record with no request_id involved.
        let taken = take_matching_restore(restore_key).expect("restore must match");
        assert!(matches!(taken.kind, PendingRequestKind::Restore));
        // Consumed on take (the CantDo path removes it exactly once).
        assert!(take_matching_restore(restore_key).is_none());

        // Cleanup the order record so global state does not leak to other tests.
        let _ = take_matching_request(order_key, Some(7));
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
        let _ = tx.send(Wake::from(DaemonReply::Confirmed {
            daemon_id: "d".to_string(),
        }));
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

        let (tx, _rx) = tokio::sync::oneshot::channel::<Wake>();
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

    /// `take_matching_dispute` mirrors the take rules for its own kind: only
    /// Dispute records, only with the exact nonce.
    #[tokio::test]
    async fn take_matching_dispute_only_consumes_dispute_records() {
        let take_key = "test-dispute-take-pubkey";
        let dispute_key = "test-dispute-dispute-pubkey";
        let _rx_t = insert_pending_take(take_key, 71);
        let _rx_d = register_dispute_request(dispute_key.to_string(), 72, 5);

        // A Take record is never consumed here, even with its exact nonce.
        assert!(take_matching_dispute(take_key, Some(71)).is_none());
        assert!(pending_requests().lock().unwrap().contains_key(take_key));

        assert!(take_matching_dispute(dispute_key, None).is_none());
        assert!(take_matching_dispute(dispute_key, Some(99)).is_none());
        assert!(matches!(
            take_matching_dispute(dispute_key, Some(72)),
            Some(DisputeMatch::Waiting(_))
        ));
        assert!(!pending_requests().lock().unwrap().contains_key(dispute_key));

        pending_requests().lock().unwrap().remove(take_key);
    }

    /// Builds the `UnwrappedMessage` for a daemon reply to an open-dispute,
    /// signed-by-sender semantics included, for driving the real dispatcher.
    /// `Action::CantDo` is a `Message::CantDo` on the wire, every other reply
    /// a `Message::Dispute` — the arms are reached through the dispatcher, not
    /// re-implemented in the test.
    fn dispute_reply_message(
        order_uuid: uuid::Uuid,
        request_id: u64,
        trade_index: u32,
        action: mostro_core::message::Action,
        payload: Option<mostro_core::message::Payload>,
    ) -> mostro_core::nip59::UnwrappedMessage {
        use mostro_core::message::{Action, Message};

        let message = match action {
            Action::CantDo => Message::cant_do(Some(order_uuid), Some(request_id), payload),
            other => Message::new_dispute(
                Some(order_uuid),
                Some(request_id),
                Some(trade_index as i64),
                other,
                payload,
            ),
        };
        let sender =
            nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey()).expect("valid mostro pubkey");
        mostro_core::nip59::UnwrappedMessage {
            message,
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::Timestamp::from(0u64),
        }
    }

    /// The acceptance, through the real dispatcher: its `DisputeInitiatedByYou`
    /// arm must wake the caller with the daemon's dispute id AND still fall
    /// through to the status arm that moves the trade to Dispute. The matcher's
    /// own test sees neither half — only this one pins the fall-through the
    /// arm's comment claims.
    #[tokio::test]
    async fn a_dispute_acceptance_wakes_the_caller_and_moves_the_trade() {
        use crate::api::types::OrderStatus;
        use mostro_core::message::{Action, Payload};

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let key = "test-dispute-accepted-pubkey";
        let dispute_uuid = uuid::Uuid::new_v4();

        // A disputable trade, bound to the generation the reply arrives on.
        let mut info = dummy_order_info(&order_id);
        info.status = OrderStatus::Active;
        order_book().upsert_order(info).await;
        store_trade_key_index(&order_id, 8).await;

        let mut rx = register_dispute_request(key.to_string(), 74, 8);

        dispatch_mostro_message(
            dispute_reply_message(
                order_uuid,
                74,
                8,
                Action::DisputeInitiatedByYou,
                Some(Payload::Dispute(dispute_uuid, None)),
            ),
            "test-dispute-accepted",
            key,
            8,
        )
        .await;

        // The waiting open_dispute gets the daemon's id — the one the solver
        // and the Kind 38386 event refer to — not a locally minted one.
        match rx.try_recv() {
            Ok(Wake {
                reply: DaemonReply::DisputeAccepted { dispute_id },
                ..
            }) => {
                assert_eq!(dispute_id, Some(dispute_uuid.to_string()));
            }
            _ => panic!("the acceptance must reach the waiting open_dispute"),
        }
        assert!(!pending_requests().lock().unwrap().contains_key(key));

        assert_eq!(
            order_book()
                .get_order(&order_id)
                .await
                .expect("order still cached")
                .status,
            OrderStatus::Dispute,
            "the acceptance is also the status update"
        );
    }

    /// #202 itself, driven through the arm that was dropping it: the CantDo arm
    /// resolves whatever request the nonce identifies, so a registered dispute
    /// is rejected through the same path as any other request. Before the
    /// dispute registered one, its rejection matched no pending request and was
    /// dropped — leaving a local dispute Open forever.
    #[tokio::test]
    async fn a_cantdo_rejection_reaches_the_waiting_open_dispute() {
        use mostro_core::error::CantDoReason;
        use mostro_core::message::{Action, Payload};

        let order_uuid = uuid::Uuid::new_v4();
        let key = "test-dispute-cantdo-pubkey";
        let mut rx = register_dispute_request(key.to_string(), 73, 6);

        dispatch_mostro_message(
            dispute_reply_message(
                order_uuid,
                73,
                6,
                Action::CantDo,
                Some(Payload::CantDo(Some(CantDoReason::NotAllowedByStatus))),
            ),
            "test-dispute-cantdo",
            key,
            6,
        )
        .await;

        match rx.try_recv() {
            Ok(Wake {
                reply: DaemonReply::Rejected { reason, .. },
                ..
            }) => {
                assert_eq!(reason, "NotAllowedByStatus");
            }
            _ => panic!("the rejection must reach the waiting open_dispute"),
        }
        assert!(!pending_requests().lock().unwrap().contains_key(key));
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

    /// Both sides learn the escrow is locked from these two actions — the
    /// only signal that the trade reached Active, which is what the daemon
    /// requires before it accepts a dispute or a fiat-sent (issue #203).
    #[test]
    fn escrow_locked_actions_imply_active() {
        use mostro_core::message::Action;

        assert_eq!(
            status_for_action(&Action::BuyerTookOrder),
            Some(OrderStatus::Active)
        );
        assert_eq!(
            status_for_action(&Action::HoldInvoicePaymentAccepted),
            Some(OrderStatus::Active)
        );
    }

    /// The public event is NIP-69's coarse view and stops updating once the
    /// trade turns private, so it may only fill an unknown or still-pending
    /// status — or announce a terminal one (issue #203).
    #[test]
    fn the_public_status_never_replaces_a_finer_local_one() {
        use OrderStatus as S;

        assert!(wire_status_applies(None, &S::InProgress));
        assert!(wire_status_applies(Some(&S::Pending), &S::InProgress));

        for local in [
            S::WaitingPayment,
            S::WaitingBuyerInvoice,
            S::Active,
            S::FiatSent,
            S::Dispute,
        ] {
            assert!(
                !wire_status_applies(Some(&local), &S::InProgress),
                "in-progress must not overwrite {local:?}"
            );
            assert!(
                !wire_status_applies(Some(&local), &S::Pending),
                "pending must not overwrite {local:?}"
            );
            assert!(
                wire_status_applies(Some(&local), &S::Canceled),
                "a terminal wire status must reach {local:?}"
            );
            assert!(wire_status_applies(Some(&local), &S::Success));
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
    /// the hold invoice (seller flow), `Order` carries the calculated sats
    /// (buyer flow), `pay-bond-invoice` maps to a stable BondRequired
    /// rejection, and action-only replies are still acceptances.
    #[test]
    fn classify_take_reply_maps_payload_shapes() {
        use mostro_core::message::{Action, Payload};
        use mostro_core::order::Status;

        // Seller taking a buy order: pay-invoice with the hold invoice.
        let so = small_order_with(Status::WaitingPayment, 7851);
        match classify_take_reply(
            &Action::PayInvoice,
            &Some(Payload::PaymentRequest(
                Some(so),
                "lnbc1invoice".into(),
                Some(7851),
            )),
        ) {
            DaemonReply::TakeAccepted {
                status,
                amount_sats,
                hold_invoice,
                ..
            } => {
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
            &Some(Payload::PaymentRequest(
                Some(so),
                "lnbc1invoice".into(),
                None,
            )),
        ) {
            DaemonReply::TakeAccepted { amount_sats, .. } => {
                assert_eq!(amount_sats, Some(500));
            }
            _ => panic!("expected TakeAccepted"),
        }

        // Buyer taking a sell order: add-invoice with the calculated sats.
        let so = small_order_with(Status::WaitingBuyerInvoice, 9526);
        match classify_take_reply(&Action::AddInvoice, &Some(Payload::Order(so))) {
            DaemonReply::TakeAccepted {
                status,
                amount_sats,
                hold_invoice,
                ..
            } => {
                assert_eq!(
                    status,
                    Some(crate::api::types::OrderStatus::WaitingBuyerInvoice)
                );
                assert_eq!(amount_sats, Some(9526));
                assert!(hold_invoice.is_none());
            }
            _ => panic!("expected TakeAccepted"),
        }

        // Anti-abuse bond: not supported — stable rejection marker.
        match classify_take_reply(&Action::PayBondInvoice, &None) {
            DaemonReply::Rejected { reason, message } => {
                assert_eq!(reason, "BondRequired");
                assert_eq!(message, "BondRequired");
            }
            _ => panic!("expected Rejected"),
        }

        // Action-only progression reply: still a genuine acceptance, with
        // the status derived from the action (see
        // classify_take_reply_derives_status_from_action_only_replies).
        match classify_take_reply(&Action::WaitingSellerToPay, &None) {
            DaemonReply::TakeAccepted {
                status,
                amount_sats,
                hold_invoice,
                ..
            } => {
                assert_eq!(status, Some(crate::api::types::OrderStatus::WaitingPayment));
                assert!(amount_sats.is_none());
                assert!(hold_invoice.is_none());
            }
            _ => panic!("expected TakeAccepted"),
        }
    }

    /// Inbound add-invoice (maker-buyer path): the Order payload carries the
    /// status and calculated sats to persist; anything else — notably the
    /// daemon's follow-up Peer payload with the counterparty's reputation —
    /// syncs nothing.
    #[test]
    fn add_invoice_sync_maps_payloads() {
        use mostro_core::message::Payload;
        use mostro_core::order::Status;

        // Real-world shape from the reproduction: status + calculated sats.
        let so = small_order_with(Status::WaitingBuyerInvoice, 484);
        match add_invoice_sync(&Some(Payload::Order(so))) {
            Some((status, amount)) => {
                assert_eq!(status, crate::api::types::OrderStatus::WaitingBuyerInvoice);
                assert_eq!(amount, Some(484));
            }
            None => panic!("expected Order payload to sync"),
        }

        // Unpriced amount must not persist as Some(0).
        let so = small_order_with(Status::WaitingBuyerInvoice, 0);
        let (_, amount) =
            add_invoice_sync(&Some(Payload::Order(so))).expect("Order payload must sync");
        assert_eq!(amount, None);

        // The daemon's follow-up Peer payload (counterparty reputation) must
        // sync nothing — it would otherwise clobber the just-written status.
        let peer = Payload::Peer(mostro_core::message::Peer {
            pubkey: String::new(),
            reputation: None,
        });
        assert!(add_invoice_sync(&Some(peer)).is_none());

        // No payload → nothing to sync.
        assert!(add_invoice_sync(&None).is_none());
    }

    /// A payload-less add-invoice must still imply WaitingBuyerInvoice, both
    /// for the ingest fallback and for action-only take replies.
    #[test]
    fn status_for_action_maps_add_invoice() {
        assert_eq!(
            status_for_action(&mostro_core::message::Action::AddInvoice),
            Some(crate::api::types::OrderStatus::WaitingBuyerInvoice)
        );

        // The mapping also feeds classify_take_reply: a payload-less
        // add-invoice take reply must carry the implied status instead of
        // persisting the trade as Pending.
        match classify_take_reply(&mostro_core::message::Action::AddInvoice, &None) {
            DaemonReply::TakeAccepted {
                status,
                amount_sats,
                hold_invoice,
                ..
            } => {
                assert_eq!(
                    status,
                    Some(crate::api::types::OrderStatus::WaitingBuyerInvoice)
                );
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
        assert!(may_reconcile_stored_id(
            "local-1",
            "daemon-1",
            Some("local-1")
        ));
        // Already the incoming id: nothing to rebind.
        assert!(!may_reconcile_stored_id(
            "daemon-1",
            "daemon-1",
            Some("local-1")
        ));
        // Stored id is a confirmed daemon id — a stale replay carrying an old
        // order id for the same (reused) trade index must not rebind it.
        assert!(!may_reconcile_stored_id(
            "daemon-1",
            "old-daemon-9",
            Some("local-1")
        ));
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

    /// PR #253 review round 2 (ermeme): a key derived after the global
    /// subscription started must join the refreshable coverage map — that is
    /// what lets the bulk Kind-14 path decrypt a solver assignment arriving
    /// after the 30-minute per-trade receiver expired. (The relay-filter
    /// refresh itself is a no-op here: no pool in unit tests.)
    #[tokio::test]
    async fn a_late_derived_key_joins_the_global_dm_coverage() {
        let keys = nostr_sdk::Keys::generate();
        let hex = keys.public_key().to_hex();

        ensure_global_dm_coverage(&keys, 91).await;
        {
            let map = global_dm_keys().read().await;
            let (stored, idx) = map.get(&hex).expect("key must be covered");
            assert_eq!(stored.public_key(), keys.public_key());
            assert_eq!(*idx, 91);
        }

        // Idempotent: a second call must not churn the map (or the relay).
        let before = global_dm_keys().read().await.len();
        ensure_global_dm_coverage(&keys, 91).await;
        assert_eq!(global_dm_keys().read().await.len(), before);
    }

    /// Startup replays arrive newest-first: a progression message for a
    /// trade already terminal is an out-of-order replay and must be
    /// skipped; open trades and unknown orders must not be blocked.
    #[tokio::test]
    async fn terminal_trades_block_replayed_status_syncs() {
        use mostro_core::message::Action;

        let canceled_id = uuid::Uuid::new_v4().to_string();
        let mut canceled = dummy_order_info(&canceled_id);
        canceled.status = crate::api::types::OrderStatus::Canceled;
        order_book().upsert_order(canceled).await;
        assert!(status_sync_blocked_by_terminal(&canceled_id, &Action::WaitingSellerToPay).await);

        let active_id = uuid::Uuid::new_v4().to_string();
        let mut active = dummy_order_info(&active_id);
        active.status = crate::api::types::OrderStatus::Active;
        order_book().upsert_order(active).await;
        assert!(!status_sync_blocked_by_terminal(&active_id, &Action::FiatSentOk).await);

        // Unknown order: nothing local to protect, sync proceeds.
        assert!(!status_sync_blocked_by_terminal("no-such-order", &Action::AddInvoice).await);
    }

    /// A stale Canceled replayed over a finished trade (the taker-timeout
    /// cancel of an order later re-taken and completed) must be skipped
    /// entirely at the handler level: no status write, no TradeUpdate.
    #[tokio::test]
    async fn replayed_cancel_over_terminal_trade_is_skipped() {
        use mostro_core::message::{Action, Message};

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let mut done = dummy_order_info(&order_id);
        done.status = crate::api::types::OrderStatus::Success;
        order_book().upsert_order(done).await;

        let mut rx = trade_updates_tx().subscribe();

        let sender =
            nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey()).expect("valid mostro pubkey");
        let unwrapped = mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(Some(order_uuid), None, None, Action::Canceled, None),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::Timestamp::from(0u64),
        };
        dispatch_mostro_message(unwrapped, "test-cancel-replay", "ff00ff00", 1).await;

        // The book entry keeps its terminal outcome...
        let status = order_book()
            .get_order(&order_id)
            .await
            .expect("order still cached")
            .status;
        assert_eq!(status, crate::api::types::OrderStatus::Success);

        // ...and no TradeUpdate was emitted for this order. Drain the
        // broadcast (parallel tests may emit for other orders) and filter
        // by our id; the suppressed emission would already be buffered by
        // the time dispatch returned.
        let mut leaked = false;
        while let Ok(update) = rx.try_recv() {
            if update.order_id == order_id {
                leaked = true;
            }
        }
        assert!(!leaked, "stale Canceled must not emit a TradeUpdate");
    }

    /// #326: the fingerprint-restore path must NOT overwrite the authoritative
    /// `daemon_id → index` mapping written at create/confirm time. A taken range
    /// order is re-published on the wire as a plain fixed-amount order, so its
    /// fingerprint can collide with an unrelated fixed order and yield the wrong
    /// index (here 21 instead of 16). Before the guard, that clobbered the trade
    /// key and release/cancel/rate were signed with the wrong key (`InvalidPeer`).
    #[tokio::test]
    async fn fingerprint_never_overwrites_authoritative_trade_index() {
        let daemon_id = uuid::Uuid::new_v4().to_string();

        // Authoritative binding from the request_id-correlated NewOrder reply.
        store_trade_key_index(&daemon_id, 16).await;

        // Fingerprint restore recovers a colliding index from another order.
        bridge_fingerprint_trade_index(&daemon_id, 21).await;

        assert_eq!(
            get_trade_key_index(&daemon_id).await,
            Some(16),
            "fingerprint restore must not overwrite the create-time trade index",
        );
    }

    /// The flip side of #326: with no prior mapping (genuine cold start, where
    /// the create/confirm binding was never persisted), the fingerprint path is
    /// still allowed to ESTABLISH the mapping so the maker keeps ownership.
    #[tokio::test]
    async fn fingerprint_establishes_trade_index_on_cold_start() {
        let daemon_id = uuid::Uuid::new_v4().to_string();

        bridge_fingerprint_trade_index(&daemon_id, 21).await;

        assert_eq!(
            get_trade_key_index(&daemon_id).await,
            Some(21),
            "fingerprint restore must establish a mapping when none exists yet",
        );
    }

    /// A stale BuyerTookOrder replayed over a finished trade must be skipped
    /// BEFORE its side effects: no peer-key/session/chat setup, no status
    /// write, no TradeUpdate. (The status assertions are the counterfactual:
    /// an unguarded arm would flip the book back to Active and emit.)
    #[tokio::test]
    async fn replayed_take_over_terminal_trade_has_no_side_effects() {
        use mostro_core::message::{Action, Message, Payload};

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let mut done = dummy_order_info(&order_id);
        done.status = crate::api::types::OrderStatus::Success;
        order_book().upsert_order(done).await;
        store_trade_key_index(&order_id, 93).await;

        let mut rx = trade_updates_tx().subscribe();

        let peer_hex = "0000000000000000000000000000000000000000000000000000000000000002";
        let so = mostro_core::order::SmallOrder::new(
            Some(order_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::Active),
            457,
            "USD".to_string(),
            None,
            None,
            100,
            "bank".to_string(),
            0,
            Some(peer_hex.to_string()),
            None,
            None,
            None,
            None,
        );
        let sender =
            nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey()).expect("valid mostro pubkey");
        let unwrapped = mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(
                Some(order_uuid),
                None,
                None,
                Action::BuyerTookOrder,
                Some(Payload::Order(so)),
            ),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::Timestamp::from(0u64),
        };
        dispatch_mostro_message(unwrapped, "test-take-replay", "ff00ff01", 93).await;

        // No session/chat state for the finished trade...
        assert!(crate::mostro::session::session_manager()
            .get_session(&order_id)
            .await
            .is_none());
        // ...the book keeps its terminal outcome (unguarded, this would be
        // Active again)...
        let status = order_book()
            .get_order(&order_id)
            .await
            .expect("order still cached")
            .status;
        assert_eq!(status, crate::api::types::OrderStatus::Success);
        // ...and nothing was emitted for this order.
        let mut leaked = false;
        while let Ok(update) = rx.try_recv() {
            if update.order_id == order_id {
                leaked = true;
            }
        }
        assert!(!leaked, "stale BuyerTookOrder must not emit a TradeUpdate");
    }

    /// #277 cause 3: the coverage seed must be a union that never evicts a
    /// key already in the map. A replace (or a missing seed at startup)
    /// leaves previous sessions' trades undecryptable — their kind-14s drop
    /// as no-matching-p-tag — and the next relay-filter rebuild silently
    /// unsubscribes them.
    #[tokio::test]
    async fn seeding_coverage_never_evicts_existing_keys() {
        let session = nostr_sdk::Keys::generate();
        ensure_global_dm_coverage(&session, 92).await;

        // No identity in unit tests → the derived set is empty; the seed
        // must still keep the session key and report it for the filter.
        let pubkeys = seed_global_dm_coverage().await;

        assert!(global_dm_keys()
            .read()
            .await
            .contains_key(&session.public_key().to_hex()));
        assert!(pubkeys.contains(&session.public_key()));
    }

    /// PR #252 review (ermeme P1): a create rejected for an unsupported node
    /// protocol must fail BEFORE any maker-ownership record is persisted. The
    /// content fingerprint is durable — were it stored, any later public order
    /// with the same kind/currency/amount/payment-method would be marked
    /// `is_mine` and bound to the unused trade key, including after restart.
    #[tokio::test]
    async fn an_unsupported_create_persists_no_maker_ownership() {
        let _guard = crate::mostro::pow::test_support::lock_pow();
        crate::mostro::protocol_version::set_protocol_version(
            &active_mostro_pubkey(),
            Some(1), // explicit v1: known-incompatible, no wait involved
        );

        let params = crate::api::types::NewOrderParams {
            kind: crate::api::types::OrderKind::Sell,
            fiat_amount: Some(100.0),
            fiat_amount_min: None,
            fiat_amount_max: None,
            fiat_code: "USD".to_string(),
            payment_method: "cashapp".to_string(),
            premium: 0.0,
            amount_sats: None,
        };
        let ck = order_content_key(
            &params.kind,
            &params.fiat_code,
            params.fiat_amount,
            params.fiat_amount_min,
            params.fiat_amount_max,
            &params.payment_method,
        );

        let err = create_order(params).await.unwrap_err();
        assert_eq!(err.to_string(), "UnsupportedNodeProtocol:1");

        // Neither the fingerprint nor anything else may have been stored —
        // the preflight must run before derivation and persistence.
        assert!(
            trade_key_for_order(&ck).await.is_none(),
            "a rejected create must leave no fingerprint mapping behind"
        );
    }

    #[tokio::test]
    async fn create_order_rejects_a_malformed_fiat_code() {
        // The fiat preflight runs before any node/derivation logic, so a
        // malformed code is rejected immediately with the InvalidFiatCode
        // marker Dart localizes (#304 review).
        let params = crate::api::types::NewOrderParams {
            kind: crate::api::types::OrderKind::Sell,
            fiat_amount: Some(100.0),
            fiat_amount_min: None,
            fiat_amount_max: None,
            fiat_code: "us1".to_string(),
            payment_method: "cashapp".to_string(),
            premium: 0.0,
            amount_sats: None,
        };
        let err = create_order(params).await.unwrap_err();
        assert!(
            err.to_string().contains("InvalidFiatCode"),
            "a malformed fiat code must be rejected at the preflight, got: {err}"
        );
    }
    #[tokio::test]
    async fn create_order_trims_the_fiat_code_before_validation() {
        // B3 (#304 review): fiat_code is normalized in place before validation
        // AND publication, so a padded-but-valid code clears the preflight. We
        // force a known post-preflight failure so the assertion isolates "the
        // fiat check passed" — an untrimmed " USD " would instead fail as
        // InvalidFiatCode (5 chars, spaces).
        let _guard = crate::mostro::pow::test_support::lock_pow();
        crate::mostro::protocol_version::set_protocol_version(&active_mostro_pubkey(), Some(1));
        let params = crate::api::types::NewOrderParams {
            kind: crate::api::types::OrderKind::Sell,
            fiat_amount: Some(100.0),
            fiat_amount_min: None,
            fiat_amount_max: None,
            fiat_code: "  USD  ".to_string(),
            payment_method: "cashapp".to_string(),
            premium: 0.0,
            amount_sats: None,
        };
        let err = create_order(params).await.unwrap_err();
        assert_eq!(
            err.to_string(),
            "UnsupportedNodeProtocol:1",
            "a padded-but-valid code must pass the fiat preflight (trimmed), got: {err}"
        );
    }

    /// A subscriber created before the emit receives the update; emitting
    /// with no subscribers must not error or panic.
    #[tokio::test]
    async fn trade_updates_reach_subscribers() {
        // No subscriber yet: emit is a silent no-op.
        emit_trade_update("order-nobody", crate::api::types::OrderStatus::Canceled);

        let mut stream = on_trade_updated().await.unwrap();
        emit_trade_update("order-x", crate::api::types::OrderStatus::Canceled);
        let update = stream
            .next()
            .await
            .expect("subscriber must receive the update");
        assert_eq!(update.order_id, "order-x");
        assert!(matches!(
            update.status,
            crate::api::types::OrderStatus::Canceled
        ));
    }

    /// The sweep only acts on positive daemon signals: pending republish
    /// (wipe for takers, resync for makers) and outright cancellation;
    /// absence from the book or ambiguous statuses leave the trade alone.
    #[test]
    fn sweep_action_requires_a_positive_book_signal() {
        use crate::api::types::OrderStatus as S;
        assert_eq!(
            sweep_action(true, Some(&S::Pending)),
            SweepAction::SyncPending
        );
        assert_eq!(sweep_action(false, Some(&S::Pending)), SweepAction::Wipe);
        for s in [S::Canceled, S::Expired, S::CanceledByAdmin] {
            assert_eq!(sweep_action(false, Some(&s)), SweepAction::Wipe);
            assert_eq!(sweep_action(true, Some(&s)), SweepAction::Wipe);
        }
        assert_eq!(sweep_action(false, None), SweepAction::Keep);
        for s in [S::InProgress, S::Active, S::Success] {
            assert_eq!(sweep_action(false, Some(&s)), SweepAction::Keep);
        }
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
            rating: 0.0,
            total_reviews: 0,
            days_active: 0,
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
            "aabbccdd", // peer_pubkey_hex (irrelevant, no trade key stored)
        )
        .await;
        // If we reach here without panicking the test passes.
    }

    // ── #259 per-order dispatch serialization ─────────────────────────────────

    /// Handlers of the same order never overlap, so a validate-then-mutate
    /// sequence cannot be interleaved by another handler of that order id.
    #[tokio::test]
    async fn handlers_of_the_same_order_run_one_at_a_time() {
        use std::sync::atomic::AtomicUsize;

        let order_id = uuid::Uuid::new_v4().to_string();
        let inside = Arc::new(AtomicUsize::new(0));
        let overlaps = Arc::new(AtomicUsize::new(0));

        let mut handles = Vec::new();
        for _ in 0..8 {
            let order_id = order_id.clone();
            let inside = Arc::clone(&inside);
            let overlaps = Arc::clone(&overlaps);
            handles.push(tokio::spawn(async move {
                let _guard = lock_order(&order_id).await;
                if inside.fetch_add(1, Ordering::SeqCst) != 0 {
                    overlaps.fetch_add(1, Ordering::SeqCst);
                }
                // Yield while holding the guard: this is the suspension point
                // a competing handler used to slip through.
                tokio::task::yield_now().await;
                inside.fetch_sub(1, Ordering::SeqCst);
            }));
        }
        for handle in handles {
            handle.await.expect("task joined");
        }

        assert_eq!(overlaps.load(Ordering::SeqCst), 0);
    }

    /// Serialization is per order, not global: one stalled handler must not
    /// stop every other trade. This deadlocks if the lock is ever made global.
    #[tokio::test]
    async fn distinct_orders_do_not_block_each_other() {
        let first = uuid::Uuid::new_v4().to_string();
        let second = uuid::Uuid::new_v4().to_string();

        let held = lock_order(&first).await;
        let _other = lock_order(&second).await;
        drop(held);
    }

    /// The registry tracks live work, not every order ever dispatched: entries
    /// no handler holds any more are dropped on the next acquisition.
    #[tokio::test]
    async fn the_registry_drops_locks_no_handler_holds() {
        let stale: Vec<String> = (0..16).map(|_| uuid::Uuid::new_v4().to_string()).collect();
        for order_id in &stale {
            drop(lock_order(order_id).await);
        }

        let live = uuid::Uuid::new_v4().to_string();
        let _guard = lock_order(&live).await;

        let map = order_locks().lock().expect("registry");
        assert!(stale.iter().all(|order_id| !map.contains_key(order_id)));
        assert!(map.contains_key(&live));
    }

    /// The #259 race, driven through the real dispatcher: a `Canceled` for a
    /// generation that is being replaced must not land in the middle of the
    /// retake persisting its own state.
    ///
    /// The retake side is represented by the lock `take_order` holds around its
    /// persistence block, because `take_order` itself needs a relay pool and a
    /// live daemon. The dispatcher is the code under test and runs unmodified,
    /// against a real `UnwrappedMessage`.
    ///
    /// The assertion is on the *order* of the two effects rather than on a
    /// timeout: unserialized, the dispatcher reaches `emit_trade_update` during
    /// the sleep below and its Canceled is observed before the retake's write.
    #[tokio::test(flavor = "multi_thread", worker_threads = 2)]
    async fn a_cancel_cannot_land_inside_a_concurrent_retake() {
        use crate::api::types::OrderStatus;
        use crate::rt::time::{sleep, Duration};
        use mostro_core::message::{Action, Message};

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        // Pending, so the terminal-status gate lets the Canceled through and
        // the arm runs its full sequence.
        order_book().upsert_order(dummy_order_info(&order_id)).await;

        let mut rx = trade_updates_tx().subscribe();

        let sender =
            nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey()).expect("valid mostro pubkey");
        let unwrapped = mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(Some(order_uuid), None, None, Action::Canceled, None),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::Timestamp::from(0u64),
        };

        // The retake enters its persistence block...
        let retake = lock_order(&order_id).await;

        // ...and the Canceled for the previous generation arrives while it runs.
        let dispatching = tokio::spawn(async move {
            dispatch_mostro_message(unwrapped, "test-cancel-retake", "ff00ff02", 1).await;
        });

        // Give the dispatcher every chance to run to completion.
        sleep(Duration::from_millis(100)).await;

        // The retake completes its own sequence and releases.
        emit_trade_update(&order_id, OrderStatus::Active);
        drop(retake);
        dispatching.await.expect("dispatch joined");

        // Effects for this order, in order: the retake's write, then the
        // Canceled. Reversed is exactly the corruption #259 is about.
        let mut seen = Vec::new();
        while let Ok(update) = rx.try_recv() {
            if update.order_id == order_id {
                seen.push(update.status);
            }
        }
        assert_eq!(seen, vec![OrderStatus::Active, OrderStatus::Canceled]);
    }

    /// Builds the `UnwrappedMessage` for a daemon `Canceled` of `order_uuid`,
    /// signed-by-sender semantics included, for driving the real dispatcher.
    fn canceled_message(order_uuid: uuid::Uuid) -> mostro_core::nip59::UnwrappedMessage {
        use mostro_core::message::{Action, Message};
        let sender =
            nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey()).expect("valid mostro pubkey");
        mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(Some(order_uuid), None, None, Action::Canceled, None),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::Timestamp::from(0u64),
        }
    }

    /// A message addressed to a superseded trade-key generation is dropped
    /// whole: after a retake rebinds the order to a newer key, the trailing
    /// `Canceled` of the replaced attempt arrives on the OLD key and must not
    /// touch the retaken trade — even with no concurrent handler to collide
    /// with (the case the lock alone cannot catch).
    #[tokio::test]
    async fn a_late_cancel_for_a_superseded_generation_is_dropped() {
        use crate::api::types::OrderStatus;

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        // The retaken trade: bound to generation 7, active, not terminal —
        // so a drop is attributable to the generation gate alone.
        let mut info = dummy_order_info(&order_id);
        info.status = OrderStatus::Active;
        order_book().upsert_order(info).await;
        store_trade_key_index(&order_id, 7).await;

        let mut rx = trade_updates_tx().subscribe();

        // The replaced attempt's Canceled, addressed to generation 3.
        dispatch_mostro_message(
            canceled_message(order_uuid),
            "test-gen-stale",
            "ff00ff03",
            3,
        )
        .await;

        let status = order_book()
            .get_order(&order_id)
            .await
            .expect("order still cached")
            .status;
        assert_eq!(status, OrderStatus::Active);

        let mut leaked = false;
        while let Ok(update) = rx.try_recv() {
            if update.order_id == order_id {
                leaked = true;
            }
        }
        assert!(!leaked, "superseded-generation Canceled must emit nothing");
    }

    /// Strictly-older only: a message on a key NEWER than the bound one must
    /// pass. That is a retake's first reply racing its own rebind — dropping
    /// it would time out every legitimate retake.
    #[tokio::test]
    async fn a_message_for_a_newer_generation_passes_the_gate() {
        use crate::api::types::OrderStatus;

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        // Pending: the stale binding of the previous attempt (generation 7)
        // is still in place; the new attempt's messages arrive on 9.
        order_book().upsert_order(dummy_order_info(&order_id)).await;
        store_trade_key_index(&order_id, 7).await;

        let mut rx = trade_updates_tx().subscribe();

        dispatch_mostro_message(
            canceled_message(order_uuid),
            "test-gen-newer",
            "ff00ff04",
            9,
        )
        .await;

        let mut seen = Vec::new();
        while let Ok(update) = rx.try_recv() {
            if update.order_id == order_id {
                seen.push(update.status);
            }
        }
        assert_eq!(seen, vec![OrderStatus::Canceled]);
    }

    /// Whether the per-order lock for `order_id` can be acquired right now.
    fn order_lock_is_free(order_id: &str) -> bool {
        match order_locks().lock().unwrap().get(order_id).cloned() {
            Some(lock) => lock.try_lock().is_ok(),
            None => true,
        }
    }

    /// The take reply that resolves a waiting `take_order` hands the
    /// dispatcher's per-order guard through the waiter channel: after
    /// `dispatch_mostro_message` returns, the lock is still held — it rides
    /// inside the unread `Wake` — so a second daemon message queued on the
    /// mutex cannot run before the woken take persists. Dropping the `Wake`
    /// (as `take_order`'s persistence block eventually does) releases it.
    #[tokio::test]
    async fn a_take_reply_hands_the_order_lock_to_the_waiter() {
        use mostro_core::message::{Action, Message};

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let trade_pk = "test-handoff-take-pubkey";
        let mut rx = insert_pending_take(trade_pk, 91);

        let sender =
            nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey()).expect("valid mostro pubkey");
        let unwrapped = mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(Some(order_uuid), Some(91), None, Action::AddInvoice, None),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::Timestamp::from(0u64),
        };
        dispatch_mostro_message(unwrapped, "test-handoff-live", trade_pk, 4).await;

        // Dispatch returned, but the lock traveled into the channel: held.
        assert!(
            !order_lock_is_free(&order_id),
            "guard must ride in the Wake"
        );

        let wake = rx.try_recv().expect("reply delivered");
        assert!(
            wake.order_guard.is_some(),
            "take reply must carry the guard"
        );
        drop(wake);
        assert!(order_lock_is_free(&order_id), "dropping the Wake releases");
    }

    /// A takeover whose waiter already timed out (receiver dropped) must not
    /// leave the handed guard stranded: the failed send returns the `Wake`,
    /// and dropping it inside the dispatcher releases the lock.
    #[tokio::test]
    async fn a_dead_take_waiter_releases_the_handed_lock() {
        use mostro_core::message::{Action, Message};

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let trade_pk = "test-handoff-dead-pubkey";
        drop(insert_pending_take(trade_pk, 92));

        let sender =
            nostr_sdk::PublicKey::from_hex(&active_mostro_pubkey()).expect("valid mostro pubkey");
        let unwrapped = mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(Some(order_uuid), Some(92), None, Action::AddInvoice, None),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::Timestamp::from(0u64),
        };
        dispatch_mostro_message(unwrapped, "test-handoff-dead", trade_pk, 4).await;

        assert!(
            order_lock_is_free(&order_id),
            "a failed handoff must release the lock, not strand it"
        );
    }
}

#[cfg(test)]
mod restore_e2e_tests {
    //! E2E smoke test for the RestoreSession handshake (#142).
    //! Requires a live regtest stack: mostrod + relay on ws://localhost:7000.
    //! Run with:  cargo test --lib restore_session_roundtrip -- --ignored --nocapture
    //! Ignored by default so it never runs in CI without the stack.
    use super::*;

    #[tokio::test]
    #[ignore = "requires live regtest daemon + relay on ws://localhost:7000"]
    async fn restore_session_roundtrip() {
        // Point ONLY at the local regtest relay.
        crate::api::nostr::initialize(Some(vec!["ws://localhost:7000".to_string()]))
            .await
            .expect("relay pool init");

        // Regtest daemon pubkey (from mostrod startup logs).
        crate::config::set_active_mostro_pubkey(Some(
            "bae71ea2566771ed45b1d267dc0c0753028fe960a7bc4aeee08a44da0cb91520".to_string(),
        ));

        // Fresh in-memory identity (no keyring needed — Rust never persists it).
        let id = crate::api::identity::create_identity()
            .await
            .expect("create identity");
        println!("[test] created identity pubkey={}", id.public_key);

        // Let the relay connection settle.
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;

        // Fire the handshake.
        println!("[test] calling restore_session()...");
        let result = restore_session().await;
        println!("[test] restore_session result: {:?}", result.is_ok());

        match result {
            Ok(info) => {
                println!(
                    "[test] ✓ round-trip OK — {} orders, {} disputes",
                    info.restore_orders.len(),
                    info.restore_disputes.len()
                );
            }
            Err(e) => panic!("[test] restore_session failed: {e}"),
        }
    }

    #[tokio::test]
    #[ignore = "requires live regtest daemon + relay on ws://localhost:7000"]
    async fn trade_then_restore_recovers_order() {
        crate::api::nostr::initialize(Some(vec!["ws://localhost:7000".to_string()]))
            .await
            .expect("relay pool init");
        crate::config::set_active_mostro_pubkey(Some(
            "bae71ea2566771ed45b1d267dc0c0753028fe960a7bc4aeee08a44da0cb91520".to_string(),
        ));
        let id = crate::api::identity::create_identity()
            .await
            .expect("create identity");
        println!("[test] identity A pubkey={}", id.public_key);
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        let params = crate::api::types::NewOrderParams {
            kind: crate::api::types::OrderKind::Sell,
            fiat_amount: Some(100.0),
            fiat_amount_min: None,
            fiat_amount_max: None,
            fiat_code: "USD".to_string(),
            payment_method: "cash".to_string(),
            premium: 0.0,
            amount_sats: None,
        };
        println!("[test] creating order...");
        let order = create_order(params)
            .await
            .expect("create_order (may need bond flow)");
        println!("[test] order created id={}", order.id);
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        println!("[test] calling restore_session()...");
        let info = restore_session().await.expect("restore round-trip");
        println!("[test] restored {} orders", info.restore_orders.len());
        for o in &info.restore_orders {
            println!("[test]   order_id={} status={}", o.order_id, o.status);
        }
        assert!(
            !info.restore_orders.is_empty(),
            "restore should recover the created order"
        );

        // #217 (grunch review): assert the resync actually ran. restore_session
        // must raise trade_key_index past every recovered trade, so the next
        // derive_trade_key can't reuse a key a recovered trade already owns.
        // This is the e2e assertion the PR body's coverage claim refers to; the
        // unit-level no-op/raise/idempotent/rollback behaviour is pinned in
        // identity.rs::load_derive_then_delete_identity_lifecycle.
        if let Some(max_recovered) = recovered_max_trade_index(&info) {
            let idx = crate::api::identity::get_identity()
                .await
                .expect("get_identity")
                .expect("identity present after restore")
                .trade_key_index;
            assert!(
                idx >= max_recovered,
                "trade_key_index ({idx}) must be >= max recovered index ({max_recovered}) after resync",
            );
        }
    }
}
