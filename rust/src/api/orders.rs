/// Orders API — read path for the public order book.
///
/// Subscribes to Kind 38383 events from the relay pool, caches locally,
/// applies filters, and exposes a stream for UI updates.
use anyhow::Result;
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};

use crate::api::types::{NewOrderParams, OrderInfo, OrderKind, OrderStatus};
use crate::config::DEFAULT_MOSTRO_PUBKEY;
use crate::mostro::actions;
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

/// Create a new order on the Mostro network.
///
/// Validates params, builds the MostroMessage, wraps via NIP-59, and
/// publishes to relays. Queues if offline.
///
/// TODO: Wire to actual Rust bridge identity + relay pool in Phase 7.
/// Currently validates params and returns a mock OrderInfo.
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
        creator_pubkey: String::new(), // filled by identity in Phase 7
        created_at: now,
        expires_at: Some(now + 24 * 3600),
        is_mine: true,
    };

    // Cache locally
    order_book().upsert_order(order.clone()).await;

    Ok(order)
}

/// Take an existing order, starting a trade.
///
/// Sends a `take-buy` or `take-sell` MostroMessage via NIP-59.
/// Returns a `TradeInfo` with the initial trade state.
///
/// TODO: Wire to actual Rust bridge identity + relay pool in Phase 8+.
/// Currently validates params and returns a mock TradeInfo.
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

    // Validate range amount.
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

    // Validate role matches order kind.
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

    let initial_step = match role {
        TradeRole::Buyer => TradeStep::Buyer(BuyerStep::OrderTaken),
        TradeRole::Seller => TradeStep::Seller(SellerStep::TakerFound),
    };

    let trade = TradeInfo {
        id: uuid::Uuid::new_v4().to_string(),
        order: order.clone(),
        role,
        counterparty_pubkey: order.creator_pubkey.clone(),
        current_step: initial_step,
        hold_invoice: None,
        buyer_invoice: None,
        trade_key_index: 0,
        cooperative_cancel_state: None,
        timeout_at: Some(now + 900), // 15 min default
        started_at: now,
        completed_at: None,
        outcome: None,
    };

    Ok(trade)
}

/// Submit buyer's Lightning invoice for a trade.
///
/// Sends an `AddInvoice` MostroMessage to the daemon.
///
/// TODO: Wire to actual NIP-59 message dispatch in Phase 9+.
pub async fn send_invoice(
    order_id: String,
    invoice_or_address: String,
    amount_sats: u64,
) -> Result<()> {
    if invoice_or_address.trim().is_empty() {
        return Err(anyhow::anyhow!("Invoice or address must not be empty"));
    }
    if amount_sats == 0 {
        return Err(anyhow::anyhow!("Amount must be greater than zero"));
    }

    let order = order_book()
        .get_order(&order_id)
        .await
        .ok_or_else(|| anyhow::anyhow!("OrderNotFound"))?;

    if order.status != OrderStatus::WaitingBuyerInvoice
        && order.status != OrderStatus::Pending
    {
        return Err(anyhow::anyhow!("WrongTradeState"));
    }

    // TODO: Build AddInvoice MostroMessage, wrap via NIP-59, publish.
    Err(anyhow::anyhow!("NotImplemented: AddInvoice dispatch not wired yet"))
}

/// Mark fiat payment as sent by the buyer.
///
/// Sends a `FiatSent` MostroMessage to the Mostro daemon.
///
/// Not yet implemented — requires NIP-59 message dispatch.
pub async fn send_fiat_sent(order_id: String) -> Result<()> {
    let order = order_book()
        .get_order(&order_id)
        .await
        .ok_or_else(|| anyhow::anyhow!("OrderNotFound"))?;

    if order.status != OrderStatus::Active {
        return Err(anyhow::anyhow!("WrongTradeState"));
    }

    // Build FiatSent MostroMessage wrapped via NIP-59.
    let sender_keys = crate::api::identity::get_active_keys().await?;
    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(DEFAULT_MOSTRO_PUBKEY)?;
    let _event_json = actions::fiat_sent(&sender_keys, &mostro_pubkey, &order_id).await?;

    // TODO(Phase 10+): Publish event_json to relay pool once connected.

    Ok(())
}

/// Seller confirms fiat received and releases escrowed sats.
///
/// Sends a `Release` MostroMessage to the Mostro daemon.
/// Transitions trade status: FiatSent → SettledHoldInvoice → Success.
///
/// Not yet implemented — requires NIP-59 message dispatch.
pub async fn release_order(order_id: String) -> Result<()> {
    let order = order_book()
        .get_order(&order_id)
        .await
        .ok_or_else(|| anyhow::anyhow!("OrderNotFound"))?;

    if order.status != OrderStatus::FiatSent {
        return Err(anyhow::anyhow!("WrongTradeState"));
    }

    // Build Release MostroMessage wrapped via NIP-59.
    let sender_keys = crate::api::identity::get_active_keys().await?;
    let mostro_pubkey = nostr_sdk::PublicKey::from_hex(DEFAULT_MOSTRO_PUBKEY)?;
    let _event_json = actions::release(&sender_keys, &mostro_pubkey, &order_id).await?;

    // TODO(Phase 10+): Publish event_json to relay pool once connected.
    // On success, daemon transitions to SettledHoldInvoice → Success.

    Ok(())
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
