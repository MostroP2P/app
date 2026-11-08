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

/// `$.order.fiat_amount` and `$.order.amount_sats` exactly as given, `None`
/// writing a JSON null (`Storage::set_trade_range_slice`).
pub(crate) fn set_range_slice(
    trade: &mut Value,
    fiat_amount: Option<f64>,
    amount_sats: Option<u64>,
) -> Result<()> {
    *field(trade, &["order", "fiat_amount"])? = serde_json::to_value(fiat_amount)?;
    *field(trade, &["order", "amount_sats"])? = serde_json::to_value(amount_sats)?;
    Ok(())
}

/// Stores the counterparty reputation snapshot as JSON numbers; an absent
/// `since` is stored as null.
pub(crate) fn set_peer_reputation(
    trade: &mut Value,
    rating: f64,
    reviews: u32,
    days: u32,
    since: Option<i64>,
) -> Result<()> {
    *field(trade, &["peer_rating"])? =
        serde_json::Number::from_f64(rating).map_or(Value::Null, Value::Number);
    *field(trade, &["peer_reviews"])? = Value::from(reviews);
    *field(trade, &["peer_days"])? = Value::from(days);
    *field(trade, &["peer_since"])? = Value::from(since);
    Ok(())
}

/// `$.bond = bond` as a JSON object.
pub(crate) fn set_bond(trade: &mut Value, bond: &crate::api::types::BondInfo) -> Result<()> {
    *field(trade, &["bond"])? = serde_json::to_value(bond)?;
    Ok(())
}

/// `$.rated_at = rated_at` as a JSON number.
pub(crate) fn mark_rated(trade: &mut Value, rated_at: i64) -> Result<()> {
    *field(trade, &["rated_at"])? = Value::from(rated_at);
    Ok(())
}

/// `$.completed_at = completed_at` as a JSON number, unless the trade already
/// has one: the first completion recorded wins, so a replayed `success`
/// never moves the end of the trade (and its chat window) forward.
pub(crate) fn mark_completed(trade: &mut Value, completed_at: i64) -> Result<()> {
    let slot = field(trade, &["completed_at"])?;
    if slot.is_null() {
        *slot = Value::from(completed_at);
    }
    Ok(())
}

/// `$.escrow_locked_at = locked_at` as a JSON number and `$.escrow_node =
/// node`, unless the trade already holds an older time: the oldest wins, so a
/// replayed or re-sent message never moves the escrow deadline.
pub(crate) fn mark_escrow_locked(trade: &mut Value, locked_at: i64, node: &str) -> Result<()> {
    let slot = field(trade, &["escrow_locked_at"])?;
    if slot.as_i64().is_some_and(|held| held <= locked_at) {
        return Ok(());
    }
    *slot = Value::from(locked_at);
    *field(trade, &["escrow_node"])? = Value::String(node.to_owned());
    Ok(())
}

/// `$.escrow_locked_at` and `$.escrow_node` back to null.
pub(crate) fn clear_escrow_lock(trade: &mut Value) -> Result<()> {
    *field(trade, &["escrow_locked_at"])? = Value::Null;
    *field(trade, &["escrow_node"])? = Value::Null;
    Ok(())
}

