//! Anti-abuse bond client handling (`docs/ANTI_ABUSE_BOND.md`).
//!
//! Covers the active node's bond policy (what the UI needs to warn before a
//! take or a create) and the `bond-slashed` forfeiture notice: a best-effort,
//! informational message the daemon sends when the local user's bond is
//! slashed. The notice is broadcast to the Dart notification layer; the tracked
//! order is never mutated (the slashed amount must not overwrite the order's
//! real amount).

use anyhow::{bail, Result};
use tokio::sync::broadcast;
use tokio::sync::broadcast::error::RecvError;

use crate::api::types::{BondPolicyInfo, BondSlashedEvent, OrderStatus, SlashCause};
use crate::db::Storage;
use crate::mostro::bond_policy;

// ── Node policy ─────────────────────────────────────────────────────────────

/// The active node's advertised bond policy, or `None` before its kind 38385
/// info event has been fetched (startup, node switch, or an unreachable node).
///
/// `None` and `Some(policy = Unsupported)` differ: the first is "not known
/// yet", the second is "known, and the daemon predates bonds".
pub fn get_bond_policy() -> Option<BondPolicyInfo> {
    bond_policy::get_for(&crate::config::active_mostro_pubkey())
}

/// Estimated bond the active node would ask for an order of
/// `order_amount_sats`, for the pre-commit warning. `None` when the policy is
/// unknown, not enabled, or advertises no percentage. Never used to charge
/// anything: the daemon sends the exact bolt11.
pub fn estimate_bond_sats(order_amount_sats: u64) -> Option<u64> {
    let policy = get_bond_policy()?;
    bond_policy::estimate_bond_sats(order_amount_sats, &policy)
}

// ── Maker bond ──────────────────────────────────────────────────────────────

/// Walk away from an order parked at `WaitingMakerBond` without paying the
/// bond (docs/ANTI_ABUSE_BOND.md §6.2). The daemon refuses a cancel in this
/// window and reaps the unpaid order itself, so this only wipes the local
/// row and emits `Canceled` with `UserCanceled`. Markers: `TradeNotFound`,
/// `NotWaitingBond` when the row is not a maker's bond window.
pub async fn abandon_bonded_order(order_id: String) -> Result<()> {
    let db = crate::db::app_db::db().ok_or_else(|| anyhow::anyhow!("StorageUnavailable"))?;
    let trade = db
        .get_trade_by_order_id(&order_id)
        .await?
        .ok_or_else(|| anyhow::anyhow!("TradeNotFound"))?;
    if trade.order.status != OrderStatus::WaitingMakerBond || !trade.order.is_mine {
        bail!("NotWaitingBond");
    }
    crate::api::orders::abandon_maker_bond(&trade).await
}

// ── Forfeiture notice ───────────────────────────────────────────────────────

/// Buffered slash notices; a slash is rare, so a small buffer is ample.
const CHANNEL_CAPACITY: usize = 64;

struct BondStore {
    /// Broadcast channel; payload = incoming bond-slashed notice.
    event_tx: broadcast::Sender<BondSlashedEvent>,
}

static BOND_STORE: std::sync::OnceLock<BondStore> = std::sync::OnceLock::new();

fn bond_store() -> &'static BondStore {
    BOND_STORE.get_or_init(|| {
        let (event_tx, _rx) = broadcast::channel(CHANNEL_CAPACITY);
        BondStore { event_tx }
    })
}

/// Infers the slash cause from the tracked order's current status.
///
/// The daemon sends the resolution message first — `canceled` for a timeout,
/// `admin-settled` / `admin-canceled` for a dispute — and only then the
/// trailing `bond-slashed`. So by the time the notice arrives, the tracked
/// status already reflects the cause. Any dispute/admin state means a
/// dispute-directed slash; everything else (including an unknown status)
/// defaults to a timeout slash.
pub(crate) fn infer_slash_cause(status: Option<&OrderStatus>) -> SlashCause {
    match status {
        Some(
            OrderStatus::Dispute
            | OrderStatus::CanceledByAdmin
            | OrderStatus::SettledByAdmin
            | OrderStatus::CompletedByAdmin,
        ) => SlashCause::Dispute,
        _ => SlashCause::Timeout,
    }
}

/// Broadcasts a `bond-slashed` notice to any active [`BondSlashedStream`].
pub(crate) fn emit_bond_slashed(event: BondSlashedEvent) {
    let _ = bond_store().event_tx.send(event);
}

/// A stream that emits incoming [`BondSlashedEvent`]s for the Dart layer.
pub struct BondSlashedStream {
    rx: broadcast::Receiver<BondSlashedEvent>,
}

