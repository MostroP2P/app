/// Orders API — read path for the public order book.
///
/// Subscribes to Kind 38383 events from the relay pool, caches locally,
/// applies filters, and exposes a stream for UI updates.
use anyhow::Result;
use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};

use crate::api::types::{NewOrderParams, OrderInfo, OrderKind, OrderStatus, TradeRole};
use crate::config::active_mostro_pubkey;
use crate::db::Storage;
use crate::mostro::actions;
use crate::mostro::pending::{
    classify_take_reply, detach_request_waiter, may_reconcile_stored_id, pending_local_uuid_for,
    pending_requests, purge_pending_request, remove_pending_request, take_matching_add_invoice,
    take_matching_dispute, take_matching_request, take_matching_restore, take_matching_take,
    DaemonReply, DisputeMatch, PendingRequest, PendingRequestKind, Wake,
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
/// The ingest path looks up a trade-key binding for every Kind 38383 event
/// (the `is_mine` cold-start restore), and for every order belonging to
/// somebody else that lookup misses — one storage round trip per event,
/// which on web is an IndexedDB transaction.
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
    /// The daemon's latest public (Kind 38383) view of an order whose book
    /// entry carries a local trade status instead — see
    /// [`Self::note_wire_order`]. Forgotten once that view is final
    /// ([`Self::forget_wire_order`]).
    wire_orders: Arc<std::sync::Mutex<HashMap<String, OrderInfo>>>,
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
            wire_orders: Arc::new(std::sync::Mutex::new(HashMap::new())),
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

    /// Publish the current book when a relay reports the end of stored events
    /// for the pending-book subscription. Returns whether it published.
    ///
    /// Every other emission is driven by an order arriving, so a node with
    /// no pending orders never emits: the UI (which stays in its loading
    /// state until the first emission, so an empty book is not flashed
    /// before the relay answers) then waits forever — on a cold start
    /// against an empty book, and every time the book screen remounts after
    /// the last order left the book. EOSE is the relay confirming there is
    /// nothing more to send, which is exactly the signal the UI is waiting
    /// on. Only the pending feed counts: the recent-changes and Kind 14
    /// feeds end their stored events too, and publishing on each would send
    /// the whole book once per relay per subscription.
    pub(crate) async fn publish_on_stored_events_end(
        &self,
        sub_id: &nostr_sdk::prelude::SubscriptionId,
    ) -> bool {
        if *sub_id != orders_subscription_id() {
            return false;
        }
        self.publish().await;
        true
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
        if self.remove_order_deferred(order_id).await {
            self.publish().await;
        }
    }

    /// Remove without notifying, reporting whether anything was there.
    ///
    /// The return value is what keeps a removal that changed nothing from
    /// publishing a whole-book snapshot.
    pub(crate) async fn remove_order_deferred(&self, order_id: &str) -> bool {
        let mut orders = self.orders.write().await;
        let before = orders.len();
        orders.retain(|o| o.id != order_id);
        orders.len() != before
    }

    /// Apply an order parsed from a Kind 38383 event.
    ///
    /// A finished order that is not ours is dropped rather than stored: the
    /// book filters to `Pending` for display, so nothing can ever show it, and
    /// nothing can act on it — but it would sit in the vector for the life of
    /// the process, inflating every snapshot clone and every bridge payload.
    ///
    /// Orders of ours are kept whatever their status, because the trade-detail
    /// screen looks them up in the book by id *after* the trade finishes.
    /// `ours` covers both roles — see the call site for why `is_mine` does not.
    ///
    /// Publishing follows the same rule as an upsert: a removal during a bulk
    /// ingest waits for the batch's single emission, and one from the relay
    /// firehose joins the coalescing window instead of sending a whole-book
    /// snapshot of its own.
    pub(crate) async fn apply_ingested_order(
        &self,
        order: OrderInfo,
        ours: bool,
        publish: Publish,
    ) {
        if !ours && crate::mostro::status::is_hard_terminal(&order.status) {
            // The removal is a no-op when the order was never in the book —
            // the common case, a stranger's order finishing unseen — and then
            // nothing is published either.
            if self.remove_order_deferred(&order.id).await && publish == Publish::Coalesced {
                self.schedule_publish();
            }
            return;
        }
        match publish {
            Publish::Coalesced => self.upsert_order_coalesced(order).await,
            Publish::WhenBatchEnds => self.upsert_order_deferred(order).await,
        }
    }

    pub(crate) fn subscribe(&self) -> broadcast::Receiver<Vec<OrderInfo>> {
        self.tx.subscribe()
    }

    /// Remember `order`, as parsed from a Kind 38383 event, as the daemon's
    /// latest public view of it.
    ///
    /// While a trade of ours lives, its book entry carries the local trade
    /// status wherever the wire's is refused (`wire_status_applies`) — the
    /// public `pending`/`in-progress` buckets are not a trade's status. That
    /// stops being right the moment the trade is wiped: the daemon published
    /// its `pending` republish *before* telling us the take was canceled, so
    /// nothing arrives afterwards to correct the entry, and the ex-taker never
    /// sees the order again. The wipe restores from this note
    /// ([`Self::settle_after_lost_take`]).
    pub(crate) fn note_wire_order(&self, order: &OrderInfo) {
        self.wire_notes().insert(order.id.clone(), order.clone());
    }

    /// Keep an existing note current. A no-op for orders never noted, so the
    /// relay firehose pays one map lookup per event.
    pub(crate) fn refresh_wire_order(&self, order: &OrderInfo) {
        if let Some(noted) = self.wire_notes().get_mut(&order.id) {
            *noted = order.clone();
        }
    }

    /// Drop the note of an order whose public view is final (hard-terminal).
    ///
    /// Only a wiped take reads its note back, and
    /// [`Self::settle_after_lost_take`] consumes it then. Every other take —
    /// one that went active, then ended in `success` or `canceled` — would
    /// otherwise leave its note here for the life of the process. Callers
    /// forget *after* the event's own wipe decision, so a never-active take
    /// ended by that event still settles from its final view.
    pub(crate) fn forget_wire_order(&self, order_id: &str) {
        self.wire_notes().remove(order_id);
    }

    /// The notes, even when a thread panicked while holding them. Every
    /// critical section is one map operation, so nothing is ever left
    /// half-applied — and a poisoned lock would otherwise switch the lost-take
    /// restore off for the rest of the session without a trace.
    fn wire_notes(&self) -> std::sync::MutexGuard<'_, HashMap<String, OrderInfo>> {
        self.wire_orders
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
    }

    #[cfg(test)]
    fn has_wire_note(&self, order_id: &str) -> bool {
        self.wire_notes().contains_key(order_id)
    }

    /// Hand the order back to the public book once the take behind its entry
    /// was wiped, the way every reference client does: without a trade of
    /// ours, the entry is whatever the wire says.
    ///
    /// * The latest public view is `pending` — the daemon republished the
    ///   order: the entry becomes that view, and the ex-taker can see and take
    ///   it again.
    /// * Anything else, or no view at all while the entry still carries a
    ///   non-`pending` local status: the entry is dropped, so the next Kind
    ///   38383 event lands on nothing local and applies as is. That covers a
    ///   `Canceled` that overtook the republish on the way here.
    /// * No view, entry already `pending`: already public, left alone.
    pub(crate) async fn settle_after_lost_take(&self, order_id: &str) {
        let noted = self.wire_notes().remove(order_id);
        let public_status = match &noted {
            Some(order) => Some(order.status.clone()),
            None => self.get_order(order_id).await.map(|o| o.status),
        };
        let short = crate::api::logging::short_id(order_id);
        match (noted, public_status) {
            (Some(order), Some(OrderStatus::Pending)) => {
                self.upsert_order(order).await;
                crate::api::logging::blog_info(
                    "orders",
                    format!("lost take order={short}: book entry restored to public pending"),
                );
            }
            (None, Some(OrderStatus::Pending)) => crate::api::logging::blog_info(
                "orders",
                format!("lost take order={short}: book entry already public pending"),
            ),
            (_, public) => {
                self.remove_order(order_id).await;
                crate::api::logging::blog_info(
                    "orders",
                    format!(
                        "lost take order={short}: book entry dropped (latest public view \
                         {public:?}) — the next Kind 38383 event applies as is"
                    ),
                );
            }
        }
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
    let now = crate::rt::unix_now();

    // One absolute expiry for both the local row and the daemon's request,
    // so a second boundary between the two cannot make them disagree.
    let requested_expiry = crate::config::order_expiry_override()
        .and_then(|secs| i64::try_from(secs).ok())
        .map(|secs| now.saturating_add(secs));
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
        // The test environment may ask the daemon for a short expiry; the
        // daemon's own default is an hour, shown here as the day-long
        // ceiling the app has always assumed until the book event says.
        expires_at: Some(requested_expiry.unwrap_or(now + 24 * 3600)),
        is_mine: true,
        // Own new order: the daemon's Kind 38383 confirmation carries the
        // real reputation snapshot; until then there is none to show.
        rating: 0.0,
        total_reviews: 0,
        days_active: 0,
    };

    // Compatibility preflight (PR #252 review): refuse an unsupported node
    // BEFORE deriving or persisting anything. The wrap re-checks as a defense,
    // but by that point the trade-key binding below is already stored —
    // durably — and a bail there would leave an orphaned maker-ownership
    // record behind.
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

    // Register the local-UUID → index binding before publishing the event,
    // so anything racing the confirmation (a cancel by local id, the
    // generation gate) can already resolve the key.
    store_trade_key_index(&order.id, trade_index).await;
    let trade_pk_hex = sender_keys.public_key().to_hex();

    // DO NOT add to order book or DB yet — wait for daemon confirmation first.
    // This avoids a phantom "pending" order when the daemon rejects (CantDo).

    let mostro_pubkey = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())?;
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
        requested_expiry,
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
        if let Err(e) = persist_trade_row(db, &trade).await {
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
    let mostro_pubkey = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())?;
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

    let mut trade = TradeInfo {
        id: uuid::Uuid::new_v4().to_string(),
        order: order_info,
        role,
        // Not the peer's trade pubkey: `creator_pubkey` on a book order is the
        // Mostro node itself (the 38383 event author) — seeding it here poisons
        // the durable peer record (#334). The real counterparty arrives via
        // `maybe_capture_peer_reveal` and is persisted below when already known.
        counterparty_pubkey: String::new(),
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
    persist_confirmed_take(&trade).await;
    // Subscribe to d-tag K38383 updates for this specific order so we still
    // see the public buckets the daemon does publish (in-progress once taken,
    // success / canceled at the end); the fine-grained states only ever arrive
    // as daemon messages.
    subscribe_single_order(&order_id).await;
    // Create (or replace, on a retake) the session so the chat API can look
    // up keys immediately. A confirmed take always wins over a session an
    // earlier confirmed take of this order left behind (#335) — a failed or
    // timed-out take returns above and leaves none.
    //
    // A session may already exist for two different reasons, and they must not
    // be treated alike: an earlier take whose `Canceled` never reached us left
    // a *stale* one (different trade_key_index — replace it), or
    // `maybe_capture_peer_reveal` created
    // this take's own session with peer + shared key already set (same index —
    // keep it, #334/#345). `install_session` distinguishes them by index.
    //
    // The only error it can return is the `order_id != order.id` mismatch,
    // i.e. a programming error here — log it rather than swallow it.
    if let Err(e) = crate::mostro::session::session_manager()
        .install_session(
            order_id.clone(),
            trade.role.clone(),
            trade_index,
            trade.order.clone(),
        )
        .await
    {
        crate::api::logging::blog_warn(
            "orders",
            format!("take_order: install_session failed: {e}"),
        );
    }
    // In the peer-reveal case the reveal ran before the trade row existed, so
    // its durable write was a no-op — replay it from the session now that the
    // row is persisted (#334). Mirror it on the returned struct too:
    // `TradeInfo.counterparty_pubkey` is what `tradeInfoToChatRoom` gates
    // the chat room on, so the value handed across the bridge must agree
    // with the row just written.
    if let Some(session) = crate::mostro::session::session_manager()
        .get_session(&order_id)
        .await
    {
        if let Some(peer) = session.peer_pubkey.filter(|p| !p.is_empty()) {
            if let Some(db) = crate::db::app_db::db() {
                if let Err(e) = db.update_trade_counterparty(&order_id, &peer).await {
                    log::warn!("[orders] take_order: failed to persist counterparty: {e}");
                }
            }
            trade.counterparty_pubkey = peer;
        }
    }

    Ok(trade)
}

/// Persist a confirmed take as its order's only trade row.
///
/// Rows are keyed by a fresh `TradeInfo.id` per take, so a plain save next to
/// a row an earlier take of the same order left behind — its `Canceled` never
/// reached this client, or it predates the wipe on a taker's own cancel —
/// makes two. Every lookup by order id then picks one of them
/// (`get_trade_by_order_id` is `LIMIT 1`, unordered), and the dead one's
/// status feeds the guards that gate the new trade's daemon messages while its
/// `trade_key_index` is what the chat-session rebuild derives keys from (the
/// durable twin of #335). One row per order id, the way every reference client
/// keys its trades. Saved through [`persist_trade_row`], which lifts the wipe
/// tombstone an earlier take of this order left, so the retake's own messages
/// are not dropped as replays.
async fn persist_confirmed_take(trade: &crate::api::types::TradeInfo) {
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    if let Err(e) = db.delete_trade_by_order_id(&trade.order.id).await {
        crate::api::logging::blog_warn(
            "orders",
            format!(
                "take_order: earlier rows for order={} not removed: {e}",
                crate::api::logging::short_id(&trade.order.id),
            ),
        );
    }
    if let Err(e) = persist_trade_row(db, trade).await {
        crate::api::logging::blog_warn(
            "orders",
            format!(
                "take_order: trade not persisted for order={}: {e}",
                crate::api::logging::short_id(&trade.order.id),
            ),
        );
    }
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
    let mostro_pubkey = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())?;

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
    let mostro_pubkey = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())?;
    let next_trade = next_trade_for_range_remainder(&order_id, TradeRole::Buyer).await?;
    let event_json = actions::fiat_sent(
        &identity_keys,
        &sender_keys,
        &mostro_pubkey,
        &order_id,
        trade_index,
        next_trade.clone(),
    )
    .await?;
    publish_event_json(&event_json).await?;
    crate::api::logging::blog_info(
        "orders",
        format!(
            "fiat_sent published for order={} trade_index={trade_index} next_trade_index={:?}",
            crate::api::logging::short_id(&order_id),
            next_trade.map(|(_, index)| index),
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
    let mostro_pubkey = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())?;
    let next_trade = next_trade_for_range_remainder(&order_id, TradeRole::Seller).await?;
    let event_json = actions::release(
        &identity_keys,
        &sender_keys,
        &mostro_pubkey,
        &order_id,
        trade_index,
        next_trade.clone(),
    )
    .await?;
    publish_event_json(&event_json).await?;
    crate::api::logging::blog_info(
        "orders",
        format!(
            "release published for order={} trade_index={trade_index} next_trade_index={:?}",
            crate::api::logging::short_id(&order_id),
            next_trade.map(|(_, index)| index),
        ),
    );
    Ok(())
}

/// The trade key the daemon should hand the remainder of a range order to,
/// when this client made the range and acts as `maker_role` on it: the
/// seller names it in the release, the buyer in fiat-sent. A fresh key,
/// already covered by the daemon-message subscriptions so the child's
/// `new-order` reaches this client. `None` only once the trade row says the
/// step leaves nothing behind: a fixed order, a taker's trade, or the other
/// role. A store or row that cannot be read is an error, never `None`: a
/// step sent without the key on a range order settles the trade and loses
/// the remainder for good.
async fn next_trade_for_range_remainder(
    order_id: &str,
    maker_role: TradeRole,
) -> Result<Option<(String, u32)>> {
    let db = crate::db::app_db::db().ok_or_else(|| {
        anyhow::anyhow!("no trade store: cannot tell whether order {order_id} leaves a remainder")
    })?;
    let trade = db.get_trade_by_order_id(order_id).await?.ok_or_else(|| {
        anyhow::anyhow!(
            "no trade row for order {order_id}: cannot tell whether it leaves a remainder"
        )
    })?;
    let is_range = trade.order.fiat_amount_min.is_some() && trade.order.fiat_amount_max.is_some();
    if !is_range || !trade.order.is_mine || trade.role != maker_role {
        return Ok(None);
    }
    let next = crate::api::identity::derive_trade_key().await?;
    let next_keys = crate::api::identity::get_active_trade_keys(next.index).await?;
    ensure_global_dm_coverage(&next_keys, next.index).await;
    // The remainder's `new-order` follows the release within a second. The
    // bulk filter refresh above is not confirmed by the relay before the
    // release goes out, so the key also gets the per-trade subscription a
    // create relies on, which is awaited before returning.
    subscribe_daemon_messages(next_keys.public_key(), next.index).await;
    Ok(Some((next.public_key, next.index)))
}

/// The trade row a daemon message proves this client owns: identity from the
/// decrypting key's `trade_index`, content from the payload's `SmallOrder`.
/// `None` when the payload names no order kind — a row without buy/sell is
/// unusable. Shared by the three paths that create a row from a message
/// instead of from a local action: the range-remainder adoption, the late
/// create confirmation, and DM-driven rebuild (#394 step 2).
#[allow(clippy::too_many_arguments)]
fn trade_row_from_small_order(
    order_id: &str,
    order: &mostro_core::order::SmallOrder,
    role: TradeRole,
    is_mine: bool,
    trade_index: u32,
    counterparty_pubkey: String,
    creator_pubkey: &str,
    status: OrderStatus,
) -> Option<crate::api::types::TradeInfo> {
    let order_kind = match order.kind {
        Some(mostro_core::order::Kind::Sell) => OrderKind::Sell,
        Some(mostro_core::order::Kind::Buy) => OrderKind::Buy,
        None => return None,
    };
    let is_range = order.min_amount.is_some() && order.max_amount.is_some();
    let now = crate::rt::unix_now();
    let info = OrderInfo {
        id: order_id.to_string(),
        kind: order_kind,
        status: status.clone(),
        amount_sats: (order.amount > 0).then_some(order.amount as u64),
        fiat_amount: (!is_range).then_some(order.fiat_amount as f64),
        fiat_amount_min: order.min_amount.map(|v| v as f64),
        fiat_amount_max: order.max_amount.map(|v| v as f64),
        fiat_code: order.fiat_code.clone(),
        payment_method: order.payment_method.clone(),
        premium: order.premium as f64,
        creator_pubkey: creator_pubkey.to_string(),
        created_at: order.created_at.unwrap_or(now),
        expires_at: order.expires_at,
        is_mine,
        rating: 0.0,
        total_reviews: 0,
        days_active: 0,
    };
    let step = match role {
        TradeRole::Seller => {
            crate::api::types::TradeStep::Seller(crate::api::types::SellerStep::OrderPublished)
        }
        TradeRole::Buyer => {
            crate::api::types::TradeStep::Buyer(crate::api::types::BuyerStep::OrderTaken)
        }
    };
    Some(crate::api::types::TradeInfo {
        id: order_id.to_string(),
        order: info,
        role,
        counterparty_pubkey,
        current_step: step,
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
    })
}

/// Adopts the remainder of a range order this client made. The daemon
/// publishes what is left of the range as a new pending order under the
/// next trade key the release named, and tells that key with a `new-order`
/// carrying the order — one no create is waiting for. The payload names
/// no trade keys (a create's confirmation does not either); ownership is
/// the message itself: decrypted with the key it arrived on, and carrying
/// that key's trade index, which the daemon echoes from the release. It
/// becomes a maker trade of this client's, listed and cancellable like the
/// parent was. Returns whether an order was adopted.
///
/// With the content fingerprint gone (#394 step 3) this is also the ONLY
/// path that restores a still-pending maker order on cold start: a create
/// sends `trade_index`, mostrod echoes it in the Pending ack, and the
/// replayed ack of a create whose confirmation timed out is adopted here as
/// a maker row once no pending record remains to intercept it (review
/// round 2).
async fn adopt_range_remainder(
    order_id: &str,
    kind: &mostro_core::message::MessageKind,
    trade_pubkey_hex: &str,
    trade_index: u32,
    event_ts: i64,
) -> bool {
    let Some(mostro_core::message::Payload::Order(order)) = &kind.payload else {
        return false;
    };
    if order.status != Some(mostro_core::order::Status::Pending)
        || kind.trade_index != Some(i64::from(trade_index))
    {
        return false;
    }
    let role = match order.kind {
        Some(mostro_core::order::Kind::Sell) => TradeRole::Seller,
        Some(mostro_core::order::Kind::Buy) => TradeRole::Buyer,
        None => return false,
    };
    let Some(db) = crate::db::app_db::db() else {
        return false;
    };
    if matches!(db.get_trade_by_order_id(order_id).await, Ok(Some(_))) {
        return false;
    }
    // A wipe tombstone covering this generation means this order id already
    // lived and died here — the adopted remainder was canceled before going
    // active. Its replayed new-order must not resurrect the row on the next
    // start (#394). A later generation is a new trade and adopts normally.
    if matches!(
        db.get_setting(&crate::db::settings_keys::trade_wiped(order_id))
            .await,
        Ok(Some(value)) if tombstone_covers(&value, trade_index)
    ) {
        crate::api::logging::blog_debug(
            "orders",
            format!(
                "skip range-remainder adoption for order={}: row wiped on purpose",
                crate::api::logging::short_id(order_id),
            ),
        );
        return false;
    }
    // Same cursor gate as the status arms and the DM rebuild (review
    // round 2): a replayed create ack older than the order's newest
    // accepted event — its maker already canceled it — must not resurrect
    // the row as Pending on the next start.
    if status_write_blocked(order_id, &kind.action, event_ts).await {
        return false;
    }
    let Some(trade) = trade_row_from_small_order(
        order_id,
        order,
        role,
        true,
        trade_index,
        String::new(),
        trade_pubkey_hex,
        OrderStatus::Pending,
    ) else {
        // Unreachable: the role match above already required a kind.
        return false;
    };
    store_trade_key_index(order_id, trade_index).await;
    if let Err(e) = persist_trade_row(db, &trade).await {
        crate::api::logging::blog_warn(
            "orders",
            format!(
                "range remainder order={} not persisted: {e}",
                crate::api::logging::short_id(order_id),
            ),
        );
        return false;
    }
    crate::api::logging::blog_info(
        "orders",
        format!(
            "adopted range remainder order={} trade_index={trade_index} src=kind14/NewOrder",
            crate::api::logging::short_id(order_id),
        ),
    );
    emit_trade_update(order_id, OrderStatus::Pending);
    true
}

/// Rebuilds the trade row a daemon message describes when none exists and
/// none was deliberately wiped (#394 step 2): the confirmation timed out but
/// the daemon proceeded, and this replayed message is the only recovery
/// signal there is. Ownership is the message itself — it decrypted with our
/// trade key — and the role is never guessed: it comes from the payload's
/// trade pubkeys, or from protocol semantics for the two actions whose
/// payload omits them (mostrod nulls both before `add-invoice`, flow.rs) —
/// `AddInvoice` only ever addresses the buyer side, `PayInvoice` the seller.
/// Anything less provable does not rebuild: a wrong role signs the wrong
/// context, the #326 failure class.
///
/// A rebuild recovers the whole trade: its progress, its signing key (the
/// durable trade-key binding), its counterparty — and its maker-ness. The
/// order kind is the maker's perspective (the maker of a sell order is its
/// seller, of a buy order its buyer), so the proven role plus the payload's
/// kind proves `is_mine` too — the same equivalence the Dart side leans on
/// (`_deriveIsBuyer`, review round 2). A rebuilt row still never claims
/// range metadata it cannot prove.
///
/// Emits the rebuilt status itself: the arm that follows sees the row
/// already holding it and skips its own write and update.
async fn rebuild_trade_from_dm(
    kind: &mostro_core::message::MessageKind,
    order_id: &str,
    trade_pubkey_hex: &str,
    trade_index: u32,
) -> Option<crate::api::types::TradeInfo> {
    use mostro_core::message::Action;
    // Actions that never describe a live trade to recover: NewOrder owns
    // row creation (create confirmation, range remainder, republish),
    // BondSlashed's payload amount is the slashed bond and must not seed
    // state, a Canceled with nothing local has nothing left to recover,
    // and the rest carry no order.
    if matches!(
        kind.action,
        Action::NewOrder
            | Action::Canceled
            | Action::CantDo
            | Action::BondSlashed
            | Action::RestoreSession
            | Action::AdminTookDispute
    ) {
        return None;
    }
    let order = match &kind.payload {
        Some(mostro_core::message::Payload::Order(o)) => o,
        Some(mostro_core::message::Payload::PaymentRequest(Some(o), _, _)) => o,
        _ => return None,
    };
    let buyer = order.buyer_trade_pubkey.as_deref();
    let seller = order.seller_trade_pubkey.as_deref();
    let role = if buyer.is_some_and(|pk| pk.eq_ignore_ascii_case(trade_pubkey_hex)) {
        TradeRole::Buyer
    } else if seller.is_some_and(|pk| pk.eq_ignore_ascii_case(trade_pubkey_hex)) {
        TradeRole::Seller
    } else if buyer.is_none() && seller.is_none() {
        match kind.action {
            Action::AddInvoice => TradeRole::Buyer,
            Action::PayInvoice => TradeRole::Seller,
            _ => return None,
        }
    } else {
        // The payload names parties and neither is our key: not ours to
        // rebuild, whatever key it decrypted with.
        crate::api::logging::blog_info(
            "orders",
            format!(
                "no rebuild for order={}: payload proves no role for this key",
                crate::api::logging::short_id(order_id),
            ),
        );
        return None;
    };
    let counterparty = match role {
        TradeRole::Buyer => seller,
        TradeRole::Seller => buyer,
    }
    .unwrap_or_default()
    .to_string();
    let status = order
        .status
        .and_then(map_core_status)
        .or_else(|| status_for_action(&kind.action))?;
    // The order kind is the maker's perspective — the maker of a sell order
    // is its seller, of a buy order its buyer — so the proven role plus the
    // payload's kind is proven maker-ness (review round 2).
    let is_mine = matches!(
        (order.kind.as_ref(), &role),
        (Some(mostro_core::order::Kind::Sell), TradeRole::Seller)
            | (Some(mostro_core::order::Kind::Buy), TradeRole::Buyer)
    );
    let db = crate::db::app_db::db()?;
    let trade = trade_row_from_small_order(
        order_id,
        order,
        role,
        is_mine,
        trade_index,
        counterparty,
        "",
        status.clone(),
    )?;
    store_trade_key_index(order_id, trade_index).await;
    if let Err(e) = persist_trade_row(db, &trade).await {
        crate::api::logging::blog_warn(
            "orders",
            format!(
                "rebuilt trade not persisted for order={}: {e}",
                crate::api::logging::short_id(order_id),
            ),
        );
        return None;
    }
    crate::api::logging::blog_info(
        "orders",
        format!(
            "rebuilt trade row from DM order={} role={:?} status={status:?} \
             trade_index={trade_index} src=kind14/{:?} (#394)",
            crate::api::logging::short_id(order_id),
            trade.role,
            kind.action,
        ),
    );
    emit_trade_update(order_id, status);
    Some(trade)
}

/// The maker row for a create whose confirmation outran its 10s waiter: the
/// daemon proceeded, the caller already returned NoDaemonResponse and
/// persisted nothing, and this echo — nonce-verified by the caller — is the
/// only record of the order there is (#394 step 2). Maker-ness is by
/// construction (only this attempt's create can echo its request_id), the
/// role comes from the order kind, and the payload is the published order,
/// min/max included, so a range order rebuilds whole.
async fn persist_late_create_confirmation(
    daemon_id: &str,
    kind: &mostro_core::message::MessageKind,
    trade_pubkey_hex: &str,
    trade_index: u32,
) {
    let Some(mostro_core::message::Payload::Order(order)) = &kind.payload else {
        crate::api::logging::blog_warn(
            "orders",
            format!(
                "late create confirmation for order={daemon_id} carries no order — \
                 nothing to persist"
            ),
        );
        return;
    };
    let role = match order.kind {
        Some(mostro_core::order::Kind::Sell) => TradeRole::Seller,
        Some(mostro_core::order::Kind::Buy) => TradeRole::Buyer,
        None => {
            crate::api::logging::blog_warn(
                "orders",
                format!("late create confirmation for order={daemon_id} names no kind"),
            );
            return;
        }
    };
    let status = order
        .status
        .and_then(map_core_status)
        .unwrap_or(OrderStatus::Pending);
    let Some(trade) = trade_row_from_small_order(
        daemon_id,
        order,
        role,
        true,
        trade_index,
        String::new(),
        trade_pubkey_hex,
        status.clone(),
    ) else {
        return;
    };
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    if let Err(e) = persist_trade_row(db, &trade).await {
        crate::api::logging::blog_warn(
            "orders",
            format!("late create confirmation not persisted for order={daemon_id}: {e}"),
        );
        return;
    }
    crate::api::logging::blog_info(
        "orders",
        format!(
            "late create confirmation persisted maker row order={} \
             trade_index={trade_index} status={status:?} (#394)",
            crate::api::logging::short_id(daemon_id),
        ),
    );
    emit_trade_update(daemon_id, status);
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
    let mostro_pubkey = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())?;
    let event_json = actions::cancel(
        &identity_keys,
        &sender_keys,
        &mostro_pubkey,
        &order_id,
        trade_index,
    )
    .await?;
    publish_event_json(&event_json).await?;

    apply_local_cancel(&order_id).await;

    crate::api::logging::blog_info(
        "orders",
        format!(
            "cancel published for order={} trade_index={trade_index}",
            crate::api::logging::short_id(&order_id),
        ),
    );
    Ok(())
}

/// The local side of a cancel request, applied once it is published.
///
/// The order leaves the in-memory book either way. The trade row depends on
/// how far the trade got:
///
/// * **Never active** (`pending` / `waiting-*`, see
///   [`cancellation_wipes_history`]), maker or taker: left untouched. The
///   daemon answers with `Canceled` — plus a Kind 38383 `canceled` when the
///   order dies with the cancel — and whichever lands first wipes such a row
///   together with its session ([`wipe_on_public_cancel`]): the same path a
///   waiting timeout takes, and what every reference client does (none of
///   them writes anything before the daemon replies). Marking
///   the row `Canceled` here first made that arm skip it as "already
///   Canceled", so the row and the session outlived the trade, and the row's
///   terminal status then refused the daemon's `pending` republish: the
///   ex-taker never saw the order in the book again. A cancel the daemon
///   refuses now also leaves a live trade looking live.
/// * **Anything further along**: marked `Canceled` straight away, as before,
///   so the UI reflects it without waiting for the daemon.
async fn apply_local_cancel(order_id: &str) {
    order_book().remove_order(order_id).await;
    let Some(db) = crate::db::app_db::db() else {
        return;
    };
    let status = match db.get_trade_by_order_id(order_id).await {
        Ok(Some(trade)) => trade.order.status,
        // No row: nothing to mark. A failed lookup is not guessed at — the
        // daemon's Canceled still settles the row either way.
        Ok(None) => return,
        Err(e) => {
            crate::api::logging::blog_warn(
                "orders",
                format!(
                    "cancel: trade lookup failed for order={}: {e}",
                    crate::api::logging::short_id(order_id),
                ),
            );
            return;
        }
    };
    if cancellation_wipes_history(&status) {
        crate::api::logging::blog_info(
            "orders",
            format!(
                "cancel order={} status={status:?}: never active — left for the daemon's Canceled",
                crate::api::logging::short_id(order_id),
            ),
        );
        return;
    }
    if let Err(e) = db
        .update_trade_fields(
            order_id,
            Some(crate::api::types::OrderStatus::Canceled),
            None,
            None,
        )
        .await
    {
        crate::api::logging::blog_warn(
            "orders",
            format!(
                "cancel status not persisted for order={}: {e}",
                crate::api::logging::short_id(order_id),
            ),
        );
    }
}

/// End a trade that never went active: its row, its session and — for a take
/// — the local status its book entry carried.
///
/// The paths that settle such a trade share it: the daemon's `Canceled`, the
/// public `canceled` event ([`wipe_on_public_cancel`]) and the stale sweep
/// (a `Canceled` this client never received). For a
/// **take** the order usually lives on — the daemon republishes it as
/// `pending` — so the entry is handed back to the public book
/// ([`OrderBook::settle_after_lost_take`]); without that, the ex-taker's entry
/// kept the dead trade's status and the order vanished from their book, while
/// every other client could take it (mostrix drops the same row for the same
/// reason). A **maker's** own order dies with the cancel, and its entry is
/// left to the Kind 38383 `canceled` the daemon publishes.
///
/// The row goes through [`wipe_trade_row`], which leaves the tombstone
/// (`wiped_at`, and the `wiped_index` of the trade key it covers) that turns
/// the order's replayed daemon messages into noise (#394): on the next start
/// neither the rebuild nor `adopt_range_remainder` brings the row back.
///
/// Nothing is touched when the row cannot be deleted: the row, the session
/// and the entry still describe the same trade.
async fn wipe_never_active_trade(
    order_id: &str,
    was_take: bool,
    wiped_at: i64,
    wiped_index: u32,
) -> Result<()> {
    if let Some(db) = crate::db::app_db::db() {
        wipe_trade_row(db, order_id, wiped_at, wiped_index).await?;
    }
    crate::mostro::session::session_manager()
        .remove_session(order_id)
        .await;
    if was_take {
        order_book().settle_after_lost_take(order_id).await;
    }
    Ok(())
}

