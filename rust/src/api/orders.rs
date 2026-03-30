/// Orders API — read path for the public order book.
///
/// Subscribes to Kind 38383 events from the relay pool, caches locally,
/// applies filters, and exposes a stream for UI updates.
use anyhow::Result;
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};

use crate::api::types::{OrderInfo, OrderKind, OrderStatus};
use crate::nostr::order_events::parse_order_event;

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

    pub fn subscribe(&self) -> broadcast::Receiver<Vec<OrderInfo>> {
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
pub async fn process_order_event(event: &nostr_sdk::Event, my_pubkey: Option<&nostr_sdk::PublicKey>) {
    if let Some(order) = parse_order_event(event, my_pubkey) {
        order_book().upsert_order(order).await;
    }
}
