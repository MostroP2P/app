//! What the current identity would lose if it were replaced now (issue #533).
//!
//! Generating a new user or importing a seed throws away the trade keys, and
//! with them the only way to act on anything still in flight: a seller's
//! escrow only moves with a `release` signed by that trade's key, a locked
//! bond is only given back when its trade ends, a payout claim is only paid
//! to the key that won it. The Account screen asks this before either swap
//! and warns; it does not block — the user may be rotating because the device
//! is compromised.
//!
//! Pure on purpose: it classifies rows already read, so every case can be
//! tested without a database or a clock.

use crate::api::types::{
    BondClaim, BondState, FundsAtRisk, FundsAtRiskReason, OrderStatus, TradeInfo, TradeRole,
};

/// Every reason the identity behind `trades` and `claims` should not be
/// replaced at `now` (unix seconds), most serious first.
///
/// One trade can yield several entries — a locked bond *and* a locked escrow
/// are two separate amounts — but at most one of the escrow / in-progress
/// pair, since the first implies the second.
pub(crate) fn funds_at_risk(
    trades: &[TradeInfo],
    claims: &[BondClaim],
    now: i64,
) -> Vec<FundsAtRisk> {
    let mut found = Vec::new();
    for trade in trades {
        if crate::mostro::status::is_hard_terminal(&trade.order.status) {
            continue;
        }
        let order_id = &trade.order.id;
        let escrow_locked =
            trade.role == TradeRole::Seller && escrow_is_locked(&trade.order.status);
        if escrow_locked {
            found.push(entry(
                order_id,
                FundsAtRiskReason::SellerEscrowLocked,
                trade.order.amount_sats,
            ));
        }
        if let Some(bond) = &trade.bond {
            match bond.state {
                BondState::Locked => {
                    found.push(entry(
                        order_id,
                        FundsAtRiskReason::BondLocked,
                        Some(bond.amount_sats),
                    ));
                }
                // An invoice that can still be paid: nothing is locked yet,
                // but the user is one scan away from locking sats under a
                // key they are about to throw away.
                BondState::Requested if bond.expires_at.is_none_or(|at| at > now) => {
                    found.push(entry(
                        order_id,
                        FundsAtRiskReason::BondInvoicePending,
                        Some(bond.amount_sats),
                    ));
                }
                _ => {}
            }
        }
        if !escrow_locked && is_in_progress(&trade.order.status) {
            found.push(entry(
                order_id,
                FundsAtRiskReason::TradeInProgress,
                trade.order.amount_sats,
            ));
        }
    }
    for claim in claims {
        if !claim.phase.is_terminal() && claim.deadline_at > now {
            found.push(entry(
                &claim.order_id,
                FundsAtRiskReason::PayoutClaimOpen,
                Some(claim.amount_sats),
            ));
        }
    }
    found.sort_by_key(|risk| severity(&risk.reason));
    found
}

fn entry(order_id: &str, reason: FundsAtRiskReason, amount_sats: Option<u64>) -> FundsAtRisk {
    FundsAtRisk {
        order_id: order_id.to_string(),
        reason,
        amount_sats,
    }
}

/// The seller's hold invoice is paid and held from `Active` until the trade
/// ends. Decided on the status, not on `TradeInfo::hold_invoice`: a row
/// rebuilt by a restore carries no bolt11, and its sats are just as locked.
fn escrow_is_locked(status: &OrderStatus) -> bool {
    matches!(
        status,
        OrderStatus::Active | OrderStatus::FiatSent | OrderStatus::Dispute
    )
}

/// A counterparty is waiting on this identity, even with no sats of its own
/// locked: a buyer who already sent fiat loses the way to claim the sats.
fn is_in_progress(status: &OrderStatus) -> bool {
    matches!(
        status,
        OrderStatus::WaitingBuyerInvoice
            | OrderStatus::WaitingPayment
            | OrderStatus::Active
            | OrderStatus::FiatSent
            | OrderStatus::SettledHoldInvoice
            | OrderStatus::Dispute
    )
}

