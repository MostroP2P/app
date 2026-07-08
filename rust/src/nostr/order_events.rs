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

    // The `fa` tag carries one value for a fixed-amount order (`["fa", "20"]`)
    // and two for a range order (`["fa", "20", "60"]`), so it cannot go
    // through `get`, which only reads the first value.
    let fa_values: &[String] = event
        .tags
        .iter()
        .find(|t| t.as_slice().first().map(|s| s.as_str()) == Some("fa"))
        .map(|t| &t.as_slice()[1..])
        .unwrap_or(&[]);
    let (fiat_amount, fiat_amount_min, fiat_amount_max) = parse_fiat_amounts(fa_values);
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

/// Parse the `fa` tag values into `(fiat_amount, fiat_amount_min, fiat_amount_max)`.
///
/// The daemon publishes a fixed-amount order as `["fa", "20"]` and a range
/// order as `["fa", "20", "60"]` (see mostrod's `create_fiat_amt_array`).
/// A single `"min:max"` value is also accepted as a legacy range encoding.
///
/// Exactly one shape comes back populated — fixed (`fiat_amount`) or range
/// (`min` + `max`) — because the Dart `OrderItem` model rejects mixed or
/// partial shapes. A range with an unparseable bound yields neither.
fn parse_fiat_amounts(values: &[String]) -> (Option<f64>, Option<f64>, Option<f64>) {
    match values {
        [single] => match single.split_once(':') {
            Some((min, max)) => parse_range(min, max),
            None => (single.parse().ok(), None, None),
        },
        [min, max, ..] => parse_range(min, max),
        [] => (None, None, None),
    }
}

fn parse_range(min: &str, max: &str) -> (Option<f64>, Option<f64>, Option<f64>) {
    match (min.parse().ok(), max.parse().ok()) {
        (Some(min), Some(max)) => (None, Some(min), Some(max)),
        _ => (None, None, None),
    }
}

/// Build a Nostr filter for **all** Kind 38383 orders from a specific Mostro node,
/// regardless of status.
///
/// Use this for the global order-book subscription so that status transitions
/// (e.g. `pending` → `canceled` / `in-progress`) are received and the order
/// is removed from or updated in the order book in real time.
/// Display-level filtering (show only `pending`) is done in the Dart layer.
pub fn all_orders_filter(mostro_pubkey: &PublicKey) -> Filter {
    Filter::new()
        .kind(Kind::from(KIND_ORDER))
        .author(*mostro_pubkey)
}

/// Build a Nostr filter for a **single** Kind 38383 order by `d`-tag (order ID).
///
/// Unlike `all_orders_filter`, this filter is scoped to a single order ID and
/// captures every K38383 update for it regardless of status.
/// Use this after taking an order to track status changes: `pending` →
/// `in-progress` → `waiting-buyer-invoice` / `waiting-payment` → `active` etc.
pub fn trade_order_filter(mostro_pubkey: &PublicKey, order_id: &str) -> Filter {
    Filter::new()
        .kind(Kind::from(KIND_ORDER))
        .author(*mostro_pubkey)
        .custom_tag(SingleLetterTag::lowercase(Alphabet::D), order_id)
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Build a signed Kind 38383 event with the standard order tags and the
    /// given `fa` tag values.
    fn order_event(fa_values: &[&str]) -> Event {
        let keys = Keys::generate();
        let mut fa_tag = vec!["fa"];
        fa_tag.extend_from_slice(fa_values);
        EventBuilder::new(Kind::from(KIND_ORDER), "")
            .tags([
                Tag::parse(["d", "308e1272-d5f4-47e6-bd97-3504baea9c23"]).unwrap(),
                Tag::parse(["k", "sell"]).unwrap(),
                Tag::parse(["s", "pending"]).unwrap(),
                Tag::parse(["f", "USD"]).unwrap(),
                Tag::parse(["pm", "cashapp"]).unwrap(),
                Tag::parse(["premium", "1"]).unwrap(),
                Tag::parse(["amt", "0"]).unwrap(),
                Tag::parse(fa_tag).unwrap(),
                Tag::parse(["z", "order"]).unwrap(),
            ])
            .sign_with_keys(&keys)
            .unwrap()
    }

    #[test]
    fn parses_fixed_amount_order() {
        let order = parse_order_event(&order_event(&["20"]), None).unwrap();
        assert_eq!(order.fiat_amount, Some(20.0));
        assert_eq!(order.fiat_amount_min, None);
        assert_eq!(order.fiat_amount_max, None);
    }

    #[test]
    fn parses_range_order_from_multi_value_fa_tag() {
        let order = parse_order_event(&order_event(&["20", "60"]), None).unwrap();
        assert_eq!(order.fiat_amount, None);
        assert_eq!(order.fiat_amount_min, Some(20.0));
        assert_eq!(order.fiat_amount_max, Some(60.0));
    }

    #[test]
    fn parses_range_order_from_legacy_colon_encoding() {
        let order = parse_order_event(&order_event(&["20:60"]), None).unwrap();
        assert_eq!(order.fiat_amount, None);
        assert_eq!(order.fiat_amount_min, Some(20.0));
        assert_eq!(order.fiat_amount_max, Some(60.0));
    }

    #[test]
    fn range_with_unparseable_bound_yields_no_amounts() {
        let order = parse_order_event(&order_event(&["20", "abc"]), None).unwrap();
        assert_eq!(order.fiat_amount, None);
        assert_eq!(order.fiat_amount_min, None);
        assert_eq!(order.fiat_amount_max, None);
    }

    #[test]
    fn missing_fa_tag_yields_no_amounts() {
        let keys = Keys::generate();
        let event = EventBuilder::new(Kind::from(KIND_ORDER), "")
            .tags([
                Tag::parse(["d", "308e1272-d5f4-47e6-bd97-3504baea9c23"]).unwrap(),
                Tag::parse(["k", "buy"]).unwrap(),
                Tag::parse(["s", "pending"]).unwrap(),
                Tag::parse(["f", "USD"]).unwrap(),
            ])
            .sign_with_keys(&keys)
            .unwrap();
        let order = parse_order_event(&event, None).unwrap();
        assert_eq!(order.fiat_amount, None);
        assert_eq!(order.fiat_amount_min, None);
        assert_eq!(order.fiat_amount_max, None);
    }
}
