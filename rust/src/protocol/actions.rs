/// Protocol action builders — construct Mostro protocol messages wrapped in
/// NIP-59 Gift Wrap events, ready for publishing to Nostr relays.
///
/// per research R3 and mostro-core 0.8.0.
use anyhow::Result;
use mostro_core::message::{Action, Message, Payload};
use nostr_sdk::{Event, Keys, PublicKey};
use uuid::Uuid;

use crate::protocol::gift_wrap;

// ─── Order Actions ────────────────────────────────────────────────────────────

/// Build a NewOrder message to publish a buy or sell order.
pub async fn build_new_order(
    order: mostro_core::order::SmallOrder,
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
) -> Result<Event> {
    let msg = Message::new_order(
        None,
        None,
        None,
        Action::NewOrder,
        Some(Payload::Order(order)),
    );
    gift_wrap::wrap_mostro_message(&msg, sender_keys, mostro_pubkey).await
}

/// Build a TakeSell message — buyer takes a sell order.
pub async fn take_sell(
    order_id: Uuid,
    trade_index: Option<i64>,
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
) -> Result<Event> {
    let msg = Message::new_order(
        Some(order_id),
        None,
        trade_index,
        Action::TakeSell,
        None,
    );
    gift_wrap::wrap_mostro_message(&msg, sender_keys, mostro_pubkey).await
}

/// Build a TakeBuy message — seller takes a buy order.
pub async fn take_buy(
    order_id: Uuid,
    trade_index: Option<i64>,
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
) -> Result<Event> {
    let msg = Message::new_order(
        Some(order_id),
        None,
        trade_index,
        Action::TakeBuy,
        None,
    );
    gift_wrap::wrap_mostro_message(&msg, sender_keys, mostro_pubkey).await
}

/// Build an AddInvoice message — buyer submits a Lightning invoice.
pub async fn add_invoice(
    order_id: Uuid,
    bolt11: &str,
    trade_index: Option<i64>,
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
) -> Result<Event> {
    let msg = Message::new_order(
        Some(order_id),
        None,
        trade_index,
        Action::AddInvoice,
        Some(Payload::PaymentRequest(None, bolt11.to_string(), None)),
    );
    gift_wrap::wrap_mostro_message(&msg, sender_keys, mostro_pubkey).await
}

/// Build a FiatSent message — buyer confirms fiat payment sent.
pub async fn fiat_sent(
    order_id: Uuid,
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
) -> Result<Event> {
    let msg = Message::new_order(Some(order_id), None, None, Action::FiatSent, None);
    gift_wrap::wrap_mostro_message(&msg, sender_keys, mostro_pubkey).await
}

/// Build a Release message — seller confirms fiat received, releases Bitcoin.
pub async fn release(
    order_id: Uuid,
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
) -> Result<Event> {
    let msg = Message::new_order(Some(order_id), None, None, Action::Release, None);
    gift_wrap::wrap_mostro_message(&msg, sender_keys, mostro_pubkey).await
}

/// Build a Cancel message — creator cancels their own pending/untaken order.
pub async fn cancel(
    order_id: Uuid,
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
) -> Result<Event> {
    let msg = Message::new_order(Some(order_id), None, None, Action::Cancel, None);
    gift_wrap::wrap_mostro_message(&msg, sender_keys, mostro_pubkey).await
}

/// Build a Dispute message — either party raises a dispute.
pub async fn dispute(
    order_id: Uuid,
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
) -> Result<Event> {
    let msg = Message::new_order(Some(order_id), None, None, Action::Dispute, None);
    gift_wrap::wrap_mostro_message(&msg, sender_keys, mostro_pubkey).await
}

/// Build a Rate message — submit a reputation rating after trade success.
pub async fn rate(
    order_id: Uuid,
    rating: u8,
    sender_keys: &Keys,
    mostro_pubkey: &PublicKey,
) -> Result<Event> {
    let msg = Message::new_order(
        Some(order_id),
        None,
        None,
        Action::RateUser,
        Some(Payload::RatingUser(rating)),
    );
    gift_wrap::wrap_mostro_message(&msg, sender_keys, mostro_pubkey).await
}

/// Build a RestoreSession message — request recovery of past orders from mnemonic.
pub async fn restore(sender_keys: &Keys, mostro_pubkey: &PublicKey) -> Result<Event> {
    let msg = Message::new_restore(None);
    gift_wrap::wrap_mostro_message(&msg, sender_keys, mostro_pubkey).await
}

// ─── P2P Chat ─────────────────────────────────────────────────────────────────

/// Build a peer-to-peer DM message wrapped in NIP-59 Gift Wrap.
/// Chat during trades uses sendDm action addressed to the counterparty.
pub async fn chat_message(
    trade_id: Uuid,
    content: &str,
    sender_keys: &Keys,
    recipient_pubkey: &PublicKey,
) -> Result<Event> {
    let msg = Message::new_dm(
        Some(trade_id),
        None,
        Action::SendDm,
        Some(Payload::TextMessage(content.to_string())),
    );
    gift_wrap::wrap_mostro_message(&msg, sender_keys, recipient_pubkey).await
}