/// `$.cooperative_cancel_state = state`, as serde spells the variant.
pub(crate) fn set_cooperative_cancel_state(
    trade: &mut Value,
    state: &crate::api::types::CooperativeCancelState,
) -> Result<()> {
    *field(trade, &["cooperative_cancel_state"])? = serde_json::to_value(state)?;
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

/// When the trade's node is `node` (ignoring case) — `$.order.node_pubkey`,
/// else the legacy `$.order.creator_pubkey` — set `$.order.node_pubkey` to
/// `""` and drop the legacy name, which serde would read as a duplicate of
/// the new one. Returns whether it changed the document; an empty `node`
/// matches nothing.
pub(crate) fn forget_node(trade: &mut Value, node: &str) -> Result<bool> {
    let order = trade.get("order");
    let current = order
        .and_then(|o| o.get("node_pubkey"))
        .or_else(|| order.and_then(|o| o.get("creator_pubkey")))
        .and_then(Value::as_str);
    if node.is_empty() || !current.is_some_and(|c| c.eq_ignore_ascii_case(node)) {
        return Ok(false);
    }
    *field(trade, &["order", "node_pubkey"])? = Value::String(String::new());
    if let Some(order) = trade.get_mut("order").and_then(Value::as_object_mut) {
        order.remove("creator_pubkey");
    }
    Ok(true)
}

/// When the trade does not know its node (`$.order.node_pubkey`, else the
/// legacy `$.order.creator_pubkey`, absent or `""`) and its
/// `$.trade_key_index` is `trade_index`, set its node to `node` and drop the
/// legacy name. Returns whether it changed the document; an empty `node`
/// changes nothing.
pub(crate) fn adopt_node(trade: &mut Value, trade_index: u32, node: &str) -> Result<bool> {
    let order = trade.get("order");
    let current = order
        .and_then(|o| o.get("node_pubkey"))
        .or_else(|| order.and_then(|o| o.get("creator_pubkey")))
        .and_then(Value::as_str);
    let index = trade.get("trade_key_index").and_then(Value::as_u64);
    if node.is_empty()
        || current.is_some_and(|c| !c.is_empty())
        || index != Some(u64::from(trade_index))
    {
        return Ok(false);
    }
    *field(trade, &["order", "node_pubkey"])? = Value::String(node.to_owned());
    if let Some(order) = trade.get_mut("order").and_then(Value::as_object_mut) {
        order.remove("creator_pubkey");
    }
    Ok(true)
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
    fn records_who_asked_for_a_cooperative_cancel() {
        use crate::api::types::CooperativeCancelState;
        let mut t = trade();
        set_cooperative_cancel_state(&mut t, &CooperativeCancelState::RequestedByMe).unwrap();
        assert_eq!(t["cooperative_cancel_state"], "RequestedByMe");
        assert_eq!(t["order"]["status"], "Pending");
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
        set_peer_reputation(&mut t, 4.5, 12, 300, Some(1699920000)).unwrap();
        mark_rated(&mut t, 1700000123).unwrap();
        assert!(t["peer_rating"].is_f64());
        assert!(t["peer_reviews"].is_u64() && t["peer_days"].is_u64());
        assert_eq!(t["peer_since"], 1699920000);
        assert!(t["rated_at"].is_i64());
    }

    #[test]
    fn an_absent_peer_since_is_stored_as_null() {
        let mut t = trade();
        set_peer_reputation(&mut t, 4.5, 12, 300, None).unwrap();
        assert!(t["peer_since"].is_null());
        assert_eq!(t["peer_days"], 300);
    }

    #[test]
    fn the_first_completion_recorded_wins() {
        let mut t = trade();
        mark_completed(&mut t, 1700000500).unwrap();
        assert!(t["completed_at"].is_i64());
        mark_completed(&mut t, 1700009999).unwrap();
        assert_eq!(t["completed_at"], 1700000500);
    }

    #[test]
    fn the_oldest_escrow_lock_wins_and_keeps_its_node() {
        let mut t = trade();
        mark_escrow_locked(&mut t, 1700000500, "node-a").unwrap();
        assert!(t["escrow_locked_at"].is_i64());
        assert_eq!(t["escrow_node"], "node-a");

        // A later message (a re-send, a replay) does not move it.
        mark_escrow_locked(&mut t, 1700009999, "node-b").unwrap();
        assert_eq!(t["escrow_locked_at"], 1700000500);
        assert_eq!(t["escrow_node"], "node-a");

        // An older one, arriving after a newer one, replaces it.
        mark_escrow_locked(&mut t, 1700000100, "node-c").unwrap();
        assert_eq!(t["escrow_locked_at"], 1700000100);
        assert_eq!(t["escrow_node"], "node-c");
    }

    #[test]
    fn a_cleared_escrow_lock_takes_a_later_one() {
        let mut t = trade();
        mark_escrow_locked(&mut t, 1700000100, "node-a").unwrap();

        clear_escrow_lock(&mut t).unwrap();
        assert!(t["escrow_locked_at"].is_null());
        assert!(t["escrow_node"].is_null());

        mark_escrow_locked(&mut t, 1700009999, "node-b").unwrap();
        assert_eq!(t["escrow_locked_at"], 1700009999);
        assert_eq!(t["escrow_node"], "node-b");
    }

    #[test]
    fn the_bond_is_replaced_whole_and_reads_back() {
        let mut t = trade();
        let bond = crate::api::types::BondInfo {
            role: crate::api::types::BondRole::Taker,
            amount_sats: 1_000,
            invoice: Some("lnbc10u1...".into()),
            state: crate::api::types::BondState::Requested,
            requested_at: 1,
            expires_at: Some(3_601),
            locked_at: None,
        };
        set_bond(&mut t, &bond).unwrap();
        let back: crate::api::types::BondInfo =
            serde_json::from_value(t["bond"].clone()).unwrap();
        assert_eq!(back, bond);
        // A later transition replaces the object, it does not merge.
        let mut locked = bond.clone();
        locked.state = crate::api::types::BondState::Locked;
        locked.locked_at = Some(2);
        set_bond(&mut t, &locked).unwrap();
        assert_eq!(t["bond"]["state"], "Locked");
        assert_eq!(t["bond"]["locked_at"], 2);
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

    #[test]
    fn adopt_node_gives_an_unknown_node_and_nothing_else() {
        let mut t = trade();
        t["order"]["node_pubkey"] = json!("");
        t["trade_key_index"] = json!(7);
        t["rated_at"] = json!(1234);
        assert!(adopt_node(&mut t, 7, "abcd").unwrap());
        assert_eq!(t["order"]["node_pubkey"], json!("abcd"));
        assert_eq!(t["rated_at"], json!(1234));
        assert_eq!(t["order"]["status"], json!("Pending"));
        assert!(!adopt_node(&mut t, 7, "ef01").unwrap(), "done once");
    }

    #[test]
    fn adopt_node_takes_a_row_with_an_empty_legacy_name_or_none() {
        let mut legacy = trade();
        legacy["order"]["creator_pubkey"] = json!("");
        legacy["trade_key_index"] = json!(7);
        assert!(adopt_node(&mut legacy, 7, "abcd").unwrap());
        assert_eq!(legacy["order"]["node_pubkey"], json!("abcd"));
        assert!(
            legacy["order"].get("creator_pubkey").is_none(),
            "one name only"
        );

        let mut absent = trade();
        absent["trade_key_index"] = json!(7);
        assert!(adopt_node(&mut absent, 7, "abcd").unwrap());
    }

    #[test]
    fn adopt_node_leaves_a_known_node_another_index_or_no_node_alone() {
        let mut known = trade();
        known["order"]["node_pubkey"] = json!("node");
        known["trade_key_index"] = json!(7);
        assert!(!adopt_node(&mut known, 7, "abcd").unwrap());
        assert_eq!(known["order"]["node_pubkey"], json!("node"));

        let mut legacy_known = trade();
        legacy_known["order"]["creator_pubkey"] = json!("node");
        legacy_known["trade_key_index"] = json!(7);
        assert!(!adopt_node(&mut legacy_known, 7, "abcd").unwrap());

        let mut other_index = trade();
        other_index["order"]["node_pubkey"] = json!("");
        other_index["trade_key_index"] = json!(8);
        assert!(!adopt_node(&mut other_index, 7, "abcd").unwrap());

        let mut unknown = trade();
        unknown["order"]["node_pubkey"] = json!("");
        unknown["trade_key_index"] = json!(7);
        assert!(!adopt_node(&mut unknown, 7, "").unwrap());
        assert_eq!(unknown["order"]["node_pubkey"], json!(""));
    }

    #[test]
    fn forget_node_clears_a_matching_node_and_nothing_else() {
        let mut t = trade();
        t["order"]["node_pubkey"] = json!("ABCD");
        t["rated_at"] = json!(1234);
        assert!(forget_node(&mut t, "abcd").unwrap());
        assert_eq!(t["order"]["node_pubkey"], json!(""));
        assert_eq!(t["rated_at"], json!(1234));
        assert_eq!(t["order"]["status"], json!("Pending"));
    }

    #[test]
    fn forget_node_moves_a_legacy_node_to_the_new_name() {
        let mut t = trade();
        t["order"]["creator_pubkey"] = json!("abcd");
        assert!(forget_node(&mut t, "abcd").unwrap());
        assert_eq!(t["order"]["node_pubkey"], json!(""));
        assert!(t["order"].get("creator_pubkey").is_none(), "one name only");
    }

    #[test]
    fn forget_node_leaves_a_real_or_an_unknown_node_alone() {
        let mut real = trade();
        real["order"]["node_pubkey"] = json!("node");
        let before = real.clone();
        assert!(!forget_node(&mut real, "abcd").unwrap());
        assert_eq!(real, before);

        let mut unknown = trade();
        unknown["order"]["node_pubkey"] = json!("");
        let before = unknown.clone();
        assert!(
            !forget_node(&mut unknown, "").unwrap(),
            "an empty node matches nothing"
        );
        assert_eq!(unknown, before);
    }
}