/// End a trade of ours that never went active when a public Kind 38383 event
/// says its order is over, the way the daemon's `Canceled` does. Returns
/// whether the trade was wiped; the caller then leaves the row alone.
///
/// mostrod reports the end of a never-active trade twice, over two
/// subscriptions this client handles independently: the `canceled` event and
/// the kind-14 `Canceled` (cancel.rs publishes the event, then enqueues the
/// message). The `Canceled` arm wipes a row that still reads `pending` /
/// `waiting-*` but keeps one that already reads `Canceled` as history, so
/// letting the event write `Canceled` first made a maker's own cancel end in
/// My Trades or out of it depending on which of the two landed first — and
/// did the same to a taker whose maker cancelled. Wiping here too makes both
/// orders end alike. It also covers what only the event reports: an expired
/// pending order gets no message at all, and mostrod publishes its `Expired`
/// as `canceled` (nip33.rs `create_status_tags`).
///
/// Reads the trade row, never [`local_trade_status`]: that falls back to the
/// book, where a stranger's `pending` order would pass for a never-active
/// trade of ours. A trade that went further keeps its row, as in the
/// `Canceled` arm. A wipe that fails reports `false`, so the caller's usual
/// status write still lands and the row reads `Canceled` instead of a stale
/// `pending`.
async fn wipe_on_public_cancel(order_id: &str, wire: &OrderStatus) -> bool {
    if !matches!(
        wire,
        OrderStatus::Canceled | OrderStatus::Expired | OrderStatus::CanceledByAdmin
    ) {
        return false;
    }
    let Some(db) = crate::db::app_db::db() else {
        return false;
    };
    let short = crate::api::logging::short_id(order_id);
    let trade = match db.get_trade_by_order_id(order_id).await {
        Ok(Some(trade)) => trade,
        Ok(None) => return false,
        Err(e) => {
            crate::api::logging::blog_warn(
                "orders",
                format!("public {wire:?}: trade lookup failed for order={short}: {e}"),
            );
            return false;
        }
    };
    let local = &trade.order;
    if !cancellation_wipes_history(&local.status) {
        return false;
    }
    match wipe_never_active_trade(
        order_id,
        !local.is_mine,
        crate::rt::unix_now(),
        trade.trade_key_index,
    )
    .await
    {
        Ok(()) => {
            crate::api::logging::blog_info(
                "orders",
                format!(
                    "public {wire:?} before active (local {:?}) — removed trade for order={short}",
                    local.status
                ),
            );
            emit_trade_update(order_id, OrderStatus::Canceled);
            true
        }
        Err(e) => {
            crate::api::logging::blog_warn(
                "orders",
                format!("public {wire:?}: failed to remove trade for order={short}: {e}"),
            );
            false
        }
    }
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
    trade_pubkey: nostr_sdk::prelude::PublicKey,
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

    let mostro_pubkey =
        match nostr_sdk::prelude::PublicKey::from_hex(&crate::config::active_mostro_pubkey()) {
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
    let filter = nostr_sdk::prelude::Filter::new()
        .kind(nostr_sdk::prelude::Kind::PrivateDirectMessage)
        .author(mostro_pubkey)
        .pubkey(trade_pubkey)
        .limit(0);
    let trade_pubkey_hex = trade_pubkey.to_hex();
    let sub_id = daemon_message_subscription_id(&trade_pubkey_hex);
    if let Err(e) = client.subscribe(filter).with_id(sub_id.clone()).await {
        log::warn!("[orders] subscribe_daemon_messages subscribe failed: {e}");
        return;
    }

    crate::api::logging::blog_info(
        "orders",
        format!(
            "daemon-message subscription active for trade={}",
            &trade_pubkey_hex[..8]
        ),
    );

    // ── Event loop: spawned as a background task ──
    let unsub_client = client.clone();
    crate::rt::spawn(async move {
        use crate::rt::time::{timeout, Duration};
        use nostr_sdk::prelude::{ClientNotification, StreamExt};

        const IDLE_TIMEOUT_SECS: u64 = 30 * 60;
        let mut last_activity = crate::rt::time::Instant::now();

        loop {
            let remaining =
                Duration::from_secs(IDLE_TIMEOUT_SECS).saturating_sub(last_activity.elapsed());
            if remaining.is_zero() {
                break;
            }

            match timeout(remaining, rx.next()).await {
                Ok(Some(ClientNotification::Event { event, .. })) => {
                    if event.kind != nostr_sdk::prelude::Kind::PrivateDirectMessage {
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
                Ok(Some(ClientNotification::Shutdown)) | Ok(None) => break,
                Err(_) => break, // idle timeout
                Ok(Some(_)) => continue,
            }
        }

        // Drop the relay-side REQ. Without this the task exits but the
        // subscription lives on: relays cap concurrent REQs, and once past the
        // cap they answer CLOSED — which can take the order-book feed down
        // with it.
        if let Err(e) = unsub_client.unsubscribe(&sub_id).await {
            crate::api::logging::blog_warn(
                "orders",
                format!(
                    "daemon-message unsubscribe failed for trade={}: {e}",
                    &trade_pubkey_hex[..8]
                ),
            );
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
    //
    // `created_at` is the kind-14 event's own timestamp, not an inner field
    // (`unwrap_message_nip44` sets it from `event.created_at`) — the very key
    // relays order their stored events by. It is the only thing that separates
    // a live daemon reply from one being replayed out of a startup backlog,
    // and until now it was dropped here.
    let mostro_core::nip59::UnwrappedMessage {
        message: msg,
        sender,
        identity: _,
        signature: _,
        created_at: event_created_at,
    } = unwrapped;

    // Daemon authentication: the kind-14 event author (`sender`) must be the
    // active Mostro pubkey. The event signature is verified inside
    // `unwrap_incoming`, so `sender` is the cryptographically authoritative
    // origin.
    match nostr_sdk::prelude::PublicKey::from_hex(&crate::config::active_mostro_pubkey()) {
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
    // `age` is the event's timestamp against the local clock. A live reply reads
    // ~0; the global kind-14 feed carries no `since`, so on every start it
    // replays the node's full history and those read hours or days. Relays hand
    // that backlog back newest-first while the arms below apply each message as
    // if it had just arrived, so a large age marks writes that are about to
    // overwrite fresher state. Negative means the node's clock runs ahead.
    let event_ts = event_created_at.as_secs() as i64;
    let event_age_secs = crate::rt::unix_now().saturating_sub(event_ts);
    crate::api::logging::blog_info(
        "daemon-msg",
        format!(
            "action={:?} order_id={:?} trade_index={:?} trade_pubkey={} age={}s payload={}",
            kind.action,
            kind.id,
            kind.trade_index,
            &trade_pubkey_hex[..8],
            event_age_secs,
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
    // empty after a restart, and maker recovery there is DM-driven — the
    // late create confirmation persists the row, the durable binding plus
    // that row restore `is_mine` on the 38383 ingest (#394).
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

    // Classify the order's local row once, under the lock, for everything
    // below (issue #394): a row wiped on purpose turns the order's whole
    // replayed history into droppable noise, while a never-written row marks
    // the one case where the message itself is the recovery signal. Before
    // the peer capture on purpose (review round 1): capture's only guard
    // falls back to the book, where a wiped trade still reads `pending`, so
    // without this a stale reveal replay re-creates the session and the
    // incoming-chat subscription for a trade deleted on purpose. Take
    // replies consumed by the waiters pay one extra point read for it.
    let mut row_state = match &kind.id {
        Some(order_id) => trade_row_state(&order_id.to_string(), trade_index).await,
        None => RowState::Unknown,
    };

    // Durable peer capture (#334), BEFORE the take-waiter interception so a
    // take's first reply — consumed below and never seen by the per-action
    // arms — still reveals the counterparty. Any payload naming both trade
    // pubkeys qualifies, whichever action carries it. BondSlashed is exempt
    // for the same reason it skips the generation gate above: it may be
    // addressed to a superseded generation and must not write order state.
    // A wiped row is exempt the other way around: nothing of it remains to
    // reveal a peer for.
    if kind.action != Action::BondSlashed && !matches!(row_state, RowState::Wiped) {
        if let Some(order_id) = &kind.id {
            maybe_capture_peer_reveal(
                &order_id.to_string(),
                &kind.action,
                kind.payload.as_ref(),
                trade_index,
            )
            .await;
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

    // #394 step 2: a row that was never written is rebuilt from the message
    // that proves it, BEFORE the arms run — the write that follows lands on
    // a real row and the update the UI gets describes a trade that exists.
    // After the interceptions on purpose: a live take or create reply is
    // consumed above and its caller owns persistence; only messages nothing
    // is waiting for — the startup replay, a reconnect backlog — reach this.
    // Gated on the same cursor the arms consult: a Canceled with no row
    // still advances the cursor, so on a newest-first replay the older take
    // reply behind it must not rebuild what the daemon already ended
    // (review round 2).
    if matches!(row_state, RowState::NeverWritten) {
        if let Some(order_id) = &kind.id {
            let oid = order_id.to_string();
            if !status_write_blocked(&oid, &kind.action, event_ts).await {
                if let Some(rebuilt) =
                    rebuild_trade_from_dm(kind, &oid, trade_pubkey_hex, trade_index).await
                {
                    row_state = RowState::Exists(Box::new(rebuilt));
                }
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
                        // nothing. This echo carries the published order, so
                        // persist the maker row from it right here (#394
                        // step 2) — before it, recovery leaned on the Kind
                        // 38383 content fingerprint, which could also match
                        // a stranger's identical order (#326).
                        crate::api::logging::blog_info("daemon-msg", format!(
                            "NewOrder: late confirmation for timed-out create \
                             local={local_uuid} daemon={daemon_id} — persisting maker row"
                        ));
                        persist_late_create_confirmation(
                            &daemon_id,
                            kind,
                            trade_pubkey_hex,
                            pending.trade_index,
                        )
                        .await;
                    }
                } else if adopt_range_remainder(
                    &daemon_id,
                    kind,
                    trade_pubkey_hex,
                    trade_index,
                    event_ts,
                )
                .await
                {
                    // What was left of a range this client sold, now its own
                    // pending order under the next trade key.
                } else if !matches!(row_state, RowState::Wiped)
                    && resync_republished_maker_order(&daemon_id, kind, event_ts).await
                {
                    // The taker walked away (cancel or timeout) and the daemon
                    // put the order back on the book under the same id. Never
                    // for a wiped row (review round 1): its book entry can
                    // read in-progress after a foreign re-take, and a
                    // republished NewOrder newer than the cancel would then
                    // emit a phantom Pending for a trade deleted on purpose.
                } else {
                    // Cold start / reconnect (no record — in-memory state is
                    // empty after a restart), or an uncorrelated event that
                    // must not consume anything. Recovery for a NewOrder is
                    // NOT the prologue rebuild (it excludes NewOrder): a
                    // replayed create ack is adopted by
                    // `adopt_range_remainder` above, which just declined —
                    // row already there, tombstone, older than the cursor,
                    // or not a Pending order of this key's (#394).
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
                if status_arm_gate(&row_state, &kind.action, &oid) {
                    return;
                }
                // A stale Canceled replayed over a finished trade — e.g. the
                // taker-timeout cancel of an order that was later re-taken
                // and completed — must not overwrite the terminal outcome.
                // The wipe path below is unaffected: it starts from
                // pending/waiting, which are not terminal.
                if status_write_blocked(&oid, &kind.action, event_ts).await {
                    return;
                }
                record_status_event(&oid, event_ts).await;
                // Deliberately NOT blindly removed from the order book. The
                // book is fed only by the daemon's Kind 38383 events, and on
                // a taker-responsible timeout mostrod republishes the order
                // as `pending` BEFORE sending this Canceled (scheduler.rs:
                // update_order_event, then notify) — a blind remove here
                // races that republish and leaves the order missing from the
                // book until restart. A genuine cancel arrives as a 38383
                // status update and the UI already filters non-pending. What
                // a lost take's entry becomes is decided by the wipe below,
                // from the latest public view it has seen.
                match &row_state {
                    RowState::Exists(trade) if cancellation_wipes_history(&trade.order.status) => {
                        // The trade never went active (no peer, no chat, no
                        // exchange — typically a waiting-state timeout): wipe
                        // it instead of keeping a meaningless Canceled history
                        // row (mirrors v1, which deletes pending/waiting
                        // sessions on cancel), leaving the tombstone that
                        // reclassifies the order's replays as noise (#394).
                        match wipe_never_active_trade(
                            &oid,
                            !trade.order.is_mine,
                            event_ts,
                            trade.trade_key_index,
                        )
                        .await
                        {
                            Ok(()) => crate::api::logging::blog_info(
                                "orders",
                                format!("Canceled before active — removed trade for order={oid}"),
                            ),
                            Err(e) => log::warn!(
                                "[orders] failed to remove canceled trade for {oid}: {e}"
                            ),
                        }
                        // Push the cancellation to Dart: after a wipe there is
                        // no DB row left to poll, and after a timeout republish
                        // the book reads `pending` — screens need this signal.
                        emit_trade_update(&oid, crate::api::types::OrderStatus::Canceled);
                    }
                    // No row was ever written for this order here — a wipe by
                    // the public `canceled` (`wipe_on_public_cancel`) leaves a
                    // tombstone, and the gate above drops this message before
                    // it gets here. A write would match nothing, so none is
                    // made (it only logged "history kept" and a no-row
                    // warning); the cancellation still reaches the UI.
                    RowState::NeverWritten => {
                        crate::api::logging::blog_debug(
                            "orders",
                            format!(
                                "Canceled order={}: no trade row to settle",
                                crate::api::logging::short_id(&oid),
                            ),
                        );
                        emit_trade_update(&oid, crate::api::types::OrderStatus::Canceled);
                    }
                    _ => {
                        // The trade is over and no wipe is coming: its
                        // public-view note has no reader left.
                        order_book().forget_wire_order(&oid);
                        // Sync the Canceled status into the trade DB so My
                        // Trades reflects the cancellation immediately. A row
                        // that already reads Canceled (a replay) writes and
                        // emits nothing.
                        let changed = match crate::db::app_db::db() {
                            Some(db) => {
                                sync_trade_fields_if_changed(
                                    db,
                                    &oid,
                                    row_state.trade(),
                                    Some(crate::api::types::OrderStatus::Canceled),
                                    None,
                                    None,
                                )
                                .await
                            }
                            None => true,
                        };
                        if changed {
                            crate::api::logging::blog_info(
                                "orders",
                                format!(
                                    "status order={} →Canceled src=kind14/Canceled (history kept)",
                                    crate::api::logging::short_id(&oid),
                                ),
                            );
                            emit_trade_update(&oid, crate::api::types::OrderStatus::Canceled);
                        }
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
                    log::warn!("[orders] daemon-msg {:?} has no order id", kind.action);
                    return;
                }
            };
            if status_arm_gate(&row_state, &kind.action, &order_id) {
                return;
            }
            // Terminal guard for the status sync below: a stale replay over a
            // finished trade must not resurrect its status. (Peer capture
            // already ran in `maybe_capture_peer_reveal`, which carries its
            // own copy of this guard.) The legit re-take of a
            // timeout-canceled order is unaffected: its wiped row is
            // re-created by `take_order` (lifting the tombstone), and the wipe
            // handed the book entry back to the public view — `pending`, or no
            // entry at all — so the local status it reads passes.
            if status_write_blocked(&order_id, &kind.action, event_ts).await {
                return;
            }
            record_status_event(&order_id, event_ts).await;
            let small_order = match &kind.payload {
                Some(mostro_core::message::Payload::Order(o)) => o,
                _ => {
                    log::warn!(
                        "[orders] daemon-msg {:?} payload is not an Order",
                        kind.action
                    );
                    return;
                }
            };
            // Peer capture happens in `maybe_capture_peer_reveal` before the
            // dispatch arms (#334) — this arm only owns the status sync.

            // Sync the order status from the payload so the trade doesn't stay
            // stuck at Pending in the DB and in-memory order book. Both actions
            // mean the escrow is locked, so a payload without an explicit
            // status still implies Active.
            if let Some(new_status) = small_order
                .status
                .and_then(map_core_status)
                .or_else(|| status_for_action(&kind.action))
            {
                order_book().update_order_status(&order_id, new_status.clone()).await;
                let changed = match crate::db::app_db::db() {
                    Some(db) => {
                        sync_trade_fields_if_changed(
                            db,
                            &order_id,
                            row_state.trade(),
                            Some(new_status.clone()),
                            None,
                            None,
                        )
                        .await
                    }
                    None => true,
                };
                if changed {
                    crate::api::logging::blog_info(
                        "orders",
                        format!(
                            "status order={} →{new_status:?} src=kind14/{:?}",
                            crate::api::logging::short_id(&order_id),
                            kind.action,
                        ),
                    );
                    emit_trade_update(&order_id, new_status);
                }
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
            if status_arm_gate(&row_state, &kind.action, &order_id) {
                return;
            }
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
            if status_write_blocked(&order_id, &kind.action, event_ts).await {
                return;
            }
            record_status_event(&order_id, event_ts).await;
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
            let changed = match crate::db::app_db::db() {
                Some(db) => {
                    sync_trade_fields_if_changed(
                        db,
                        &order_id,
                        row_state.trade(),
                        Some(new_status.clone()),
                        None,
                        amount,
                    )
                    .await
                }
                None => true,
            };
            // After the book update and the DB attempt, so a listener that
            // reacts to the push (e.g. auto-opening the add-invoice screen)
            // reads the freshest state available; a logged DB failure does
            // not suppress the notification — only a proven no-op does.
            if changed {
                crate::api::logging::blog_info(
                    "orders",
                    format!(
                        "status order={} →{new_status:?} src=kind14/AddInvoice",
                        crate::api::logging::short_id(&order_id),
                    ),
                );
                emit_trade_update(&order_id, new_status);
            }
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
            if status_arm_gate(&row_state, &kind.action, &order_id) {
                return;
            }
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
            if status_write_blocked(&order_id, &kind.action, event_ts).await {
                return;
            }
            record_status_event(&order_id, event_ts).await;
            // Save the hold invoice and update status to WaitingPayment. A
            // replay carrying the invoice and amount the row already holds
            // writes and emits nothing.
            order_book().update_order_status(&order_id, crate::api::types::OrderStatus::WaitingPayment).await;
            let changed = match crate::db::app_db::db() {
                Some(db) => {
                    sync_trade_fields_if_changed(
                        db,
                        &order_id,
                        row_state.trade(),
                        Some(crate::api::types::OrderStatus::WaitingPayment),
                        Some(bolt11),
                        amount,
                    )
                    .await
                }
                None => true,
            };
            if changed {
                crate::api::logging::blog_info(
                    "orders",
                    format!(
                        "status order={} →WaitingPayment src=kind14/PayInvoice",
                        crate::api::logging::short_id(&order_id),
                    ),
                );
                emit_trade_update(&order_id, crate::api::types::OrderStatus::WaitingPayment);
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
        | Action::InvoiceUpdated
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
            if status_arm_gate(&row_state, &kind.action, &order_id) {
                return;
            }
            // Map action → OrderStatus for DB sync (shared with the take
            // reply classification).
            let new_status = status_for_action(&kind.action);
            if let Some(status) = new_status {
                if status_write_blocked(&order_id, &kind.action, event_ts).await {
                    return;
                }
                record_status_event(&order_id, event_ts).await;
                order_book().update_order_status(&order_id, status.clone()).await;
                let changed = match crate::db::app_db::db() {
                    Some(db) => {
                        sync_trade_fields_if_changed(
                            db,
                            &order_id,
                            row_state.trade(),
                            Some(status.clone()),
                            None,
                            None,
                        )
                        .await
                    }
                    None => true,
                };
                if is_hard_terminal(&status) {
                    // Finished without a wipe: the note has no reader left.
                    order_book().forget_wire_order(&order_id);
                }
                let settled = status == crate::api::types::OrderStatus::SettledHoldInvoice;
                if changed {
                    crate::api::logging::blog_info(
                        "orders",
                        format!(
                            "status order={} →{status:?} src=kind14/{:?}",
                            crate::api::logging::short_id(&order_id),
                            kind.action,
                        ),
                    );
                    emit_trade_update(&order_id, status);
                }
                if settled {
                    // The seller hears nothing further from the daemon about
                    // the payout; confirm it against the public book. Spawned
                    // even when the row already read settled: a replay is
                    // another chance to finish a payout confirmation a kill
                    // interrupted, and the check no-ops once Success landed.
                    crate::rt::spawn(confirm_payout_completion(order_id.clone()));
                }
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
                // mostro-core 0.14.6: the node is draining (e.g. before a
                // Lightning node migration) and refuses new orders and takes;
                // actions on existing orders keep working. Marker only, no
                // prose: Dart maps `MaintenanceMode` to a localized message.
                "MaintenanceMode" => "MaintenanceMode".to_string(),
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
/// The daemon also sends `new-order` to the maker of a taken order it put
/// back on the book: the taker cancelled, or let the waiting window lapse,
/// and the order is pending again under the same id (mostrod's cancel path
/// republishes and then notifies the maker with the order payload).
///
/// A trade this client still holds in a waiting state is synced back to
/// `Pending` right away — the stale sweep would do the same, but only after
/// its 30-minute cadence and 15-minute minimum age, so until then My Trades
/// and the trade detail kept showing a take that no longer exists. A trade
/// this client never held, one already past the waiting states, or a stale
/// replay is left alone. Returns whether the trade was resynced.
async fn resync_republished_maker_order(
    order_id: &str,
    kind: &mostro_core::message::MessageKind,
    event_ts: i64,
) -> bool {
    let republished_pending = matches!(
        &kind.payload,
        Some(mostro_core::message::Payload::Order(order))
            if order.status == Some(mostro_core::order::Status::Pending)
    );
    if !republished_pending {
        return false;
    }
    let Some(local) = current_local_status(order_id).await else {
        return false;
    };
    if !matches!(
        local,
        OrderStatus::WaitingPayment | OrderStatus::WaitingBuyerInvoice | OrderStatus::InProgress
    ) {
        return false;
    }
    if status_write_blocked(order_id, &kind.action, event_ts).await {
        return false;
    }
    record_status_event(order_id, event_ts).await;
    crate::api::logging::blog_info(
        "orders",
        format!(
            "status order={} {local:?}→Pending src=kind14/NewOrder (taker walked away, order republished)",
            crate::api::logging::short_id(order_id),
        ),
    );
    order_book()
        .update_order_status(order_id, OrderStatus::Pending)
        .await;
    if let Some(db) = crate::db::app_db::db() {
        if let Err(e) = db
            .update_trade_fields(order_id, Some(OrderStatus::Pending), None, None)
            .await
        {
            crate::api::logging::blog_warn(
                "orders",
                format!(
                    "republished status not persisted for order={}: {e}",
                    crate::api::logging::short_id(order_id),
                ),
            );
        }
    }
    emit_trade_update(order_id, OrderStatus::Pending);
    true
}

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

/// Newest daemon-message timestamp already applied to `order_id`'s status.
///
/// `None` when nothing was ever recorded, or when there is no durable store
/// (web, until #233) — both mean "no high-water mark", which fails open.
async fn load_status_cursor(order_id: &str) -> Option<i64> {
    let db = crate::db::app_db::db()?;
    db.get_setting(&crate::db::settings_keys::status_cursor(order_id))
        .await
        .ok()
        .flatten()?
        .parse()
        .ok()
}

/// Record that a daemon message dated `event_created_at` was allowed to write
/// `order_id`'s status.
///
/// The mark is stored **raw**, in the node's own time domain, because that is
/// the domain [`status_write_blocked`] compares against. Clamping it to the
/// local clock — as the chat cursor does — is wrong here: there the cursor is a
/// subscription `since`, where a low value only asks for more than needed, but
/// here it is an ordering comparator. With a local clock behind the node's, a
/// newest event at 3000 would store 1000 and a *later, older* event at 2000
/// would then pass `2000 < 1000` and overwrite it — the very replay regression
/// this guard exists to stop (PR #396 review).
///
/// The freedom that costs is bounded by a skew check instead: an event dated
/// implausibly far ahead of the local clock does not move the mark, so one
/// malformed timestamp cannot silence an order's status for good. Same
/// tolerance the chat envelope already applies to node-adjacent events. A node
/// whose clock is genuinely further ahead makes the guard inert for that order
/// rather than wrong — logged, because that is a silent degradation otherwise.
/// Ordering between the node's own events survives any uniform skew: they all
/// carry the same clock.
///
/// The read-modify-write is safe because every caller runs under this order's
/// dispatch lock.
///
/// Best-effort, like every other write here: losing it costs the durability of
/// the guard, not its correctness within the session.
async fn record_status_event(order_id: &str, event_created_at: i64) {
    let horizon =
        crate::rt::unix_now().saturating_add(crate::nostr::transport::MAX_CLOCK_SKEW_SECS as i64);
    if event_created_at > horizon {
        crate::api::logging::blog_warn(
            "orders",
            format!(
                "status cursor not advanced for order={}: event is {}s ahead of the local clock",
                crate::api::logging::short_id(order_id),
                event_created_at.saturating_sub(horizon),
            ),
        );
        return;
    }
    if load_status_cursor(order_id)
        .await
        .is_some_and(|c| c >= event_created_at)
    {
        return;
    }
    if let Some(db) = crate::db::app_db::db() {
        let key = crate::db::settings_keys::status_cursor(order_id);
        if let Err(e) = db.set_setting(&key, &event_created_at.to_string()).await {
            crate::api::logging::blog_warn(
                "orders",
                format!(
                    "status cursor persist failed order={}: {e}",
                    crate::api::logging::short_id(order_id),
                ),
            );
        }
    }
}

/// Whether a daemon message may write `order_id`'s status.
///
/// Two independent reasons to refuse, both about the same thing — the startup
/// backlog:
///
/// * the trade already sits in a hard-terminal status
///   ([`status_sync_blocked_by_terminal`]), and
/// * the message is **older** than one whose write was already applied.
///
/// The second is the general rule and the first is defence in depth, kept
/// because it is the only one that still works without a durable store (web),
/// where it reads the in-memory book.
///
/// Strictly older is what is refused: the daemon emits several messages for one
/// order within the same second (the `PayInvoice` reputation follow-up, for
/// one), and those are genuine, in-order traffic.
///
/// That strictness is also why the callers record the mark *before* the writes
/// they gate, rather than after a successful one (PR #396 review). The mark
/// answers "which message have I decided to accept", not "which write
/// succeeded" — every write here is best-effort, `record_status_event`
/// included, and there is no transaction spanning the settings key and the
/// trade row. Recording afterwards would leave the mark unmoved when a write
/// fails, and then a *strictly older* message from the same backlog would be
/// applied over the row that just failed to update — trading a fault that
/// heals for one that corrupts. It heals because the failed message is not
/// blocked on its next delivery: its timestamp equals the mark, and equal
/// passes. The global feed carries no `since`, so the next start replays it.
async fn status_write_blocked(
    order_id: &str,
    action: &mostro_core::message::Action,
    event_created_at: i64,
) -> bool {
    if status_sync_blocked_by_terminal(order_id, action).await {
        return true;
    }
    if let Some(cursor) = load_status_cursor(order_id).await {
        if event_created_at < cursor {
            crate::api::logging::blog_info(
                "orders",
                format!(
                    "skip replayed {action:?} order={}: event is {}s older than the last applied",
                    crate::api::logging::short_id(order_id),
                    cursor.saturating_sub(event_created_at),
                ),
            );
            return true;
        }
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

/// Why a daemon message's order id has — or does not have — a local trade row.
///
/// "No row" has two opposite meanings (issue #394): a pre-active cancel or the
/// stale sweeper deleted it **on purpose**, in which case the order's replayed
/// history is noise; or it was **never written** (a confirmation timeout while
/// the daemon proceeded), in which case the message is the only recovery
/// signal there is. Classified once per dispatched message, under the
/// per-order lock, from the row and the wipe tombstone
/// (`settings_keys::trade_wiped`).
enum RowState {
    /// The row exists; carried so arms don't read it again.
    Exists(Box<crate::api::types::TradeInfo>),
    /// Deleted on purpose: status arms drop the message whole — no cursor
    /// advance, no write, no TradeUpdate.
    Wiped,
    /// No row and no tombstone covering the message's generation: never
    /// persisted, or a later take of a wiped order. The dispatch prologue
    /// rebuilds the row when the message proves one
    /// (`rebuild_trade_from_dm`, #394 step 2); a message that proves
    /// nothing falls through to the pre-#394 path — the write warns
    /// "matched no row", the update still emits.
    NeverWritten,
    /// No store yet, or the store failed to answer: nothing to classify on,
    /// arms behave exactly as before this classification existed.
    Unknown,
}

impl RowState {
    /// The row snapshot, when there is one.
    fn trade(&self) -> Option<&crate::api::types::TradeInfo> {
        match self {
            RowState::Exists(trade) => Some(trade),
            _ => None,
        }
    }
}

/// Whether a wipe tombstone covers a message decrypted with `trade_index`'s
/// key. The tombstone records the generation it wiped
/// (`<wiped_at>:<trade_index>`): a message on a LATER index belongs to a new
/// take of the same order — a different trade, possibly one whose
/// confirmation timed out — and must stay classified `NeverWritten` so the
/// DM rebuild can recover it (review round 2, probe P5). A tombstone whose
/// index does not parse covers every generation, degrading to the
/// pre-generation behavior: replays dropped, recovery muted.
fn tombstone_covers(value: &str, trade_index: u32) -> bool {
    let wiped_index = value
        .split(':')
        .nth(1)
        .and_then(|s| s.parse::<u32>().ok())
        .unwrap_or(u32::MAX);
    trade_index <= wiped_index
}

async fn trade_row_state(order_id: &str, trade_index: u32) -> RowState {
    let Some(db) = crate::db::app_db::db() else {
        return RowState::Unknown;
    };
    match db.get_trade_by_order_id(order_id).await {
        Ok(Some(trade)) => RowState::Exists(Box::new(trade)),
        Ok(None) => match db
            .get_setting(&crate::db::settings_keys::trade_wiped(order_id))
            .await
        {
            Ok(Some(value)) if tombstone_covers(&value, trade_index) => RowState::Wiped,
            Ok(Some(_)) | Ok(None) => RowState::NeverWritten,
            Err(e) => {
                crate::api::logging::blog_warn(
                    "orders",
                    format!("tombstone lookup failed for order={order_id}: {e}"),
                );
                RowState::Unknown
            }
        },
        Err(e) => {
            crate::api::logging::blog_warn(
                "orders",
                format!("trade lookup failed for order={order_id}: {e}"),
            );
            RowState::Unknown
        }
    }
}

/// Gate for the status-writing dispatch arms (issue #394). `true` means drop
/// the message whole. A wiped row is the normal drop on every restart replay,
/// so it logs at debug. A never-written row reaching an arm means the
/// prologue rebuild already declined — the message proved no trade — so it
/// falls through to the pre-#394 behavior and logs the recovery candidate it
/// still is: the line that measured DM coverage before the fingerprint went
/// (#394 step 3), kept because a gap here is a lost trade.
fn status_arm_gate(
    row_state: &RowState,
    action: &mostro_core::message::Action,
    order_id: &str,
) -> bool {
    match row_state {
        RowState::Wiped => {
            crate::api::logging::blog_debug(
                "orders",
                format!(
                    "drop {action:?} order={}: trade row wiped on purpose",
                    crate::api::logging::short_id(order_id),
                ),
            );
            true
        }
        RowState::NeverWritten => {
            crate::api::logging::blog_info(
                "orders",
                format!(
                    "{action:?} order={} has no trade row (never persisted) — \
                     recovery candidate (#394)",
                    crate::api::logging::short_id(order_id),
                ),
            );
            false
        }
        RowState::Exists(_) | RowState::Unknown => false,
    }
}

/// Deletes `order_id`'s trade row **on purpose**, leaving the wipe tombstone
/// that reclassifies the order's replayed daemon messages as noise
/// (issue #394). Shared by the two wipe paths: the pre-active cancel and the
/// stale sweeper. Session removal and the UI push stay with the callers —
/// they already differ between the two.
///
/// The tombstone records the generation it wiped (`<wiped_at>:<trade_index>`,
/// the dead row's trade key index): a later take of the same order is a
/// different trade, and its messages must not read as noise — see
/// [`tombstone_covers`] (review round 2).
async fn wipe_trade_row(
    db: &impl Storage,
    order_id: &str,
    wiped_at: i64,
    wiped_index: u32,
) -> Result<()> {
    db.delete_trade_by_order_id(order_id).await?;
    if let Err(e) = db
        .set_setting(
            &crate::db::settings_keys::trade_wiped(order_id),
            &format!("{wiped_at}:{wiped_index}"),
        )
        .await
    {
        // Classification degrades to pre-#394 behavior for this order:
        // replays write to nothing and emit, as they always did.
        crate::api::logging::blog_warn(
            "orders",
            format!("wipe tombstone not persisted for order={order_id}: {e}"),
        );
    }
    Ok(())
}

/// The one way to (re)create a trade row: lifts any wipe tombstone left on the
/// order id — a canceled order can be legitimately re-taken — before saving.
/// A direct `save_trade` for a *new* row would leave a stale tombstone
/// swallowing the new trade's daemon messages (issue #394).
async fn persist_trade_row(db: &impl Storage, trade: &crate::api::types::TradeInfo) -> Result<()> {
    let key = crate::db::settings_keys::trade_wiped(&trade.order.id);
    if let Err(e) = db.delete_setting(&key).await {
        // Save anyway: a stale tombstone only mutes replays for this order,
        // and the next (re)creation retries the delete.
        crate::api::logging::blog_warn(
            "orders",
            format!(
                "failed to lift wipe tombstone for order={}: {e} — replays for \
                 this trade stay muted until a (re)creation retries the lift",
                trade.order.id
            ),
        );
    }
    db.save_trade(trade).await
}

/// Writes `status` / `hold_invoice` / `amount_sats` to the trade row only when
/// at least one *provided* field differs from what the row already holds, and
/// says whether it wrote — callers skip their TradeUpdate on `false`, which is
/// what keeps a startup replay from re-emitting values the UI already has
/// (issue #394, "minor").
///
/// A missing row keeps today's behavior on purpose: the write runs (the DB
/// layer logs its no-match warning) and the caller still emits — the stream
/// means "the daemon moved this trade", not "the commit succeeded". A write
/// error is logged here and also counts as changed, for the same reason.
///
/// `current` is the row the caller already holds (the prologue snapshot in
/// the dispatch arms, a fresh read in the Kind 38383 sync paths) — handed in
/// rather than re-read here, so the startup replay never reads the same row
/// twice per message (review round 1).
async fn sync_trade_fields_if_changed(
    db: &impl Storage,
    order_id: &str,
    current: Option<&crate::api::types::TradeInfo>,
    status: Option<OrderStatus>,
    hold_invoice: Option<String>,
    amount_sats: Option<u64>,
) -> bool {
    if let Some(trade) = current {
        let same = status.as_ref().is_none_or(|s| *s == trade.order.status)
            && hold_invoice
                .as_deref()
                .is_none_or(|inv| trade.hold_invoice.as_deref() == Some(inv))
            && amount_sats.is_none_or(|a| trade.order.amount_sats == Some(a));
        if same {
            crate::api::logging::blog_debug(
                "orders",
                format!(
                    "status order={} already {:?} — write and update skipped",
                    crate::api::logging::short_id(order_id),
                    trade.order.status,
                ),
            );
            return false;
        }
    }
    if let Err(e) = db
        .update_trade_fields(order_id, status, hold_invoice, amount_sats)
        .await
    {
        crate::api::logging::blog_warn(
            "orders",
            format!(
                "status not persisted for order={}: {e}",
                crate::api::logging::short_id(order_id),
            ),
        );
    }
    true
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

/// Durable peer capture (#334), mirroring mostrix's symmetric resolution:
/// any daemon message whose payload carries a `SmallOrder` naming BOTH trade
/// pubkeys reveals the counterparty. Match our own trade key against the two
/// and take the other — no per-action role table to maintain, and every
/// replayed reveal is another chance to self-heal a trade row that missed
/// it. Persists the peer to the trade row (the durable record — the session
/// is only a cache) and routes through [`apply_peer_reveal`] for the
/// session and the incoming-chat subscription.
///
/// `trade_index` is the index of the key that decrypted the message — ours by
/// construction, and generation-gated by the caller, so it is more reliable
/// than a book lookup (a take's first reply arrives before the binding).
async fn maybe_capture_peer_reveal(
    order_id: &str,
    action: &mostro_core::message::Action,
    payload: Option<&mostro_core::message::Payload>,
    trade_index: u32,
) {
    let Some((buyer_hex, seller_hex)) = peer_reveal_pubkeys(payload) else {
        return;
    };
    // Capture already complete → free. This path runs for essentially every
    // daemon message of a trade — and for the whole replayed history on each
    // restart (the global DM filter carries no `since` on purpose) — so
    // without this the key derivation, DB write, ECDH and spawn below repeat
    // per message. The self-heal property survives: after a restart there is
    // no session, so the first replayed reveal still does the full pass
    // (including the durable write) and only the repeats short-circuit.
    // Session pubkeys are normalized lowercase hex; a payload in another case
    // merely misses the shortcut and takes the (idempotent) full path.
    if let Some(session) = crate::mostro::session::session_manager()
        .get_session(order_id)
        .await
    {
        if session.shared_key.is_some()
            && session
                .peer_pubkey
                .as_deref()
                .is_some_and(|p| p == buyer_hex || p == seller_hex)
        {
            return;
        }
    }
    let (Ok(buyer_pk), Ok(seller_pk)) = (
        nostr_sdk::prelude::PublicKey::from_hex(buyer_hex),
        nostr_sdk::prelude::PublicKey::from_hex(seller_hex),
    ) else {
        log::warn!(
            "[orders] peer-reveal {action:?} order={order_id}: unparseable trade pubkeys in payload"
        );
        return;
    };
    // A stale replay over a finished trade must not respawn chat state.
    if status_sync_blocked_by_terminal(order_id, action).await {
        return;
    }
    let trade_keys = match crate::api::identity::get_active_trade_keys(trade_index).await {
        Ok(k) => k,
        Err(e) => {
            log::error!("[orders] peer-reveal: key load failed: {e}");
            return;
        }
    };
    let Some((peer_pk, role)) = resolve_peer_side(&trade_keys.public_key(), &buyer_pk, &seller_pk)
    else {
        // Decrypted with our key but names two other parties — not ours to
        // record (e.g. a payload echoing someone else's trade by daemon bug).
        log::debug!(
            "[orders] peer-reveal {action:?} order={order_id}: neither party is our trade key"
        );
        return;
    };
    let peer_hex = peer_pk.to_hex();
    log::info!("[orders] peer-reveal {action:?}: order={order_id} role={role:?} peer={peer_hex}");
    if let Some(db) = crate::db::app_db::db() {
        if let Err(e) = db.update_trade_counterparty(order_id, &peer_hex).await {
            log::warn!("[orders] peer-reveal: failed to persist counterparty: {e}");
        }
    }
    apply_peer_reveal(order_id, &peer_hex, &trade_keys, trade_index, role).await;
}

/// Pure payload side of the reveal: the two trade pubkeys a daemon payload
/// names, or `None` when it names fewer than both. Both sides required: with
/// only one pubkey there is no telling which side is ours, and single-sided
/// payloads (e.g. the maker's own NewOrder confirmation) reveal nothing
/// anyway. `Some("")` counts as absent, matching mostrix — this runs for
/// every daemon message and every replayed one, so letting an empty string
/// through to `PublicKey::from_hex` would warn-log the whole history on each
/// restart of a daemon that emits `Some("")` for "no pubkey".
fn peer_reveal_pubkeys(payload: Option<&mostro_core::message::Payload>) -> Option<(&str, &str)> {
    let small_order = match payload {
        Some(mostro_core::message::Payload::Order(o)) => o,
        Some(mostro_core::message::Payload::PaymentRequest(Some(o), _, _)) => o,
        _ => return None,
    };
    match (
        small_order.buyer_trade_pubkey.as_deref(),
        small_order.seller_trade_pubkey.as_deref(),
    ) {
        (Some(buyer_hex), Some(seller_hex)) if !buyer_hex.is_empty() && !seller_hex.is_empty() => {
            Some((buyer_hex, seller_hex))
        }
        _ => None,
    }
}

/// Pure side of the symmetric reveal: which of the two named trade pubkeys is
/// the counterparty, given our own. `None` when we are neither party.
fn resolve_peer_side(
    my_pk: &nostr_sdk::prelude::PublicKey,
    buyer_pk: &nostr_sdk::prelude::PublicKey,
    seller_pk: &nostr_sdk::prelude::PublicKey,
) -> Option<(nostr_sdk::prelude::PublicKey, TradeRole)> {
    if my_pk == buyer_pk {
        Some((*seller_pk, TradeRole::Buyer))
    } else if my_pk == seller_pk {
        Some((*buyer_pk, TradeRole::Seller))
    } else {
        None
    }
}

/// Called when a daemon message reveals the counterparty's trade pubkey
/// (via [`maybe_capture_peer_reveal`], which already holds the trade keys —
/// no second identity load or BIP-32 derivation here).
///
/// Derives the ECDH shared key from `(our_trade_key, peer_trade_pubkey)`,
/// stores it in the session — creating the session if none exists, which is
/// the maker's normal case, `take_order` being the only other creator (#334)
/// — and spawns an incoming-chat subscription on the shared-key pubkey so we
/// receive peer messages from the moment the trade goes active. Split from
/// the capture so tests can exercise the session logic with generated keys
/// instead of mutating the process-global identity (shared with every other
/// test in the binary).
async fn apply_peer_reveal(
    order_id: &str,
    peer_pubkey_hex: &str,
    trade_keys: &nostr_sdk::prelude::Keys,
    trade_index: u32,
    role: TradeRole,
) {
    let peer_pubkey = match nostr_sdk::prelude::PublicKey::from_hex(peer_pubkey_hex) {
        Ok(pk) => pk,
        Err(e) => {
            log::error!("[orders] peer-reveal: invalid peer pubkey: {e}");
            return;
        }
    };
    // Derive the 32-byte ECDH shared secret.
    let shared_key_bytes =
        match crate::crypto::ecdh::derive_nip04_shared_key(trade_keys, &peer_pubkey) {
            Ok(k) => k,
            Err(e) => {
                log::error!("[orders] peer-reveal: ECDH failed: {e}");
                return;
            }
        };
    // Derive the shared-key *pubkey* (the p-tag subscribed by chat listeners).
    // The shared secret is used as a private scalar to derive the corresponding
    // public key — this is the convention used by v1 and the chat protocol spec.
    let shared_pubkey = match nostr_sdk::prelude::SecretKey::from_slice(&shared_key_bytes) {
        Ok(sk) => nostr_sdk::prelude::Keys::new(sk).public_key(),
        Err(e) => {
            log::error!("[orders] peer-reveal: shared key→pubkey failed: {e}");
            return;
        }
    };
    log::info!(
        "[orders] peer-reveal: order={order_id} peer={peer_pubkey_hex} shared_pubkey={}",
        shared_pubkey.to_hex()
    );
    // Update or create the session with peer + shared key. No session is the
    // maker's NORMAL case, not a race: `take_order` is the only other
    // creator, so a maker reaches this reveal without one and could never
    // send (#334). On web this session is also the only chat-identity store
    // — the trades row is stubbed there (#233).
    let mgr = crate::mostro::session::session_manager();
    let session = match mgr.get_session(order_id).await {
        Some(s) => Some(s),
        None => {
            // Order info: the persisted trade row wins; the public book
            // covers platforms without one (web) and the pre-persistence
            // window of a take's first reply.
            let from_row = match crate::db::app_db::db() {
                Some(db) => db
                    .get_trade_by_order_id(order_id)
                    .await
                    .ok()
                    .flatten()
                    .map(|t| t.order),
                None => None,
            };
            let order_info = match from_row {
                Some(o) => Some(o),
                None => order_book().get_order(order_id).await,
            };
            match order_info {
                None => {
                    log::warn!(
                        "[orders] peer-reveal: no order info for order={order_id} — cannot create session"
                    );
                    None
                }
                Some(order_info) => mgr
                    .create_session(order_id.to_string(), role, trade_index, order_info)
                    .await
                    .map_err(|e| log::warn!("[orders] peer-reveal: session create failed: {e}"))
                    .ok(),
            }
        }
    };
    if let Some(mut session) = session {
        session.peer_pubkey = Some(peer_pubkey_hex.to_string());
        session.shared_key = Some(shared_key_bytes);
        if let Err(e) = mgr.update_session(order_id, session).await {
            log::warn!("[orders] peer-reveal: session update failed: {e}");
        }
    } else {
        log::warn!(
            "[orders] peer-reveal: no session and none creatable for order={order_id} — incoming subscription still spawned"
        );
    }
    // Derive the chat conversation keys (K_conv / K_sign — HKDF split of the
    // trade-key ECDH secret, protocol chat spec) and spawn the incoming-chat
    // subscription pinned to their author key.
    let (conv, sign) = match crate::crypto::chat_keys::derive_chat_keys(trade_keys, &peer_pubkey) {
        Ok(pair) => pair,
        Err(e) => {
            log::error!("[orders] peer-reveal: chat key derivation failed: {e}");
            return;
        }
    };
    let order_id_owned = order_id.to_string();
    let trade_keys = trade_keys.clone();
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

/// Apply one Kind 38383 update of an order we created or took, as delivered
/// by [`subscribe_single_order`].
///
/// The wire's status reaches the trade row and the book entry only where
/// `wire_status_applies` allows it; otherwise the entry keeps the local trade
/// status. The wire's view is noted either way, so a take that is wiped later
/// can hand the order back to the public book
/// ([`OrderBook::settle_after_lost_take`]); a final view is forgotten once
/// that decision is made. A `canceled` that ends a trade before it went
/// active wipes it instead ([`wipe_on_public_cancel`]), and the wipe has
/// already settled the entry.
async fn apply_single_order_update(mut order: OrderInfo) {
    order_book().note_wire_order(&order);
    if wipe_on_public_cancel(&order.id, &order.status).await {
        return;
    }
    if is_hard_terminal(&order.status) {
        order_book().forget_wire_order(&order.id);
    }
    let local = local_trade_status(&order.id).await;
    let applies = wire_status_applies(local.as_ref(), &order.status);
    // This subscription only exists for orders we created or took, so every
    // decision is ours to log.
    log_wire_status_sync(
        &order.id,
        &order.status,
        local.as_ref(),
        applies,
        "38383/d-tag",
    );
    // Gated whole on `applies`: a public bucket that may not replace the
    // private status must not sneak its amount into the row either (#394
    // review), and an event carrying what the row already holds writes
    // nothing.
    if applies {
        if let Some(db) = crate::db::app_db::db() {
            let row = db.get_trade_by_order_id(&order.id).await.ok().flatten();
            sync_trade_fields_if_changed(
                db,
                &order.id,
                row.as_ref(),
                Some(order.status.clone()),
                None,
                order.amount_sats,
            )
            .await;
        }
    }
    if !applies {
        if let Some(local) = local {
            order.status = local;
        }
    }
    order_book().upsert_order(order).await;
}

/// What the single-order task made of one notification.
#[derive(Debug, PartialEq)]
enum SingleOrderEvent {
    /// Not an event of this order from the node the task watches.
    Ignored,
    /// Applied to the trade row and the book entry.
    Applied,
    /// An event of this order, but the watched node is no longer the active
    /// one: the task stops.
    NodeChanged,
}

/// Handle one notification of the single-order task for `order_id`, opened
/// for `watched_node`. `active_node` is read only for an event of this order,
/// so the rest of the notification stream never pays for it.
///
/// The stream carries every subscription's events, and a d-tag is public:
/// only the daemon may move a trade of ours — a `canceled` wipes a
/// never-active one ([`wipe_on_public_cancel`]). And only the *active*
/// daemon, as everywhere else: `dispatch_mostro_message` rejects any other
/// sender, and the book loop drops other authors. A node switch re-targets
/// the long-lived subscriptions but leaves this task running, which kept
/// writing the previous node's view into the trade row and into the new
/// node's book. It stops instead, as soon as its order shows up.
async fn handle_single_order_event(
    event: &nostr_sdk::prelude::Event,
    order_id: &str,
    watched_node: &nostr_sdk::prelude::PublicKey,
    active_node: impl FnOnce() -> String,
) -> SingleOrderEvent {
    if event.pubkey != *watched_node {
        return SingleOrderEvent::Ignored;
    }
    let Some(order) = parse_order_event(event, None) else {
        return SingleOrderEvent::Ignored;
    };
    if order.id != order_id {
        return SingleOrderEvent::Ignored;
    }
    if active_node() != watched_node.to_hex() {
        crate::api::logging::blog_info(
            "orders",
            format!(
                "d-tag subscription order={} stops: its node is no longer the active one",
                crate::api::logging::short_id(order_id),
            ),
        );
        return SingleOrderEvent::NodeChanged;
    }
    log::info!(
        "[orders] d-tag update: order={} status={:?}",
        order_id,
        order.status
    );
    apply_single_order_update(order).await;
    SingleOrderEvent::Applied
}

/// Subscribe to K38383 updates for a single order (by `d`-tag) so that status
/// changes after taking the order are reflected in the local order book.
///
/// Spawns a short-lived background task that watches for Kind 38383 events with
/// `d = order_id` and upserts them.  The task exits when the relay pool shuts
/// down or after a generous idle timeout (no updates for 30 minutes).
async fn subscribe_single_order(order_id: &str) {
    let order_id = order_id.to_string();
    // Claimed before the spawn, so a retake that calls this again supersedes
    // the earlier take's task at once rather than after it gets scheduled.
    let (generation, replaced) = claim_single_order_task(&order_id);
    crate::rt::spawn(async move {
        let Ok(pool) = crate::api::nostr::get_pool() else {
            log::warn!("[orders] subscribe_single_order: relay pool not initialized");
            release_single_order_task(&order_id, generation);
            return;
        };
        let client = pool.client();
        let mostro_pubkey =
            match nostr_sdk::prelude::PublicKey::from_hex(&crate::config::active_mostro_pubkey()) {
                Ok(pk) => pk,
                Err(e) => {
                    log::error!("[orders] subscribe_single_order: invalid pubkey: {e}");
                    release_single_order_task(&order_id, generation);
                    return;
                }
            };

        let mut rx = client.notifications();
        let filter = crate::nostr::order_events::trade_order_filter(&mostro_pubkey, &order_id);
        let sub_id = single_order_subscription_id(&order_id);
        if replaced {
            // The earlier take's REQ is still open under this same id, and
            // nostr-sdk refuses a subscribe whose id exists (it keeps the old
            // filter and reports that per relay, not as an error). Drop it so
            // this subscribe is accepted and owned by this task; the relay
            // replays the order's latest event on the new REQ, so nothing is
            // missed in between.
            let _ = client.unsubscribe(&sub_id).await;
        }
        if let Err(e) = client.subscribe(filter).with_id(sub_id.clone()).await {
            release_single_order_task(&order_id, generation);
            log::warn!("[orders] subscribe_single_order subscribe failed: {e}");
            return;
        }
        log::info!("[orders] subscribed to d-tag updates for order={order_id}");

        use crate::rt::time::{timeout, Duration};
        use nostr_sdk::prelude::{ClientNotification, StreamExt};

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

            match timeout(remaining, rx.next()).await {
                Ok(Some(ClientNotification::Event { event, .. })) => {
                    // A retake replaced this task while it waited: stop
                    // before handling anything, so no event is applied twice.
                    if !single_order_task_is_current(&order_id, generation) {
                        break;
                    }
                    match handle_single_order_event(
                        &event,
                        &order_id,
                        &mostro_pubkey,
                        crate::config::active_mostro_pubkey,
                    )
                    .await
                    {
                        SingleOrderEvent::Applied => {
                            last_activity = crate::rt::time::Instant::now();
                        }
                        SingleOrderEvent::NodeChanged => break,
                        SingleOrderEvent::Ignored => {}
                    }
                }
                Ok(Some(ClientNotification::Shutdown)) | Ok(None) => break,
                Err(_) => break, // idle timeout
                Ok(Some(_)) => continue,
            }
        }

        // Drop the relay-side REQ; see subscribe_daemon_messages. Only while
        // this task still owns it: a superseded task leaves the REQ to the
        // retake's task, which re-opened it under the same id.
        if release_single_order_task(&order_id, generation) {
            if let Err(e) = client.unsubscribe(&sub_id).await {
                log::warn!(
                    "[orders] subscribe_single_order unsubscribe failed for order={order_id}: {e}"
                );
            }
        } else {
            crate::api::logging::blog_debug(
                "orders",
                format!(
                    "d-tag task order={} superseded by a retake — subscription left to it",
                    crate::api::logging::short_id(&order_id),
                ),
            );
        }
    });
}

/// Live single-order tasks, by order id: the generation of the task that owns
/// the order's `mostro-order-<id>` subscription.
///
/// A retake calls [`subscribe_single_order`] again while the first take's
/// task may still be running — it stops only on a 30-minute idle, a shutdown
/// or a node switch, and a wipe is none of those. Two tasks would then read
/// the same notifications and apply every event twice, and whichever exited
/// first would unsubscribe the REQ the other relies on. The newest claim
/// replaces the older one instead: the old task stops at its next wake
/// without touching the subscription, and the new task re-opens and owns it,
/// with an idle window that starts from the retake.
fn single_order_tasks() -> &'static std::sync::Mutex<HashMap<String, u64>> {
    static TASKS: OnceLock<std::sync::Mutex<HashMap<String, u64>>> = OnceLock::new();
    TASKS.get_or_init(Default::default)
}

/// Source of single-order task generations; strictly increasing.
static SINGLE_ORDER_GENERATION: AtomicU64 = AtomicU64::new(0);

/// Claim the single-order task for `order_id`: a fresh generation, and
/// whether it replaced a task still holding the order.
fn claim_single_order_task(order_id: &str) -> (u64, bool) {
    let generation = SINGLE_ORDER_GENERATION.fetch_add(1, Ordering::Relaxed) + 1;
    let replaced = single_order_tasks()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .insert(order_id.to_string(), generation)
        .is_some();
    (generation, replaced)
}

/// Whether `generation` still owns `order_id`'s single-order task.
fn single_order_task_is_current(order_id: &str, generation: u64) -> bool {
    single_order_tasks()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .get(order_id)
        == Some(&generation)
}

/// Release `generation`'s claim on `order_id`, returning whether it still held
/// it — only then does the task own the subscription it is about to drop.
fn release_single_order_task(order_id: &str, generation: u64) -> bool {
    let mut tasks = single_order_tasks()
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if tasks.get(order_id) == Some(&generation) {
        tasks.remove(order_id);
        true
    } else {
        false
    }
}

// ── Internal helpers ─────────────────────────────────────────────────────────

/// Parse and publish a serialised Nostr event JSON via the relay pool.
///
/// Returns an error if the pool is not initialised, the JSON is malformed,
/// or the relay client reports a publish error.
async fn publish_event_json(event_json: &str) -> Result<()> {
    let pool =
        crate::api::nostr::get_pool().map_err(|_| anyhow::anyhow!("RelayPoolNotInitialized"))?;
    let event: nostr_sdk::prelude::Event =
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
    for relay in output.success.keys() {
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
    // The SDK returns Ok even when every relay rejected the event (re-verified
    // on the 0.45 bump: the pool collects per-relay outcomes and ends in a
    // bare `Ok(output)`, with no empty-success guard. `success` still means
    // accepted — an `OK false` becomes a relay error and lands in `failed`.
    // nostr-relay-pool was folded into nostr-sdk itself in 0.45.)
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
/// 1. Subscribes to the `order_book_filters()` pair via the relay pool client.
/// 2. Loops over `ClientNotification::Event` messages.
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
    /// The book says `success` for a trade this client still holds at
    /// `SettledHoldInvoice`. The daemon tells only the buyer about
    /// `PurchaseCompleted`; the seller learns of the payout from the public
    /// event alone, and a client that missed that one event would show
    /// "payout pending" forever, restarts included.
    SyncSuccess,
    /// No positive daemon signal — absent from the book, or the ambiguous
    /// `in-progress` public marker: leave untouched.
    Keep,
}

fn sweep_action(
    is_mine: bool,
    local_status: &crate::api::types::OrderStatus,
    book_status: Option<&crate::api::types::OrderStatus>,
) -> SweepAction {
    use crate::api::types::OrderStatus as S;
    match (local_status, book_status) {
        (S::SettledHoldInvoice, Some(S::Success)) => SweepAction::SyncSuccess,
        (S::SettledHoldInvoice, _) => SweepAction::Keep,
        (_, Some(S::Pending)) if is_mine => SweepAction::SyncPending,
        (_, Some(S::Pending)) => SweepAction::Wipe,
        (_, Some(S::Canceled | S::Expired | S::CanceledByAdmin)) => SweepAction::Wipe,
        _ => SweepAction::Keep,
    }
}

/// Marks `order_id` completed once the public book shows `success`,
/// checking a bounded number of times a few seconds apart.
///
/// The seller's completion arrives only through the public Kind 38383
/// event (the daemon sends `PurchaseCompleted` to the buyer alone). The
/// live subscription usually delivers it; when it does not, this check,
/// started as the trade enters `SettledHoldInvoice`, closes the gap within
/// a minute instead of leaving "payout pending" on screen.
async fn confirm_payout_completion(order_id: String) {
    const ATTEMPTS: u32 = 12;
    const EVERY_SECS: u64 = 5;
    for _ in 0..ATTEMPTS {
        crate::rt::time::sleep(crate::rt::time::Duration::from_secs(EVERY_SECS)).await;
        match local_trade_status(&order_id).await {
            Some(crate::api::types::OrderStatus::SettledHoldInvoice) => {}
            _ => return,
        }
        if fetch_public_order_status(&order_id).await
            == Some(crate::api::types::OrderStatus::Success)
        {
            apply_payout_completed(&order_id).await;
            return;
        }
    }
}

/// Applies the payout completion the public book reported for a trade this
/// client still held at `SettledHoldInvoice`.
///
/// Re-checked under the per-order lock right before writing: a daemon
/// message (a dispute, an admin cancel) can move the trade while the book
/// was being fetched, and that newer status must not be overwritten.
async fn apply_payout_completed(order_id: &str) {
    let _order = lock_order(order_id).await;
    if local_trade_status(order_id).await
        != Some(crate::api::types::OrderStatus::SettledHoldInvoice)
    {
        log::debug!("[orders] payout completion for {order_id} skipped: status moved on");
        return;
    }
    let status = crate::api::types::OrderStatus::Success;
    order_book()
        .update_order_status(order_id, status.clone())
        .await;
    if let Some(db) = crate::db::app_db::db() {
        if let Err(e) = db
            .update_trade_fields(order_id, Some(status.clone()), None, None)
            .await
        {
            log::warn!("[orders] payout completion not persisted for {order_id}: {e}");
            return;
        }
    }
    crate::api::logging::blog_info(
        "orders",
        format!(
            "status order={} →Success src=book/payout-check",
            crate::api::logging::short_id(order_id)
        ),
    );
    emit_trade_update(order_id, status);
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

/// Look a single order's public status up directly on the relays, bypassing
/// the in-memory book.
///
/// The book is fed by [`order_book_filters`], whose any-status half is
/// windowed to `RECENT_ORDERS_WINDOW_SECS` (48 h). A trade whose cancellation
/// the app missed while offline for longer than that window therefore has no
/// cached status at all, and the sweep would keep it waiting forever — which
/// is exactly the case the sweep exists for. An unwindowed `d`-tag query
/// returns a single addressable event, so it is cheap and no relay replay cap
/// can hide it.
async fn fetch_public_order_status(order_id: &str) -> Option<crate::api::types::OrderStatus> {
    let pool = crate::api::nostr::get_pool().ok()?;
    let mostro_pubkey = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey()).ok()?;
    let filter = crate::nostr::order_events::trade_order_filter(&mostro_pubkey, order_id);
    let events = match pool
        .client()
        .fetch_events(filter)
        .timeout(std::time::Duration::from_secs(10))
        .await
    {
        Ok(events) => events,
        Err(e) => {
            log::warn!("[orders] sweep: d-tag fetch for {order_id} failed: {e}");
            return None;
        }
    };
    newest_book_status(events, &mostro_pubkey, order_id)
}

/// The newest status among `events` that the daemon published for exactly
/// `order_id`. The relay was asked for that author and that order; a relay
/// is not trusted to have honoured either, so both are checked again here:
/// a genuine daemon event for another order must not move this trade.
fn newest_book_status(
    events: impl IntoIterator<Item = nostr_sdk::prelude::Event>,
    mostro_pubkey: &nostr_sdk::prelude::PublicKey,
    order_id: &str,
) -> Option<crate::api::types::OrderStatus> {
    events
        .into_iter()
        .filter(|e| e.pubkey == *mostro_pubkey)
        .filter_map(|e| {
            crate::nostr::order_events::parse_order_event(&e, None)
                .filter(|order| order.id == order_id)
                .map(|order| (e.created_at, order.status))
        })
        .max_by_key(|(created_at, _)| *created_at)
        .map(|(_, status)| status)
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
        let payout_pending =
            trade.order.status == crate::api::types::OrderStatus::SettledHoldInvoice;
        if !payout_pending
            && !matches!(
                trade.order.status,
                crate::api::types::OrderStatus::WaitingBuyerInvoice
                    | crate::api::types::OrderStatus::WaitingPayment
            )
        {
            continue;
        }
        // Age gate: never race the take/propagation window of a live trade.
        // A settled escrow awaiting its payout is exempt: the payout is
        // expected promptly and nothing else reports it.
        let deadline = trade
            .timeout_at
            .unwrap_or(trade.started_at + SWEEP_MIN_AGE_SECS);
        if !payout_pending && now <= deadline {
            continue;
        }
        examined += 1;
        let oid = trade.order.id.clone();
        // The book first (free); on a miss, ask the relays for this one order.
        // A miss is the long-offline case the windowed filter cannot cover.
        let book_status = match order_book().get_order(&oid).await.map(|o| o.status) {
            Some(status) => Some(status),
            None => fetch_public_order_status(&oid).await,
        };
        match sweep_action(
            trade.order.is_mine,
            &trade.order.status,
            book_status.as_ref(),
        ) {
            SweepAction::SyncSuccess => {
                apply_payout_completed(&oid).await;
                log::info!("[orders] sweep: payout completed for order={oid}");
                resynced += 1;
            }
            SweepAction::Wipe => match wipe_never_active_trade(
                &oid,
                !trade.order.is_mine,
                crate::rt::unix_now(),
                trade.trade_key_index,
            )
            .await
            {
                Ok(()) => {
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
    let mostro_pubkey = match nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey()) {
        Ok(pk) => pk,
        Err(e) => {
            log::error!("[orders] refetch: invalid mostro pubkey: {e}");
            return;
        }
    };
    // Same two filters as the live subscription (see `order_book_filters`).
    let (pending_filter, recent_filter) = order_book_filters(&mostro_pubkey);
    let client = pool.client();
    let timeout = std::time::Duration::from_secs(10);
    // Fetched independently on purpose: the two scopes fail independently, and
    // losing the recent-changes pass must not throw away a pending book that
    // arrived fine (that would leave the UI empty on a transient relay error).
    let pending = client.fetch_events(pending_filter).timeout(timeout).await;
    let recent = client.fetch_events(recent_filter).timeout(timeout).await;
    if let Err(e) = &pending {
        log::warn!("[orders] refetch: pending-book fetch failed: {e}");
    }
    if let Err(e) = &recent {
        log::warn!("[orders] refetch: recent-changes fetch failed: {e}");
    }
    if pending.is_err() && recent.is_err() {
        // Both scopes failed: nothing to ingest, and the warnings above say why.
        return;
    }
    let mut events: Vec<nostr_sdk::prelude::Event> = Vec::new();
    for batch in [pending, recent].into_iter().flatten() {
        events.extend(batch);
    }
    crate::api::logging::blog_info(
        "orders",
        format!("refetched {} current orders for active node", events.len()),
    );
    // The relays were asked for the daemon's events only; one that did not
    // honour the author must not move a trade of ours — a `canceled` wipes a
    // never-active one (`wipe_on_public_cancel`). The live subscription checks
    // the same before ingesting.
    for event in events
        .into_iter()
        .filter(|event| event.pubkey == mostro_pubkey)
    {
        ingest_order_event_with(&event, Publish::WhenBatchEnds).await;
    }
    // One emission for the batch. Publishing per event made a refetch
    // O(N²): each upsert cloned the whole book and sent it across the
    // bridge, so N orders cost N clones of an N-element vector. This
    // path runs on cold start, on every node switch, and on every
    // pull-to-refresh.
    order_book().publish().await;
}

/// Stable subscription ID for the Kind 38383 pending order-book feed.
fn orders_subscription_id() -> nostr_sdk::prelude::SubscriptionId {
    nostr_sdk::prelude::SubscriptionId::new("mostro-orders")
}

/// Stable id for a trade's daemon-message subscription.
///
/// Stable so the task can drop the relay-side REQ when it exits. Keyed by
/// trade pubkey, so unsubscribing one trade cannot close another's feed.
///
/// NIP-01 caps subscription ids at 64 characters and relays enforce it
/// (`relay.mostro.network` answers CLOSED with "max length 64 chars"); the
/// full 64-hex pubkey would push the id to 78. The first 32 hex characters
/// (128 bits) keep it at 46 and rule out any realistic cross-trade collision.
/// [`subscription_ids_fit_nip01`] pins the bound.
fn daemon_message_subscription_id(trade_pubkey_hex: &str) -> nostr_sdk::prelude::SubscriptionId {
    let key = trade_pubkey_hex.get(..32).unwrap_or(trade_pubkey_hex);
    nostr_sdk::prelude::SubscriptionId::new(format!("mostro-daemon-{key}"))
}

/// Stable id for a single order's d-tag update subscription.
fn single_order_subscription_id(order_id: &str) -> nostr_sdk::prelude::SubscriptionId {
    nostr_sdk::prelude::SubscriptionId::new(format!("mostro-order-{order_id}"))
}

/// Stable subscription ID for the windowed any-status Kind 38383 feed that
/// carries the transitions taking an order *out* of the book.
fn recent_orders_subscription_id() -> nostr_sdk::prelude::SubscriptionId {
    nostr_sdk::prelude::SubscriptionId::new("mostro-orders-recent")
}

/// The pair of Kind 38383 filters that together give a complete, bounded
/// view of a node's book: every pending order plus every status change of
/// the last [`RECENT_ORDERS_WINDOW_SECS`] hours. Shared by the live
/// subscription and the refetch so neither can drift back to the
/// unbounded query.
///
/// [`RECENT_ORDERS_WINDOW_SECS`]: crate::nostr::order_events::RECENT_ORDERS_WINDOW_SECS
fn order_book_filters(
    mostro_pubkey: &nostr_sdk::prelude::PublicKey,
) -> (nostr_sdk::prelude::Filter, nostr_sdk::prelude::Filter) {
    use crate::nostr::order_events::{
        pending_orders_filter, recent_orders_filter, RECENT_ORDERS_WINDOW_SECS,
    };
    let since = nostr_sdk::prelude::Timestamp::now() - RECENT_ORDERS_WINDOW_SECS;
    (
        pending_orders_filter(mostro_pubkey),
        recent_orders_filter(mostro_pubkey, since),
    )
}

/// Stable subscription ID for the Kind 14 Mostro-reply feed.
fn mostro_dm_subscription_id() -> nostr_sdk::prelude::SubscriptionId {
    nostr_sdk::prelude::SubscriptionId::new("mostro-dm")
}

/// Stable subscription ID for the node's kind 10002 relay list.
fn relay_list_subscription_id() -> nostr_sdk::prelude::SubscriptionId {
    nostr_sdk::prelude::SubscriptionId::new("mostro-relay-list")
}

/// Point the long-lived subscription `id` at `filter`, replacing whatever it
/// carried before.
///
/// nostr-sdk 0.45 refuses a subscribe whose id already exists and keeps the
/// old filters, so the id is closed first (a no-op when it was never open).
/// The brief gap between CLOSE and REQ loses nothing: a node switch refetches
/// the book right after, and the Kind-14 feed has no `since`, so its REQ
/// replays history.
///
/// The SDK reports per-relay failures inside an `Ok` output, which is how a
/// rejected re-subscribe used to pass for a live one. No relay accepting it is
/// an error here; a partial failure is logged.
async fn replace_subscription(
    client: &nostr_sdk::prelude::Client,
    id: nostr_sdk::prelude::SubscriptionId,
    filter: nostr_sdk::prelude::Filter,
) -> Result<()> {
    if let Err(e) = client.unsubscribe(&id).await {
        log::warn!("[orders] closing {id} before re-subscribing failed: {e}");
    }
    let output = client
        .subscribe(filter)
        .with_id(id.clone())
        .await
        .map_err(|e| anyhow::anyhow!("subscribe {id} failed: {e}"))?;
    if output.success.is_empty() {
        return Err(anyhow::anyhow!(
            "subscribe {id} rejected by every relay: {:?}",
            output.failed
        ));
    }
    for (url, err) in &output.failed {
        crate::api::logging::blog_warn(
            "relay",
            format!(
                "sub {id} failed relay={} err={}",
                crate::api::logging::display_relay(&url.to_string()),
                crate::api::logging::sanitize_relay_text(err),
            ),
        );
    }
    Ok(())
}

/// (Re)subscribe the order-book (Kind 38383) and Mostro-reply (Kind 14)
/// filters, author-pinned to `mostro_pubkey`.
///
/// Uses **stable** subscription IDs so that calling this again for a different
/// node replaces the existing author-pinned filters (see
/// [`replace_subscription`]) instead of leaking a second subscription that
/// keeps the old node's events flowing.
async fn subscribe_node_filters(
    client: &nostr_sdk::prelude::Client,
    mostro_pubkey: nostr_sdk::prelude::PublicKey,
) -> Result<()> {
    // Two filters, not one unbounded one: relays cap how many stored events
    // they replay per REQ (relay.mostro.network: 300, oldest-first when no
    // limit is given), so a bare `kind+author` filter comes back with the
    // node's dead history and none of the live book. See `pending_orders_filter`.
    let (pending_filter, recent_filter) = order_book_filters(&mostro_pubkey);
    replace_subscription(client, orders_subscription_id(), pending_filter).await?;
    replace_subscription(client, recent_orders_subscription_id(), recent_filter).await?;
    crate::api::logging::blog_info(
        "relay",
        format!(
            "subs created id={} (kinds=[38383] s=pending) + id={} (kinds=[38383] since=-{}h) author={}",
            orders_subscription_id(),
            recent_orders_subscription_id(),
            crate::nostr::order_events::RECENT_ORDERS_WINDOW_SECS / 3600,
            crate::api::logging::short_id(&mostro_pubkey.to_hex()),
        ),
    );

    // The node's NIP-65 relay list, kept live so an operator adding a relay
    // reaches running clients; applied additively by apply_relay_list_event.
    replace_subscription(
        client,
        relay_list_subscription_id(),
        crate::nostr::relay_list::relay_list_filter(&mostro_pubkey),
    )
    .await?;
    crate::api::logging::blog_info(
        "relay",
        format!(
            "sub created id={} kinds=[10002]",
            relay_list_subscription_id()
        ),
    );

    // Kind-14 NIP-44 replies authored by Mostro for all known trade pubkeys.
    // The author pin disambiguates from NIP-17 peer chat (also kind 14).
    //
    // Deliberately NO `since` here: this is the offline catch-up channel —
    // after any downtime it must replay the full stored history so status
    // changes and late reconciliations are never lost. Only the ephemeral
    // per-trade subscription (subscribe_daemon_messages) carries a cutoff.
    replace_global_dm_filter(client, mostro_pubkey).await
}

/// Re-issue the bulk Kind-14 subscription from the full coverage map
/// ([`global_dm_keys`]); a no-op while the map is empty.
///
/// Serialized: a node switch and a key joining mid-session both land here,
/// and two interleaved CLOSE/REQ pairs either leave the filter built from an
/// older key set or make one REQ fail with "subscription ID already exists".
/// Reading the map under the lock means whichever replacement runs last
/// carries every covered key.
async fn replace_global_dm_filter(
    client: &nostr_sdk::prelude::Client,
    mostro_pubkey: nostr_sdk::prelude::PublicKey,
) -> Result<()> {
    static DM_FILTER_LOCK: tokio::sync::Mutex<()> = tokio::sync::Mutex::const_new(());
    let _guard = DM_FILTER_LOCK.lock().await;
    let trade_pubkeys: Vec<nostr_sdk::prelude::PublicKey> = global_dm_keys()
        .read()
        .await
        .keys()
        .filter_map(|hex| nostr_sdk::prelude::PublicKey::from_hex(hex).ok())
        .collect();
    if trade_pubkeys.is_empty() {
        return Ok(());
    }
    let p_count = trade_pubkeys.len();
    let dm_filter = nostr_sdk::prelude::Filter::new()
        .kind(nostr_sdk::prelude::Kind::PrivateDirectMessage)
        .author(mostro_pubkey)
        .pubkeys(trade_pubkeys);
    replace_subscription(client, mostro_dm_subscription_id(), dm_filter).await?;
    crate::api::logging::blog_info(
        "relay",
        format!(
            "sub replaced id={} kinds=[14] p_count={p_count}",
            mostro_dm_subscription_id(),
        ),
    );
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

    let mostro_pubkey = match nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey()) {
        Ok(pk) => pk,
        Err(e) => {
            log::error!("[orders] node switch: invalid mostro pubkey: {e}");
            return;
        }
    };

    seed_global_dm_coverage().await;

    if let Err(e) = subscribe_node_filters(&client, mostro_pubkey).await {
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
    tokio::sync::RwLock<HashMap<String, (nostr_sdk::prelude::Keys, u32)>>,
> = std::sync::OnceLock::new();

fn global_dm_keys() -> &'static tokio::sync::RwLock<HashMap<String, (nostr_sdk::prelude::Keys, u32)>>
{
    GLOBAL_DM_KEYS.get_or_init(|| tokio::sync::RwLock::new(HashMap::new()))
}

/// Add a freshly derived trade key to the global decryption map and refresh
/// the bulk Kind-14 relay filter to include it, so daemon messages for this
/// key (including an admin-took-dispute long after creation) are received
/// for the whole life of the process, not just while the temporary per-trade
/// receiver runs. Idempotent: a key already covered causes no relay churn.
pub(crate) async fn ensure_global_dm_coverage(keys: &nostr_sdk::prelude::Keys, trade_index: u32) {
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
    let Ok(mostro_pubkey) = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey()) else {
        return;
    };
    if let Err(e) = replace_global_dm_filter(&pool.client(), mostro_pubkey).await {
        log::warn!("[orders] bulk DM filter refresh failed: {e}");
    }
}

/// Derive every known trade key and merge it into the refreshable coverage
/// map, returning the full pubkey set for the relay filter.
///
/// Union, not replace: a session key inserted concurrently (create/take in
/// flight while subscriptions restart) must never be evicted.
async fn seed_global_dm_coverage() -> Vec<nostr_sdk::prelude::PublicKey> {
    let derived = build_trade_key_map().await;
    let mut map = global_dm_keys().write().await;
    for (hex, entry) in derived {
        map.entry(hex).or_insert(entry);
    }
    map.keys()
        .filter_map(|hex| nostr_sdk::prelude::PublicKey::from_hex(hex).ok())
        .collect()
}

async fn build_trade_key_map() -> HashMap<String, (nostr_sdk::prelude::Keys, u32)> {
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
async fn resolve_dm_recipient(
    event: &nostr_sdk::prelude::Event,
) -> Option<(String, nostr_sdk::prelude::Keys, u32)> {
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
    event: &nostr_sdk::prelude::Event,
    recipient: (String, nostr_sdk::prelude::Keys, u32),
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
pub(crate) enum Publish {
    /// At most one emission per coalescing window — the relay firehose, where
    /// events arrive faster than the UI can consume whole-book snapshots.
    Coalesced,
    /// Bulk ingest: the caller publishes once for the whole batch.
    WhenBatchEnds,
}

async fn ingest_order_event(event: &nostr_sdk::prelude::Event) {
    ingest_order_event_with(event, Publish::Coalesced).await;
}

async fn ingest_order_event_with(event: &nostr_sdk::prelude::Event, publish: Publish) {
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
            // Restore `is_mine` — "I am the maker" — on cold start from the
            // durable trade-key binding plus the trade row it points at,
            // keyed by the daemon UUID and never by order content (#394
            // step 3): a content fingerprint also matches a stranger's
            // identical order, and a taken range order republishes as a
            // plain fixed order — index 21 bound where 16 belonged, and
            // release/cancel/rate signed with the wrong key (#326). Every
            // reference client keys ownership by daemon UUID. The binding
            // miss is the common case (every stranger's order), answered by
            // the in-memory map or the negative cache; the row read only
            // runs on a hit. A row recovered by DM rebuild proves its
            // maker-ness from the payload's kind plus the proven role
            // (review round 2), so this restore trusts the row for makers
            // and takers alike.
            if !info.is_mine && lookup_trade_key_index(&info.id).await.is_some() {
                if let Some(db) = crate::db::app_db::db() {
                    if let Ok(Some(trade)) = db.get_trade_by_order_id(&info.id).await {
                        info.is_mine = trade.order.is_mine;
                    }
                }
            }
            // The note a lost take is restored from must follow the wire even
            // after the d-tag subscription idled out. Only refreshed, never
            // created here: this feed never overrides a `pending`, and any
            // other view ends in dropping the entry, note or not. For orders
            // never noted this is a single map lookup.
            order_book().refresh_wire_order(&info);
            let final_view = is_hard_terminal(&info.status);
            // Sync trade status in DB for own orders so My Trades
            // reflects status changes even without daemon-message delivery.
            // A `canceled` that ends a trade of ours before it went active —
            // maker or taker — wipes it instead, and leaves nothing local to
            // sync or to hold the entry at (`wipe_on_public_cancel`; one more
            // indexed row lookup, for `canceled` events only).
            if info.status != crate::api::types::OrderStatus::Pending
                && !wipe_on_public_cancel(&info.id, &info.status).await
            {
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
                    // Gated whole on `applies`: a public bucket that may not
                    // replace the private status must not sneak its amount
                    // into the row either (#394 review), and an event
                    // carrying what the row already holds writes nothing.
                    if applies {
                        if let Some(db) = crate::db::app_db::db() {
                            let row = db.get_trade_by_order_id(&info.id).await.ok().flatten();
                            sync_trade_fields_if_changed(
                                db,
                                &info.id,
                                row.as_ref(),
                                Some(info.status.clone()),
                                None,
                                info.amount_sats,
                            )
                            .await;
                        }
                    }
                }
                if !applies {
                    if let Some(local) = local {
                        info.status = local;
                    }
                }
            }
            // After the wipe decision above, which settles a never-active take
            // from this very view.
            if final_view {
                order_book().forget_wire_order(&info.id);
            }
            // Whether this order is *ours*, which is not what `is_mine`
            // answers: that flag means "I am the maker". `parse_order_event`
            // hardcodes it to false, and the binding+row restore above only
            // raises it for maker rows, so an order we *took* arrives with
            // `is_mine == false` and is indistinguishable from a stranger's at
            // this layer. What both roles do have is a trade-key binding for
            // the order id, so that is the question asked.
            //
            // Asked only when the answer can change what happens — a
            // hard-terminal order — so the firehose of pending updates never
            // pays for the lookup. It is answered from the in-memory map or the
            // negative cache in the common case, which also keeps it correct on
            // web, where the trade store is a stub (#233) and a DB-only test
            // would call every trade of ours a stranger's.
            let ours = info.is_mine
                || (is_hard_terminal(&info.status)
                    && lookup_trade_key_index(&info.id).await.is_some());
            order_book().apply_ingested_order(info, ours, publish).await;
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
    let mostro_pubkey =
        match nostr_sdk::prelude::PublicKey::from_hex(&crate::config::active_mostro_pubkey()) {
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
    if let Err(e) = subscribe_node_filters(&client, mostro_pubkey).await {
        log::error!("[orders] subscribe failed: {e}");
        return;
    }

    crate::api::logging::blog_info(
        "orders",
        "subscriptions active — waiting for events".to_string(),
    );

    use nostr_sdk::prelude::{ClientNotification, StreamExt};

    loop {
        match rx.next().await {
            Some(ClientNotification::Event { event, .. }) => {
                // Resolve the *current* active node for each event so a node
                // switch is respected without restarting this loop.
                let Ok(active_mostro) =
                    nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
                else {
                    continue;
                };

                // ── Kind 14 NIP-44 Mostro reply: decrypt and dispatch ──
                if event.kind == nostr_sdk::prelude::Kind::PrivateDirectMessage {
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

                // Everything below is authored by the active node only.
                // Ignore stale events from a previously-active node (e.g.
                // buffered across a node switch): the book only ever holds
                // the active node's orders, and only its relay list is applied.
                if event.pubkey != active_mostro {
                    continue;
                }

                // ── Kind 10002 relay list: auto-add announced relays ──
                if event.kind.as_u16() == crate::nostr::relay_list::KIND_RELAY_LIST {
                    crate::api::nostr::apply_relay_list_event(&event).await;
                    continue;
                }

                // ── Kind 38383 order book event ──
                ingest_order_event(&event).await;
            }
            // Raw relay control messages. Observation only — every arm just
            // logs. CLOSED and NOTICE are anomalies (a relay refusing or
            // complaining about a subscription) that were previously
            // swallowed by the catch-all and undiagnosable in the field.
            Some(ClientNotification::Message { relay_url, message }) => {
                use nostr_sdk::prelude::RelayMessage;
                match *message {
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
                        // An empty book is only ever confirmed by this: the
                        // stream otherwise emits on ingest alone, and the UI
                        // shows its loading state until the first emission.
                        order_book().publish_on_stored_events_end(&sub_id).await;
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
            Some(ClientNotification::Shutdown) => {
                log::info!("[orders] relay pool shutdown — subscription loop exiting");
                break;
            }
            None => {
                log::warn!("[orders] notification stream closed");
                break;
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
    event: &nostr_sdk::prelude::Event,
    my_pubkey: Option<&nostr_sdk::prelude::PublicKey>,
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

/// Coerce a wire trade index (`i64`) into a usable counter value, or `None`.
///
/// Trade indexes cross the wire as `i64` (restore payloads, the
/// `LastTradeIndex` reply). A value that is negative or `>= u32::MAX` is not a
/// real trade index: negatives are nonsense, and `u32::MAX` is the reserved
/// terminal index — storing it as the counter would make the next
/// `derive_trade_key` compute `u32::MAX + 1` and overflow (panic in debug, wrap
/// to 0 in release, reissuing index 0 — the exact key-reuse the resync
/// prevents). Such a value is dropped rather than truncated into the counter.
fn sanitize_trade_index(i: i64) -> Option<u32> {
    u32::try_from(i).ok().filter(|&v| v < u32::MAX)
}

/// Highest trade-key index across all recovered orders and disputes (#217).
///
/// The counter must be raised to this so the next `derive_trade_key()` cannot
/// hand out an index a recovered trade already owns. Returns `None` when the
/// restore carried no trades (nothing to resync to).
///
/// NOTE (#328): this is only a *lower bound* of the daemon's real counter —
/// the restore payload lists only non-finalized orders, so a finalized trade
/// holding a higher index is invisible here. `restore_session` sources its
/// resync floor from `last_trade_index()` (authoritative) and falls back to
/// this only when the daemon does not answer.
fn recovered_max_trade_index(info: &mostro_core::message::RestoreSessionInfo) -> Option<u32> {
    let all: Vec<i64> = info
        .restore_orders
        .iter()
        .map(|o| o.trade_index)
        .chain(info.restore_disputes.iter().map(|d| d.trade_index))
        .collect();
    let total = all.len();
    let valid: Vec<u32> = all
        .iter()
        .copied()
        .filter_map(sanitize_trade_index)
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

/// Pick the resync floor as the highest of the daemon counter and the
/// restore-payload maximum (#328).
///
/// The daemon's `LastTradeIndex` answer (`daemon_counter`) is authoritative and
/// is the real high-water mark, including finalized trades. The payload maximum
/// is a proven lower bound — every recovered order carries its own index.
///
/// Against a consistent daemon the counter is always `>=` the payload maximum:
/// the daemon raises `last_trade_index` to every index it accepts
/// (`update_user_trade_index`) and rejects any index it has already seen, so an
/// order it still returns in the restore payload was necessarily seen at or
/// below the counter. Taking the max is therefore a no-op in practice — kept as
/// cheap defense-in-depth so the floor stays correct independent of that
/// invariant: a stale/partial reply or a daemon bug can never make us resync
/// below a recovered trade's own index and reuse its key. Returns `None` only
/// when neither source has a usable index.
fn resync_floor(
    daemon_counter: Option<u32>,
    info: &mostro_core::message::RestoreSessionInfo,
) -> Option<u32> {
    let payload_max = recovered_max_trade_index(info);
    match (daemon_counter, payload_max) {
        (Some(daemon), Some(payload)) => {
            if payload > daemon {
                // The invariant argued above says this cannot happen against a
                // consistent daemon — so seeing it means a stale/partial reply
                // or a daemon bug, the same "the daemon sent something this
                // client's model does not cover" class
                // recovered_max_trade_index already warns about. The behaviour
                // (take the payload bound) is right; the silence would not be.
                crate::api::logging::blog_warn(
                    "restore",
                    format!(
                        "LastTradeIndex counter {daemon} is below the restore \
                         payload max {payload} — inconsistent daemon reply; \
                         resyncing to the payload bound"
                    ),
                );
            }
            Some(daemon.max(payload))
        }
        (daemon, payload) => daemon.or(payload),
    }
}

/// True only for the reply to THIS `LastTradeIndex` request: the action
/// matches and the daemon echoed our correlation nonce
/// (`mostro/src/app/last_trade_index.rs` copies `request_id` into the reply).
///
/// A replayed reply from an earlier request carries a different nonce — or
/// none: mostro-cli sends this action with `request_id: None`
/// (`src/cli/last_trade_index.rs`), so nonce-less replies for the same account
/// exist in the wild wherever the user also runs the CLI. Accepting `None`
/// would readmit exactly those replays. This is deliberately stricter than
/// the spec — <https://mostro.network/protocol/last_trade_index.html>
/// documents no `request_id` on either side — so a conforming daemon that
/// never echoes one falls back to the restore-payload maximum, the same
/// designed path as a silent daemon.
fn is_matching_last_trade_index_reply(
    kind: &mostro_core::message::MessageKind,
    request_id: u64,
) -> bool {
    kind.action == mostro_core::message::Action::LastTradeIndex
        && kind.request_id == Some(request_id)
}

/// True for the daemon's refusal of THIS request: `CantDo` echoing our nonce.
///
/// The daemon currently answers `LastTradeIndex` with `CantDo(NotFound)` when
/// the account is unknown — an identity with no trade history on this node,
/// and every privacy-mode request, since without an identity proof there is no
/// account to look up — and `CantDo(InvalidTradeIndex)` when the stored
/// counter is 0 (where the spec instead says the counter comes back as 1;
/// either way the caller ends at the payload fallback). Both echo
/// `request_id` (`mostro/src/app.rs` routes `MostroCantDo` through
/// `enqueue_cant_do_msg` with the request's id).
/// Treating them as terminal turns a full REPLY_TIMEOUT stall on those paths
/// into an immediate, logged fallback.
fn is_matching_cant_do_refusal(kind: &mostro_core::message::MessageKind, request_id: u64) -> bool {
    kind.action == mostro_core::message::Action::CantDo && kind.request_id == Some(request_id)
}

/// Ask the daemon for its authoritative last-known trade index (#328).
///
/// The rumor is authored by `sender_keys` — the fresh trade key the caller
/// (`restore_session`) already derived — like every other daemon-bound event:
/// the outer kind-14 must never be authored by the master identity pubkey,
/// which would publish a permanent identity→Mostro link on every relay. The
/// daemon resolves the account from the encrypted identity proof
/// (`event.identity`) and replies to the rumor author (`event.sender`), so the
/// reply is a kind-14 addressed to the trade key, carrying the counter in
/// `MessageKind::trade_index`. The identity keys come from
/// `get_transport_identity_keys` — the privacy-toggle gate: in full-privacy
/// mode no proof is attached, the daemon finds no account and refuses with
/// `CantDo(NotFound)`, and the caller takes the payload fallback (privacy mode
/// has no stable account to ask about).
///
/// Returns `Ok(Some(idx))` with the sanitized counter, or `Ok(None)` when the
/// daemon refuses (`CantDo`), does not answer within the timeout, or the reply
/// carries no usable index — the caller then falls back to
/// `recovered_max_trade_index`.
///
/// This is a self-contained request/reply (own subscription + inline wait, like
/// mostro-cli's `wait_for_dm`) rather than a `pending_requests` record: the
/// reply also reaches the global dispatch path (the trade key is in the bulk
/// coverage), which ignores it — the restore's pending record was already
/// consumed — while this loop correlates by its own nonce.
async fn last_trade_index(sender_keys: &nostr_sdk::prelude::Keys) -> Result<Option<u32>> {
    use crate::rt::time::{timeout, Duration};
    use nostr_sdk::prelude::{ClientNotification, StreamExt};

    let trade_pk = sender_keys.public_key();
    let trade_pk_hex = trade_pk.to_hex();
    let mostro_pubkey = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())?;
    let identity_keys = crate::api::identity::get_transport_identity_keys(sender_keys).await?;

    // Correlation nonce, echoed by the daemon in its reply. Without it any
    // authenticated LastTradeIndex reply resolves this request, so a malicious
    // relay could replay an old one. Monotonicity caps the damage (the max in
    // resync_floor means a stale counter degrades to the payload fallback, the
    // same as a silent daemon) — but the daemon echoes request_id, so binding
    // the reply to this request costs nothing.
    let request_id: u64 = {
        use rand::RngCore;
        rand::rngs::OsRng.next_u64().max(1) // 0 is indistinguishable from "unset"
    };

    // Build the event BEFORE subscribing: wrap_message_first_contact awaits the
    // PoW capability snapshot and mines the PoW synchronously, so building
    // after subscribe would start the relay-side auto-close early and shrink
    // the usable reply window by the PoW + publish cost — at a high
    // pow_first_contact on a slow device the relay could CLOSE before the
    // request is even published.
    let event_json =
        actions::last_trade_index(&identity_keys, sender_keys, &mostro_pubkey, request_id).await?;

    let pool = crate::api::nostr::get_pool()?;
    let client = pool.client();

    // Grab the notifications receiver BEFORE subscribing so the reply can't
    // arrive in the gap between subscribe and the first recv.
    let mut rx = client.notifications();

    // This query, unlike the restore itself, has a fallback (the payload
    // maximum), so a shorter wait halves the worst-case restore latency
    // against a silent daemon. Shared by the relay-side auto-close and the
    // outer wait loop — both started at subscribe below, so the two budgets
    // actually run together.
    const REPLY_TIMEOUT: Duration = Duration::from_secs(5);

    // limit(0): live-only, same rationale as subscribe_daemon_messages — the
    // reply is published after we subscribe, and we never want a replayed
    // historical LastTradeIndex to resolve this request.
    let filter = nostr_sdk::prelude::Filter::new()
        .kind(nostr_sdk::prelude::Kind::PrivateDirectMessage)
        .author(mostro_pubkey)
        .pubkey(trade_pk)
        .limit(0);
    // Auto-close the relay-side subscription — this is a one-shot request/reply
    // (mostro-cli's wait_for_dm shape), not a long-lived watcher. Leaving the
    // CLOSE to manual bookkeeping is the leak class #182/#255 address.
    // WaitDurationAfterEOSE, not WaitForEventsAfterEOSE(1): the recipient is
    // the restore's trade key, so a late-propagating duplicate of the restore
    // reply matches this filter too and would consume a one-event budget before
    // the LastTradeIndex reply arrives. Holding the subscription open for the
    // full reply window closes it deterministically on every path without that
    // race. Auto-close subs are deliberately excluded from reconnect
    // re-subscription (correct here: if the socket drops mid-request we fall
    // back to the payload maximum by design).
    let close_opts = nostr_sdk::prelude::SubscribeAutoCloseOptions::default()
        .exit_policy(nostr_sdk::prelude::ReqExitPolicy::WaitDurationAfterEOSE(
            REPLY_TIMEOUT,
        ))
        .timeout(Some(REPLY_TIMEOUT));
    if let Err(e) = client.subscribe(filter).close_on(close_opts).await {
        log::warn!("[orders] last_trade_index subscribe failed: {e}");
        return Ok(None);
    }
    // Client-side deadline, started at subscribe time — the same instant the
    // relay-side auto-close starts — so both give up together.
    let start = crate::rt::time::Instant::now();

    publish_event_json(&event_json).await?;
    crate::api::logging::blog_info(
        "restore",
        "LastTradeIndex published — waiting for daemon".to_string(),
    );

    loop {
        let remaining = REPLY_TIMEOUT.saturating_sub(start.elapsed());
        if remaining.is_zero() {
            break;
        }
        match timeout(remaining, rx.next()).await {
            Ok(Some(ClientNotification::Event { event, .. })) => {
                if event.kind != nostr_sdk::prelude::Kind::PrivateDirectMessage
                    || event.pubkey != mostro_pubkey
                {
                    continue;
                }
                let is_for_us = event.tags.iter().any(|t| {
                    let s = t.as_slice();
                    s.first().map(|v| v.as_str()) == Some("p")
                        && s.get(1).map(|v| v.as_str()) == Some(trade_pk_hex.as_str())
                });
                if !is_for_us {
                    continue;
                }
                match crate::nostr::transport::unwrap_mostro_message(sender_keys, &event).await {
                    Ok(Some(unwrapped)) => {
                        // Authenticate: the kind-14 author must be the node.
                        if unwrapped.sender != mostro_pubkey {
                            continue;
                        }
                        let kind = unwrapped.message.get_inner_message_kind();
                        if is_matching_last_trade_index_reply(kind, request_id) {
                            let idx = kind.trade_index.and_then(sanitize_trade_index);
                            crate::api::logging::blog_info(
                                "restore",
                                format!(
                                    "LastTradeIndex reply: trade_index={:?} -> floor={idx:?}",
                                    kind.trade_index
                                ),
                            );
                            return Ok(idx);
                        }
                        if is_matching_cant_do_refusal(kind, request_id) {
                            let reason = match &kind.payload {
                                Some(mostro_core::message::Payload::CantDo(Some(r))) => {
                                    format!("{r:?}")
                                }
                                _ => "unspecified".to_string(),
                            };
                            crate::api::logging::blog_warn(
                                "restore",
                                format!(
                                    "LastTradeIndex refused: CantDo({reason}) — \
                                 falling back to restore payload max"
                                ),
                            );
                            return Ok(None);
                        }
                        continue;
                    }
                    Ok(None) => continue,
                    Err(e) => {
                        log::warn!("[orders] last_trade_index decrypt failed: {e}");
                        continue;
                    }
                }
            }
            Ok(Some(ClientNotification::Shutdown)) | Ok(None) => break,
            Err(_) => break, // timeout
            Ok(Some(_)) => continue,
        }
    }
    crate::api::logging::blog_warn(
        "restore",
        "LastTradeIndex: no usable daemon reply — falling back to restore payload max".to_string(),
    );
    Ok(None)
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

    let mostro_pubkey = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())?;
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
            // #217: raise trade_key_index before returning, so the next
            // derive_trade_key() can't reuse a key a recovered trade already
            // owns. Monotonic and idempotent. A persist failure fails the
            // restore: an un-resynced counter reopens the key-reuse bug this
            // closes, so silent success would be worse than a surfaced error
            // the caller can retry.
            //
            // #328: the authoritative floor is the daemon's LastTradeIndex
            // counter. The restore payload lists only non-finalized orders, so
            // recovered_max_trade_index is a lower bound (a finalized trade
            // holding a higher index is invisible) — kept only as a fallback
            // for when the daemon does not answer.
            let daemon_counter = match last_trade_index(&sender_keys).await {
                Ok(idx) => idx,
                Err(e) => {
                    crate::api::logging::blog_warn(
                        "restore",
                        format!(
                            "LastTradeIndex request errored ({e}); \
                         falling back to restore payload max"
                        ),
                    );
                    None
                }
            };
            if let Some(floor) = resync_floor(daemon_counter, &info) {
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

    /// Unsubscribing is only safe if each id addresses exactly one feed: a
    /// collision would have one trade's exit close another's subscription, or
    /// the order-book feed itself.
    #[test]
    fn every_subscription_id_addresses_one_feed() {
        let a = "aa".repeat(32);
        let b = "bb".repeat(32);

        assert_eq!(
            daemon_message_subscription_id(&a),
            daemon_message_subscription_id(&a),
            "the id must be stable, or the exit path unsubscribes nothing"
        );

        let ids = [
            daemon_message_subscription_id(&a),
            daemon_message_subscription_id(&b),
            single_order_subscription_id(&a),
            single_order_subscription_id(&b),
            orders_subscription_id(),
            recent_orders_subscription_id(),
            relay_list_subscription_id(),
            mostro_dm_subscription_id(),
        ];
        let unique: std::collections::HashSet<_> = ids.iter().collect();
        assert_eq!(
            unique.len(),
            ids.len(),
            "subscription ids collided: {ids:?}"
        );
    }

    /// NIP-01 caps subscription ids at 64 characters and relays enforce it
    /// with an asynchronous CLOSED that the client only logs — so an id past
    /// the cap is a subscription that silently never exists. A stable id that
    /// no relay accepts is worse than the auto-generated one it replaced.
    #[test]
    fn subscription_ids_fit_nip01() {
        const NIP01_MAX_SUBSCRIPTION_ID_LEN: usize = 64;
        let trade_pubkey_hex = "ab".repeat(32);
        let order_id = "3f2504e0-4f89-11d3-9a0c-0305e82c3301";

        for id in [
            daemon_message_subscription_id(&trade_pubkey_hex),
            single_order_subscription_id(order_id),
            orders_subscription_id(),
            recent_orders_subscription_id(),
            relay_list_subscription_id(),
            mostro_dm_subscription_id(),
        ] {
            let len = id.to_string().len();
            assert!(
                len <= NIP01_MAX_SUBSCRIPTION_ID_LEN,
                "subscription id {id} is {len} chars; NIP-01 relays reject anything over 64"
            );
        }
    }

    /// A node switch re-runs `subscribe_node_filters` under the same stable
    /// ids. nostr-sdk 0.45 refuses a subscribe whose id already exists and
    /// keeps the old filters — reporting it per relay, not as an error — so
    /// every live feed stayed pinned to the previous node until a restart.
    #[tokio::test]
    async fn a_node_switch_retargets_every_live_subscription() {
        use nostr_sdk::local_relay::MockRelay;
        use nostr_sdk::prelude::{Client, Keys};

        let relay = MockRelay::run().await.expect("mock relay");
        let url = relay.url().await;
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        client
            .try_connect_relay(url, std::time::Duration::from_secs(3))
            .await
            .expect("connect");
        let trade = Keys::generate();
        global_dm_keys()
            .write()
            .await
            .insert(trade.public_key().to_hex(), (trade, 93));
        let previous = Keys::generate().public_key();
        let next = Keys::generate().public_key();

        subscribe_node_filters(&client, previous)
            .await
            .expect("first subscribe");
        subscribe_node_filters(&client, next)
            .await
            .expect("node switch");

        for id in [
            orders_subscription_id(),
            recent_orders_subscription_id(),
            relay_list_subscription_id(),
            mostro_dm_subscription_id(),
        ] {
            let per_relay = client.subscription(&id).await;
            assert!(!per_relay.is_empty(), "{id} has no live subscription");
            for filter in per_relay.values().flatten() {
                assert_eq!(
                    filter.authors,
                    Some(std::collections::BTreeSet::from([next])),
                    "{id} is still pinned to the previous node"
                );
            }
        }
    }

    /// The SDK reports a subscribe that failed on every relay as an `Ok`
    /// output. Accepting that meant a feed with no REQ anywhere was logged
    /// as created; a relay that was never connected must make it an error.
    #[tokio::test]
    async fn a_subscription_no_relay_accepts_is_an_error() {
        use nostr_sdk::local_relay::MockRelay;
        use nostr_sdk::prelude::{Client, Keys};

        let relay = MockRelay::run().await.expect("mock relay");
        let client = Client::new();
        client
            .add_relay(relay.url().await)
            .await
            .expect("add relay");

        let result = subscribe_node_filters(&client, Keys::generate().public_key()).await;

        assert!(
            result.is_err(),
            "a subscription no relay accepted must not pass for a live one"
        );
    }

    /// PR #423 review: a node switch and a mid-session key joining the
    /// coverage both replace `mostro-dm`. Interleaved, the CLOSE/REQ pairs
    /// either leave the filter built from the stale key set or make one REQ
    /// hit "subscription ID already exists". The last replace must win with
    /// every covered key, and neither caller may fail.
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn concurrent_dm_filter_replacements_keep_every_covered_key() {
        use nostr_sdk::local_relay::MockRelay;
        use nostr_sdk::prelude::{Client, Keys};

        const RACERS: usize = 16;

        let relay = MockRelay::run().await.expect("mock relay");
        let url = relay.url().await;
        let client = Client::new();
        client.add_relay(&url).await.expect("add relay");
        client
            .try_connect_relay(url, std::time::Duration::from_secs(3))
            .await
            .expect("connect");
        let node = Keys::generate().public_key();
        let snapshot = Keys::generate();
        global_dm_keys()
            .write()
            .await
            .insert(snapshot.public_key().to_hex(), (snapshot.clone(), 94));

        // Against an in-process relay one replacement never yields, so the
        // race only shows with real parallelism: the barrier releases every
        // racer at once, each adding its own key and replacing `mostro-dm`.
        let barrier = std::sync::Arc::new(tokio::sync::Barrier::new(RACERS));
        let joined: Vec<Keys> = (0..RACERS).map(|_| Keys::generate()).collect();
        let racers: Vec<_> = joined
            .iter()
            .cloned()
            .map(|keys| {
                let (client, barrier) = (client.clone(), barrier.clone());
                tokio::spawn(async move {
                    barrier.wait().await;
                    global_dm_keys()
                        .write()
                        .await
                        .insert(keys.public_key().to_hex(), (keys, 95));
                    replace_global_dm_filter(&client, node).await
                })
            })
            .collect();
        for racer in racers {
            racer
                .await
                .expect("racer panicked")
                .expect("a concurrent replacement failed");
        }
        let per_relay = client.subscription(&mostro_dm_subscription_id()).await;
        let pubkeys = per_relay
            .values()
            .flatten()
            .filter_map(|f| {
                f.generic_tags
                    .get(&nostr_sdk::prelude::SingleLetterTag::LOWERCASE_P)
                    .cloned()
            })
            .flatten()
            .collect::<std::collections::BTreeSet<_>>();
        for key in std::iter::once(&snapshot).chain(&joined) {
            assert!(
                pubkeys.contains(&key.public_key().to_hex()),
                "mostro-dm lost a covered key"
            );
        }
    }

    /// The truncation that keeps the daemon id under the cap must not merge
    /// two trade keys that share a prefix shorter than what is kept.
    #[test]
    fn daemon_ids_stay_distinct_past_the_truncation_point() {
        let a = "ab".repeat(32);
        let b = "ab".repeat(15) + "cd" + &"ab".repeat(16);
        assert_ne!(
            daemon_message_subscription_id(&a),
            daemon_message_subscription_id(&b)
        );
    }

    /// Nothing ever displays a stranger's finished order — the book filters to
    /// Pending for display — but every one of them was kept for the life of
    /// the process, inflating every snapshot clone and every bridge payload.
    #[tokio::test]
    async fn a_strangers_finished_order_leaves_the_book() {
        let book = OrderBook::new();
        let mut done = dummy_order_info("stranger-done");
        done.is_mine = false;
        done.status = crate::api::types::OrderStatus::Pending;
        book.upsert_order(done.clone()).await;
        assert!(book.get_order("stranger-done").await.is_some());

        done.status = crate::api::types::OrderStatus::Success;
        book.apply_ingested_order(done, false, Publish::Coalesced)
            .await;

        assert!(
            book.get_order("stranger-done").await.is_none(),
            "a finished order nobody can act on should not be retained"
        );
    }

    /// Orders of ours stay: the trade detail screen looks them up in the book
    /// by id after the trade finishes.
    #[tokio::test]
    async fn our_own_finished_order_stays_in_the_book() {
        let book = OrderBook::new();
        let mut mine = dummy_order_info("mine-done");
        mine.status = crate::api::types::OrderStatus::Success;

        book.apply_ingested_order(mine, true, Publish::Coalesced)
            .await;

        assert!(
            book.get_order("mine-done").await.is_some(),
            "our own history must remain addressable by id"
        );
    }

    /// Build a signed Kind 38383 event for `order_id` at `status`, the shape
    /// the relay feed delivers.
    fn book_event(order_id: &str, status: &str) -> nostr_sdk::prelude::Event {
        book_event_amt(order_id, status, "0")
    }

    /// [`book_event`] signed by `author`.
    fn book_event_by(
        order_id: &str,
        status: &str,
        author: &nostr_sdk::prelude::Keys,
    ) -> nostr_sdk::prelude::Event {
        book_event_with(order_id, status, "0", author)
    }

    /// [`book_event`] with an explicit `amt` tag, for the amount-gate tests.
    fn book_event_amt(order_id: &str, status: &str, amt: &str) -> nostr_sdk::prelude::Event {
        book_event_with(order_id, status, amt, &nostr_sdk::prelude::Keys::generate())
    }

    /// The Kind 38383 event behind [`book_event_by`] and [`book_event_amt`].
    fn book_event_with(
        order_id: &str,
        status: &str,
        amt: &str,
        author: &nostr_sdk::prelude::Keys,
    ) -> nostr_sdk::prelude::Event {
        use nostr::event::FinalizeEvent;
        use nostr_sdk::prelude::{EventBuilder, Kind, Tag};
        EventBuilder::new(Kind::from(38383u16), "")
            .tags([
                Tag::parse(["d", order_id]).unwrap(),
                Tag::parse(["k", "sell"]).unwrap(),
                Tag::parse(["s", status]).unwrap(),
                Tag::parse(["f", "USD"]).unwrap(),
                Tag::parse(["pm", "cashapp"]).unwrap(),
                Tag::parse(["premium", "1"]).unwrap(),
                Tag::parse(["amt", amt]).unwrap(),
                Tag::parse(["fa", "20"]).unwrap(),
                Tag::parse(["z", "order"]).unwrap(),
            ])
            .finalize(author)
            .unwrap()
    }

    /// Review round 2: the Kind 38383 sync is gated WHOLE on
    /// `wire_status_applies` — a public bucket that may not replace the
    /// private status must not sneak its amount into the row either. The
    /// pre-#394 shape wrote the amount even when the status was refused;
    /// this pins the gate so restoring that shape goes red. The d-tag half
    /// is pinned through `apply_single_order_update` by
    /// `a_refused_d_tag_status_does_not_sneak_its_amount_into_the_row`.
    #[tokio::test]
    async fn a_refused_wire_status_does_not_sneak_its_amount_into_the_row() {
        let path = std::env::temp_dir().join(format!("mostro_amtgate_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_id = uuid::Uuid::new_v4().to_string();
        let mut row = seam_trade_row(&order_id, crate::api::types::OrderStatus::Active);
        row.order.amount_sats = Some(5_000);
        db.save_trade(&row).await.expect("save the trade row");
        store_trade_key_index(&order_id, 7).await;

        // `in-progress` over an Active row is the canonical refusal (#203):
        // neither the status nor the event's amount may land.
        ingest_order_event_with(
            &book_event_amt(&order_id, "in-progress", "7777"),
            Publish::WhenBatchEnds,
        )
        .await;
        let row = db
            .get_trade_by_order_id(&order_id)
            .await
            .expect("lookup")
            .expect("row exists");
        assert_eq!(row.order.status, crate::api::types::OrderStatus::Active);
        assert_eq!(
            row.order.amount_sats,
            Some(5_000),
            "a refused wire status must not sneak its amount into the row",
        );

        // The control: a terminal wire status applies, and its amount lands
        // with it — the gate refuses the pair, not the amount.
        ingest_order_event_with(
            &book_event_amt(&order_id, "canceled", "7777"),
            Publish::WhenBatchEnds,
        )
        .await;
        let row = db
            .get_trade_by_order_id(&order_id)
            .await
            .expect("lookup")
            .expect("row exists");
        assert_eq!(row.order.status, crate::api::types::OrderStatus::Canceled);
        assert_eq!(
            row.order.amount_sats,
            Some(7_777),
            "an applied wire status carries its amount",
        );
        order_book().remove_order(&order_id).await;
    }

    /// The regression this PR was one predicate away from shipping: an order we
    /// **took** arrives with `is_mine == false` — `parse_order_event` hardcodes
    /// it and the cold-start restore only raises it for *maker* rows — so a
    /// prune keyed on `is_mine` alone drops it the moment the trade succeeds,
    /// and the trade-detail screen the app navigates to right afterwards loses
    /// the amount, the currency and the created-at line it reads from the book.
    ///
    /// The trade-key binding is what both roles have, so that is what decides.
    #[tokio::test]
    async fn a_finished_order_we_took_survives_ingest() {
        // Arrange — in the book as pending, with a trade key of ours bound to
        // it, which is what taking an order leaves behind.
        let order_id = uuid::Uuid::new_v4().to_string();
        order_book().upsert_order(dummy_order_info(&order_id)).await;
        store_trade_key_index(&order_id, 7).await;

        // Act — the daemon publishes the finished order.
        ingest_order_event_with(&book_event(&order_id, "success"), Publish::WhenBatchEnds).await;

        // Assert
        assert!(
            order_book().get_order(&order_id).await.is_some(),
            "an order we took must stay addressable once it finishes"
        );
        order_book().remove_order(&order_id).await;
    }

    /// The other half: with no binding and no `is_mine`, the same event is a
    /// stranger's finished order and leaves.
    #[tokio::test]
    async fn a_finished_order_of_a_strangers_is_dropped_by_ingest() {
        // Arrange
        let order_id = uuid::Uuid::new_v4().to_string();
        order_book().upsert_order(dummy_order_info(&order_id)).await;

        // Act
        ingest_order_event_with(&book_event(&order_id, "success"), Publish::WhenBatchEnds).await;

        // Assert
        assert!(
            order_book().get_order(&order_id).await.is_none(),
            "nothing can ever act on a stranger's finished order"
        );
    }

    /// A removal that removed nothing must not publish: a stranger's order
    /// finishing unseen is the common case on a busy node, and every emission
    /// carries the whole book across the bridge.
    #[tokio::test]
    async fn dropping_an_order_that_was_never_in_the_book_publishes_nothing() {
        let book = OrderBook::new();
        let mut stream = book.subscribe();
        let mut unseen = dummy_order_info("never-seen");
        unseen.status = crate::api::types::OrderStatus::Canceled;

        book.apply_ingested_order(unseen, false, Publish::Coalesced)
            .await;

        assert!(
            stream.try_recv().is_err(),
            "a no-op removal must not send a whole-book snapshot"
        );
    }

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

    /// The relay's EOSE on the pending-book subscription is the only signal
    /// that an empty book is *confirmed* empty. Without it the UI has nothing
    /// to leave its loading state on: the stream publishes on ingest alone,
    /// and a node with no pending orders never ingests anything.
    #[tokio::test]
    async fn eose_on_the_pending_subscription_publishes_the_empty_book() {
        let book = OrderBook::new();
        let mut rx = book.subscribe();

        let published = book
            .publish_on_stored_events_end(&orders_subscription_id())
            .await;

        assert!(published);
        let snapshot = rx.try_recv().expect("EOSE must publish the current book");
        assert!(snapshot.is_empty(), "an empty book is published as empty");
    }

    /// Only the pending-book feed is the "book loaded" signal. The recent
    /// changes feed and the Kind 14 feed end their stored events too, and
    /// re-publishing on each would send the whole book across the bridge
    /// once per relay per subscription.
    #[tokio::test]
    async fn eose_on_other_subscriptions_does_not_publish() {
        let book = OrderBook::new();
        let mut rx = book.subscribe();

        let published = book
            .publish_on_stored_events_end(&recent_orders_subscription_id())
            .await;

        assert!(!published);
        assert!(
            matches!(rx.try_recv(), Err(broadcast::error::TryRecvError::Empty)),
            "EOSE on another subscription must not publish"
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
        use nostr_sdk::prelude::{EventBuilder, FinalizeEvent, Kind, Tag};

        let mine = nostr_sdk::prelude::Keys::generate();
        let mine_hex = mine.public_key().to_hex();
        let stranger = nostr_sdk::prelude::Keys::generate();

        let addressed_to_us = EventBuilder::new(Kind::PrivateDirectMessage, "")
            .tags([Tag::parse(["p", &mine_hex]).unwrap()])
            .finalize(&nostr_sdk::prelude::Keys::generate())
            .unwrap();
        // A stranger's key is never inserted, so this one resolves to None
        // whatever else the shared map happens to hold.
        let addressed_elsewhere = EventBuilder::new(Kind::PrivateDirectMessage, "")
            .tags([Tag::parse(["p", &stranger.public_key().to_hex()]).unwrap()])
            .finalize(&nostr_sdk::prelude::Keys::generate())
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

    // ── #328 sanitize_trade_index / resync_floor ─────────────────────────────
    #[test]
    fn sanitize_trade_index_drops_negative_and_out_of_range() {
        assert_eq!(sanitize_trade_index(0), Some(0));
        assert_eq!(sanitize_trade_index(42), Some(42));
        assert_eq!(sanitize_trade_index(-1), None);
        // u32::MAX is the reserved terminal index (dropped to avoid +1 overflow).
        assert_eq!(sanitize_trade_index(i64::from(u32::MAX)), None);
        assert_eq!(
            sanitize_trade_index(i64::from(u32::MAX) - 1),
            Some(u32::MAX - 1)
        );
        assert_eq!(sanitize_trade_index(i64::from(u32::MAX) + 1), None);
    }

    #[test]
    fn resync_floor_takes_the_higher_of_daemon_counter_and_payload_max() {
        // The #328 scenario: order X open at index 1 (the only non-finalized
        // trade the restore returns), order Y canceled at index 2. The payload
        // max is 1, but the daemon's LastTradeIndex counter is 2 — the real
        // high-water mark — and must win, or the first new order collides.
        assert_eq!(
            resync_floor(Some(2), &restore_info(vec![1], vec![])),
            Some(2)
        );
        // Defense-in-depth: never resync below a recovered trade's own index.
        // A consistent daemon cannot answer below an index it still tracks (it
        // raised last_trade_index when it accepted that order), so this only
        // guards a stale/partial reply — the payload lower bound then wins.
        assert_eq!(
            resync_floor(Some(1), &restore_info(vec![5], vec![])),
            Some(5)
        );
        // Daemon present, payload empty -> the daemon value.
        assert_eq!(
            resync_floor(Some(7), &restore_info(vec![], vec![])),
            Some(7)
        );
    }

    #[test]
    fn a_replayed_last_trade_index_reply_is_rejected() {
        use mostro_core::message::{Action, MessageKind};

        let reply = |request_id: Option<u64>| {
            MessageKind::new(None, request_id, Some(7), Action::LastTradeIndex, None)
        };
        // The genuine reply echoes our nonce.
        assert!(is_matching_last_trade_index_reply(&reply(Some(42)), 42));
        // A replay of an earlier request's reply carries a different nonce...
        assert!(!is_matching_last_trade_index_reply(&reply(Some(41)), 42));
        // ...or none at all — mostro-cli sends this action with no request_id,
        // so nonce-less replies for the same account exist in the wild and are
        // exactly the replay material to reject.
        assert!(!is_matching_last_trade_index_reply(&reply(None), 42));
        // A different action never matches, even with the right nonce.
        let other = MessageKind::new(None, Some(42), Some(7), Action::RestoreSession, None);
        assert!(!is_matching_last_trade_index_reply(&other, 42));
    }

    #[test]
    fn a_cant_do_refusal_matches_only_our_nonce() {
        use mostro_core::message::{Action, MessageKind};

        let refusal = |request_id: Option<u64>| {
            MessageKind::new(None, request_id, None, Action::CantDo, None)
        };
        // The daemon's refusal of THIS request echoes our nonce and is
        // terminal — the caller falls back immediately instead of stalling.
        assert!(is_matching_cant_do_refusal(&refusal(Some(42)), 42));
        // A replayed or foreign CantDo does not resolve this request.
        assert!(!is_matching_cant_do_refusal(&refusal(Some(41)), 42));
        assert!(!is_matching_cant_do_refusal(&refusal(None), 42));
        // The genuine counter reply is not a refusal.
        let counter = MessageKind::new(None, Some(42), Some(7), Action::LastTradeIndex, None);
        assert!(!is_matching_cant_do_refusal(&counter, 42));
    }

    #[test]
    fn resync_floor_falls_back_to_payload_max_when_daemon_is_silent() {
        // No LastTradeIndex answer (timeout / error): the restore-payload
        // maximum is the best available lower bound.
        assert_eq!(
            resync_floor(None, &restore_info(vec![3, 9], vec![4])),
            Some(9)
        );
        // Nothing anywhere -> no resync (None).
        assert_eq!(resync_floor(None, &restore_info(vec![], vec![])), None);
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
        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        mostro_core::nip59::UnwrappedMessage {
            message,
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::prelude::Timestamp::from(0u64),
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

    /// #394 step 3: with the content fingerprint gone, `is_mine` on cold
    /// start comes from the durable trade-key binding plus the trade row it
    /// points at — keyed by daemon UUID, immune to the content collisions of
    /// #326. A binding alone is not maker-ness: a taker row keeps
    /// `is_mine = false`, and a stranger's order restores nothing.
    #[tokio::test]
    async fn cold_start_restores_is_mine_from_binding_and_row() {
        let path = std::env::temp_dir().join(format!("mostro_ismine_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        // A maker row + binding, as create/confirm leave them.
        let maker_id = uuid::Uuid::new_v4().to_string();
        db.save_trade(&seam_trade_row(
            &maker_id,
            crate::api::types::OrderStatus::Pending,
        ))
        .await
        .expect("save maker row");
        store_trade_key_index(&maker_id, 42).await;
        ingest_order_event_with(&book_event(&maker_id, "pending"), Publish::WhenBatchEnds).await;
        assert!(
            order_book()
                .get_order(&maker_id)
                .await
                .expect("book entry")
                .is_mine,
            "binding + maker row must restore is_mine on cold start",
        );

        // A stranger's order: no binding, nothing restored.
        let stranger_id = uuid::Uuid::new_v4().to_string();
        ingest_order_event_with(&book_event(&stranger_id, "pending"), Publish::WhenBatchEnds).await;
        assert!(
            !order_book()
                .get_order(&stranger_id)
                .await
                .expect("book entry")
                .is_mine,
        );

        // A taker row: binding exists, but the row says we are not the maker.
        let taken_id = uuid::Uuid::new_v4().to_string();
        let mut taken = seam_trade_row(&taken_id, crate::api::types::OrderStatus::Active);
        taken.order.is_mine = false;
        db.save_trade(&taken).await.expect("save taker row");
        store_trade_key_index(&taken_id, 43).await;
        ingest_order_event_with(
            &book_event(&taken_id, "in-progress"),
            Publish::WhenBatchEnds,
        )
        .await;
        assert!(
            !order_book()
                .get_order(&taken_id)
                .await
                .expect("book entry")
                .is_mine,
            "a binding alone must never claim maker-ness",
        );
    }

    /// PR #253 review round 2 (ermeme): a key derived after the global
    /// subscription started must join the refreshable coverage map — that is
    /// what lets the bulk Kind-14 path decrypt a solver assignment arriving
    /// after the 30-minute per-trade receiver expired. (The relay-filter
    /// refresh itself is a no-op here: no pool in unit tests.)
    #[tokio::test]
    async fn a_late_derived_key_joins_the_global_dm_coverage() {
        let keys = nostr_sdk::prelude::Keys::generate();
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

        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        let unwrapped = mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(Some(order_uuid), None, None, Action::Canceled, None),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::prelude::Timestamp::from(0u64),
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

    /// A taker's trade row for the cancel tests, at `order.status`.
    fn cancel_test_row(order: crate::api::types::OrderInfo) -> crate::api::types::TradeInfo {
        crate::api::types::TradeInfo {
            id: uuid::Uuid::new_v4().to_string(),
            order,
            role: TradeRole::Buyer,
            counterparty_pubkey: String::new(),
            current_step: crate::api::types::TradeStep::Buyer(
                crate::api::types::BuyerStep::OrderTaken,
            ),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 1,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
        }
    }

    /// A cancel of a trade that never went active must leave the row for the
    /// daemon's `Canceled`, which wipes it together with its session. Marking
    /// it `Canceled` locally first made that arm skip it as "already
    /// Canceled", so the row and the session outlived the trade — and the
    /// row's terminal status then refused the daemon's `pending` republish,
    /// hiding the order from the ex-taker's book for good.
    ///
    /// Goes through the real `Canceled` arm: restoring the optimistic write
    /// fails the first assertion, and the wipe after it is only reachable
    /// because the row was left alone.
    #[tokio::test]
    async fn cancel_of_a_never_active_take_is_left_for_the_daemons_canceled() {
        use mostro_core::message::{Action, Message};

        let path = std::env::temp_dir()
            .join(format!("mostro_cancel_never_active_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let mut order_info = dummy_order_info(&order_id);
        order_info.status = crate::api::types::OrderStatus::WaitingBuyerInvoice;
        order_book().upsert_order(order_info.clone()).await;
        db.save_trade(&cancel_test_row(order_info.clone()))
            .await
            .expect("save the trade row");
        session_manager()
            .install_session(order_id.clone(), TradeRole::Buyer, 1, order_info)
            .await
            .expect("install the take's session");

        apply_local_cancel(&order_id).await;

        assert!(
            order_book().get_order(&order_id).await.is_none(),
            "the cancel still takes the order out of the in-memory book"
        );
        assert_eq!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("trade lookup")
                .expect("the row must still be there")
                .order
                .status,
            crate::api::types::OrderStatus::WaitingBuyerInvoice,
            "a never-active row must be left for the daemon's Canceled"
        );

        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        dispatch_mostro_message(
            mostro_core::nip59::UnwrappedMessage {
                message: Message::new_order(Some(order_uuid), None, None, Action::Canceled, None),
                signature: None,
                sender,
                identity: sender,
                created_at: nostr_sdk::prelude::Timestamp::from(1_000u64),
            },
            "test-cancel-never-active",
            "ff00ff20",
            1,
        )
        .await;

        assert!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("trade lookup")
                .is_none(),
            "the daemon's Canceled must wipe the never-active row"
        );
        assert!(
            session_manager().get_session(&order_id).await.is_none(),
            "the daemon's Canceled must remove the take's session"
        );
    }

    /// Dispatch the daemon's `Canceled` for `order_uuid`, as the relay feed
    /// would deliver it.
    async fn dispatch_daemon_canceled(order_uuid: uuid::Uuid, event_id: &str) {
        use mostro_core::message::{Action, Message};
        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        dispatch_mostro_message(
            mostro_core::nip59::UnwrappedMessage {
                message: Message::new_order(Some(order_uuid), None, None, Action::Canceled, None),
                signature: None,
                sender,
                identity: sender,
                created_at: nostr_sdk::prelude::Timestamp::from(1_000u64),
            },
            event_id,
            "ff00ff21",
            1,
        )
        .await;
    }

    /// The order as a Kind 38383 event of the daemon would carry it.
    fn wire_order(order_id: &str, status: OrderStatus) -> OrderInfo {
        let mut order = dummy_order_info(order_id);
        order.status = status;
        order
    }

    async fn book_status(order_id: &str) -> Option<OrderStatus> {
        order_book().get_order(order_id).await.map(|o| o.status)
    }

    /// A lost take, in the order mostrod sends it: the `pending` republish
    /// first — refused while our `waiting-*` row still stands, so the entry
    /// keeps the local status — then the `Canceled`. The wipe must hand the
    /// order back to the book as `pending`; before, nothing arrived after the
    /// `Canceled` to correct the entry, and the order vanished from the
    /// ex-taker's book although every other client could take it.
    #[tokio::test]
    async fn a_lost_take_returns_to_the_book_when_the_republish_came_first() {
        let path = std::env::temp_dir()
            .join(format!("mostro_lost_take_republish_first_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let taken = wire_order(&order_id, OrderStatus::WaitingBuyerInvoice);
        order_book().upsert_order(taken.clone()).await;
        db.save_trade(&cancel_test_row(taken))
            .await
            .expect("save the trade row");

        apply_single_order_update(wire_order(&order_id, OrderStatus::Pending)).await;
        assert_eq!(
            book_status(&order_id).await,
            Some(OrderStatus::WaitingBuyerInvoice),
            "while the take stands, the entry keeps the local status"
        );

        dispatch_daemon_canceled(order_uuid, "test-lost-take-republish-first").await;

        assert!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("trade lookup")
                .is_none(),
            "the lost take's row is wiped"
        );
        assert_eq!(
            book_status(&order_id).await,
            Some(OrderStatus::Pending),
            "the republished order must be back in the ex-taker's book"
        );
    }

    /// The same lost take with the `Canceled` overtaking the republish on the
    /// way here. The last public view is the take's `in-progress`, so the entry
    /// is dropped rather than restored — and the `pending` that arrives next
    /// lands on nothing local and applies. Kept, the entry's local status
    /// would refuse it exactly as the row did.
    #[tokio::test]
    async fn a_lost_take_returns_to_the_book_when_the_canceled_came_first() {
        let path = std::env::temp_dir()
            .join(format!("mostro_lost_take_canceled_first_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let taken = wire_order(&order_id, OrderStatus::WaitingBuyerInvoice);
        order_book().upsert_order(taken.clone()).await;
        db.save_trade(&cancel_test_row(taken))
            .await
            .expect("save the trade row");
        apply_single_order_update(wire_order(&order_id, OrderStatus::InProgress)).await;

        dispatch_daemon_canceled(order_uuid, "test-lost-take-canceled-first").await;
        assert_eq!(
            book_status(&order_id).await,
            None,
            "no public pending seen yet: the entry is dropped, not left stale"
        );

        apply_single_order_update(wire_order(&order_id, OrderStatus::Pending)).await;
        assert_eq!(
            book_status(&order_id).await,
            Some(OrderStatus::Pending),
            "the republish arriving after the wipe must apply"
        );
    }

    /// The note must follow the wire on the book feed too. The d-tag
    /// subscription noted the take's `in-progress` and then went quiet (it
    /// idles out); the republish reaches the book feed alone, which applies
    /// `pending` directly. Had the note stayed at `in-progress`, the wipe would
    /// drop the correctly public entry and hide the order again.
    #[tokio::test]
    async fn a_republish_seen_only_by_the_book_feed_survives_the_wipe() {
        let path = std::env::temp_dir()
            .join(format!("mostro_lost_take_book_feed_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let taken = wire_order(&order_id, OrderStatus::WaitingBuyerInvoice);
        order_book().upsert_order(taken.clone()).await;
        db.save_trade(&cancel_test_row(taken))
            .await
            .expect("save the trade row");
        apply_single_order_update(wire_order(&order_id, OrderStatus::InProgress)).await;

        ingest_order_event_with(&book_event(&order_id, "pending"), Publish::WhenBatchEnds).await;
        dispatch_daemon_canceled(order_uuid, "test-lost-take-book-feed").await;

        assert_eq!(
            book_status(&order_id).await,
            Some(OrderStatus::Pending),
            "the republish the book feed applied must survive the wipe"
        );
    }

    /// A confirmed take is its order's only row. A row an earlier take of the
    /// same order left behind (its `Canceled` lost, or written before takers'
    /// cancels were wiped) used to stay next to the new one, and lookups by
    /// order id could return the dead take — its status and its trade key.
    #[tokio::test]
    async fn a_confirmed_take_replaces_the_orders_earlier_row() {
        let path = std::env::temp_dir()
            .join(format!("mostro_one_row_per_order_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_id = uuid::Uuid::new_v4().to_string();
        let earlier = cancel_test_row(wire_order(&order_id, OrderStatus::Canceled));
        db.save_trade(&earlier).await.expect("save the earlier take");
        let mut retake = cancel_test_row(wire_order(&order_id, OrderStatus::WaitingBuyerInvoice));
        retake.trade_key_index = 2;

        persist_confirmed_take(&retake).await;

        let rows: Vec<_> = db
            .list_trades()
            .await
            .expect("list trades")
            .into_iter()
            .filter(|t| t.order.id == order_id)
            .collect();
        assert_eq!(rows.len(), 1, "one row per order after a retake");
        assert_eq!(rows[0].id, retake.id, "the row left is the retake's");
        assert_eq!(rows[0].trade_key_index, 2, "carrying the retake's trade key");
    }

    /// Only a *take* is handed back. A maker's own order dies with the
    /// cancel: even with an earlier `pending` view noted, its entry is left to
    /// the daemon's Kind 38383 `canceled`, never restored to `pending`.
    #[tokio::test]
    async fn a_makers_wiped_order_is_not_handed_back_to_the_book() {
        let path = std::env::temp_dir()
            .join(format!("mostro_maker_wipe_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let mut mine = wire_order(&order_id, OrderStatus::Pending);
        mine.is_mine = true;
        order_book().upsert_order(mine.clone()).await;
        let mut row = cancel_test_row(mine);
        row.role = TradeRole::Seller;
        db.save_trade(&row).await.expect("save the trade row");
        // The d-tag subscription noted the order as pending at creation; the
        // daemon's `canceled` then reached the book.
        apply_single_order_update(wire_order(&order_id, OrderStatus::Pending)).await;
        order_book()
            .update_order_status(&order_id, OrderStatus::Canceled)
            .await;

        dispatch_daemon_canceled(order_uuid, "test-maker-wipe").await;

        assert!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("trade lookup")
                .is_none(),
            "the maker's never-active row is still wiped"
        );
        assert_eq!(
            book_status(&order_id).await,
            Some(OrderStatus::Canceled),
            "a canceled maker order must not be restored to pending"
        );
    }

    /// Past `waiting-*` nothing changes: the cancel of an active trade still
    /// marks its row `Canceled` straight away.
    #[tokio::test]
    async fn cancel_of_an_active_trade_still_marks_it_canceled() {
        let path = std::env::temp_dir()
            .join(format!("mostro_cancel_active_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_id = uuid::Uuid::new_v4().to_string();
        let mut order_info = dummy_order_info(&order_id);
        order_info.status = crate::api::types::OrderStatus::Active;
        db.save_trade(&cancel_test_row(order_info))
            .await
            .expect("save the trade row");

        apply_local_cancel(&order_id).await;

        assert_eq!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("trade lookup")
                .expect("the row must still be there")
                .order
                .status,
            crate::api::types::OrderStatus::Canceled,
            "an active trade's row is still marked Canceled optimistically"
        );
    }

    async fn trade_row_gone(order_id: &str) -> bool {
        crate::db::app_db::db()
            .expect("store initialised")
            .get_trade_by_order_id(order_id)
            .await
            .expect("trade lookup")
            .is_none()
    }

    /// A maker's own cancel of an order that never went active ends out of
    /// My Trades whichever of the daemon's two reports this client handles
    /// first. mostrod publishes the Kind 38383 `canceled` and sends the
    /// kind-14 `Canceled`, and the two reach separate subscriptions: event
    /// first used to write `Canceled` into the row, which the message then
    /// kept as history, while the opposite order wiped it.
    ///
    /// The event-first half also stands for an expired pending order, which
    /// gets the event (mostrod publishes `Expired` as `canceled`) and no
    /// message at all: the row must be gone before any `Canceled` arrives.
    #[tokio::test]
    async fn a_makers_never_active_cancel_is_wiped_whichever_signal_lands_first() {
        let path = std::env::temp_dir()
            .join(format!("mostro_maker_cancel_race_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        for (status, event_first) in [
            (OrderStatus::Pending, true),
            (OrderStatus::Pending, false),
            (OrderStatus::WaitingPayment, true),
            (OrderStatus::WaitingPayment, false),
        ] {
            let case = format!("{status:?}, event first: {event_first}");
            let order_uuid = uuid::Uuid::new_v4();
            let order_id = order_uuid.to_string();
            let mut mine = wire_order(&order_id, status);
            mine.is_mine = true;
            order_book().upsert_order(mine.clone()).await;
            db.save_trade(&cancel_test_row(mine.clone()))
                .await
                .expect("save the trade row");
            session_manager()
                .install_session(order_id.clone(), TradeRole::Buyer, 1, mine)
                .await
                .expect("install the maker's session");

            apply_local_cancel(&order_id).await;
            let canceled_event = book_event(&order_id, "canceled");
            let message_id = format!("test-maker-cancel-{order_id}");
            if event_first {
                ingest_order_event_with(&canceled_event, Publish::WhenBatchEnds).await;
                assert!(
                    trade_row_gone(&order_id).await,
                    "{case}: the public canceled alone must wipe the row"
                );
                dispatch_daemon_canceled(order_uuid, &message_id).await;
            } else {
                dispatch_daemon_canceled(order_uuid, &message_id).await;
                ingest_order_event_with(&canceled_event, Publish::WhenBatchEnds).await;
            }

            assert!(
                trade_row_gone(&order_id).await,
                "{case}: the cancelled order must not stay in My Trades"
            );
            assert!(
                session_manager().get_session(&order_id).await.is_none(),
                "{case}: the maker's session must go with the row"
            );
        }
    }

    /// The same race from the taker's side: the maker cancels while the take
    /// waits, and the taker's d-tag subscription delivers the `canceled` next
    /// to the kind-14 `Canceled`. Event first used to mark the row `Canceled`
    /// and keep it; it must wipe it with its session and drop the entry — the
    /// order is dead, not back in the book.
    #[tokio::test]
    async fn a_take_whose_maker_cancelled_is_wiped_by_the_public_canceled() {
        let path = std::env::temp_dir()
            .join(format!("mostro_take_maker_cancelled_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let taken = wire_order(&order_id, OrderStatus::WaitingBuyerInvoice);
        order_book().upsert_order(taken.clone()).await;
        db.save_trade(&cancel_test_row(taken.clone()))
            .await
            .expect("save the trade row");
        session_manager()
            .install_session(order_id.clone(), TradeRole::Buyer, 1, taken)
            .await
            .expect("install the take's session");
        apply_single_order_update(wire_order(&order_id, OrderStatus::InProgress)).await;

        apply_single_order_update(wire_order(&order_id, OrderStatus::Canceled)).await;

        assert!(
            trade_row_gone(&order_id).await,
            "the public canceled must wipe the never-active take"
        );
        assert!(
            session_manager().get_session(&order_id).await.is_none(),
            "the take's session must go with the row"
        );
        assert_eq!(
            book_status(&order_id).await,
            None,
            "a cancelled order must not be handed back to the book"
        );

        dispatch_daemon_canceled(order_uuid, "test-take-maker-cancelled").await;
        assert!(
            trade_row_gone(&order_id).await,
            "the Canceled that follows must not bring the row back"
        );
    }

    /// Only a trade that never went active is wiped by the event. Past
    /// `waiting-*` the `canceled` bucket also stands for a cooperative or an
    /// admin cancel, and the row stays as history.
    #[tokio::test]
    async fn a_public_canceled_keeps_an_active_trade_as_history() {
        let path = std::env::temp_dir()
            .join(format!("mostro_public_canceled_active_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_id = uuid::Uuid::new_v4().to_string();
        db.save_trade(&cancel_test_row(wire_order(&order_id, OrderStatus::Active)))
            .await
            .expect("save the trade row");

        apply_single_order_update(wire_order(&order_id, OrderStatus::Canceled)).await;

        assert_eq!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("trade lookup")
                .expect("an active trade's row must be kept")
                .order
                .status,
            OrderStatus::Canceled,
            "the active trade is kept as a Canceled history row"
        );
    }

    /// A never-active trade wiped by the public `canceled` leaves the same
    /// tombstone as one wiped by the daemon's `Canceled`, so the create ack
    /// replayed on the next start is not adopted back as a `Pending` maker
    /// row. Without it the ack was adopted whenever nothing else stopped it:
    /// the replayed `Canceled` finds no row and the book no longer holds the
    /// order.
    #[tokio::test]
    async fn a_public_canceled_wipe_stops_the_replayed_create_ack() {
        use mostro_core::message::{Action, Message, Payload};

        let path = std::env::temp_dir()
            .join(format!("mostro_public_wipe_ack_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let my_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let mut mine = wire_order(&order_id, OrderStatus::Pending);
        mine.is_mine = true;
        let mut row = cancel_test_row(mine);
        row.trade_key_index = 21;
        db.save_trade(&row).await.expect("save the maker's row");

        ingest_order_event_with(&book_event(&order_id, "canceled"), Publish::WhenBatchEnds).await;
        assert!(
            trade_row_gone(&order_id).await,
            "the public canceled wipes the maker's never-active row"
        );
        let tombstone = db
            .get_setting(&crate::db::settings_keys::trade_wiped(&order_id))
            .await
            .expect("tombstone lookup");
        assert!(
            tombstone.as_deref().is_some_and(|v| v.ends_with(":21")),
            "the wipe records the generation it covers, got {tombstone:?}"
        );

        // The next start replays the create's ack: NewOrder, Pending, this
        // key's trade index echoed — what `adopt_range_remainder` accepts.
        let ack = mostro_core::order::SmallOrder::new(
            Some(order_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::Pending),
            0,
            "USD".to_string(),
            None,
            None,
            100,
            "Bank".to_string(),
            0,
            None,
            Some(my_hex.clone()),
            None,
            Some(1_700_000_000),
            Some(1_700_003_600),
        );
        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        dispatch_mostro_message(
            mostro_core::nip59::UnwrappedMessage {
                message: Message::new_order(
                    Some(order_uuid),
                    None,
                    Some(21),
                    Action::NewOrder,
                    Some(Payload::Order(ack)),
                ),
                signature: None,
                sender,
                identity: sender,
                created_at: nostr_sdk::prelude::Timestamp::from(2_000u64),
            },
            "test-public-wipe-ack",
            &my_hex,
            21,
        )
        .await;
        assert!(
            trade_row_gone(&order_id).await,
            "the replayed ack must not adopt the canceled order back"
        );
    }

    /// The d-tag half of the Kind 38383 amount gate (#394 review): a public
    /// bucket refused as the trade's status must not sneak its amount into
    /// the row either. The book-feed half is pinned by
    /// `a_refused_wire_status_does_not_sneak_its_amount_into_the_row`.
    #[tokio::test]
    async fn a_refused_d_tag_status_does_not_sneak_its_amount_into_the_row() {
        let path = std::env::temp_dir()
            .join(format!("mostro_dtag_amtgate_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_id = uuid::Uuid::new_v4().to_string();
        let mut row = cancel_test_row(wire_order(&order_id, OrderStatus::Active));
        row.order.amount_sats = Some(5_000);
        db.save_trade(&row).await.expect("save the trade row");

        let mut in_progress = wire_order(&order_id, OrderStatus::InProgress);
        in_progress.amount_sats = Some(7_777);
        apply_single_order_update(in_progress).await;
        let row = db
            .get_trade_by_order_id(&order_id)
            .await
            .expect("lookup")
            .expect("row exists");
        assert_eq!(row.order.status, OrderStatus::Active);
        assert_eq!(
            row.order.amount_sats,
            Some(5_000),
            "a refused wire status must not sneak its amount into the row"
        );

        // The control: a terminal status applies, and its amount lands with
        // it. The row went active, so the `canceled` keeps it as history.
        let mut canceled = wire_order(&order_id, OrderStatus::Canceled);
        canceled.amount_sats = Some(7_777);
        apply_single_order_update(canceled).await;
        let row = db
            .get_trade_by_order_id(&order_id)
            .await
            .expect("lookup")
            .expect("row exists");
        assert_eq!(row.order.status, OrderStatus::Canceled);
        assert_eq!(
            row.order.amount_sats,
            Some(7_777),
            "an applied wire status carries its amount"
        );
    }

    /// A never-active take watched by a d-tag task: its row, its session and
    /// its book entry, all at `waiting-buyer-invoice`.
    async fn watched_never_active_take(order_id: &str) {
        let db = crate::db::app_db::db().expect("store initialised");
        let taken = wire_order(order_id, OrderStatus::WaitingBuyerInvoice);
        order_book().upsert_order(taken.clone()).await;
        db.save_trade(&cancel_test_row(taken.clone()))
            .await
            .expect("save the trade row");
        session_manager()
            .install_session(order_id.to_string(), TradeRole::Buyer, 1, taken)
            .await
            .expect("install the take's session");
    }

    /// After a node switch the d-tag task is still running, watching the
    /// previous node: an event of its order must stop it rather than move
    /// local state. Everything else already ignores a non-active node
    /// (`dispatch_mostro_message`, the book loop); this task used to keep
    /// writing that node's view into the row and into the new node's book,
    /// and a `canceled` now wipes the row.
    #[tokio::test]
    async fn the_d_tag_task_stops_once_its_node_is_no_longer_active() {
        let path = std::env::temp_dir()
            .join(format!("mostro_d_tag_node_switch_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;

        let order_id = uuid::Uuid::new_v4().to_string();
        watched_never_active_take(&order_id).await;
        let previous_node = nostr_sdk::prelude::Keys::generate();
        let active_node = nostr_sdk::prelude::Keys::generate().public_key().to_hex();

        let outcome = handle_single_order_event(
            &book_event_by(&order_id, "canceled", &previous_node),
            &order_id,
            &previous_node.public_key(),
            || active_node,
        )
        .await;

        assert_eq!(outcome, SingleOrderEvent::NodeChanged);
        assert!(
            !trade_row_gone(&order_id).await,
            "the previous node's canceled must not wipe the row"
        );
        assert!(
            session_manager().get_session(&order_id).await.is_some(),
            "nor remove the session"
        );
        assert_eq!(
            book_status(&order_id).await,
            Some(OrderStatus::WaitingBuyerInvoice),
            "nor touch the book entry"
        );
    }

    /// On the active node the task applies its order's events, and only
    /// those: another author's event for the same d-tag, or the node's event
    /// for another order, changes nothing.
    #[tokio::test]
    async fn the_d_tag_task_applies_only_its_active_nodes_events() {
        let path = std::env::temp_dir()
            .join(format!("mostro_d_tag_active_node_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;

        let order_id = uuid::Uuid::new_v4().to_string();
        watched_never_active_take(&order_id).await;
        let node = nostr_sdk::prelude::Keys::generate();
        let node_hex = node.public_key().to_hex();

        let forged = book_event_by(
            &order_id,
            "canceled",
            &nostr_sdk::prelude::Keys::generate(),
        );
        assert_eq!(
            handle_single_order_event(&forged, &order_id, &node.public_key(), || {
                node_hex.clone()
            })
            .await,
            SingleOrderEvent::Ignored,
        );
        let other_order = book_event_by(&uuid::Uuid::new_v4().to_string(), "canceled", &node);
        assert_eq!(
            handle_single_order_event(&other_order, &order_id, &node.public_key(), || {
                node_hex.clone()
            })
            .await,
            SingleOrderEvent::Ignored,
        );
        assert!(
            !trade_row_gone(&order_id).await,
            "neither may touch the row"
        );

        let canceled = book_event_by(&order_id, "canceled", &node);
        assert_eq!(
            handle_single_order_event(&canceled, &order_id, &node.public_key(), || {
                node_hex.clone()
            })
            .await,
            SingleOrderEvent::Applied,
        );
        assert!(
            trade_row_gone(&order_id).await,
            "the active node's canceled wipes the never-active take"
        );
        assert!(session_manager().get_session(&order_id).await.is_none());
    }

    /// A retake's single-order task replaces the first take's: the first stops
    /// being current, and releasing it does not hand back the subscription —
    /// only the current task may drop the REQ both would otherwise share.
    #[test]
    fn a_retake_replaces_the_earlier_single_order_task() {
        let order_id = uuid::Uuid::new_v4().to_string();

        let (first, replaced) = claim_single_order_task(&order_id);
        assert!(!replaced, "the first take replaces nothing");
        let (second, replaced) = claim_single_order_task(&order_id);
        assert!(replaced, "the retake replaces the first take's task");

        assert!(
            !single_order_task_is_current(&order_id, first),
            "the first take's task must stop"
        );
        assert!(single_order_task_is_current(&order_id, second));
        assert!(
            !release_single_order_task(&order_id, first),
            "a superseded task must not drop the subscription"
        );
        assert!(
            single_order_task_is_current(&order_id, second),
            "nor take the retake's claim with it"
        );
        assert!(
            release_single_order_task(&order_id, second),
            "the current task owns the subscription it drops"
        );
        assert!(!single_order_task_is_current(&order_id, second));
    }

    /// `subscribe_single_order` claims before it spawns, so a second call
    /// supersedes the first task at once; and both tasks leave the registry
    /// empty when they end (here at once: no relay pool in unit tests).
    #[tokio::test]
    async fn subscribe_single_order_claims_before_it_spawns() {
        let order_id = uuid::Uuid::new_v4().to_string();
        let current = || {
            single_order_tasks()
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .get(&order_id)
                .copied()
        };

        subscribe_single_order(&order_id).await;
        let first = current().expect("the first call claims the order");
        subscribe_single_order(&order_id).await;
        let second = current().expect("the retake's call claims the order");
        assert_ne!(first, second, "the retake's task replaces the first");

        for _ in 0..20 {
            if current().is_none() {
                break;
            }
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }
        assert_eq!(current(), None, "no claim outlives its task");
    }

    /// Dispatch an action-only daemon message for `order_uuid`, as the relay
    /// feed would deliver it.
    async fn dispatch_daemon_action(
        order_uuid: uuid::Uuid,
        action: mostro_core::message::Action,
        event_id: &str,
    ) {
        use mostro_core::message::Message;
        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        dispatch_mostro_message(
            mostro_core::nip59::UnwrappedMessage {
                message: Message::new_order(Some(order_uuid), None, None, action, None),
                signature: None,
                sender,
                identity: sender,
                created_at: nostr_sdk::prelude::Timestamp::from(1_000u64),
            },
            event_id,
            "ff00ff22",
            1,
        )
        .await;
    }

    /// An active take, its public `in-progress` noted by the d-tag path.
    async fn noted_active_take() -> (uuid::Uuid, String) {
        let db = crate::db::app_db::db().expect("store initialised");
        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        db.save_trade(&cancel_test_row(wire_order(&order_id, OrderStatus::Active)))
            .await
            .expect("save the trade row");
        apply_single_order_update(wire_order(&order_id, OrderStatus::InProgress)).await;
        assert!(
            order_book().has_wire_note(&order_id),
            "precondition: the take's public view is noted"
        );
        (order_uuid, order_id)
    }

    /// A take whose public view is final leaves no note behind. Only a wipe
    /// reads the note back, and none follows a trade that went active, so
    /// every way such a trade ends must forget it: a final view on either
    /// ingest path (the d-tag subscription, and the book feed that outlives
    /// it), and the kind-14 arms that end a trade without a wipe.
    #[tokio::test]
    async fn a_finished_take_leaves_no_wire_note_behind() {
        use mostro_core::message::Action;

        let path = std::env::temp_dir()
            .join(format!("mostro_finished_take_note_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;

        let (_, order_id) = noted_active_take().await;
        apply_single_order_update(wire_order(&order_id, OrderStatus::Success)).await;
        assert!(
            !order_book().has_wire_note(&order_id),
            "a final view on the d-tag path must forget the note"
        );

        let (_, order_id) = noted_active_take().await;
        ingest_order_event_with(&book_event(&order_id, "success"), Publish::WhenBatchEnds).await;
        assert!(
            !order_book().has_wire_note(&order_id),
            "a final view on the book feed must forget the note"
        );

        let (order_uuid, order_id) = noted_active_take().await;
        dispatch_daemon_canceled(order_uuid, &format!("test-note-canceled-{order_id}")).await;
        assert!(
            !order_book().has_wire_note(&order_id),
            "a Canceled that keeps the row as history must forget the note"
        );

        let (order_uuid, order_id) = noted_active_take().await;
        dispatch_daemon_action(
            order_uuid,
            Action::PurchaseCompleted,
            &format!("test-note-completed-{order_id}"),
        )
        .await;
        assert!(
            !order_book().has_wire_note(&order_id),
            "a daemon message that finishes the trade must forget the note"
        );
    }

    /// The final view is forgotten only after the event's own wipe decision,
    /// because a never-active take ended by that `canceled` settles from it.
    /// Here the book feed had already written a `pending` republish into the
    /// entry (it never gates `pending`) when the order was cancelled for
    /// good: forgetting first would leave the settle nothing but that stale
    /// `pending`, and the dead order would stay takeable in the ex-taker's
    /// book.
    #[tokio::test]
    async fn a_cancelled_take_settles_before_its_note_is_forgotten() {
        let path = std::env::temp_dir()
            .join(format!("mostro_settle_before_forget_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_id = uuid::Uuid::new_v4().to_string();
        let taken = wire_order(&order_id, OrderStatus::WaitingBuyerInvoice);
        order_book().upsert_order(taken.clone()).await;
        db.save_trade(&cancel_test_row(taken))
            .await
            .expect("save the trade row");
        ingest_order_event_with(&book_event(&order_id, "pending"), Publish::WhenBatchEnds).await;
        assert_eq!(
            book_status(&order_id).await,
            Some(OrderStatus::Pending),
            "precondition: the book feed wrote the republish into the entry"
        );

        apply_single_order_update(wire_order(&order_id, OrderStatus::Canceled)).await;

        assert!(trade_row_gone(&order_id).await, "the never-active take is wiped");
        assert_eq!(
            book_status(&order_id).await,
            None,
            "a cancelled order must not stay pending in the ex-taker's book"
        );
        assert!(
            !order_book().has_wire_note(&order_id),
            "the settle consumed the note"
        );
    }

    /// A panic while the notes were locked must not switch the lost-take
    /// restore off for the rest of the session: the lock is poisoned, but
    /// no note operation is ever left half-applied, so they carry on.
    #[test]
    fn a_poisoned_note_lock_still_notes_and_forgets() {
        let book = OrderBook::new();
        let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let _held = book.wire_orders.lock().unwrap();
            panic!("poison the notes");
        }));
        assert!(
            book.wire_orders.is_poisoned(),
            "precondition: the lock is poisoned"
        );

        book.note_wire_order(&wire_order("poisoned-notes", OrderStatus::InProgress));
        assert!(
            book.has_wire_note("poisoned-notes"),
            "a poisoned lock must still take a note"
        );
        book.forget_wire_order("poisoned-notes");
        assert!(
            !book.has_wire_note("poisoned-notes"),
            "a poisoned lock must still forget a note"
        );
    }

    /// The startup backlog must not walk a trade's status backwards.
    ///
    /// The global kind-14 subscription carries no `since`, so every start
    /// replays the node's whole history for the order, and relays serve stored
    /// events newest-first. Applied blindly, the *oldest* message lands last
    /// and wins: a disputed trade came back as `waiting-buyer-invoice` on every
    /// restart, with the intermediate states emitted to the UI on the way down.
    ///
    /// Replays in that exact order — newest first, none of them terminal, so
    /// only the ordering rule can refuse them.
    #[tokio::test]
    async fn a_replayed_backlog_cannot_walk_the_status_backwards() {
        use mostro_core::message::{Action, Message};

        let path =
            std::env::temp_dir().join(format!("mostro_status_replay_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let order_info = dummy_order_info(&order_id);
        order_book().upsert_order(order_info.clone()).await;
        db.save_trade(&crate::api::types::TradeInfo {
            id: order_id.clone(),
            order: order_info,
            role: TradeRole::Seller,
            counterparty_pubkey: String::new(),
            current_step: crate::api::types::TradeStep::Seller(
                crate::api::types::SellerStep::OrderPublished,
            ),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 1,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
        })
        .await
        .expect("save the trade row");

        let mut rx = trade_updates_tx().subscribe();
        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");

        // Newest first, exactly how the relay hands the backlog back.
        for (action, created_at) in [
            (Action::DisputeInitiatedByYou, 3_000u64),
            (Action::FiatSentOk, 2_000),
            (Action::WaitingBuyerInvoice, 1_000),
        ] {
            dispatch_mostro_message(
                mostro_core::nip59::UnwrappedMessage {
                    message: Message::new_order(Some(order_uuid), None, None, action, None),
                    signature: None,
                    sender,
                    identity: sender,
                    created_at: nostr_sdk::prelude::Timestamp::from(created_at),
                },
                &format!("test-backlog-{created_at}"),
                "ff00ff10",
                1,
            )
            .await;
        }

        // The newest message is the one that stuck, in both the book...
        assert_eq!(
            order_book()
                .get_order(&order_id)
                .await
                .expect("order still cached")
                .status,
            crate::api::types::OrderStatus::Dispute,
            "the newest replayed message must own the status",
        );
        // ...and the row My Trades reads.
        assert_eq!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("trade lookup")
                .expect("trade row")
                .order
                .status,
            crate::api::types::OrderStatus::Dispute,
            "the persisted status must not walk backwards across a restart",
        );
        // The cursor is the high-water mark that survives the restart.
        assert_eq!(
            db.get_setting(&crate::db::settings_keys::status_cursor(&order_id))
                .await
                .unwrap()
                .as_deref(),
            Some("3000"),
            "the applied event's timestamp must be recorded",
        );
        // Nothing older reached the UI on the way down: one update, not three.
        let mut emitted = Vec::new();
        while let Ok(update) = rx.try_recv() {
            if update.order_id == order_id {
                emitted.push(update.status);
            }
        }
        assert_eq!(
            emitted,
            vec![crate::api::types::OrderStatus::Dispute],
            "a refused replay must not emit a TradeUpdate",
        );
    }

    /// The ordering mark must live in the node's time domain, not the local
    /// one. Clamping it to the local clock (as the chat cursor does, where it
    /// is a subscription `since` and not a comparator) breaks the guard
    /// whenever the local clock runs behind the node's: the newest event
    /// stores a clamped, smaller value, and the next *older* event then
    /// compares above it and wins — the replay regression, restored.
    ///
    /// Both events here are dated ahead of the local clock, replayed
    /// newest-first, and inside the skew tolerance so the mark may move.
    #[tokio::test]
    async fn a_cursor_behind_the_local_clock_still_orders_future_dated_events() {
        use mostro_core::message::{Action, Message};

        let path =
            std::env::temp_dir().join(format!("mostro_status_skew_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let order_info = dummy_order_info(&order_id);
        order_book().upsert_order(order_info.clone()).await;
        db.save_trade(&crate::api::types::TradeInfo {
            id: order_id.clone(),
            order: order_info,
            role: TradeRole::Seller,
            counterparty_pubkey: String::new(),
            current_step: crate::api::types::TradeStep::Seller(
                crate::api::types::SellerStep::OrderPublished,
            ),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 1,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
        })
        .await
        .expect("save the trade row");

        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        let now = crate::rt::unix_now() as u64;
        let newest = now + 6;
        let oldest = now + 3;

        for (action, created_at) in [
            (Action::DisputeInitiatedByYou, newest),
            (Action::WaitingBuyerInvoice, oldest),
        ] {
            dispatch_mostro_message(
                mostro_core::nip59::UnwrappedMessage {
                    message: Message::new_order(Some(order_uuid), None, None, action, None),
                    signature: None,
                    sender,
                    identity: sender,
                    created_at: nostr_sdk::prelude::Timestamp::from(created_at),
                },
                &format!("test-skew-{created_at}"),
                "ff00ff11",
                1,
            )
            .await;
        }

        assert_eq!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("trade lookup")
                .expect("trade row")
                .order
                .status,
            crate::api::types::OrderStatus::Dispute,
            "a future-dated newest event must still outrank an older one",
        );
        assert_eq!(
            db.get_setting(&crate::db::settings_keys::status_cursor(&order_id))
                .await
                .unwrap()
                .as_deref(),
            Some(newest.to_string().as_str()),
            "the mark must be stored raw, in the node's time domain",
        );
    }

    /// One malformed timestamp must not be able to silence an order for good:
    /// an event far beyond the skew tolerance is still applied, but it does not
    /// move the mark, so the messages that follow it are not all refused.
    #[tokio::test]
    async fn an_absurdly_future_event_does_not_move_the_cursor() {
        let path =
            std::env::temp_dir().join(format!("mostro_status_skew_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_id = format!("skew-{}", uuid::Uuid::new_v4());
        record_status_event(&order_id, crate::rt::unix_now() + 365 * 24 * 3600).await;

        assert_eq!(
            db.get_setting(&crate::db::settings_keys::status_cursor(&order_id))
                .await
                .unwrap(),
            None,
            "an event a year ahead must not become the high-water mark",
        );
    }

    /// A taken order whose taker walks away comes back to the maker as a
    /// `new-order` carrying the order in `pending`, under the same id and
    /// with no create waiting for it. The trade the maker holds at
    /// `waiting-payment` must follow the book back to pending right away,
    /// not half an hour later when the stale sweep gets to it.
    #[tokio::test]
    async fn a_republished_maker_order_returns_to_pending_on_new_order() {
        use mostro_core::message::{Action, Message, Payload};

        let path =
            std::env::temp_dir().join(format!("mostro_republished_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let mut order_info = dummy_order_info(&order_id);
        order_info.kind = crate::api::types::OrderKind::Sell;
        order_info.status = crate::api::types::OrderStatus::WaitingPayment;
        order_info.is_mine = true;
        order_book().upsert_order(order_info.clone()).await;
        db.save_trade(&crate::api::types::TradeInfo {
            id: order_id.clone(),
            order: order_info,
            role: TradeRole::Seller,
            counterparty_pubkey: String::new(),
            current_step: crate::api::types::TradeStep::Seller(
                crate::api::types::SellerStep::OrderPublished,
            ),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 7,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
        })
        .await
        .expect("save the trade row");
        let mut rx = trade_updates_tx().subscribe();

        let republished = mostro_core::order::SmallOrder::new(
            Some(order_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::Pending),
            1000,
            "ARS".to_string(),
            None,
            None,
            1000,
            "cash".to_string(),
            0,
            None,
            None,
            None,
            None,
            None,
        );
        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        let unwrapped = mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(
                Some(order_uuid),
                None,
                None,
                Action::NewOrder,
                Some(Payload::Order(republished)),
            ),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::prelude::Timestamp::now(),
        };
        dispatch_mostro_message(unwrapped, "test-republish", "ff00ff07", 7).await;

        let row = db
            .get_trade_by_order_id(&order_id)
            .await
            .expect("lookup")
            .expect("row kept");
        assert_eq!(row.order.status, crate::api::types::OrderStatus::Pending);
        let mut emitted = false;
        while let Ok(update) = rx.try_recv() {
            if update.order_id == order_id
                && update.status == crate::api::types::OrderStatus::Pending
            {
                emitted = true;
            }
        }
        assert!(emitted, "the UI must learn the order is pending again");
    }

    /// A release must know whether it leaves a remainder: a missing trade
    /// row is an error, a fixed order or a taker's trade is `None`, and only
    /// a range order this client sold names a key.
    #[tokio::test]
    async fn the_next_trade_key_fails_closed_without_a_trade_row() {
        let path =
            std::env::temp_dir().join(format!("mostro_next_trade_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let unknown = uuid::Uuid::new_v4().to_string();
        assert!(next_trade_for_range_remainder(&unknown, TradeRole::Seller)
            .await
            .is_err());

        let fixed_id = uuid::Uuid::new_v4().to_string();
        let mut fixed = dummy_order_info(&fixed_id);
        fixed.kind = crate::api::types::OrderKind::Sell;
        fixed.is_mine = true;
        let row = |id: &str, order: crate::api::types::OrderInfo, role: TradeRole| {
            crate::api::types::TradeInfo {
                id: id.to_string(),
                order,
                role,
                counterparty_pubkey: String::new(),
                current_step: crate::api::types::TradeStep::Seller(
                    crate::api::types::SellerStep::OrderPublished,
                ),
                hold_invoice: None,
                buyer_invoice: None,
                trade_key_index: 1,
                cooperative_cancel_state: None,
                timeout_at: None,
                started_at: 1,
                completed_at: None,
                outcome: None,
                peer_rating: None,
                peer_reviews: None,
                peer_days: None,
                rated_at: None,
            }
        };
        db.save_trade(&row(&fixed_id, fixed, TradeRole::Seller))
            .await
            .expect("save");
        assert_eq!(
            next_trade_for_range_remainder(&fixed_id, TradeRole::Seller)
                .await
                .unwrap(),
            None,
            "a fixed order leaves nothing behind"
        );

        let taken_id = uuid::Uuid::new_v4().to_string();
        let mut taken_range = dummy_order_info(&taken_id);
        taken_range.kind = crate::api::types::OrderKind::Buy;
        taken_range.fiat_amount_min = Some(10.0);
        taken_range.fiat_amount_max = Some(30.0);
        taken_range.is_mine = false;
        db.save_trade(&row(&taken_id, taken_range, TradeRole::Seller))
            .await
            .expect("save");
        assert_eq!(
            next_trade_for_range_remainder(&taken_id, TradeRole::Seller)
                .await
                .unwrap(),
            None,
            "a taker's release leaves nothing behind"
        );
    }

    /// The remainder of a range order arrives at the next trade key as a
    /// `new-order` no create is waiting for, carrying that key's trade
    /// index: it is this client's own pending order, listed and bound to
    /// the key.
    #[tokio::test]
    async fn a_range_remainder_addressed_to_the_next_trade_key_is_adopted() {
        use mostro_core::message::{Action, Message, Payload};

        let path = std::env::temp_dir().join(format!("mostro_remainder_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");
        let mut rx = trade_updates_tx().subscribe();

        let child_uuid = uuid::Uuid::new_v4();
        let child_id = child_uuid.to_string();
        let next_key = "ab".repeat(32);
        let remainder = mostro_core::order::SmallOrder::new(
            Some(child_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::Pending),
            0,
            "ARS".to_string(),
            None,
            None,
            1000,
            "cash".to_string(),
            0,
            None,
            Some(next_key.clone()),
            None,
            Some(1_700_000_000),
            Some(1_700_003_600),
        );
        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        let unwrapped = mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(
                Some(child_uuid),
                None,
                Some(9),
                Action::NewOrder,
                Some(Payload::Order(remainder)),
            ),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::prelude::Timestamp::now(),
        };
        dispatch_mostro_message(unwrapped, "test-remainder", &next_key, 9).await;

        let row = db
            .get_trade_by_order_id(&child_id)
            .await
            .expect("lookup")
            .expect("the remainder is a trade of ours");
        assert_eq!(row.role, TradeRole::Seller);
        assert_eq!(row.trade_key_index, 9);
        assert_eq!(row.order.status, crate::api::types::OrderStatus::Pending);
        assert!(row.order.is_mine);
        assert_eq!(row.order.fiat_amount, Some(1000.0));
        assert_eq!(get_trade_key_index(&child_id).await, Some(9));
        assert!(rx.try_recv().is_ok(), "the UI learns about the new trade");

        // A new-order whose trade index is not this key's is not an order
        // the daemon assigned to it: nothing is adopted.
        let other_uuid = uuid::Uuid::new_v4();
        let foreign = mostro_core::order::SmallOrder::new(
            Some(other_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::Pending),
            0,
            "ARS".to_string(),
            None,
            None,
            1000,
            "cash".to_string(),
            0,
            None,
            Some("cd".repeat(32)),
            None,
            None,
            None,
        );
        let unwrapped = mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(
                Some(other_uuid),
                None,
                Some(3),
                Action::NewOrder,
                Some(Payload::Order(foreign)),
            ),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::prelude::Timestamp::now(),
        };
        dispatch_mostro_message(unwrapped, "test-foreign", &next_key, 9).await;
        assert!(db
            .get_trade_by_order_id(&other_uuid.to_string())
            .await
            .expect("lookup")
            .is_none());
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
        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
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
            created_at: nostr_sdk::prelude::Timestamp::from(0u64),
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
        let session = nostr_sdk::prelude::Keys::generate();
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
    /// protocol must fail BEFORE deriving or persisting anything. The exact
    /// error string pins the ordering: had the preflight run after key
    /// derivation, this identity-less test environment would fail with a
    /// different error first — and a rejected create would burn a durable
    /// trade-key index per attempt.
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
        let err = create_order(params).await.unwrap_err();
        assert_eq!(err.to_string(), "UnsupportedNodeProtocol:1");
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
        let waiting = S::WaitingPayment;
        assert_eq!(
            sweep_action(true, &waiting, Some(&S::Pending)),
            SweepAction::SyncPending
        );
        assert_eq!(
            sweep_action(false, &waiting, Some(&S::Pending)),
            SweepAction::Wipe
        );
        for s in [S::Canceled, S::Expired, S::CanceledByAdmin] {
            assert_eq!(sweep_action(false, &waiting, Some(&s)), SweepAction::Wipe);
            assert_eq!(sweep_action(true, &waiting, Some(&s)), SweepAction::Wipe);
        }
        assert_eq!(sweep_action(false, &waiting, None), SweepAction::Keep);
        for s in [S::InProgress, S::Active, S::Success] {
            assert_eq!(sweep_action(false, &waiting, Some(&s)), SweepAction::Keep);
        }
    }

    /// A relay is asked for the daemon's event about one order; what comes
    /// back is checked for both. A genuine daemon event about another order,
    /// or an event about this order from another key, reports nothing.
    #[test]
    fn book_status_needs_the_daemons_event_about_this_very_order() {
        use crate::api::types::OrderStatus as S;
        use nostr_sdk::prelude::{EventBuilder, FinalizeEvent, Keys, Kind, Tag};
        let daemon = Keys::generate();
        let stranger = Keys::generate();
        let event = |keys: &Keys, id: &str, status: &str, at: u64| {
            EventBuilder::new(Kind::from(38383u16), "")
                .tags([
                    Tag::parse(["d", id]).unwrap(),
                    Tag::parse(["k", "sell"]).unwrap(),
                    Tag::parse(["s", status]).unwrap(),
                    Tag::parse(["f", "USD"]).unwrap(),
                    Tag::parse(["pm", "cash"]).unwrap(),
                    Tag::parse(["premium", "0"]).unwrap(),
                    Tag::parse(["amt", "0"]).unwrap(),
                    Tag::parse(["fa", "100"]).unwrap(),
                    Tag::parse(["z", "order"]).unwrap(),
                ])
                .custom_created_at(nostr_sdk::prelude::Timestamp::from_secs(at))
                .finalize(keys)
                .unwrap()
        };
        let mine = "308e1272-d5f4-47e6-bd97-3504baea9c23";
        let other = "9b2d8f7e-1c3a-4e5b-8f6d-0a1b2c3d4e5f";
        let pk = daemon.public_key();
        assert_eq!(
            newest_book_status([event(&daemon, other, "success", 20)], &pk, mine),
            None,
            "the daemon's success for another order says nothing about this one"
        );
        assert_eq!(
            newest_book_status([event(&stranger, mine, "success", 20)], &pk, mine),
            None,
            "a success from another key is not the daemon's"
        );
        assert_eq!(
            newest_book_status(
                [
                    event(&daemon, mine, "in-progress", 10),
                    event(&daemon, other, "success", 30),
                    event(&daemon, mine, "success", 20),
                ],
                &pk,
                mine
            ),
            Some(S::Success)
        );
    }

    /// The seller learns of the payout only from the public book: a trade
    /// held at `SettledHoldInvoice` whose book status is `success` is
    /// completed by the sweep, and nothing else touches such a trade.
    #[test]
    fn a_settled_escrow_is_completed_when_the_book_says_success() {
        use crate::api::types::OrderStatus as S;
        assert_eq!(
            sweep_action(true, &S::SettledHoldInvoice, Some(&S::Success)),
            SweepAction::SyncSuccess
        );
        assert_eq!(
            sweep_action(false, &S::SettledHoldInvoice, Some(&S::Success)),
            SweepAction::SyncSuccess
        );
        for s in [S::Pending, S::Canceled, S::Expired, S::InProgress] {
            assert_eq!(
                sweep_action(false, &S::SettledHoldInvoice, Some(&s)),
                SweepAction::Keep
            );
        }
        assert_eq!(
            sweep_action(false, &S::SettledHoldInvoice, None),
            SweepAction::Keep
        );
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

    /// #335 part 1, the replacement semantics `take_order` depends on: a
    /// second `install_session` for an order that already has one wins,
    /// carrying the retake's fresh `trade_key_index`. A retake derives a new
    /// trade key, so keeping the earlier session would leave chat key lookups
    /// reading a superseded index.
    ///
    /// Scope: this pins `install_session` itself, not the `take_order` call
    /// site — reaching that needs a daemon. `retake_e2e_taker_cancels_and_retakes`
    /// (`#[ignore]`, live daemon) drives it, with the first take's session
    /// planted so the retake meets a stale one.
    #[tokio::test]
    async fn retake_replaces_stale_session_trade_key_index() {
        let order_id = uuid::Uuid::new_v4().to_string();
        let order = dummy_order_info(&order_id);
        let mgr = session_manager();

        // First take: derives trade key index 0, session gets created.
        mgr.install_session(order_id.clone(), TradeRole::Buyer, 0, order.clone())
            .await
            .expect("first install must succeed");

        // Retake (the first take's `Canceled` never arrived, so its session
        // is still here): derives a fresh trade key index 1. `take_order`
        // calls `install_session` the same way.
        mgr.install_session(order_id.clone(), TradeRole::Buyer, 1, order)
            .await
            .expect("retake install must succeed");

        let session = mgr
            .get_session(&order_id)
            .await
            .expect("session must exist");
        assert_eq!(
            session.trade_key_index, 1,
            "the confirmed retake's trade_key_index must win, not the stale one"
        );
    }

    /// The replacement is total: a retake also clears the peer material the
    /// previous attempt accumulated. That is what makes it correct rather than
    /// merely last-write-wins — the old `shared_key` was derived from the old
    /// trade key, so carrying it forward would leave chat keys that no longer
    /// decrypt anything. It is also the reason `install_session` is documented
    /// as only for a confirmed take.
    #[tokio::test]
    async fn install_session_discards_previous_peer_material() {
        let order_id = uuid::Uuid::new_v4().to_string();
        let order = dummy_order_info(&order_id);
        let mgr = session_manager();

        mgr.install_session(order_id.clone(), TradeRole::Buyer, 0, order.clone())
            .await
            .expect("first install must succeed");

        // Give the first attempt's session peer material, as a reveal would.
        let mut with_peer = mgr
            .get_session(&order_id)
            .await
            .expect("session must exist");
        with_peer.peer_pubkey = Some("aabbccdd".to_string());
        with_peer.shared_key = Some([7u8; 32]);
        with_peer.admin_shared_key = Some([9u8; 32]);
        mgr.update_session(&order_id, with_peer)
            .await
            .expect("planting peer material must succeed");

        // The retake must still win, and must not inherit that material.
        mgr.install_session(order_id.clone(), TradeRole::Buyer, 1, order)
            .await
            .expect("retake install must succeed");

        let session = mgr
            .get_session(&order_id)
            .await
            .expect("session must exist");
        assert_eq!(
            session.trade_key_index, 1,
            "the retake must win even over a session holding peer material"
        );
        assert!(
            session.peer_pubkey.is_none(),
            "peer_pubkey from the superseded take must not survive"
        );
        assert!(
            session.shared_key.is_none(),
            "shared_key derived from the old trade key must not survive"
        );
        assert!(
            session.admin_shared_key.is_none(),
            "admin_shared_key from the superseded take must not survive"
        );
    }

    /// The mirror case, and the one #345/#347 made reachable: the session
    /// `take_order` finds already belongs to *this* take, because
    /// `apply_peer_reveal` created it when the daemon's first reply carried
    /// both trade pubkeys. Same `trade_key_index`, but with peer material the
    /// call site cannot rebuild — replacing it would silently drop the chat
    /// keys the peer-reveal path exists to establish (#334).
    ///
    /// The index is what tells the two cases apart: a stale session from a
    /// failed attempt always carries an older index, because every take
    /// derives a fresh trade key.
    #[tokio::test]
    async fn install_session_keeps_this_takes_own_session_with_peer_material() {
        let order_id = uuid::Uuid::new_v4().to_string();
        let order = dummy_order_info(&order_id);
        let mgr = session_manager();

        // The peer reveal got there first, with the shared key already derived.
        mgr.install_session(order_id.clone(), TradeRole::Buyer, 4, order.clone())
            .await
            .expect("peer-reveal install must succeed");
        let mut revealed = mgr
            .get_session(&order_id)
            .await
            .expect("session must exist");
        revealed.peer_pubkey = Some("aabbccdd".to_string());
        revealed.shared_key = Some([7u8; 32]);
        mgr.update_session(&order_id, revealed)
            .await
            .expect("planting peer material must succeed");

        // `take_order` now runs for the same take: same trade_key_index.
        let returned = mgr
            .install_session(order_id.clone(), TradeRole::Buyer, 4, order)
            .await
            .expect("install for the same index must succeed");

        let session = mgr
            .get_session(&order_id)
            .await
            .expect("session must exist");
        assert_eq!(
            session.trade_key_index, 4,
            "the index must be unchanged — same take"
        );
        assert_eq!(
            session.peer_pubkey.as_deref(),
            Some("aabbccdd"),
            "peer_pubkey established by the reveal must survive take_order"
        );
        assert_eq!(
            session.shared_key,
            Some([7u8; 32]),
            "shared_key established by the reveal must survive take_order"
        );
        assert_eq!(
            returned.peer_pubkey, session.peer_pubkey,
            "the returned session must be the kept one, not a fresh empty one"
        );
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

    /// `create_session_with_peer` is the atomic counterpart (#381 review):
    /// the session is complete from the first moment any reader can see it —
    /// what the MANAGER returns for the order already carries peer and
    /// shared key, so no concurrent send can observe a keyless intermediate
    /// and degrade to local-only. Duplicate semantics match `create_session`.
    #[tokio::test]
    async fn session_created_with_peer_is_never_observable_keyless() {
        let order_id = uuid::Uuid::new_v4().to_string();
        let order = dummy_order_info(&order_id);
        let peer_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let shared = [7u8; 32];

        let mgr = session_manager();
        let returned = mgr
            .create_session_with_peer(
                order_id.clone(),
                TradeRole::Buyer,
                4,
                order.clone(),
                peer_hex.clone(),
                shared,
            )
            .await
            .unwrap();
        assert_eq!(returned.peer_pubkey.as_deref(), Some(peer_hex.as_str()));
        assert_eq!(returned.shared_key, Some(shared));

        // The stored copy — what any concurrent reader gets — is the same
        // complete session, not a keyless one later patched up.
        let observed = mgr.get_session(&order_id).await.expect("session stored");
        assert_eq!(observed.peer_pubkey.as_deref(), Some(peer_hex.as_str()));
        assert_eq!(observed.shared_key, Some(shared));

        // Same duplicate guard as create_session: second insert fails and
        // leaves the original untouched.
        let dup = mgr
            .create_session_with_peer(
                order_id.clone(),
                TradeRole::Buyer,
                4,
                order,
                "other-peer".into(),
                [9u8; 32],
            )
            .await;
        assert!(dup.is_err());
        let kept = mgr.get_session(&order_id).await.expect("still stored");
        assert_eq!(kept.peer_pubkey.as_deref(), Some(peer_hex.as_str()));
    }

    // ── Peer-pubkey resolution ────────────────────────────────────────────────

    /// Symmetric reveal resolution (#334): whichever side our trade key
    /// matches, the counterparty is the other one — and a payload naming two
    /// strangers resolves to nothing.
    #[test]
    fn resolve_peer_side_is_symmetric() {
        let buyer = nostr_sdk::prelude::Keys::generate().public_key();
        let seller = nostr_sdk::prelude::Keys::generate().public_key();
        let stranger = nostr_sdk::prelude::Keys::generate().public_key();

        let (peer, role) = resolve_peer_side(&buyer, &buyer, &seller).expect("we are the buyer");
        assert_eq!(peer, seller);
        assert!(matches!(role, TradeRole::Buyer));

        let (peer, role) = resolve_peer_side(&seller, &buyer, &seller).expect("we are the seller");
        assert_eq!(peer, buyer);
        assert!(matches!(role, TradeRole::Seller));

        assert!(resolve_peer_side(&stranger, &buyer, &seller).is_none());
    }

    /// The payload side of the capture (#334): only a `SmallOrder` naming
    /// BOTH trade pubkeys qualifies as a reveal, whether it arrives as an
    /// `Order` payload or inside a `PaymentRequest`.
    #[test]
    fn peer_reveal_pubkeys_requires_both_sides() {
        use mostro_core::message::Payload;
        let order = |buyer: Option<&str>, seller: Option<&str>| {
            let mut o = small_order_with(mostro_core::order::Status::Active, 100);
            o.buyer_trade_pubkey = buyer.map(String::from);
            o.seller_trade_pubkey = seller.map(String::from);
            o
        };

        // Both pubkeys present → reveals, from either carrying payload.
        let both = Payload::Order(order(Some("b"), Some("s")));
        assert_eq!(peer_reveal_pubkeys(Some(&both)), Some(("b", "s")));
        let pay_req =
            Payload::PaymentRequest(Some(order(Some("b"), Some("s"))), "lnbc1".into(), None);
        assert_eq!(peer_reveal_pubkeys(Some(&pay_req)), Some(("b", "s")));

        // Single-sided payloads (e.g. the maker's own NewOrder confirmation)
        // reveal nothing — there is no telling which side is ours.
        let buyer_only = Payload::Order(order(Some("b"), None));
        assert_eq!(peer_reveal_pubkeys(Some(&buyer_only)), None);
        let seller_only = Payload::Order(order(None, Some("s")));
        assert_eq!(peer_reveal_pubkeys(Some(&seller_only)), None);

        // `Some("")` is absent, not present (mostrix parity): it must be
        // filtered here, not warn-logged downstream for every replayed
        // message of a daemon that encodes "no pubkey" as an empty string.
        let empty_buyer = Payload::Order(order(Some(""), Some("s")));
        assert_eq!(peer_reveal_pubkeys(Some(&empty_buyer)), None);
        let empty_seller = Payload::Order(order(Some("b"), Some("")));
        assert_eq!(peer_reveal_pubkeys(Some(&empty_seller)), None);

        // No SmallOrder at all: bare PaymentRequest, non-order payload, none.
        let bare_pay_req = Payload::PaymentRequest(None, "lnbc1".into(), None);
        assert_eq!(peer_reveal_pubkeys(Some(&bare_pay_req)), None);
        let text = Payload::TextMessage("hi".into());
        assert_eq!(peer_reveal_pubkeys(Some(&text)), None);
        assert_eq!(peer_reveal_pubkeys(None), None);
    }

    /// A reveal for an order with no session AND no order info anywhere
    /// (row or book) cannot create one — it must degrade to a warning, not
    /// a panic. Exercised through `apply_peer_reveal` with generated keys,
    /// same as the maker-session test below.
    #[tokio::test]
    async fn peer_pubkey_with_no_session_does_not_panic() {
        let trade_keys = nostr_sdk::prelude::Keys::generate();
        let peer_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        // Random order_id: no session, no trade row, not in the order book.
        apply_peer_reveal(
            &uuid::Uuid::new_v4().to_string(),
            &peer_hex,
            &trade_keys,
            0,
            TradeRole::Buyer,
        )
        .await;
        // If we reach here without panicking the test passes.
    }

    /// The maker path of #334: a reveal with no existing session creates one
    /// carrying the peer pubkey and the ECDH shared key, sourcing order info
    /// from the public book (the maker's trade row may not exist yet, and on
    /// web never does). Exercised through `apply_peer_reveal` with generated
    /// keys — loading a real identity would mutate process-global state
    /// shared with every other test in the binary.
    #[tokio::test]
    async fn peer_reveal_creates_missing_maker_session() {
        let order_id = uuid::Uuid::new_v4().to_string();
        let trade_keys = nostr_sdk::prelude::Keys::generate();
        let peer_keys = nostr_sdk::prelude::Keys::generate();
        let peer_hex = peer_keys.public_key().to_hex();

        order_book().upsert_order(dummy_order_info(&order_id)).await;

        apply_peer_reveal(&order_id, &peer_hex, &trade_keys, 7, TradeRole::Seller).await;

        let session = session_manager()
            .get_session(&order_id)
            .await
            .expect("reveal must create the maker's missing session");
        assert!(matches!(session.role, TradeRole::Seller));
        assert_eq!(session.trade_key_index, 7);
        assert_eq!(session.peer_pubkey.as_deref(), Some(peer_hex.as_str()));
        let expected =
            crate::crypto::ecdh::derive_nip04_shared_key(&trade_keys, &peer_keys.public_key())
                .expect("ECDH derivation");
        assert_eq!(session.shared_key, Some(expected));
    }

    /// The seam test for #334: `dispatch_mostro_message` is the ONLY caller
    /// of `maybe_capture_peer_reveal` — deleting that call leaves every other
    /// test green, because they exercise the pieces directly. This drives one
    /// daemon message naming both trade pubkeys through the real dispatcher,
    /// starting from a row exactly as `take_order` leaves it (empty
    /// counterparty), and asserts the durable write and the session both
    /// happened.
    ///
    /// `#[ignore]`d because it claims two process-global singletons for the
    /// whole test binary — the `app_db` OnceCell and the in-memory identity —
    /// which cannot be shared with the rest of the suite (same pattern as
    /// `restore_e2e_tests`). Run with:
    ///   cargo test --lib peer_reveal_capture_is_wired_into_dispatch -- --ignored
    #[tokio::test]
    #[ignore = "claims the process-global app_db and identity — run with --ignored"]
    async fn peer_reveal_capture_is_wired_into_dispatch() {
        use mostro_core::message::{Action, Message, Payload};

        let db_path =
            std::env::temp_dir().join(format!("mostro-wiring-test-{}.db", uuid::Uuid::new_v4()));
        crate::db::app_db::init_db(db_path.to_str().unwrap())
            .await
            .expect("init app db");
        crate::api::identity::import_from_mnemonic(
            "abandon abandon abandon abandon abandon abandon abandon abandon \
             abandon abandon abandon about"
                .split_whitespace()
                .map(String::from)
                .collect(),
            false,
        )
        .await
        .expect("import identity");

        let trade_index = 3u32;
        let trade_keys = crate::api::identity::get_active_trade_keys(trade_index)
            .await
            .expect("derive trade key");
        let my_hex = trade_keys.public_key().to_hex();
        let peer_keys = nostr_sdk::prelude::Keys::generate();
        let peer_hex = peer_keys.public_key().to_hex();

        // The world as a maker-seller take leaves it: book entry, trade-key
        // binding (the generation gate reads it), and a persisted row with an
        // EMPTY counterparty.
        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let mut order_info = dummy_order_info(&order_id);
        order_info.kind = crate::api::types::OrderKind::Sell;
        order_info.status = crate::api::types::OrderStatus::Active;
        order_book().upsert_order(order_info.clone()).await;
        store_trade_key_index(&order_id, trade_index).await;
        let db = crate::db::app_db::db().expect("db just initialized");
        db.save_trade(&crate::api::types::TradeInfo {
            id: order_id.clone(),
            order: order_info,
            role: TradeRole::Seller,
            counterparty_pubkey: String::new(),
            current_step: crate::api::types::TradeStep::Seller(
                crate::api::types::SellerStep::TakerFound,
            ),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: trade_index,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
        })
        .await
        .expect("save the pre-reveal row");

        // One daemon message whose payload names BOTH trade pubkeys — the
        // buyer is the peer, the seller is our derived trade key.
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
            Some(peer_hex.clone()),
            Some(my_hex.clone()),
            None,
            None,
            None,
        );
        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
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
            created_at: nostr_sdk::prelude::Timestamp::from(0u64),
        };
        dispatch_mostro_message(unwrapped, "test-peer-reveal-wiring", &my_hex, trade_index).await;

        // The durable write: the row now holds the peer. This is the
        // assertion that fails when the dispatcher call is deleted.
        let row = db
            .get_trade_by_order_id(&order_id)
            .await
            .expect("row query")
            .expect("row survives dispatch");
        assert_eq!(row.counterparty_pubkey, peer_hex);

        // The session cache: created by the same capture, with peer, role and
        // the real ECDH shared key.
        let session = session_manager()
            .get_session(&order_id)
            .await
            .expect("capture must create the maker's session");
        assert!(matches!(session.role, TradeRole::Seller));
        assert_eq!(session.peer_pubkey.as_deref(), Some(peer_hex.as_str()));
        let expected =
            crate::crypto::ecdh::derive_nip04_shared_key(&trade_keys, &peer_keys.public_key())
                .expect("ECDH derivation");
        assert_eq!(session.shared_key, Some(expected));

        let _ = std::fs::remove_file(&db_path);
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

        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        let unwrapped = mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(Some(order_uuid), None, None, Action::Canceled, None),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::prelude::Timestamp::from(0u64),
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
        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(Some(order_uuid), None, None, Action::Canceled, None),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::prelude::Timestamp::from(0u64),
        }
    }

    /// Builds an `UnwrappedMessage` for `action` on `order_uuid` with a
    /// chosen `created_at`, for driving the real dispatcher through replay
    /// scenarios (the cursor and the #394 classification both key on time).
    fn daemon_message(
        order_uuid: uuid::Uuid,
        action: mostro_core::message::Action,
        payload: Option<mostro_core::message::Payload>,
        created_at: u64,
    ) -> mostro_core::nip59::UnwrappedMessage {
        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        mostro_core::nip59::UnwrappedMessage {
            message: mostro_core::message::Message::new_order(
                Some(order_uuid),
                None,
                None,
                action,
                payload,
            ),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::prelude::Timestamp::from(created_at),
        }
    }

    /// A trade row in `status` for the #394 seam tests.
    fn seam_trade_row(
        order_id: &str,
        status: crate::api::types::OrderStatus,
    ) -> crate::api::types::TradeInfo {
        let mut order = dummy_order_info(order_id);
        order.status = status;
        order.is_mine = true;
        crate::api::types::TradeInfo {
            id: order_id.to_string(),
            order,
            role: TradeRole::Seller,
            counterparty_pubkey: String::new(),
            current_step: crate::api::types::TradeStep::Seller(
                crate::api::types::SellerStep::OrderPublished,
            ),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 1,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
        }
    }

    /// TradeUpdates for `order_id` currently buffered on `rx`.
    fn drain_updates(
        rx: &mut broadcast::Receiver<crate::api::types::TradeUpdate>,
        order_id: &str,
    ) -> Vec<crate::api::types::OrderStatus> {
        let mut seen = Vec::new();
        while let Ok(update) = rx.try_recv() {
            if update.order_id == order_id {
                seen.push(update.status);
            }
        }
        seen
    }

    /// #394: a Canceled over a pre-active trade wipes the row and leaves the
    /// tombstone; the SAME message replayed on the next start (the global
    /// feed carries no `since`) is then dropped whole — no write to nothing,
    /// no TradeUpdate. Before the tombstone, every restart re-ran the write
    /// and pushed a phantom update per pass.
    #[tokio::test]
    async fn a_replayed_cancel_for_a_wiped_trade_is_dropped_whole() {
        use mostro_core::message::Action;

        let path = std::env::temp_dir().join(format!("mostro_wiped_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        order_book().upsert_order(dummy_order_info(&order_id)).await;
        db.save_trade(&seam_trade_row(
            &order_id,
            crate::api::types::OrderStatus::WaitingPayment,
        ))
        .await
        .expect("save the trade row");

        let mut rx = trade_updates_tx().subscribe();

        // The live cancel: wipes the row, tombstones the id, pushes once.
        dispatch_mostro_message(
            daemon_message(order_uuid, Action::Canceled, None, 1_000),
            "test-wipe-live",
            "ff00ff20",
            1,
        )
        .await;
        assert!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("lookup")
                .is_none(),
            "the pre-active cancel must wipe the row",
        );
        assert!(
            db.get_setting(&crate::db::settings_keys::trade_wiped(&order_id))
                .await
                .expect("tombstone lookup")
                .is_some(),
            "the wipe must leave its tombstone",
        );
        assert_eq!(
            drain_updates(&mut rx, &order_id),
            vec![crate::api::types::OrderStatus::Canceled],
            "the live cancel pushes exactly once",
        );

        // The replay: classified as wiped-on-purpose and dropped whole.
        dispatch_mostro_message(
            daemon_message(order_uuid, Action::Canceled, None, 1_000),
            "test-wipe-replay",
            "ff00ff20",
            1,
        )
        .await;
        assert!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("lookup")
                .is_none(),
            "a replay must not resurrect anything",
        );
        assert!(
            drain_updates(&mut rx, &order_id).is_empty(),
            "a replay over a wiped trade must not emit",
        );
    }

    /// #394: the tombstone must not outlive a legitimate re-take. Re-creating
    /// the row through the shared persistence helper (the seam `create_order`,
    /// `take_order` and the range-remainder adoption all use) lifts it, and
    /// the new generation's daemon messages flow again.
    #[tokio::test]
    async fn a_retake_after_a_wipe_lifts_the_tombstone() {
        use mostro_core::message::Action;

        let path = std::env::temp_dir().join(format!("mostro_retake_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        order_book().upsert_order(dummy_order_info(&order_id)).await;
        db.save_trade(&seam_trade_row(
            &order_id,
            crate::api::types::OrderStatus::WaitingBuyerInvoice,
        ))
        .await
        .expect("save the trade row");

        dispatch_mostro_message(
            daemon_message(order_uuid, Action::Canceled, None, 1_000),
            "test-retake-wipe",
            "ff00ff21",
            1,
        )
        .await;
        assert!(db
            .get_setting(&crate::db::settings_keys::trade_wiped(&order_id))
            .await
            .expect("tombstone lookup")
            .is_some());

        // The re-take persists a fresh row the way take_order does.
        persist_trade_row(
            db,
            &seam_trade_row(&order_id, crate::api::types::OrderStatus::Active),
        )
        .await
        .expect("re-create the row");
        assert!(
            db.get_setting(&crate::db::settings_keys::trade_wiped(&order_id))
                .await
                .expect("tombstone lookup")
                .is_none(),
            "re-creating the row must lift the tombstone",
        );

        let mut rx = trade_updates_tx().subscribe();
        dispatch_mostro_message(
            daemon_message(order_uuid, Action::DisputeInitiatedByPeer, None, 2_000),
            "test-retake-msg",
            "ff00ff21",
            2,
        )
        .await;
        assert_eq!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("lookup")
                .expect("row exists")
                .order
                .status,
            crate::api::types::OrderStatus::Dispute,
            "messages for the re-taken generation must apply again",
        );
        assert_eq!(
            drain_updates(&mut rx, &order_id),
            vec![crate::api::types::OrderStatus::Dispute],
        );
    }

    /// Review round 2, probe P5: the tombstone records the generation it
    /// wiped, so a message of a LATER take of the same order — decrypted
    /// with a higher trade index — is not noise: it classifies
    /// `NeverWritten` and the DM rebuild recovers it. A replay of the wiped
    /// generation itself stays dropped.
    #[tokio::test]
    async fn a_later_generation_is_not_covered_by_the_wipe_tombstone() {
        use mostro_core::message::{Action, Payload};

        let path = std::env::temp_dir().join(format!("mostro_wipegen_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let my5_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let peer_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        order_book().upsert_order(dummy_order_info(&order_id)).await;
        db.save_trade(&seam_trade_row(
            &order_id,
            crate::api::types::OrderStatus::WaitingPayment,
        ))
        .await
        .expect("save the generation-1 row");

        // The cancel wipes generation 1 (seam_trade_row's index) and
        // records it in the tombstone.
        dispatch_mostro_message(
            daemon_message(order_uuid, Action::Canceled, None, 1_000),
            "test-wipegen-cancel",
            "ff00ff23",
            1,
        )
        .await;
        assert!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("lookup")
                .is_none(),
            "the pre-active cancel must wipe the row",
        );

        // A replay of the wiped generation (equal timestamp passes the
        // cursor, so the tombstone is what drops it) stays noise.
        let mut rx = trade_updates_tx().subscribe();
        let replay = Payload::Order(mostro_core::order::SmallOrder::new(
            Some(order_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::WaitingBuyerInvoice),
            457,
            "USD".to_string(),
            None,
            None,
            100,
            "Bank".to_string(),
            0,
            Some(my5_hex.clone()),
            Some(peer_hex.clone()),
            None,
            None,
            None,
        ));
        dispatch_mostro_message(
            daemon_message(
                order_uuid,
                Action::AddInvoice,
                Some(replay.clone()),
                1_000,
            ),
            "test-wipegen-replay",
            &my5_hex,
            1,
        )
        .await;
        assert!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("lookup")
                .is_none(),
            "the wiped generation's replay must stay dropped",
        );
        assert!(drain_updates(&mut rx, &order_id).is_empty());

        // The same message on a later index is a NEW take whose
        // confirmation timed out — exactly what the rebuild exists for.
        dispatch_mostro_message(
            daemon_message(order_uuid, Action::AddInvoice, Some(replay), 2_000),
            "test-wipegen-newgen",
            &my5_hex,
            5,
        )
        .await;
        let row = db
            .get_trade_by_order_id(&order_id)
            .await
            .expect("lookup")
            .expect("the later generation must be rebuilt");
        assert_eq!(row.trade_key_index, 5);
        assert_eq!(
            row.order.status,
            crate::api::types::OrderStatus::WaitingBuyerInvoice,
        );
        assert_eq!(
            drain_updates(&mut rx, &order_id),
            vec![crate::api::types::OrderStatus::WaitingBuyerInvoice],
        );
    }

    /// `tombstone_covers` — the generation rule, plus the conservative
    /// fallback: a value without a parseable index covers everything.
    #[test]
    fn tombstone_covers_older_generations_only() {
        assert!(tombstone_covers("1000:3", 2));
        assert!(tombstone_covers("1000:3", 3));
        assert!(!tombstone_covers("1000:3", 4));
        assert!(tombstone_covers("1000", 999), "legacy value covers all");
        assert!(tombstone_covers("1000:junk", 999), "unparseable covers all");
    }

    /// Review round 2, blocker 3: `persist_trade_row` is the one way to
    /// (re)create a trade row — it lifts the wipe tombstone first. A direct
    /// `save_trade` reverted into any production path (`take_order`,
    /// `create_order`, the adoption, the rebuild) would leave a stale
    /// tombstone silently swallowing every daemon message of the new trade,
    /// and `a_retake_after_a_wipe_lifts_the_tombstone` above only proves the
    /// helper works, not that the callers use it. Pin the callers statically.
    #[test]
    fn production_code_saves_trades_only_through_persist_trade_row() {
        let source = include_str!("orders.rs");
        // Cut at the test module, not at the first `#[cfg(test)]`: test-only
        // helpers such as `OrderBook::has_wire_note` sit earlier in the file,
        // and cutting there would leave `persist_trade_row` out of the count.
        let production = source
            .split("\n#[cfg(test)]\nmod tests {")
            .next()
            .expect("split always yields a first chunk");
        assert_eq!(
            production.matches(".save_trade(").count(),
            1,
            "expected exactly one .save_trade( call in production code — the \
             one inside persist_trade_row. Route new call sites through \
             persist_trade_row so the wipe tombstone is lifted (#394).",
        );
    }

    /// #394 "minor": a replayed message carrying the value the row already
    /// holds must neither write nor emit — but the cursor still advances
    /// (the message WAS accepted), so strictly-older backlog stays refused.
    /// A later real transition still writes and emits.
    #[tokio::test]
    async fn an_unchanged_status_replay_writes_and_emits_nothing() {
        use mostro_core::message::Action;

        let path = std::env::temp_dir().join(format!("mostro_noop_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        order_book().upsert_order(dummy_order_info(&order_id)).await;
        db.save_trade(&seam_trade_row(
            &order_id,
            crate::api::types::OrderStatus::FiatSent,
        ))
        .await
        .expect("save the trade row");

        let mut rx = trade_updates_tx().subscribe();
        dispatch_mostro_message(
            daemon_message(order_uuid, Action::FiatSentOk, None, 2_000),
            "test-noop-replay",
            "ff00ff22",
            1,
        )
        .await;
        assert!(
            drain_updates(&mut rx, &order_id).is_empty(),
            "re-writing the value the row holds must not emit",
        );
        assert_eq!(
            db.get_setting(&crate::db::settings_keys::status_cursor(&order_id))
                .await
                .unwrap()
                .as_deref(),
            Some("2000"),
            "the accepted no-op must still advance the cursor",
        );

        dispatch_mostro_message(
            daemon_message(order_uuid, Action::DisputeInitiatedByPeer, None, 3_000),
            "test-noop-transition",
            "ff00ff22",
            1,
        )
        .await;
        assert_eq!(
            drain_updates(&mut rx, &order_id),
            vec![crate::api::types::OrderStatus::Dispute],
            "a real transition still writes and emits",
        );
    }

    /// #394 review: `PayInvoice` also writes the hold invoice, so its no-op
    /// detection must compare all three fields. A replay with the same
    /// status, bolt11 and sats is skipped whole; a different invoice at the
    /// same timestamp (equal passes the cursor) still writes.
    #[tokio::test]
    async fn a_replayed_pay_invoice_with_identical_fields_is_a_no_op() {
        use mostro_core::message::{Action, Payload};

        let path = std::env::temp_dir().join(format!("mostro_payinv_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        order_book().upsert_order(dummy_order_info(&order_id)).await;
        let mut row = seam_trade_row(&order_id, crate::api::types::OrderStatus::WaitingPayment);
        row.hold_invoice = Some("lnbc1same".to_string());
        row.order.amount_sats = Some(5_000);
        db.save_trade(&row).await.expect("save the trade row");

        let mut rx = trade_updates_tx().subscribe();
        dispatch_mostro_message(
            daemon_message(
                order_uuid,
                Action::PayInvoice,
                Some(Payload::PaymentRequest(
                    None,
                    "lnbc1same".to_string(),
                    Some(5_000),
                )),
                2_000,
            ),
            "test-payinv-same",
            "ff00ff23",
            1,
        )
        .await;
        assert!(
            drain_updates(&mut rx, &order_id).is_empty(),
            "identical status+invoice+sats must be a no-op",
        );

        dispatch_mostro_message(
            daemon_message(
                order_uuid,
                Action::PayInvoice,
                Some(Payload::PaymentRequest(
                    None,
                    "lnbc2other".to_string(),
                    Some(5_000),
                )),
                2_000,
            ),
            "test-payinv-diff",
            "ff00ff23",
            1,
        )
        .await;
        assert_eq!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("lookup")
                .expect("row exists")
                .hold_invoice
                .as_deref(),
            Some("lnbc2other"),
            "a different invoice must still be persisted",
        );
        assert_eq!(
            drain_updates(&mut rx, &order_id),
            vec![crate::api::types::OrderStatus::WaitingPayment],
        );
    }

    /// #394 step 2: a message for a trade that was never persisted (the
    /// take's confirmation timed out, the daemon proceeded) rebuilds the row
    /// from the message itself — role from the payload's trade pubkeys,
    /// binding from the decrypting key — and emits exactly once.
    #[tokio::test]
    async fn a_never_written_trade_is_rebuilt_from_the_dm() {
        use mostro_core::message::{Action, Payload};

        let path = std::env::temp_dir().join(format!("mostro_rebuild_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let my_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let peer_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();

        let mut rx = trade_updates_tx().subscribe();
        let so = mostro_core::order::SmallOrder::new(
            Some(order_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::Active),
            457,
            "USD".to_string(),
            None,
            None,
            100,
            "Bank".to_string(),
            0,
            Some(peer_hex.clone()),
            Some(my_hex.clone()),
            None,
            None,
            None,
        );
        dispatch_mostro_message(
            daemon_message(
                order_uuid,
                Action::BuyerTookOrder,
                Some(Payload::Order(so)),
                2_000,
            ),
            "test-rebuild-took",
            &my_hex,
            11,
        )
        .await;

        let row = db
            .get_trade_by_order_id(&order_id)
            .await
            .expect("lookup")
            .expect("row rebuilt from the DM");
        assert_eq!(row.role, TradeRole::Seller, "our key is the seller's");
        assert_eq!(row.counterparty_pubkey, peer_hex);
        assert_eq!(row.order.status, crate::api::types::OrderStatus::Active);
        assert_eq!(row.trade_key_index, 11);
        assert!(
            row.order.is_mine,
            "the maker of a sell order is its seller (review round 2)",
        );
        assert_eq!(row.order.amount_sats, Some(457));
        assert_eq!(
            get_trade_key_index(&order_id).await,
            Some(11),
            "the decrypting key's index must be bound durably",
        );
        assert_eq!(
            drain_updates(&mut rx, &order_id),
            vec![crate::api::types::OrderStatus::Active],
            "the rebuild emits once; the arm sees the row current and stays quiet",
        );
    }

    /// Review round 2, blocker 2 — the taker mirror of the rebuild above:
    /// our key is the buyer of a sell order, so the row is a trade of ours
    /// but not an order of ours (`is_mine == false`).
    #[tokio::test]
    async fn a_rebuilt_taker_row_is_not_mine() {
        use mostro_core::message::{Action, Payload};

        let path =
            std::env::temp_dir().join(format!("mostro_rebuild_tk_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let my_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let peer_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();

        let so = mostro_core::order::SmallOrder::new(
            Some(order_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::Active),
            457,
            "USD".to_string(),
            None,
            None,
            100,
            "Bank".to_string(),
            0,
            Some(my_hex.clone()),
            Some(peer_hex.clone()),
            None,
            None,
            None,
        );
        dispatch_mostro_message(
            daemon_message(
                order_uuid,
                Action::HoldInvoicePaymentAccepted,
                Some(Payload::Order(so)),
                2_000,
            ),
            "test-rebuild-taker",
            &my_hex,
            13,
        )
        .await;

        let row = db
            .get_trade_by_order_id(&order_id)
            .await
            .expect("lookup")
            .expect("row rebuilt from the DM");
        assert_eq!(row.role, TradeRole::Buyer, "our key is the buyer's");
        assert!(
            !row.order.is_mine,
            "the buyer of a sell order took it — not the maker",
        );
    }

    /// #394 step 2: mostrod nulls both trade pubkeys before `add-invoice`
    /// (flow.rs), so the buyer side is proven by protocol semantics — an
    /// AddInvoice only ever addresses the buyer — not guessed.
    #[tokio::test]
    async fn an_add_invoice_without_payload_pubkeys_rebuilds_the_buyer_side() {
        use mostro_core::message::{Action, Payload};

        let path = std::env::temp_dir().join(format!("mostro_rebuild2_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let mut rx = trade_updates_tx().subscribe();

        let so = mostro_core::order::SmallOrder::new(
            Some(order_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::WaitingBuyerInvoice),
            6_307,
            "EUR".to_string(),
            None,
            None,
            50,
            "SEPA".to_string(),
            0,
            None,
            None,
            None,
            None,
            None,
        );
        dispatch_mostro_message(
            daemon_message(
                order_uuid,
                Action::AddInvoice,
                Some(Payload::Order(so)),
                2_000,
            ),
            "test-rebuild-addinv",
            "ff00ff31",
            12,
        )
        .await;

        let row = db
            .get_trade_by_order_id(&order_id)
            .await
            .expect("lookup")
            .expect("row rebuilt from the DM");
        assert_eq!(
            row.role,
            TradeRole::Buyer,
            "add-invoice addresses the buyer"
        );
        assert!(
            !row.order.is_mine,
            "buyer of a sell order: the fallback role derives taker-ness too",
        );
        assert_eq!(
            row.order.status,
            crate::api::types::OrderStatus::WaitingBuyerInvoice
        );
        assert_eq!(row.order.amount_sats, Some(6_307));
        assert_eq!(
            drain_updates(&mut rx, &order_id),
            vec![crate::api::types::OrderStatus::WaitingBuyerInvoice],
        );
    }

    /// #394 step 2: a payload naming two strangers proves no role for the
    /// decrypting key — nothing is rebuilt, and the arm keeps today's
    /// warn-and-emit path for the never-written row.
    #[tokio::test]
    async fn a_payload_naming_two_strangers_does_not_rebuild() {
        use mostro_core::message::{Action, Payload};

        let path = std::env::temp_dir().join(format!("mostro_rebuild3_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let mut rx = trade_updates_tx().subscribe();

        let so = mostro_core::order::SmallOrder::new(
            Some(order_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::FiatSent),
            457,
            "USD".to_string(),
            None,
            None,
            100,
            "Bank".to_string(),
            0,
            Some(nostr_sdk::prelude::Keys::generate().public_key().to_hex()),
            Some(nostr_sdk::prelude::Keys::generate().public_key().to_hex()),
            None,
            None,
            None,
        );
        dispatch_mostro_message(
            daemon_message(
                order_uuid,
                Action::FiatSentOk,
                Some(Payload::Order(so)),
                2_000,
            ),
            "test-rebuild-foreign",
            "ff00ff32",
            13,
        )
        .await;

        assert!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("lookup")
                .is_none(),
            "no role proof → no rebuild",
        );
        assert_eq!(
            drain_updates(&mut rx, &order_id),
            vec![crate::api::types::OrderStatus::FiatSent],
            "the never-written arm keeps today's warn-and-emit behavior",
        );
    }

    /// #394 step 2: a create whose confirmation arrived after the 10s
    /// timeout persists the maker row from the echoed order — nonce-gated,
    /// maker by construction, min/max preserved so a range order rebuilds
    /// whole. Before this, the branch only logged and left recovery to the
    /// Kind 38383 content fingerprint.
    #[tokio::test]
    async fn a_late_create_confirmation_persists_the_maker_row() {
        use mostro_core::message::{Action, Payload};

        let path = std::env::temp_dir().join(format!("mostro_late_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let trade_pk = "ff00ff33";
        // The record a timed-out create_order leaves behind: waiter detached
        // (tx: None), nonce still armed.
        if let Ok(mut map) = pending_requests().lock() {
            map.insert(
                trade_pk.to_string(),
                PendingRequest {
                    request_id: 777,
                    trade_index: 14,
                    kind: PendingRequestKind::Create {
                        local_uuid: "local-uuid-late".to_string(),
                    },
                    tx: None,
                },
            );
        }

        let mut rx = trade_updates_tx().subscribe();
        let so = mostro_core::order::SmallOrder::new(
            Some(order_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::Pending),
            0,
            "VES".to_string(),
            Some(100),
            Some(500),
            0,
            "PagoMovil".to_string(),
            2,
            None,
            None,
            None,
            None,
            None,
        );
        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        dispatch_mostro_message(
            mostro_core::nip59::UnwrappedMessage {
                message: mostro_core::message::Message::new_order(
                    Some(order_uuid),
                    Some(777),
                    None,
                    Action::NewOrder,
                    Some(Payload::Order(so)),
                ),
                signature: None,
                sender,
                identity: sender,
                created_at: nostr_sdk::prelude::Timestamp::from(3_000u64),
            },
            "test-late-create",
            trade_pk,
            14,
        )
        .await;

        let row = db
            .get_trade_by_order_id(&order_id)
            .await
            .expect("lookup")
            .expect("late confirmation must persist the maker row");
        assert!(row.order.is_mine, "maker by construction");
        assert_eq!(row.role, TradeRole::Seller);
        assert_eq!(row.trade_key_index, 14);
        assert_eq!(row.order.fiat_amount_min, Some(100.0));
        assert_eq!(row.order.fiat_amount_max, Some(500.0));
        assert_eq!(
            get_trade_key_index(&order_id).await,
            Some(14),
            "the arm binds the daemon id to this attempt's index",
        );
        assert_eq!(
            drain_updates(&mut rx, &order_id),
            vec![crate::api::types::OrderStatus::Pending],
        );
    }

    /// The #394 review's seam: rebuild × cursor × newest-first replay.
    /// Relays hand the backlog back newest-first, so the FIRST replayed
    /// message rebuilds the row already at its final status and pins the
    /// cursor; the older tail is refused by strictly-older, and the UI gets
    /// exactly one update.
    #[tokio::test]
    async fn the_newest_first_replay_rebuilds_once_and_blocks_the_tail() {
        use mostro_core::message::{Action, Payload};

        let path = std::env::temp_dir().join(format!("mostro_rebuild4_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let my_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let peer_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let mut rx = trade_updates_tx().subscribe();

        let payload_at = |status: mostro_core::order::Status| {
            Payload::Order(mostro_core::order::SmallOrder::new(
                Some(order_uuid),
                Some(mostro_core::order::Kind::Sell),
                Some(status),
                457,
                "USD".to_string(),
                None,
                None,
                100,
                "Bank".to_string(),
                0,
                Some(peer_hex.clone()),
                Some(my_hex.clone()),
                None,
                None,
                None,
            ))
        };
        // Newest first, exactly how the relay hands the backlog back.
        for (action, status, ts) in [
            (
                Action::FiatSentOk,
                mostro_core::order::Status::FiatSent,
                3_000u64,
            ),
            (
                Action::BuyerTookOrder,
                mostro_core::order::Status::Active,
                2_000,
            ),
        ] {
            dispatch_mostro_message(
                daemon_message(order_uuid, action, Some(payload_at(status)), ts),
                &format!("test-rebuild-tail-{ts}"),
                &my_hex,
                15,
            )
            .await;
        }

        assert_eq!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("lookup")
                .expect("row rebuilt")
                .order
                .status,
            crate::api::types::OrderStatus::FiatSent,
            "the newest message owns the rebuilt status",
        );
        assert_eq!(
            db.get_setting(&crate::db::settings_keys::status_cursor(&order_id))
                .await
                .unwrap()
                .as_deref(),
            Some("3000"),
            "the rebuild's message pins the cursor",
        );
        assert_eq!(
            drain_updates(&mut rx, &order_id),
            vec![crate::api::types::OrderStatus::FiatSent],
            "one rebuild, one update — the older tail is refused",
        );
    }

    /// Review round 2, blocker 1 (probes P1/P2): a Canceled with no row
    /// still advances the status cursor, so on a newest-first replay the
    /// older take reply behind it must not rebuild the row — the daemon
    /// already ended this trade and will never speak of it again, and the
    /// rebuilt row would sit in its waiting state forever.
    #[tokio::test]
    async fn a_rebuild_older_than_an_accepted_cancel_is_refused() {
        use mostro_core::message::{Action, Payload};

        let path = std::env::temp_dir().join(format!("mostro_rebuild5_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let my_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let peer_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let mut rx = trade_updates_tx().subscribe();

        // P1 — buyer side: Canceled@3000, then the older AddInvoice@2000.
        let buy_uuid = uuid::Uuid::new_v4();
        let buy_id = buy_uuid.to_string();
        let add_invoice = Payload::Order(mostro_core::order::SmallOrder::new(
            Some(buy_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::WaitingBuyerInvoice),
            457,
            "USD".to_string(),
            None,
            None,
            100,
            "Bank".to_string(),
            0,
            Some(my_hex.clone()),
            Some(peer_hex.clone()),
            None,
            None,
            None,
        ));
        dispatch_mostro_message(
            daemon_message(buy_uuid, Action::Canceled, None, 3_000),
            "test-necro-cancel-buy",
            &my_hex,
            15,
        )
        .await;
        dispatch_mostro_message(
            daemon_message(buy_uuid, Action::AddInvoice, Some(add_invoice), 2_000),
            "test-necro-addinvoice",
            &my_hex,
            15,
        )
        .await;
        assert!(
            db.get_trade_by_order_id(&buy_id)
                .await
                .expect("lookup")
                .is_none(),
            "an AddInvoice older than the accepted cancel must not rebuild the row",
        );
        assert_eq!(
            drain_updates(&mut rx, &buy_id),
            vec![crate::api::types::OrderStatus::Canceled],
            "only the cancel reaches the UI",
        );

        // P2 — seller side: Canceled@3000, then the older PayInvoice@2000.
        let sell_uuid = uuid::Uuid::new_v4();
        let sell_id = sell_uuid.to_string();
        let pay_invoice = Payload::PaymentRequest(
            Some(mostro_core::order::SmallOrder::new(
                Some(sell_uuid),
                Some(mostro_core::order::Kind::Buy),
                Some(mostro_core::order::Status::WaitingPayment),
                457,
                "USD".to_string(),
                None,
                None,
                100,
                "Bank".to_string(),
                0,
                Some(peer_hex.clone()),
                Some(my_hex.clone()),
                None,
                None,
                None,
            )),
            "lnbc1".to_string(),
            None,
        );
        dispatch_mostro_message(
            daemon_message(sell_uuid, Action::Canceled, None, 3_000),
            "test-necro-cancel-sell",
            &my_hex,
            15,
        )
        .await;
        dispatch_mostro_message(
            daemon_message(sell_uuid, Action::PayInvoice, Some(pay_invoice), 2_000),
            "test-necro-payinvoice",
            &my_hex,
            15,
        )
        .await;
        assert!(
            db.get_trade_by_order_id(&sell_id)
                .await
                .expect("lookup")
                .is_none(),
            "a PayInvoice older than the accepted cancel must not rebuild the row",
        );
        assert_eq!(
            drain_updates(&mut rx, &sell_id),
            vec![crate::api::types::OrderStatus::Canceled],
            "only the cancel reaches the UI",
        );
    }

    /// Review round 2, blocker 1 (probe P3): the replayed ack of a create
    /// whose maker later canceled the order must not be adopted back as a
    /// Pending maker row. Same cursor gate, applied to
    /// `adopt_range_remainder` — this closes a variant that predates the
    /// classification (`main` resurrected the order too).
    #[tokio::test]
    async fn a_create_ack_older_than_an_accepted_cancel_is_not_adopted() {
        use mostro_core::message::{Action, Message, Payload};

        let path = std::env::temp_dir().join(format!("mostro_rebuild6_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let my_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        let mut rx = trade_updates_tx().subscribe();

        dispatch_mostro_message(
            daemon_message(order_uuid, Action::Canceled, None, 3_000),
            "test-necro-cancel-ack",
            &my_hex,
            21,
        )
        .await;

        // The create's ack: NewOrder, status Pending, this key's trade
        // index echoed — exactly what `adopt_range_remainder` accepts.
        let ack = mostro_core::order::SmallOrder::new(
            Some(order_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::Pending),
            0,
            "ARS".to_string(),
            None,
            None,
            1000,
            "cash".to_string(),
            0,
            None,
            Some(my_hex.clone()),
            None,
            Some(1_700_000_000),
            Some(1_700_003_600),
        );
        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        let unwrapped = mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(
                Some(order_uuid),
                None,
                Some(21),
                Action::NewOrder,
                Some(Payload::Order(ack)),
            ),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::prelude::Timestamp::from(2_000u64),
        };
        dispatch_mostro_message(unwrapped, "test-necro-ack", &my_hex, 21).await;

        assert!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("lookup")
                .is_none(),
            "a create ack older than the accepted cancel must not be adopted",
        );
        assert_eq!(
            drain_updates(&mut rx, &order_id),
            vec![crate::api::types::OrderStatus::Canceled],
            "only the cancel reaches the UI",
        );
    }

    /// Review round 2: the adoption's own tombstone check, isolated from the
    /// cursor gate — a wipe recorded with no status cursor must still refuse
    /// the replayed create ack of its generation, while a later generation
    /// (a fresh create of the same order id) adopts normally.
    #[tokio::test]
    async fn adoption_respects_the_wipe_tombstone_without_a_cursor() {
        use mostro_core::message::{Action, Message, Payload};

        let path = std::env::temp_dir().join(format!("mostro_adoptts_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let my_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();
        db.set_setting(&crate::db::settings_keys::trade_wiped(&order_id), "1000:5")
            .await
            .expect("write the tombstone");

        let ack_at = |ts: u64, idx: i64| {
            let so = mostro_core::order::SmallOrder::new(
                Some(order_uuid),
                Some(mostro_core::order::Kind::Sell),
                Some(mostro_core::order::Status::Pending),
                0,
                "ARS".to_string(),
                None,
                None,
                1000,
                "cash".to_string(),
                0,
                None,
                Some(my_hex.clone()),
                None,
                Some(1_700_000_000),
                Some(1_700_003_600),
            );
            let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
                .expect("valid mostro pubkey");
            mostro_core::nip59::UnwrappedMessage {
                message: Message::new_order(
                    Some(order_uuid),
                    None,
                    Some(idx),
                    Action::NewOrder,
                    Some(Payload::Order(so)),
                ),
                signature: None,
                sender,
                identity: sender,
                created_at: nostr_sdk::prelude::Timestamp::from(ts),
            }
        };

        dispatch_mostro_message(ack_at(2_000, 5), "test-adoptts-covered", &my_hex, 5).await;
        assert!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("lookup")
                .is_none(),
            "the wiped generation's replayed ack must not be adopted",
        );

        dispatch_mostro_message(ack_at(3_000, 6), "test-adoptts-later", &my_hex, 6).await;
        let row = db
            .get_trade_by_order_id(&order_id)
            .await
            .expect("lookup")
            .expect("a later generation adopts normally");
        assert_eq!(row.trade_key_index, 6);
        assert!(row.order.is_mine);
    }

    /// The change detector behind the #394 no-op suppression: only provided
    /// fields are compared, a missing row counts as changed (today's
    /// warn-and-emit path), and a real difference in any field writes.
    #[tokio::test]
    async fn sync_trade_fields_reports_only_real_changes() {
        let path =
            std::env::temp_dir().join(format!("mostro_syncfields_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_id = uuid::Uuid::new_v4().to_string();
        let mut row = seam_trade_row(&order_id, crate::api::types::OrderStatus::Active);
        row.hold_invoice = Some("lnbc1".to_string());
        row.order.amount_sats = Some(5_000);
        db.save_trade(&row).await.expect("save the trade row");

        assert!(
            !sync_trade_fields_if_changed(
                db,
                &order_id,
                Some(&row),
                Some(crate::api::types::OrderStatus::Active),
                None,
                None,
            )
            .await,
            "same status, other fields not provided → no-op",
        );
        assert!(
            !sync_trade_fields_if_changed(
                db,
                &order_id,
                Some(&row),
                Some(crate::api::types::OrderStatus::Active),
                Some("lnbc1".to_string()),
                Some(5_000),
            )
            .await,
            "all three provided and identical → no-op",
        );
        assert!(
            sync_trade_fields_if_changed(
                db,
                &order_id,
                Some(&row),
                Some(crate::api::types::OrderStatus::FiatSent),
                None,
                None,
            )
            .await,
            "a status transition writes",
        );
        let row = db
            .get_trade_by_order_id(&order_id)
            .await
            .expect("lookup")
            .expect("row exists");
        assert!(
            sync_trade_fields_if_changed(db, &order_id, Some(&row), None, None, Some(6_000)).await,
            "an amount change writes",
        );
        assert_eq!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("lookup")
                .expect("row exists")
                .order
                .amount_sats,
            Some(6_000),
        );
        assert!(
            sync_trade_fields_if_changed(
                db,
                &uuid::Uuid::new_v4().to_string(),
                None,
                Some(crate::api::types::OrderStatus::Active),
                None,
                None,
            )
            .await,
            "a missing row keeps today's warn-and-emit behavior",
        );
    }

    /// Review round 1: a republished `new-order` must not resurrect a wiped
    /// trade through `resync_republished_maker_order`. The window is narrow —
    /// the book must read a waiting/in-progress status (e.g. a foreign
    /// re-take) and the NewOrder must be newer than the cancel — but inside
    /// it the resync wrote Pending to nothing and emitted a phantom update.
    #[tokio::test]
    async fn a_republished_new_order_for_a_wiped_trade_stays_dead() {
        use mostro_core::message::{Action, Payload};

        let path = std::env::temp_dir().join(format!("mostro_resync_{}.db", std::process::id()));
        let _ = crate::db::app_db::init_db(path.to_str().unwrap()).await;
        let db = crate::db::app_db::db().expect("store initialised");

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        let mut book_entry = dummy_order_info(&order_id);
        book_entry.status = crate::api::types::OrderStatus::InProgress;
        order_book().upsert_order(book_entry).await;
        db.save_trade(&seam_trade_row(
            &order_id,
            crate::api::types::OrderStatus::WaitingPayment,
        ))
        .await
        .expect("save the trade row");

        dispatch_mostro_message(
            daemon_message(order_uuid, Action::Canceled, None, 1_000),
            "test-resync-wipe",
            "ff00ff24",
            1,
        )
        .await;

        let mut rx = trade_updates_tx().subscribe();
        let republished = mostro_core::order::SmallOrder::new(
            Some(order_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::Pending),
            0,
            "USD".to_string(),
            None,
            None,
            100,
            "Bank".to_string(),
            0,
            None,
            None,
            None,
            None,
            None,
        );
        dispatch_mostro_message(
            daemon_message(
                order_uuid,
                Action::NewOrder,
                Some(Payload::Order(republished)),
                2_000,
            ),
            "test-resync-republish",
            "ff00ff24",
            1,
        )
        .await;

        assert!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("lookup")
                .is_none(),
            "the republished new-order must not resurrect the wiped row",
        );
        assert!(
            drain_updates(&mut rx, &order_id).is_empty(),
            "no phantom Pending update for a trade deleted on purpose",
        );
        assert_eq!(
            order_book()
                .get_order(&order_id)
                .await
                .expect("book entry kept")
                .status,
            crate::api::types::OrderStatus::InProgress,
            "the book stays fed by the wire, not by the gated resync",
        );
    }

    /// Review round 1: a peer-reveal replay for a wiped trade must not
    /// respawn session or chat state — capture's own terminal guard falls
    /// back to the book, where the republished order reads `pending`.
    ///
    /// `#[ignore]`d for the same reason as
    /// `peer_reveal_capture_is_wired_into_dispatch`: it claims the
    /// process-global app_db and identity. Run with:
    ///   cargo test --lib a_reveal_replay_for_a_wiped_trade -- --ignored
    #[tokio::test]
    #[ignore = "claims the process-global app_db and identity — run with --ignored"]
    async fn a_reveal_replay_for_a_wiped_trade_respawns_no_session() {
        use mostro_core::message::{Action, Payload};

        let db_path =
            std::env::temp_dir().join(format!("mostro-wiped-reveal-{}.db", uuid::Uuid::new_v4()));
        crate::db::app_db::init_db(db_path.to_str().unwrap())
            .await
            .expect("init app db");
        crate::api::identity::import_from_mnemonic(
            "abandon abandon abandon abandon abandon abandon abandon abandon \
             abandon abandon abandon about"
                .split_whitespace()
                .map(String::from)
                .collect(),
            false,
        )
        .await
        .expect("import identity");
        let db = crate::db::app_db::db().expect("db just initialized");

        let trade_index = 4u32;
        let trade_keys = crate::api::identity::get_active_trade_keys(trade_index)
            .await
            .expect("derive trade key");
        let my_hex = trade_keys.public_key().to_hex();
        let peer_hex = nostr_sdk::prelude::Keys::generate().public_key().to_hex();

        let order_uuid = uuid::Uuid::new_v4();
        let order_id = order_uuid.to_string();
        order_book().upsert_order(dummy_order_info(&order_id)).await;
        db.save_trade(&seam_trade_row(
            &order_id,
            crate::api::types::OrderStatus::WaitingPayment,
        ))
        .await
        .expect("save the trade row");

        // The cancel wipes the trade and its session.
        dispatch_mostro_message(
            daemon_message(order_uuid, Action::Canceled, None, 1_000),
            "test-wiped-reveal-cancel",
            &my_hex,
            trade_index,
        )
        .await;
        assert!(session_manager().get_session(&order_id).await.is_none());

        // The replayed reveal (both trade pubkeys, ours as seller) must be
        // skipped before it derives keys or spawns the chat subscription.
        let so = mostro_core::order::SmallOrder::new(
            Some(order_uuid),
            Some(mostro_core::order::Kind::Sell),
            Some(mostro_core::order::Status::Active),
            457,
            "USD".to_string(),
            None,
            None,
            100,
            "Bank".to_string(),
            0,
            Some(peer_hex),
            Some(my_hex.clone()),
            None,
            None,
            None,
        );
        dispatch_mostro_message(
            daemon_message(
                order_uuid,
                Action::BuyerTookOrder,
                Some(Payload::Order(so)),
                2_000,
            ),
            "test-wiped-reveal-replay",
            &my_hex,
            trade_index,
        )
        .await;

        assert!(
            session_manager().get_session(&order_id).await.is_none(),
            "a reveal replay for a wiped trade must not re-create the session",
        );
        assert!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("lookup")
                .is_none(),
            "and must not resurrect the row",
        );
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

        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        let unwrapped = mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(Some(order_uuid), Some(91), None, Action::AddInvoice, None),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::prelude::Timestamp::from(0u64),
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

        let sender = nostr_sdk::prelude::PublicKey::from_hex(&active_mostro_pubkey())
            .expect("valid mostro pubkey");
        let unwrapped = mostro_core::nip59::UnwrappedMessage {
            message: Message::new_order(Some(order_uuid), Some(92), None, Action::AddInvoice, None),
            signature: None,
            sender,
            identity: sender,
            created_at: nostr_sdk::prelude::Timestamp::from(0u64),
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
    //! Set MOSTRO_REGTEST_PUBKEY to your daemon's pubkey (from mostrod's
    //! startup logs); MOSTRO_REGTEST_RELAY overrides the default relay,
    //! ws://localhost:7000.
    use super::*;

    /// Shared regtest setup. Every test here ends up in `derive_trade_key`
    /// (via `create_order`, or as `restore_session`'s reply address), which
    /// refuses to run without durable storage — so a throwaway SQLite file
    /// must be initialised before anything else. `init_db` is a process-wide
    /// no-op after the first call, so tests sharing a process share the first
    /// file; each creates a fresh identity, so that's fine.
    async fn init_regtest() {
        let dbp = std::env::temp_dir().join(format!("e2e-restore-{}.db", uuid::Uuid::new_v4()));
        crate::db::app_db::init_db(dbp.to_str().expect("utf-8 temp path"))
            .await
            .expect("init_db");
        // Point ONLY at the daemon's relay.
        let relay = std::env::var("MOSTRO_REGTEST_RELAY")
            .unwrap_or_else(|_| "ws://localhost:7000".to_string());
        crate::api::nostr::initialize(Some(vec![relay]))
            .await
            .expect("relay pool init");
        let mostro_pk = std::env::var("MOSTRO_REGTEST_PUBKEY").expect(
            "MOSTRO_REGTEST_PUBKEY env var required \
             (your regtest daemon's pubkey, from mostrod's startup logs)",
        );
        crate::config::set_active_mostro_pubkey(Some(mostro_pk));
    }

    #[tokio::test]
    #[ignore = "requires live regtest stack — set MOSTRO_REGTEST_PUBKEY (relay defaults to ws://localhost:7000)"]
    async fn restore_session_roundtrip() {
        init_regtest().await;

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
    #[ignore = "requires live regtest stack — set MOSTRO_REGTEST_PUBKEY (relay defaults to ws://localhost:7000)"]
    async fn trade_then_restore_recovers_order() {
        init_regtest().await;
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

    /// #328 e2e: the highest-index trade is already finalized, so the restore
    /// payload's maximum is a lower bound and only LastTradeIndex carries the
    /// real counter. Mirrors the probe in the issue: order A open at index 1,
    /// order B canceled at index 2 — a fresh install that restores must end
    /// with the counter at the daemon's high-water mark (2) and get its first
    /// new order accepted (index 3), where the payload-only resync of #239
    /// left the counter at 1 and the daemon refused the next order with
    /// CantDo(InvalidTradeIndex).
    #[tokio::test]
    #[ignore = "requires live regtest stack — set MOSTRO_REGTEST_PUBKEY (relay defaults to ws://localhost:7000)"]
    async fn restore_with_finalized_top_index_resyncs_from_last_trade_index() {
        init_regtest().await;

        let id = crate::api::identity::create_identity()
            .await
            .expect("create identity");
        let words = id.mnemonic_words.clone();
        println!("[test] identity pubkey={}", id.public_key);
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;

        let params = |fiat: f64| crate::api::types::NewOrderParams {
            kind: crate::api::types::OrderKind::Sell,
            fiat_amount: Some(fiat),
            fiat_amount_min: None,
            fiat_amount_max: None,
            fiat_code: "USD".to_string(),
            payment_method: "cash".to_string(),
            premium: 0.0,
            amount_sats: None,
        };
        // Distinct fiat amounts keep the two orders visibly distinct in
        // logs and on the regtest book.
        println!("[test] creating order A (index 1)...");
        let order_a = create_order(params(100.0)).await.expect("create order A");
        println!("[test] order A id={}", order_a.id);
        println!("[test] creating order B (index 2)...");
        let order_b = create_order(params(200.0)).await.expect("create order B");
        println!("[test] order B id={}", order_b.id);

        // Finalize the top-index trade: cancel B. cancel_order publishes and
        // returns without waiting for the daemon, so poll B's public Kind
        // 38383 view until the daemon's cancellation lands — the restore
        // below must not see B as pending. (The s-tag is NIP-69's public
        // bucket, never a trade's live status — but the pending→canceled
        // transition is exactly the "daemon processed the cancel" proof this
        // needs, and it is the authoritative, relay-visible one.)
        cancel_order(order_b.id.clone())
            .await
            .expect("cancel order B");
        let mostro_pk =
            nostr_sdk::prelude::PublicKey::from_hex(&crate::config::active_mostro_pubkey())
                .expect("mostro pubkey");
        let client = crate::api::nostr::get_pool().expect("pool").client();
        let b_filter = crate::nostr::order_events::trade_order_filter(&mostro_pk, &order_b.id);
        let start = crate::rt::time::Instant::now();
        loop {
            let canceled = client
                .fetch_events(b_filter.clone())
                .timeout(std::time::Duration::from_secs(2))
                .await
                .ok()
                .and_then(|events| {
                    // Newest first: 38383 is addressable, but don't rely on
                    // the relay's replacement — read the latest snapshot.
                    events
                        .iter()
                        .max_by_key(|ev| ev.created_at)
                        .and_then(|ev| parse_order_event(ev, None))
                })
                .is_some_and(|o| o.status == OrderStatus::Canceled);
            if canceled {
                break;
            }
            assert!(
                start.elapsed() < std::time::Duration::from_secs(15),
                "daemon did not publish order B as canceled within 15s"
            );
            tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        }

        // Fresh install: same mnemonic, counter back to zero.
        crate::api::identity::delete_identity()
            .await
            .expect("delete identity");
        crate::api::identity::import_from_mnemonic(words, false)
            .await
            .expect("re-import identity");
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;

        println!("[test] calling restore_session()...");
        let info = restore_session().await.expect("restore round-trip");
        for o in &info.restore_orders {
            println!(
                "[test]   order_id={} status={} index={}",
                o.order_id, o.status, o.trade_index
            );
        }

        // The canceled order B must be invisible here — that is exactly what
        // makes the payload maximum (1) a lower bound of the daemon counter (2).
        let payload_max = recovered_max_trade_index(&info);
        assert_eq!(
            payload_max,
            Some(1),
            "restore payload should carry only the open order A"
        );

        // The resync floor must have come from LastTradeIndex: with the
        // payload fallback alone the counter would sit at 1.
        let idx = crate::api::identity::get_identity()
            .await
            .expect("get_identity")
            .expect("identity present after restore")
            .trade_key_index;
        assert!(
            idx >= 2,
            "counter ({idx}) must be >= 2 — the LastTradeIndex floor, not the payload bound"
        );

        // And the point of #328: the first post-restore order must be ACCEPTED.
        println!("[test] creating first post-restore order...");
        let order_c = create_order(params(300.0)).await.expect(
            "first post-restore order must be accepted \
             (was CantDo(InvalidTradeIndex) before #328)",
        );
        println!("[test] ✓ post-restore order accepted id={}", order_c.id);
        let idx_after = crate::api::identity::get_identity()
            .await
            .expect("get_identity")
            .expect("identity present")
            .trade_key_index;
        assert_eq!(
            idx_after, 3,
            "the post-restore order should consume index 3"
        );
    }

    /// Poll the in-memory book until `order_id` shows `status`.
    async fn wait_for_book_status(order_id: &str, status: OrderStatus, secs: u64) -> bool {
        for _ in 0..secs * 2 {
            if order_book()
                .get_order(order_id)
                .await
                .is_some_and(|o| o.status == status)
            {
                return true;
            }
            tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        }
        false
    }

    /// Poll until the trade row of `order_id` and its session are both gone,
    /// or `secs` run out; the caller asserts each half. The wipe deletes the
    /// row and then removes the session, in the task handling the daemon's
    /// `Canceled`, so neither can be read the moment another signal shows.
    async fn wait_for_take_wiped(order_id: &str, secs: u64) {
        let db = crate::db::app_db::db().expect("store initialised");
        for _ in 0..secs * 2 {
            let row_gone = db
                .get_trade_by_order_id(order_id)
                .await
                .expect("trade lookup")
                .is_none();
            if row_gone
                && crate::mostro::session::session_manager()
                    .get_session(order_id)
                    .await
                    .is_none()
            {
                return;
            }
            tokio::time::sleep(std::time::Duration::from_millis(500)).await;
        }
    }

    /// Retake E2E, phase 1 of 2: a maker publishes a sell order and prints its
    /// id for phase 2, which must run in its own process — the identity and
    /// `app_db` are process-wide, and the taker needs a different identity.
    ///
    ///   cargo test --lib retake_e2e_maker -- --ignored --nocapture
    ///
    /// The order is real and public on the daemon's relays; it stays `pending`
    /// until the node's `expiration_hours`.
    #[tokio::test]
    #[ignore = "requires live regtest stack — set MOSTRO_REGTEST_PUBKEY (relay defaults to ws://localhost:7000)"]
    async fn retake_e2e_maker_creates_order() {
        init_regtest().await;
        let id = crate::api::identity::create_identity()
            .await
            .expect("create identity");
        println!("[test] maker identity pubkey={}", id.public_key);
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        let order = create_order(crate::api::types::NewOrderParams {
            kind: crate::api::types::OrderKind::Sell,
            fiat_amount: Some(100.0),
            fiat_amount_min: None,
            fiat_amount_max: None,
            fiat_code: "USD".to_string(),
            payment_method: "cash".to_string(),
            premium: 0.0,
            amount_sats: None,
        })
        .await
        .expect("create_order");
        println!("[test] RETAKE_ORDER_ID={}", order.id);
    }

    /// Retake E2E, phase 2 of 2: a taker loses a take by cancelling it, sees
    /// the order back in its book, and takes it again — through the real
    /// `take_order` / `cancel_order` against a live daemon.
    ///
    ///   RETAKE_ORDER_ID=<id from phase 1> \
    ///     cargo test --lib retake_e2e_taker -- --ignored --nocapture
    ///
    /// Before the retake it plants the first take's row and session again,
    /// standing in for what this flow no longer leaves (a `Canceled` never
    /// received, or a row written before takers' cancels were wiped), so
    /// `take_order`'s one-row-per-order rule and its replacement of a stale
    /// session (#335) are exercised too. It ends by cancelling the retake,
    /// which returns the order to `pending` for the next run.
    #[tokio::test]
    #[ignore = "requires live regtest stack and phase 1 — set MOSTRO_REGTEST_PUBKEY and RETAKE_ORDER_ID"]
    async fn retake_e2e_taker_cancels_and_retakes() {
        let order_id = std::env::var("RETAKE_ORDER_ID")
            .expect("RETAKE_ORDER_ID env var required (printed by retake_e2e_maker_creates_order)");
        init_regtest().await;
        let db = crate::db::app_db::db().expect("store initialised");
        let id = crate::api::identity::create_identity()
            .await
            .expect("create identity");
        println!("[test] taker identity pubkey={}", id.public_key);
        tokio::time::sleep(std::time::Duration::from_secs(3)).await;
        subscribe_orders().await;
        assert!(
            wait_for_book_status(&order_id, OrderStatus::Pending, 40).await,
            "the order must be in the book as pending"
        );

        let first = take_order(order_id.clone(), TradeRole::Buyer, None)
            .await
            .expect("first take");
        println!("[test] first take idx={}", first.trade_key_index);
        cancel_order(order_id.clone()).await.expect("cancel the first take");

        // The wipe first: the book is no signal for it. mostrod publishes the
        // `pending` republish before it sends the `Canceled`, and the book
        // feed writes a `pending` straight into the entry, so the book can
        // read `pending` while the row and the session still stand.
        wait_for_take_wiped(&order_id, 40).await;
        assert!(
            db.get_trade_by_order_id(&order_id)
                .await
                .expect("trade lookup")
                .is_none(),
            "the daemon's Canceled must wipe the never-active row"
        );
        assert!(
            crate::mostro::session::session_manager()
                .get_session(&order_id)
                .await
                .is_none(),
            "the daemon's Canceled must remove the take's session"
        );
        assert!(
            wait_for_book_status(&order_id, OrderStatus::Pending, 40).await,
            "a lost take's order must come back to the ex-taker's book"
        );

        db.save_trade(&first).await.expect("plant the first take's row");
        crate::mostro::session::session_manager()
            .install_session(
                order_id.clone(),
                TradeRole::Buyer,
                first.trade_key_index,
                first.order.clone(),
            )
            .await
            .expect("plant the first take's session");
        let second = take_order(order_id.clone(), TradeRole::Buyer, None)
            .await
            .expect("the retake must be accepted");
        println!("[test] retake idx={}", second.trade_key_index);
        assert_ne!(second.trade_key_index, first.trade_key_index);

        let rows: Vec<_> = db
            .list_trades()
            .await
            .expect("list trades")
            .into_iter()
            .filter(|t| t.order.id == order_id)
            .collect();
        assert_eq!(rows.len(), 1, "one row per order after the retake");
        assert_eq!(rows[0].trade_key_index, second.trade_key_index);
        assert_eq!(
            crate::mostro::session::session_manager()
                .get_session(&order_id)
                .await
                .map(|s| s.trade_key_index),
            Some(second.trade_key_index),
            "the session must carry the retake's trade key"
        );

        cancel_order(order_id.clone()).await.expect("cancel the retake");
        assert!(
            wait_for_book_status(&order_id, OrderStatus::Pending, 40).await,
            "the order must be pending again for the next run"
        );
        println!("[test] ✓ retake round-trip OK");
    }
}
