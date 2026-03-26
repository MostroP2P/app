/// Order state machine — Mostro protocol transition validator.
///
/// Enforces the 15-state transition graph from data-model.md.
/// All state changes MUST go through `transition()` to ensure protocol
/// compliance.
///
/// Key invariants:
/// - PaymentFailed is an Action, NOT a status transition.
///   When received, order stays in SettledHoldInvoice.
/// - CooperativelyCanceled is client-side only; the daemon does not emit
///   a status-change for it. It is set locally when both parties accept.
use crate::api::types::OrderStatus;

/// Attempt a state transition from `current` to `next`.
/// Returns `Ok(())` if the transition is valid, `Err` otherwise.
pub fn transition(current: OrderStatus, next: OrderStatus) -> Result<(), TransitionError> {
    if is_valid_transition(current, next) {
        Ok(())
    } else {
        Err(TransitionError::Invalid { from: current, to: next })
    }
}

#[derive(Debug)]
pub enum TransitionError {
    Invalid { from: OrderStatus, to: OrderStatus },
}

impl std::fmt::Display for TransitionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TransitionError::Invalid { from, to } => {
                write!(f, "invalid state transition: {:?} → {:?}", from, to)
            }
        }
    }
}

impl std::error::Error for TransitionError {}

/// Returns true if the `from → to` transition is valid per protocol.
pub fn is_valid_transition(from: OrderStatus, to: OrderStatus) -> bool {
    use OrderStatus::*;
    matches!(
        (from, to),
        // Pending can go to WaitingBuyerInvoice (sell orders) or Canceled
        (Pending, WaitingBuyerInvoice)
        | (Pending, WaitingPayment)     // buy orders skip WaitingBuyerInvoice
        | (Pending, Canceled)

        // WaitingBuyerInvoice → WaitingPayment (buyer provided invoice)
        | (WaitingBuyerInvoice, WaitingPayment)
        | (WaitingBuyerInvoice, Canceled)

        // WaitingPayment → Active (hold invoice paid) | Expired (timeout)
        | (WaitingPayment, Active)
        | (WaitingPayment, Expired)
        | (WaitingPayment, Canceled)

        // Active → FiatSent | Dispute | CooperativelyCanceled (client-side)
        | (Active, FiatSent)
        | (Active, Dispute)
        | (Active, CooperativelyCanceled)

        // FiatSent → SettledHoldInvoice (seller confirmed release) | Dispute
        | (FiatSent, SettledHoldInvoice)
        | (FiatSent, Dispute)

        // SettledHoldInvoice → Success (LN payment succeeded)
        // NOTE: on PaymentFailed action → order STAYS in SettledHoldInvoice;
        // this is NOT a state transition.
        | (SettledHoldInvoice, Success)

        // Dispute → InProgress (admin engaged) or direct admin resolution
        | (Dispute, InProgress)
        | (Dispute, CanceledByAdmin)
        | (Dispute, SettledByAdmin)
        | (Dispute, CompletedByAdmin)

        // InProgress → admin resolutions
        | (InProgress, CanceledByAdmin)
        | (InProgress, SettledByAdmin)
        | (InProgress, CompletedByAdmin)
    )
}

/// Determine the TradeStep from the current order status and user role.
pub fn trade_step_from_status(
    status: OrderStatus,
    role: crate::api::types::TradeRole,
    is_disputed: bool,
) -> crate::api::types::TradeStep {
    use crate::api::types::{BuyerStep, SellerStep, TradeRole, TradeStep};
    use OrderStatus::*;

    if is_disputed {
        return TradeStep::Disputed;
    }

    match role {
        TradeRole::Buyer => TradeStep::Buyer(match status {
            Pending | WaitingBuyerInvoice | WaitingPayment => BuyerStep::OrderTaken,
            Active => BuyerStep::PaymentLocked,
            FiatSent => BuyerStep::FiatSent,
            SettledHoldInvoice => BuyerStep::AwaitingRelease,
            Success | CooperativelyCanceled => BuyerStep::Complete,
            _ => BuyerStep::OrderTaken,
        }),
        TradeRole::Seller => TradeStep::Seller(match status {
            Pending => SellerStep::OrderPublished,
            WaitingBuyerInvoice => SellerStep::TakerFound,
            WaitingPayment => SellerStep::InvoiceCreated,
            Active => SellerStep::PaymentLocked,
            FiatSent | SettledHoldInvoice => SellerStep::AwaitingFiat,
            Success | CooperativelyCanceled => SellerStep::Complete,
            _ => SellerStep::OrderPublished,
        }),
    }
}

/// Determine a TradeOutcome from a terminal order status.
/// Returns None for non-terminal statuses.
pub fn outcome_from_status(status: OrderStatus) -> Option<crate::api::types::TradeOutcome> {
    use crate::api::types::TradeOutcome;
    use OrderStatus::*;
    match status {
        Success => Some(TradeOutcome::Success),
        Canceled | CooperativelyCanceled => Some(TradeOutcome::Canceled),
        Expired => Some(TradeOutcome::Expired),
        CanceledByAdmin => Some(TradeOutcome::Canceled),
        SettledByAdmin | CompletedByAdmin => Some(TradeOutcome::Success),
        _ => None,
    }
}

/// Returns true if the order is in a terminal state (no further transitions).
pub fn is_terminal(status: OrderStatus) -> bool {
    use OrderStatus::*;
    matches!(
        status,
        Success
            | Canceled
            | CooperativelyCanceled
            | Expired
            | CanceledByAdmin
            | SettledByAdmin
            | CompletedByAdmin
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::types::OrderStatus::*;

    #[test]
    fn valid_happy_path_sell() {
        assert!(is_valid_transition(Pending, WaitingBuyerInvoice));
        assert!(is_valid_transition(WaitingBuyerInvoice, WaitingPayment));
        assert!(is_valid_transition(WaitingPayment, Active));
        assert!(is_valid_transition(Active, FiatSent));
        assert!(is_valid_transition(FiatSent, SettledHoldInvoice));
        assert!(is_valid_transition(SettledHoldInvoice, Success));
    }

    #[test]
    fn valid_happy_path_buy() {
        assert!(is_valid_transition(Pending, WaitingPayment));
        assert!(is_valid_transition(WaitingPayment, Active));
        assert!(is_valid_transition(Active, FiatSent));
    }

    #[test]
    fn invalid_backward_transition() {
        assert!(!is_valid_transition(Active, Pending));
        assert!(!is_valid_transition(Success, Active));
    }

    #[test]
    fn terminal_states_have_no_valid_transitions() {
        let terminals = [Success, Canceled, Expired, CanceledByAdmin, SettledByAdmin];
        let all = [
            Pending, WaitingBuyerInvoice, WaitingPayment, Active, FiatSent,
            SettledHoldInvoice, Success, Canceled, Expired, CooperativelyCanceled,
            CanceledByAdmin, SettledByAdmin, CompletedByAdmin, Dispute, InProgress,
        ];
        for &terminal in &terminals {
            for &next in &all {
                if !is_terminal(next) {
                    assert!(!is_valid_transition(terminal, next),
                        "terminal {:?} should not transition to {:?}", terminal, next);
                }
            }
        }
    }
}