fn severity(reason: &FundsAtRiskReason) -> u8 {
    match reason {
        FundsAtRiskReason::SellerEscrowLocked => 0,
        FundsAtRiskReason::BondLocked => 1,
        FundsAtRiskReason::PayoutClaimOpen => 2,
        FundsAtRiskReason::TradeInProgress => 3,
        FundsAtRiskReason::BondInvoicePending => 4,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::{
        BondClaimPhase, BondInfo, BondRole, BuyerStep, OrderInfo, OrderKind, TradeStep,
    };

    const NOW: i64 = 1_000_000;

    fn trade(order_id: &str, role: TradeRole, status: OrderStatus) -> TradeInfo {
        TradeInfo {
            id: format!("row-{order_id}"),
            order: OrderInfo {
                id: order_id.into(),
                kind: OrderKind::Sell,
                status,
                amount_sats: Some(50_000),
                fiat_amount: Some(100.0),
                fiat_amount_min: None,
                fiat_amount_max: None,
                fiat_code: "USD".into(),
                payment_method: "bank".into(),
                premium: 0.0,
                creator_pubkey: "node".into(),
                created_at: 1,
                expires_at: None,
                is_mine: false,
                rating: 0.0,
                total_reviews: 0,
                days_active: 0,
            },
            role,
            counterparty_pubkey: String::new(),
            current_step: TradeStep::Buyer(BuyerStep::OrderTaken),
            hold_invoice: None,
            buyer_invoice: None,
            trade_key_index: 1,
            cooperative_cancel_state: None,
            timeout_at: None,
            started_at: 1,
            completed_at: None,
            outcome: None,
            peer_rating: None,
            peer_reviews: None,
            peer_days: None,
            rated_at: None,
            bond: None,
        }
    }

    fn bond(state: BondState, expires_at: Option<i64>) -> BondInfo {
        BondInfo {
            role: BondRole::Taker,
            amount_sats: 1_500,
            invoice: None,
            state,
            requested_at: 1,
            expires_at,
            locked_at: None,
        }
    }

    fn claim(order_id: &str, phase: BondClaimPhase, deadline_at: i64) -> BondClaim {
        BondClaim {
            order_id: order_id.into(),
            node_pubkey: "node".into(),
            trade_index: Some(1),
            amount_sats: 700,
            slashed_at: 1,
            deadline_at,
            phase,
            submitted_invoice: None,
            fiat_code: "USD".into(),
            fiat_amount: None,
            payment_method: "bank".into(),
            updated_at: 1,
        }
    }

    fn reasons(found: &[FundsAtRisk]) -> Vec<FundsAtRiskReason> {
        found.iter().map(|risk| risk.reason.clone()).collect()
    }

    #[test]
    fn an_identity_with_only_finished_trades_has_nothing_at_risk() {
        let trades = [
            trade("a", TradeRole::Seller, OrderStatus::Success),
            trade("b", TradeRole::Buyer, OrderStatus::Canceled),
            trade("c", TradeRole::Seller, OrderStatus::CooperativelyCanceled),
            // An open order of the user's own: abandoned by a swap, but no
            // sats and no counterparty hang on it.
            trade("d", TradeRole::Seller, OrderStatus::Pending),
        ];
        assert!(funds_at_risk(&trades, &[], NOW).is_empty());
    }

    #[test]
    fn a_sellers_escrow_is_locked_from_active_until_the_trade_ends() {
        for status in [
            OrderStatus::Active,
            OrderStatus::FiatSent,
            OrderStatus::Dispute,
        ] {
            let found = funds_at_risk(&[trade("a", TradeRole::Seller, status.clone())], &[], NOW);
            assert_eq!(
                reasons(&found),
                [FundsAtRiskReason::SellerEscrowLocked],
                "{status:?}"
            );
            assert_eq!(found[0].amount_sats, Some(50_000));
        }
        // Before the hold invoice is paid nothing of the seller's is locked,
        // but the trade is live.
        let waiting = funds_at_risk(
            &[trade("a", TradeRole::Seller, OrderStatus::WaitingPayment)],
            &[],
            NOW,
        );
        assert_eq!(reasons(&waiting), [FundsAtRiskReason::TradeInProgress]);
    }

    #[test]
    fn the_escrow_is_found_on_a_restored_row_without_its_invoice() {
        let mut restored = trade("a", TradeRole::Seller, OrderStatus::Active);
        restored.hold_invoice = None;
        assert_eq!(
            reasons(&funds_at_risk(&[restored], &[], NOW)),
            [FundsAtRiskReason::SellerEscrowLocked]
        );
    }

    #[test]
    fn a_buyer_mid_trade_is_in_progress() {
        let found = funds_at_risk(
            &[trade("a", TradeRole::Buyer, OrderStatus::FiatSent)],
            &[],
            NOW,
        );
        assert_eq!(reasons(&found), [FundsAtRiskReason::TradeInProgress]);
    }

    #[test]
    fn a_locked_bond_counts_next_to_the_escrow_of_the_same_trade() {
        let mut both = trade("a", TradeRole::Seller, OrderStatus::Active);
        both.bond = Some(bond(BondState::Locked, None));
        let found = funds_at_risk(&[both], &[], NOW);
        assert_eq!(
            reasons(&found),
            [
                FundsAtRiskReason::SellerEscrowLocked,
                FundsAtRiskReason::BondLocked
            ]
        );
        assert_eq!(found[1].amount_sats, Some(1_500));
    }

    #[test]
    fn a_bond_invoice_counts_only_while_it_can_still_be_paid() {
        let mut payable = trade("a", TradeRole::Buyer, OrderStatus::WaitingTakerBond);
        payable.bond = Some(bond(BondState::Requested, Some(NOW + 60)));
        assert_eq!(
            reasons(&funds_at_risk(&[payable.clone()], &[], NOW)),
            [FundsAtRiskReason::BondInvoicePending]
        );

        payable.bond = Some(bond(BondState::Requested, Some(NOW - 1)));
        assert!(funds_at_risk(&[payable.clone()], &[], NOW).is_empty());

        // Released and slashed bonds are history, not risk.
        for state in [BondState::Released, BondState::Slashed] {
            payable.bond = Some(bond(state, None));
            assert!(funds_at_risk(&[payable.clone()], &[], NOW).is_empty());
        }
    }

    #[test]
    fn a_payout_claim_counts_until_it_is_paid_or_lapses() {
        let open = [
            claim("a", BondClaimPhase::Pending, NOW + 60),
            claim("b", BondClaimPhase::Submitted, NOW + 60),
            claim("c", BondClaimPhase::Acknowledged, NOW + 60),
        ];
        let found = funds_at_risk(&[], &open, NOW);
        assert_eq!(found.len(), 3);
        assert!(found
            .iter()
            .all(|risk| risk.reason == FundsAtRiskReason::PayoutClaimOpen
                && risk.amount_sats == Some(700)));

        let over = [
            claim("d", BondClaimPhase::Completed, NOW + 60),
            claim("e", BondClaimPhase::Expired, NOW + 60),
            // Still `Pending` on disk, but its window has closed.
            claim("f", BondClaimPhase::Pending, NOW - 1),
        ];
        assert!(funds_at_risk(&[], &over, NOW).is_empty());
    }

    #[test]
    fn the_most_serious_reason_comes_first() {
        let mut bonded = trade("bond", TradeRole::Buyer, OrderStatus::WaitingTakerBond);
        bonded.bond = Some(bond(BondState::Requested, None));
        let trades = [
            bonded,
            trade("buying", TradeRole::Buyer, OrderStatus::Active),
            trade("selling", TradeRole::Seller, OrderStatus::FiatSent),
        ];
        let claims = [claim("claim", BondClaimPhase::Pending, NOW + 60)];
        assert_eq!(
            reasons(&funds_at_risk(&trades, &claims, NOW)),
            [
                FundsAtRiskReason::SellerEscrowLocked,
                FundsAtRiskReason::PayoutClaimOpen,
                FundsAtRiskReason::TradeInProgress,
                FundsAtRiskReason::BondInvoicePending,
            ]
        );
    }
}
