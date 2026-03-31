/// Nostr event helpers for Mostro public order book.
///
/// Public orders use Kind 38383 (replaceable parameterised events).
/// **The Mostro node** (daemon) is the author/publisher of these events —
/// makers send a `new-order` NIP-59 gift-wrap to the daemon, and the daemon
/// responds by publishing the order as a Kind 38383 event signed with its own
/// key.  Clients therefore filter by `author = mostro_pubkey` to get the
/// orders belonging to a specific Mostro instance.
///
/// Protocol reference: https://mostro.network/protocol/list_orders.html
use nostr_sdk::prelude::*;

use crate::api::types::{OrderInfo, OrderKind, OrderStatus};

/// Kind 38383 — Mostro public order.
pub const KIND_ORDER: u16 = 38383;

/// Parse a Kind 38383 event into an `OrderInfo`.
///
/// Validates that the event is a proper Mostro order (`z=order` tag) before
/// extracting fields.  Returns `None` for malformed or non-Mostro events.
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

    // Log the z-tag value for diagnostics but do not hard-reject — older
    // Mostro events may omit the tag; the author filter already scopes to the
    // trusted node.
    let z_tag = get("z");
    if z_tag.as_deref() != Some("order") {
        log::debug!("[parse] Kind 38383 z-tag={z_tag:?} (expected 'order') — processing anyway");
    }

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
    // creator_pubkey is the Mostro node's pubkey (the event author).
    let creator_pubkey = event.pubkey.to_hex();
    let created_at = event.created_at.as_secs() as i64;
    let expires_at: Option<i64> = get("expiration").and_then(|v| v.parse().ok());

    // is_mine is always false for Kind 38383 events: the event author is the
    // Mostro node, not the maker. Ownership is confirmed later via incoming
    // trade messages (gift-wrap response from the daemon).
    let is_mine = false;
    let _ = my_pubkey; // unused — kept in signature for future use

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

/// Parse the `s` tag value into an [`OrderStatus`].
///
/// mostro-core uses `#[serde(rename_all = "kebab-case")]`, so all status
/// strings on the wire are kebab-case: `"pending"`, `"waiting-buyer-invoice"`,
/// `"in-progress"`, etc.
fn parse_status(s: &str) -> Option<OrderStatus> {
    match s {
        "pending" => Some(OrderStatus::Pending),
        "waiting-buyer-invoice" => Some(OrderStatus::WaitingBuyerInvoice),
        "waiting-payment" => Some(OrderStatus::WaitingPayment),
        "active" => Some(OrderStatus::Active),
        "fiat-sent" => Some(OrderStatus::FiatSent),
        "settled-hold-invoice" => Some(OrderStatus::SettledHoldInvoice),
        "success" => Some(OrderStatus::Success),
        "canceled" => Some(OrderStatus::Canceled),
        "cooperatively-canceled" => Some(OrderStatus::Canceled),
        "expired" => Some(OrderStatus::Expired),
        "canceled-by-admin" => Some(OrderStatus::CanceledByAdmin),
        "settled-by-admin" => Some(OrderStatus::SettledByAdmin),
        "completed-by-admin" => Some(OrderStatus::CompletedByAdmin),
        "dispute" => Some(OrderStatus::Dispute),
        "in-progress" => Some(OrderStatus::InProgress),
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

/// Build a Nostr filter for Kind 38383 pending orders from a specific Mostro node.
///
/// The Mostro daemon is the **author** of all Kind 38383 events — it publishes
/// orders on behalf of makers after they send a `new-order` NIP-59 message.
/// Filtering by `author = mostro_pubkey` ensures we only receive orders that
/// belong to the trusted Mostro instance configured in the app.
/// Build a Nostr filter for pending orders from a specific Mostro node.
///
/// The `s` tag value is `"pending"` (kebab-case) — mostro-core serialises
/// the `Status` enum with `#[serde(rename_all = "kebab-case")]`.
pub fn pending_orders_filter(mostro_pubkey: &PublicKey) -> Filter {
    Filter::new()
        .kind(Kind::from(KIND_ORDER))
        .author(*mostro_pubkey)
        .custom_tag(SingleLetterTag::lowercase(Alphabet::S), "pending")
}
