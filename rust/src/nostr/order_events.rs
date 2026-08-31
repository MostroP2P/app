/// Nostr event helpers for Mostro public order book.
///
/// Public orders use Kind 38383 (replaceable parameterised events).
/// **The Mostro node** (daemon) is the author/publisher of these events —
/// makers send a `new-order` daemon message (transport v2) to the daemon, and it
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
    // The `pm` tag carries one value per accepted payment method
    // (`["pm", "Revolut", "Zelle"]` — mostro's `nip33` splits the order's
    // comma-separated methods into tag values), so it cannot go through
    // `get`, which only reads the first value. Re-join with commas: the Dart
    // payment filter tokenizes this string on `,`.
    let payment_method = event
        .tags
        .iter()
        .find(|t| t.as_slice().first().map(|s| s.as_str()) == Some("pm"))
        .map(|t| t.as_slice()[1..].join(", "))
        .unwrap_or_default();
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
    // trade messages (the daemon's kind-14 response).
    let is_mine = false;
    let _ = my_pubkey; // unused — kept in signature for future use

    let (rating, total_reviews, days_active) = parse_rating_tag(get("rating").as_deref());

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
        rating,
        total_reviews,
        days_active,
    })
}

/// Parse the `rating` tag value into `(total_rating, total_reviews, days)`.
///
/// The daemon publishes the maker's reputation snapshot on each order event:
/// `"none"` for full-privacy makers, otherwise a JSON object
/// `{"total_reviews":47,"total_rating":4.9,"last_rating":5,"max_rate":5,
/// "min_rate":1,"days":312}` (mostro-core `Rating`). Some deployments wrap it
/// as `["rating", {…}]` — v1 accepts both shapes, so we do too. Missing tag or
/// malformed JSON degrades to zeros rather than dropping the order.
fn parse_rating_tag(value: Option<&str>) -> (f64, u32, u32) {
    const EMPTY: (f64, u32, u32) = (0.0, 0, 0);
    let Some(raw) = value else { return EMPTY };
    if raw == "none" {
        return EMPTY;
    }
    let Ok(parsed) = serde_json::from_str::<serde_json::Value>(raw) else {
        log::debug!("[parse] unparseable rating tag: {raw:?}");
        return EMPTY;
    };
    let obj = match &parsed {
        serde_json::Value::Object(map) => map,
        serde_json::Value::Array(arr)
            if arr.len() > 1 && arr[0].as_str() == Some("rating") && arr[1].is_object() =>
        {
            arr[1].as_object().expect("checked is_object above")
        }
        _ => return EMPTY,
    };
    // Validate ranges instead of blindly casting: total_rating is defined as
    // 0–5, and counts must be non-negative whole numbers that fit u32. Any
    // out-of-range value falls back to that field's zero default.
    (
        obj.get("total_rating")
            .and_then(|v| v.as_f64())
            .filter(|rating| (0.0..=5.0).contains(rating))
            .unwrap_or(0.0),
        obj.get("total_reviews")
            .and_then(|v| v.as_u64())
            .and_then(|value| u32::try_from(value).ok())
            .unwrap_or(0),
        obj.get("days")
            .and_then(|v| v.as_u64())
            .and_then(|value| u32::try_from(value).ok())
            .unwrap_or(0),
    )
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

/// Ceiling on the stored events a relay may replay for the order book, both on
/// the live subscription and on the one-shot refetch.
///
/// Kind 38383 is addressable, so a well-behaved relay already returns only the
/// latest event per order — this is a bound on what a misbehaving or hostile
/// one can push at us, not on the book itself. Set well above any realistic
/// active book: if a node ever legitimately approaches it, the answer is
/// pagination, not a larger number, because the cost of the replay is paid on
/// the ingest path.
pub const ORDER_BOOK_FETCH_LIMIT: usize = 5_000;

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
        .limit(ORDER_BOOK_FETCH_LIMIT)
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

    /// An unbounded filter lets a relay replay its entire history of the
    /// node's orders, and every replayed event is paid for on the ingest path.
    #[test]
    fn the_order_book_filter_caps_what_a_relay_may_replay() {
        let mostro = Keys::generate().public_key();

        let filter = all_orders_filter(&mostro);

        assert_eq!(
            filter.limit,
            Some(ORDER_BOOK_FETCH_LIMIT),
            "the order-book filter must carry a replay ceiling"
        );
    }

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
        // Single-method order: the sole `pm` value comes through unchanged.
        assert_eq!(order.payment_method, "cashapp");
    }

    /// The `pm` tag carries one value per payment method and every one must
    /// survive parsing (regression: only the first value was read, so the
    /// book showed one method and the payment filter missed the rest).
    #[test]
    fn parses_all_payment_methods_from_multi_value_pm_tag() {
        let keys = Keys::generate();
        let event = EventBuilder::new(Kind::from(KIND_ORDER), "")
            .tags([
                Tag::parse(["d", "308e1272-d5f4-47e6-bd97-3504baea9c23"]).unwrap(),
                Tag::parse(["k", "sell"]).unwrap(),
                Tag::parse(["s", "pending"]).unwrap(),
                Tag::parse(["f", "USD"]).unwrap(),
                Tag::parse(["pm", "Revolut", "Zelle", "Strike"]).unwrap(),
                Tag::parse(["premium", "1"]).unwrap(),
                Tag::parse(["amt", "0"]).unwrap(),
                Tag::parse(["fa", "20"]).unwrap(),
                Tag::parse(["z", "order"]).unwrap(),
            ])
            .sign_with_keys(&keys)
            .unwrap();
        let order = parse_order_event(&event, None).unwrap();
        assert_eq!(order.payment_method, "Revolut, Zelle, Strike");
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

    /// Build a signed Kind 38383 event carrying the given `rating` tag value.
    fn order_event_with_rating(rating_value: &str) -> Event {
        let keys = Keys::generate();
        EventBuilder::new(Kind::from(KIND_ORDER), "")
            .tags([
                Tag::parse(["d", "308e1272-d5f4-47e6-bd97-3504baea9c23"]).unwrap(),
                Tag::parse(["k", "sell"]).unwrap(),
                Tag::parse(["s", "pending"]).unwrap(),
                Tag::parse(["f", "USD"]).unwrap(),
                Tag::parse(["fa", "20"]).unwrap(),
                Tag::parse(["rating", rating_value]).unwrap(),
                Tag::parse(["z", "order"]).unwrap(),
            ])
            .sign_with_keys(&keys)
            .unwrap()
    }

    #[test]
    fn parses_rating_tag_object_form() {
        let order = parse_order_event(
            &order_event_with_rating(
                r#"{"total_reviews":47,"total_rating":4.9,"last_rating":5,"max_rate":5,"min_rate":1,"days":312}"#,
            ),
            None,
        )
        .unwrap();
        assert_eq!(order.rating, 4.9);
        assert_eq!(order.total_reviews, 47);
        assert_eq!(order.days_active, 312);
    }

    #[test]
    fn parses_rating_tag_array_wrapped_form() {
        let order = parse_order_event(
            &order_event_with_rating(
                r#"["rating",{"total_reviews":11,"total_rating":4.8,"days":203}]"#,
            ),
            None,
        )
        .unwrap();
        assert_eq!(order.rating, 4.8);
        assert_eq!(order.total_reviews, 11);
        assert_eq!(order.days_active, 203);
    }

    #[test]
    fn full_privacy_rating_none_yields_zeros() {
        let order = parse_order_event(&order_event_with_rating("none"), None).unwrap();
        assert_eq!(order.rating, 0.0);
        assert_eq!(order.total_reviews, 0);
        assert_eq!(order.days_active, 0);
    }

    #[test]
    fn malformed_rating_json_degrades_to_zeros_without_dropping_order() {
        let order = parse_order_event(&order_event_with_rating("{not json"), None).unwrap();
        assert_eq!(order.rating, 0.0);
        assert_eq!(order.total_reviews, 0);
        assert_eq!(order.days_active, 0);
        // The order itself must survive a bad rating tag.
        assert_eq!(order.fiat_amount, Some(20.0));
    }

    #[test]
    fn out_of_range_rating_values_fall_back_to_zeros() {
        // total_rating above 5, negative reviews, fractional days: each
        // invalid field independently degrades to its zero default.
        let order = parse_order_event(
            &order_event_with_rating(
                r#"{"total_reviews":-3,"total_rating":9.7,"days":2.5}"#,
            ),
            None,
        )
        .unwrap();
        assert_eq!(order.rating, 0.0);
        assert_eq!(order.total_reviews, 0);
        assert_eq!(order.days_active, 0);
    }

    #[test]
    fn boundary_rating_values_are_accepted() {
        let order = parse_order_event(
            &order_event_with_rating(r#"{"total_reviews":0,"total_rating":5.0,"days":0}"#),
            None,
        )
        .unwrap();
        assert_eq!(order.rating, 5.0);

        let order = parse_order_event(
            &order_event_with_rating(r#"{"total_reviews":1,"total_rating":0.0,"days":1}"#),
            None,
        )
        .unwrap();
        assert_eq!(order.rating, 0.0);
        assert_eq!(order.total_reviews, 1);
        assert_eq!(order.days_active, 1);
    }

    #[test]
    fn review_count_larger_than_u32_falls_back_to_zero() {
        let order = parse_order_event(
            &order_event_with_rating(
                r#"{"total_reviews":4294967296,"total_rating":4.0,"days":10}"#,
            ),
            None,
        )
        .unwrap();
        assert_eq!(order.rating, 4.0);
        assert_eq!(order.total_reviews, 0);
        assert_eq!(order.days_active, 10);
    }

    #[test]
    fn order_info_json_without_reputation_fields_deserializes_with_zeros() {
        // Rows persisted before the reputation fields existed (orders table,
        // trades JSON) must keep loading after an app upgrade.
        let legacy = r#"{
            "id":"308e1272-d5f4-47e6-bd97-3504baea9c23",
            "kind":"Buy","status":"Pending","amount_sats":null,
            "fiat_amount":100.0,"fiat_amount_min":null,"fiat_amount_max":null,
            "fiat_code":"USD","payment_method":"Bank","premium":0.0,
            "creator_pubkey":"","created_at":0,"expires_at":null,"is_mine":false
        }"#;
        let order: OrderInfo = serde_json::from_str(legacy).unwrap();
        assert_eq!(order.rating, 0.0);
        assert_eq!(order.total_reviews, 0);
        assert_eq!(order.days_active, 0);
    }

    #[test]
    fn missing_rating_tag_yields_zeros() {
        let order = parse_order_event(&order_event(&["20"]), None).unwrap();
        assert_eq!(order.rating, 0.0);
        assert_eq!(order.total_reviews, 0);
        assert_eq!(order.days_active, 0);
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