impl BondSlashedStream {
    /// Poll for the next incoming bond-slashed notice.
    ///
    /// `RecvError::Lagged` is skipped gracefully rather than ending the stream.
    pub async fn next(&mut self) -> Result<BondSlashedEvent> {
        loop {
            match self.rx.recv().await {
                Ok(event) => return Ok(event),
                Err(RecvError::Lagged(_)) => continue,
                Err(RecvError::Closed) => bail!("BondSlashedStream closed: sender dropped"),
            }
        }
    }
}

/// Subscribe to incoming `bond-slashed` notices.
pub fn on_bond_slashed() -> BondSlashedStream {
    BondSlashedStream {
        rx: bond_store().event_tx.subscribe(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dispute_and_admin_states_infer_dispute() {
        for status in [
            OrderStatus::Dispute,
            OrderStatus::CanceledByAdmin,
            OrderStatus::SettledByAdmin,
            OrderStatus::CompletedByAdmin,
        ] {
            assert_eq!(infer_slash_cause(Some(&status)), SlashCause::Dispute);
        }
    }

    #[test]
    fn canceled_and_other_states_infer_timeout() {
        for status in [
            OrderStatus::Canceled,
            OrderStatus::InProgress,
            OrderStatus::WaitingPayment,
            OrderStatus::WaitingBuyerInvoice,
            OrderStatus::Active,
        ] {
            assert_eq!(infer_slash_cause(Some(&status)), SlashCause::Timeout);
        }
    }

    #[test]
    fn unknown_status_defaults_to_timeout() {
        assert_eq!(infer_slash_cause(None), SlashCause::Timeout);
    }

    /// A trade row written before the `bond` field existed must still load,
    /// and a row with a bond must round-trip it intact.
    #[test]
    fn trade_rows_round_trip_with_and_without_a_bond() {
        use crate::api::types::{
            BondInfo, BondRole, BondState, BuyerStep, OrderInfo, OrderKind, TradeInfo, TradeRole,
            TradeStep,
        };

        let order = OrderInfo {
            id: "o1".into(),
            kind: OrderKind::Sell,
            status: OrderStatus::WaitingTakerBond,
            amount_sats: Some(100_000),
            fiat_amount: Some(10.0),
            fiat_amount_min: None,
            fiat_amount_max: None,
            fiat_code: "USD".into(),
            payment_method: "cash".into(),
            premium: 0.0,
            creator_pubkey: String::new(),
            created_at: 1,
            expires_at: None,
            is_mine: false,
            rating: 0.0,
            total_reviews: 0,
            days_active: 0,
        };
        let trade = TradeInfo {
            id: "t1".into(),
            order,
            role: TradeRole::Buyer,
            counterparty_pubkey: String::new(),
            current_step: TradeStep::Buyer(BuyerStep::OrderTaken),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 3,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
            bond: Some(BondInfo {
                role: BondRole::Taker,
                amount_sats: 1_000,
                invoice: Some("lnbc10u1...".into()),
                state: BondState::Requested,
                requested_at: 1,
                expires_at: Some(3601),
                locked_at: None,
            }),
        };

        let json = serde_json::to_string(&trade).unwrap();
        let back: TradeInfo = serde_json::from_str(&json).unwrap();
        assert_eq!(back.bond, trade.bond);
        assert_eq!(back.order.status, OrderStatus::WaitingTakerBond);

        // A pre-bond row: strip the field and deserialise again.
        let mut value: serde_json::Value = serde_json::from_str(&json).unwrap();
        value.as_object_mut().unwrap().remove("bond");
        let legacy: TradeInfo = serde_json::from_value(value).unwrap();
        assert_eq!(legacy.bond, None);
    }

    #[test]
    fn the_estimate_reads_the_active_node_policy_only() {
        use crate::api::types::{BondPolicy, BondPolicyInfo};
        let enabled = BondPolicyInfo {
            policy: BondPolicy::Enabled,
            amount_pct: Some(0.01),
            base_amount_sats: Some(1_000),
            ..BondPolicyInfo::default()
        };
        bond_policy::clear();
        assert_eq!(get_bond_policy(), None);
        assert_eq!(estimate_bond_sats(500_000), None);

        // A policy fetched from some other node is not the active node's.
        bond_policy::set_from_tags("not-the-active-node", enabled.clone());
        assert_eq!(get_bond_policy(), None);
        assert_eq!(estimate_bond_sats(500_000), None);

        bond_policy::set_from_tags(&crate::config::active_mostro_pubkey(), enabled);
        assert_eq!(estimate_bond_sats(500_000), Some(5_000));
        assert_eq!(estimate_bond_sats(10), Some(1_000));
        bond_policy::clear();
    }
}
