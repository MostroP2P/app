/// Nostr event helpers for Mostro public order book.
///
/// Public orders use Kind 38383 (replaceable parameterised events).
/// This module converts between `OrderInfo` and raw Nostr events.
use nostr_sdk::prelude::*;

use crate::api::types::{OrderInfo, OrderKind, OrderStatus};

/// Kind 38383 — Mostro public order.
pub const KIND_ORDER: u16 = 38383;

/// Parse a Kind 38383 event into an `OrderInfo`.
/// Returns `None` for events that are not valid Mostro orders.
pub fn parse_order_event(event: &Event, my_pubkey: Option<&PublicKey>) -> Option<OrderInfo> {
    if event.kind.as_u16() != KIND_ORDER {
        return None;
    }

    let get = |name: &str| -> Option<String> {
        event
            .tags
            .iter()
            .find(|t| t.as_slice().first().map(|s| s.as_str()) == Some(name))
            .and_then(|t| t.as_slice().get(1).map(|s| s.to_string()))
    };

    let id = get("d")?;
    let kind = match get("k")?.as_str() {
        "buy" => OrderKind::Buy,
        "sell" => OrderKind::Sell,
        _ => return None,
    };
    let status = parse_status(&get("s")?)?;
    let fiat_code = get("f")?;
    let payment_method = get("pm").unwrap_or_default();
    let premium: f64 = get("premium")
        .and_then(|v| v.parse().ok())
        .unwrap_or(0.0);

    let fa_raw = get("fa");
    let fiat_amount: Option<f64> = fa_raw.as_deref().and_then(|v| {
        if v.contains(':') {
            None
        } else {
            v.parse().ok()
        }
    });
    let (fiat_amount_min, fiat_amount_max) = parse_fiat_range(&fa_raw);
    let amount_sats: Option<u64> = get("amt").and_then(|v| v.parse().ok());
    let creator_pubkey = event.pubkey.to_hex();
    let created_at = event.created_at.as_u64() as i64;
    let expires_at: Option<i64> = get("expiration").and_then(|v| v.parse().ok());

    let is_mine = my_pubkey
        .map(|pk| pk == &event.pubkey)
        .unwrap_or(false);

    Some(OrderInfo {
        id,
        kind,
        status,
        amount_sats,
        fiat_amount,
        fiat_amount_min,
        fiat_amount_max,
        fiat_code,
        payment_method,
        premium,
        creator_pubkey,
        created_at,
        expires_at,
        is_mine,
    })
}

fn parse_status(s: &str) -> Option<OrderStatus> {
    match s {
        "Pending" => Some(OrderStatus::Pending),
        "WaitingBuyerInvoice" => Some(OrderStatus::WaitingBuyerInvoice),
        "WaitingPayment" => Some(OrderStatus::WaitingPayment),
        "Active" => Some(OrderStatus::Active),
        "FiatSent" => Some(OrderStatus::FiatSent),
        "SettledHoldInvoice" => Some(OrderStatus::SettledHoldInvoice),
        "Success" => Some(OrderStatus::Success),
        "Canceled" => Some(OrderStatus::Canceled),
        "Expired" => Some(OrderStatus::Expired),
        "CanceledByAdmin" => Some(OrderStatus::CanceledByAdmin),
        "SettledByAdmin" => Some(OrderStatus::SettledByAdmin),
        "CompletedByAdmin" => Some(OrderStatus::CompletedByAdmin),
        "Dispute" => Some(OrderStatus::Dispute),
        "InProgress" => Some(OrderStatus::InProgress),
        _ => None,
    }
}

/// Parse a range from the `fa` tag. Format: `"min:max"` or plain `"amount"`.
fn parse_fiat_range(raw: &Option<String>) -> (Option<f64>, Option<f64>) {
    let Some(v) = raw else { return (None, None) };
    if let Some((min, max)) = v.split_once(':') {
        (min.parse().ok(), max.parse().ok())
    } else {
        (None, None)
    }
}

/// Build a filter for Kind 38383 events with status=Pending.
pub fn pending_orders_filter() -> Filter {
    Filter::new()
        .kind(Kind::from(KIND_ORDER))
        .custom_tag(SingleLetterTag::lowercase(Alphabet::S), "Pending")
}
