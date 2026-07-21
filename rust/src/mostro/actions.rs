/// Mostro action dispatch — builds and wraps `mostro_core::Message` values.
///
/// Each function constructs a `Message` using the `mostro-core` types,
/// wraps it via NIP-59 Gift Wrap using `mostro_core::nip59::wrap_message`,
/// and returns the event JSON ready for publication.
///
/// **Key split.** Mostro-core 0.10 requires two `Keys` values per wrap:
/// `identity_keys` sign the Seal (Kind 13) so the node can tie the rumor to
/// a long-lived pubkey for reputation purposes, while `trade_keys` author
/// the rumor (Kind 1) and produce the inner tuple signature. Callers who
/// want "full-privacy mode" (no reputation) pass `trade_keys` for both
/// arguments — see `api::identity::get_transport_identity_keys`, which
/// applies the runtime privacy toggle.
use anyhow::Result;
use mostro_core::message::{Action, Message, Payload};
use nostr_sdk::prelude::*;
use uuid::Uuid;

use crate::api::types::{NewOrderParams, OrderKind};
use crate::nostr::gift_wrap;

// ── Public action builders ────────────────────────────────────────────────────

/// Build and wrap a NewOrder MostroMessage.
///
/// `request_id` is a caller-generated correlation nonce: the daemon echoes it
/// in the `NewOrder` confirmation and in any `CantDo` rejection, which is how
/// `create_order` tells the genuine reply apart from stale relay-replayed
/// events addressed to the same trade key.
///
/// Returns the NIP-59 Gift Wrap event JSON ready for publication.
pub async fn new_order(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    params: &NewOrderParams,
    trade_index: u32,
    request_id: u64,
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
    let msg = Message::new_order(
        None,
        Some(request_id),
        Some(trade_index as i64),
        Action::NewOrder,
        payload,
    );
    wrap_message(identity_keys, trade_keys, mostro_pubkey, &msg).await
}

/// Build and wrap a TakeBuy MostroMessage.
///
/// `request_id` is the correlation nonce echoed by the daemon in its reply —
/// see [`take_order_impl`].
#[allow(clippy::too_many_arguments)]
pub async fn take_buy(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    amount: Option<f64>,
    request_id: u64,
) -> Result<String> {
    take_order_impl(
        identity_keys,
        trade_keys,
        mostro_pubkey,
        order_id,
        trade_index,
        amount,
        None,
        Action::TakeBuy,
        request_id,
    )
    .await
}

/// Build and wrap a TakeSell MostroMessage.
///
/// If `ln_address` is `Some`, it is included in the payload so Mostro can
/// pay the buyer directly (take-sell-ln-address variant). `request_id` is the
/// correlation nonce echoed by the daemon in its reply — see
/// [`take_order_impl`].
#[allow(clippy::too_many_arguments)]
pub async fn take_sell(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    amount: Option<f64>,
    ln_address: Option<&str>,
    request_id: u64,
) -> Result<String> {
    take_order_impl(
        identity_keys,
        trade_keys,
        mostro_pubkey,
        order_id,
        trade_index,
        amount,
        ln_address,
        Action::TakeSell,
        request_id,
    )
    .await
}

/// Build and wrap a FiatSent MostroMessage.
pub async fn fiat_sent(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
) -> Result<String> {
    simple_action(
        identity_keys,
        trade_keys,
        mostro_pubkey,
        order_id,
        trade_index,
        Action::FiatSent,
    )
    .await
}

/// Build and wrap a Release MostroMessage.
pub async fn release(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
) -> Result<String> {
    simple_action(
        identity_keys,
        trade_keys,
        mostro_pubkey,
        order_id,
        trade_index,
        Action::Release,
    )
    .await
}

/// Build and wrap a Cancel MostroMessage.
pub async fn cancel(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
) -> Result<String> {
    simple_action(
        identity_keys,
        trade_keys,
        mostro_pubkey,
        order_id,
        trade_index,
        Action::Cancel,
    )
    .await
}

/// Build and wrap a Dispute MostroMessage.
pub async fn dispute(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
) -> Result<String> {
    simple_action(
        identity_keys,
        trade_keys,
        mostro_pubkey,
        order_id,
        trade_index,
        Action::Dispute,
    )
    .await
}

/// Build and wrap a RateUser MostroMessage.
///
/// Sends a 1–5 star rating for the counterparty to the Mostro daemon via
/// NIP-59 Gift Wrap after a trade completes.
pub async fn rate_user(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    score: u8,
) -> Result<String> {
    let id = Uuid::parse_str(order_id)?;
    let payload = Some(Payload::RatingUser(score));
    let msg = Message::new_order(
        Some(id),
        None,
        Some(trade_index as i64),
        Action::RateUser,
        payload,
    );
    wrap_message(identity_keys, trade_keys, mostro_pubkey, &msg).await
}

/// Build and wrap an AddInvoice MostroMessage (buyer submits Lightning invoice
/// or LN address).
///
/// For bolt11 invoices the amount is already encoded in the invoice itself, so
/// the third payload field is `None`.  For Lightning Addresses Mostro needs the
/// sats amount in the payload so it can resolve the address and generate the
/// invoice on behalf of the buyer — pass it via `amount_sats`.
///
/// `request_id` is the correlation nonce the daemon echoes in its reply
/// (progression message or CantDo); `send_invoice` relies on it to tell the
/// genuine reply apart from stale relay-replayed events.
#[allow(clippy::too_many_arguments)]
pub async fn add_invoice(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    invoice: &str,
    amount_sats: Option<u64>,
    request_id: u64,
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
        Some(request_id),
        Some(trade_index as i64),
        Action::AddInvoice,
        payload,
    );
    wrap_message(identity_keys, trade_keys, mostro_pubkey, &msg).await
}

