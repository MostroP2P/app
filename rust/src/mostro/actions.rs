/// Mostro action dispatch — builds and wraps MostroMessages.
///
/// Each function constructs a `MostroMessage` JSON payload using the
/// `mostro-core` types and wraps it via NIP-59 Gift Wrap, returning the
/// event JSON ready for publication.
///
/// Wire format: `[{"order":{...}}, null]` — a JSON-serialised
/// `(Message, Option<Peer>)` tuple where the second element is always `null`
/// (no peer info is sent by the client).
use anyhow::Result;
use mostro_core::message::{Action, Message, Payload};
use nostr_sdk::prelude::*;
use uuid::Uuid;

use crate::api::types::{NewOrderParams, OrderKind};
use crate::nostr::gift_wrap;
use crate::nostr::order_events::KIND_ORDER;

// ── Public action builders ────────────────────────────────────────────────────

/// Build and wrap a NewOrder MostroMessage.
///
/// Returns the NIP-59 Gift Wrap event JSON ready for publication.
pub async fn new_order(
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
    params: &NewOrderParams,
    trade_index: u32,
) -> Result<String> {
    use mostro_core::order::{Kind, SmallOrder, Status};

    let kind = match params.kind {
        OrderKind::Buy => Kind::Buy,
        OrderKind::Sell => Kind::Sell,
    };

    let fiat_amount = params.fiat_amount.unwrap_or(0.0) as i64;
    let fiat_amount_min = params.fiat_amount_min.map(|v| v as i64);
    let fiat_amount_max = params.fiat_amount_max.map(|v| v as i64);
    let premium = params.premium as i64;

    let small_order = SmallOrder::new(
        None,
        Some(kind),
        Some(Status::Pending),
        params.amount_sats.unwrap_or(0) as i64,
        params.fiat_code.clone(),
        fiat_amount_min,
        fiat_amount_max,
        fiat_amount,
        params.payment_method.clone(),
        premium,
        None,
        None,
        None,
        None,
        None,
    );

    let payload = Some(Payload::Order(small_order));
    let msg = Message::new_order(None, None, Some(trade_index as i64), Action::NewOrder, payload);
    wrap_message(sender_keys, mostro_pubkey, msg).await
}

/// Build and wrap a TakeBuy MostroMessage.
pub async fn take_buy(
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    amount: Option<f64>,
) -> Result<String> {
    take_order_impl(
        sender_keys,
        mostro_pubkey,
        order_id,
        trade_index,
        amount,
        None,
        Action::TakeBuy,
    )
    .await
}

/// Build and wrap a TakeSell MostroMessage.
///
/// If `ln_address` is `Some`, it is included in the payload so Mostro can
/// pay the buyer directly (take-sell-ln-address variant).
pub async fn take_sell(
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    amount: Option<f64>,
    ln_address: Option<&str>,
) -> Result<String> {
    take_order_impl(
        sender_keys,
        mostro_pubkey,
        order_id,
        trade_index,
        amount,
        ln_address,
        Action::TakeSell,
    )
    .await
}

/// Build and wrap a FiatSent MostroMessage.
pub async fn fiat_sent(
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
) -> Result<String> {
    simple_action(sender_keys, mostro_pubkey, order_id, trade_index, Action::FiatSent).await
}

/// Build and wrap a Release MostroMessage.
pub async fn release(
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
) -> Result<String> {
    simple_action(sender_keys, mostro_pubkey, order_id, trade_index, Action::Release).await
}

/// Build and wrap a Cancel MostroMessage.
pub async fn cancel(
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
) -> Result<String> {
    simple_action(sender_keys, mostro_pubkey, order_id, trade_index, Action::Cancel).await
}

/// Build and wrap an AddInvoice MostroMessage (buyer submits Lightning invoice
/// or LN address).
///
/// For bolt11 invoices the amount is already encoded in the invoice itself, so
/// the third payload field is `None`.  For Lightning Addresses Mostro needs the
/// sats amount in the payload so it can resolve the address and generate the
/// invoice on behalf of the buyer — pass it via `amount_sats`.
pub async fn add_invoice(
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    invoice: &str,
    amount_sats: Option<u64>,
) -> Result<String> {
    let id = Uuid::parse_str(order_id)?;
    // A Lightning Address contains '@'; a bolt11 invoice does not.
    let is_ln_address = invoice.contains('@');
    let amount_field: Option<i64> = if is_ln_address {
        amount_sats.map(|a| a as i64)
    } else {
        None
    };
    let payload = Some(Payload::PaymentRequest(None, invoice.to_string(), amount_field));
    let msg = Message::new_order(
        Some(id),
        None,
        Some(trade_index as i64),
        Action::AddInvoice,
        payload,
    );
    wrap_message(sender_keys, mostro_pubkey, msg).await
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Internal helper for take-buy / take-sell actions.
async fn take_order_impl(
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    amount: Option<f64>,
    ln_address: Option<&str>,
    action: Action,
) -> Result<String> {
    let id = Uuid::parse_str(order_id)?;

    let payload = match (amount, ln_address) {
        // LN address + optional range amount
        (amt, Some(addr)) => Some(Payload::PaymentRequest(
            None,
            addr.to_string(),
            amt.map(|a| a as i64),
        )),
        // Range amount only (no LN address)
        (Some(amt), None) => Some(Payload::Amount(amt as i64)),
        // Standard fixed-amount take
        (None, None) => None,
    };

    let msg = Message::new_order(
        Some(id),
        None,
        Some(trade_index as i64),
        action,
        payload,
    );
    wrap_message(sender_keys, mostro_pubkey, msg).await
}

/// Helper for actions that only need an order ID and no additional payload.
async fn simple_action(
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    action: Action,
) -> Result<String> {
    let id = Uuid::parse_str(order_id)?;
    let msg = Message::new_order(Some(id), None, Some(trade_index as i64), action, None);
    wrap_message(sender_keys, mostro_pubkey, msg).await
}

/// Serialise `msg` as `[message, null]` (Mostro wire format), then wrap via
/// NIP-59 Gift Wrap.
async fn wrap_message(
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
    msg: Message,
) -> Result<String> {
    let json = serde_json::to_string(&(msg, Option::<mostro_core::message::Peer>::None))?;
    gift_wrap::wrap(sender_keys, mostro_pubkey, &json, Kind::from(KIND_ORDER)).await
}
