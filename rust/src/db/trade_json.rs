//! Field-level mutations on a persisted trade's JSON document.
//!
//! The SQLite backend applies trade updates with `json_set` inside the
//! database, so it never deserialises a row it only needs to patch. The
//! IndexedDB backend holds the same JSON documents but has no query engine,
//! so it patches them here, on `serde_json::Value`, with the same semantics:
//! every function touches only the fields it names and leaves a row written
//! by an older app version otherwise intact.
use anyhow::{anyhow, Result};
use serde_json::Value;

use crate::api::types::OrderStatus;

/// The order id a trade document belongs to (`$.order.id`).
pub(crate) fn order_id_of(trade: &Value) -> Option<&str> {
    trade.get("order")?.get("id")?.as_str()
}

/// `$.started_at`, or `0` for a document without one, so a sort never fails.
pub(crate) fn started_at_of(trade: &Value) -> i64 {
    trade
        .get("started_at")
        .and_then(Value::as_i64)
        .unwrap_or_default()
}

/// `$.order.id = new_id`.
pub(crate) fn rename_order_id(trade: &mut Value, new_id: &str) -> Result<()> {
    *field(trade, &["order", "id"])? = Value::String(new_id.to_owned());
    Ok(())
}

/// Applies the optional status, hold invoice and amount mutations of
/// `Storage::update_trade_fields`.
pub(crate) fn apply_fields(
    trade: &mut Value,
    status: Option<&OrderStatus>,
    hold_invoice: Option<&str>,
    amount_sats: Option<u64>,
) -> Result<()> {
    if let Some(status) = status {
        *field(trade, &["order", "status"])? = serde_json::to_value(status)?;
    }
    if let Some(invoice) = hold_invoice {
        *field(trade, &["hold_invoice"])? = Value::String(invoice.to_owned());
    }
    if let Some(sats) = amount_sats {
        *field(trade, &["order", "amount_sats"])? = Value::from(sats);
    }
    Ok(())
}

/// Stores the counterparty reputation snapshot as JSON numbers.
pub(crate) fn set_peer_reputation(
    trade: &mut Value,
    rating: f64,
    reviews: u32,
    days: u32,
) -> Result<()> {
    *field(trade, &["peer_rating"])? =
        serde_json::Number::from_f64(rating).map_or(Value::Null, Value::Number);
    *field(trade, &["peer_reviews"])? = Value::from(reviews);
    *field(trade, &["peer_days"])? = Value::from(days);
    Ok(())
}

/// `$.rated_at = rated_at` as a JSON number.
pub(crate) fn mark_rated(trade: &mut Value, rated_at: i64) -> Result<()> {
    *field(trade, &["rated_at"])? = Value::from(rated_at);
    Ok(())
}

/// `$.counterparty_pubkey = pubkey`. Reveals are monotonic, so an empty
/// value is a caller bug and is refused rather than wiping a good row.
pub(crate) fn set_counterparty(trade: &mut Value, pubkey: &str) -> Result<()> {
    if pubkey.is_empty() {
        return Err(anyhow!(
            "set_counterparty: refusing to clear the counterparty of a trade"
        ));
    }
    *field(trade, &["counterparty_pubkey"])? = Value::String(pubkey.to_owned());
    Ok(())
}

/// The mutable slot at `path`, creating missing intermediate objects the way
/// `json_set` does. Fails when a segment exists but is not an object.
fn field<'a>(trade: &'a mut Value, path: &[&str]) -> Result<&'a mut Value> {
    let mut node = trade;
    for segment in path {
        if node.is_null() {
            *node = Value::Object(Default::default());
        }
        let object = node
            .as_object_mut()
            .ok_or_else(|| anyhow!("trade document: `{segment}` is not inside an object"))?;
        node = object.entry((*segment).to_owned()).or_insert(Value::Null);
    }
    Ok(node)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn trade() -> Value {
        json!({
            "id": "t1",
            "order": {"id": "local-uuid", "status": "Pending", "amount_sats": null},
            "counterparty_pubkey": "",
            "hold_invoice": null,
            "started_at": 1700000000
        })
    }

    #[test]
    fn reads_the_order_id_and_start_time() {
        assert_eq!(order_id_of(&trade()), Some("local-uuid"));
        assert_eq!(started_at_of(&trade()), 1700000000);
        assert_eq!(started_at_of(&json!({})), 0);
        assert_eq!(order_id_of(&json!({"order": {}})), None);
    }

    #[test]
    fn renames_the_order_id_and_nothing_else() {
        let mut t = trade();
        rename_order_id(&mut t, "daemon-uuid").unwrap();
        assert_eq!(order_id_of(&t), Some("daemon-uuid"));
        assert_eq!(t["order"]["status"], "Pending");
        assert_eq!(t["id"], "t1");
    }

    #[test]
    fn applies_only_the_fields_that_were_given() {
        let mut t = trade();
        apply_fields(&mut t, Some(&OrderStatus::Active), None, Some(6307)).unwrap();
        assert_eq!(
            t["order"]["status"],
            serde_json::to_value(OrderStatus::Active).unwrap()
        );
        assert_eq!(t["order"]["amount_sats"], 6307);
        assert!(
            t["hold_invoice"].is_null(),
            "an absent mutation leaves the field alone"
        );

        apply_fields(&mut t, None, Some("lnbcrt1..."), None).unwrap();
        assert_eq!(t["hold_invoice"], "lnbcrt1...");
        assert_eq!(t["order"]["amount_sats"], 6307);
    }

    #[test]
    fn numbers_stay_numbers_so_the_row_deserialises_again() {
        let mut t = trade();
        set_peer_reputation(&mut t, 4.5, 12, 300).unwrap();
        mark_rated(&mut t, 1700000123).unwrap();
        assert!(t["peer_rating"].is_f64());
        assert!(t["peer_reviews"].is_u64() && t["peer_days"].is_u64());
        assert!(t["rated_at"].is_i64());
    }

    #[test]
    fn a_counterparty_is_set_but_never_cleared() {
        let mut t = trade();
        set_counterparty(&mut t, "npub-peer").unwrap();
        assert_eq!(t["counterparty_pubkey"], "npub-peer");
        assert!(set_counterparty(&mut t, "").is_err());
        assert_eq!(t["counterparty_pubkey"], "npub-peer");
    }

    #[test]
    fn missing_intermediate_objects_are_created_like_json_set() {
        let mut t = json!({"id": "t2"});
        apply_fields(&mut t, Some(&OrderStatus::Active), None, None).unwrap();
        assert_eq!(
            t["order"]["status"],
            serde_json::to_value(OrderStatus::Active).unwrap()
        );
        let mut bad = json!({"order": "not an object"});
        assert!(rename_order_id(&mut bad, "x").is_err());
    }
}