// ── Helpers ───────────────────────────────────────────────────────────────────

/// Internal helper for take-buy / take-sell actions.
///
/// `request_id` is the caller-generated correlation nonce: the daemon echoes
/// it in its reply (add-invoice, pay-invoice, pay-bond-invoice, or CantDo),
/// which is how `take_order` tells the genuine reply apart from stale
/// relay-replayed events addressed to the same trade key.
#[allow(clippy::too_many_arguments)]
async fn take_order_impl(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    amount: Option<f64>,
    ln_address: Option<&str>,
    action: Action,
    request_id: u64,
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
        Some(request_id),
        Some(trade_index as i64),
        action,
        payload,
    );
    wrap_message(identity_keys, trade_keys, mostro_pubkey, &msg).await
}

/// Helper for actions that only need an order ID and no additional payload.
async fn simple_action(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    order_id: &str,
    trade_index: u32,
    action: Action,
) -> Result<String> {
    let id = Uuid::parse_str(order_id)?;
    let msg = Message::new_order(Some(id), None, Some(trade_index as i64), action, None);
    wrap_message(identity_keys, trade_keys, mostro_pubkey, &msg).await
}

/// Wrap `msg` as a NIP-59 Gift Wrap via `mostro_core::nip59::wrap_message`,
/// applying the daemon-advertised PoW difficulty, and return the event JSON.
async fn wrap_message(
    identity_keys: &Keys,
    trade_keys: &Keys,
    mostro_pubkey: &PublicKey,
    msg: &Message,
) -> Result<String> {
    let pow = crate::mostro::pow::get_pow();
    let event =
        gift_wrap::wrap_mostro_message(identity_keys, trade_keys, mostro_pubkey, msg, pow).await?;
    Ok(event.as_json())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The outgoing new-order message must carry the caller's request_id —
    /// it is the correlation nonce the daemon echoes in its reply, and
    /// `create_order` relies on it to tell the genuine reply apart from
    /// stale relay-replayed events.
    #[tokio::test]
    async fn new_order_carries_request_id_and_trade_index() {
        let identity_keys = Keys::generate();
        let trade_keys = Keys::generate();
        let mostro_keys = Keys::generate();

        let params = NewOrderParams {
            kind: OrderKind::Sell,
            fiat_amount: Some(100.0),
            fiat_amount_min: None,
            fiat_amount_max: None,
            fiat_code: "USD".to_string(),
            payment_method: "cashapp".to_string(),
            premium: 0.0,
            amount_sats: None,
        };

        let json = new_order(
            &identity_keys,
            &trade_keys,
            &mostro_keys.public_key(),
            &params,
            3,
            42,
        )
        .await
        .unwrap();

        let event = Event::from_json(&json).unwrap();
        let unwrapped = gift_wrap::unwrap_mostro_message(&mostro_keys, &event)
            .await
            .unwrap()
            .expect("message must decrypt for the recipient");

        let kind = unwrapped.message.get_inner_message_kind();
        assert_eq!(kind.request_id, Some(42));
        assert_eq!(kind.trade_index, Some(3));
        assert!(matches!(kind.action, Action::NewOrder));
    }

    /// The outgoing take messages must carry the caller's request_id — the
    /// correlation nonce the daemon echoes in its reply (add-invoice,
    /// pay-invoice, pay-bond-invoice, or CantDo) that `take_order` relies on
    /// to tell the genuine reply apart from stale relay-replayed events.
    #[tokio::test]
    async fn take_messages_carry_request_id_and_order_id() {
        let identity_keys = Keys::generate();
        let trade_keys = Keys::generate();
        let mostro_keys = Keys::generate();
        let order_id = "94486ae3-4083-4dfe-b543-53fe761025e9";

        let json = take_sell(
            &identity_keys,
            &trade_keys,
            &mostro_keys.public_key(),
            order_id,
            5,
            None,
            None,
            77,
        )
        .await
        .unwrap();

        let event = Event::from_json(&json).unwrap();
        let unwrapped = gift_wrap::unwrap_mostro_message(&mostro_keys, &event)
            .await
            .unwrap()
            .expect("message must decrypt for the recipient");

        let kind = unwrapped.message.get_inner_message_kind();
        assert_eq!(kind.request_id, Some(77));
        assert_eq!(kind.trade_index, Some(5));
        assert_eq!(kind.id.map(|u| u.to_string()).as_deref(), Some(order_id));
        assert!(matches!(kind.action, Action::TakeSell));

        let json = take_buy(
            &identity_keys,
            &trade_keys,
            &mostro_keys.public_key(),
            order_id,
            6,
            Some(100.0),
            78,
        )
        .await
        .unwrap();

        let event = Event::from_json(&json).unwrap();
        let unwrapped = gift_wrap::unwrap_mostro_message(&mostro_keys, &event)
            .await
            .unwrap()
            .expect("message must decrypt for the recipient");

        let kind = unwrapped.message.get_inner_message_kind();
        assert_eq!(kind.request_id, Some(78));
        assert!(matches!(kind.action, Action::TakeBuy));
        assert!(matches!(kind.payload, Some(Payload::Amount(100))));
    }
}

/// Build a `RestoreSession` request (mostro-core `Message::new_restore`).
///
/// Payload MUST be `None` — the daemon rejects any other payload
/// (`MessageKind::verify`). Sent from the IDENTITY key, not a derived trade
/// key: the daemon's restore_session handler replies to the requesting
/// (identity) pubkey. Returns the NIP-59 Gift Wrap event JSON.
pub async fn restore_session(
    identity_keys: &Keys,
    mostro_pubkey: &PublicKey,
) -> Result<String> {
    let msg = Message::new_restore(None);
    wrap_message(identity_keys, identity_keys, mostro_pubkey, &msg).await
}
