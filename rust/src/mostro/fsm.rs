/// Mostro protocol finite state machine.
///
/// 15 `OrderStatus` states with allowed actions per role.
/// Reference: data-model.md state machine, contracts/types.md.
use crate::api::types::{OrderStatus, TradeRole};

/// Actions a participant can take on an order/trade.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    NewOrder,
    TakeBuy,
    TakeSell,
    AddInvoice,
    PayInvoice,
    FiatSent,
    Release,
    Cancel,
    CooperativeCancel,
    AcceptCooperativeCancel,
    Dispute,
    AdminTakeDispute,
    AdminCancel,
    AdminSettle,
    AdminComplete,
}

/// Compute the next status given the current status, action, and role.
///
/// Returns `None` if the transition is not allowed.
pub fn next_status(current: &OrderStatus, action: Action, role: TradeRole) -> Option<OrderStatus> {
    match (current, action, role) {
        // ── Order creation ──────────────────────────────────────────────
        (_, Action::NewOrder, _) => Some(OrderStatus::Pending),

        // ── Taking an order ─────────────────────────────────────────────
        (OrderStatus::Pending, Action::TakeBuy, TradeRole::Buyer) => Some(OrderStatus::WaitingBuyerInvoice),
        (OrderStatus::Pending, Action::TakeSell, TradeRole::Seller) => Some(OrderStatus::WaitingPayment),

        // ── Invoice flow ────────────────────────────────────────────────
        (OrderStatus::WaitingBuyerInvoice, Action::AddInvoice, TradeRole::Buyer) => Some(OrderStatus::WaitingPayment),

        // ── Payment locked → Active ─────────────────────────────────────
        (OrderStatus::WaitingPayment, Action::PayInvoice, TradeRole::Seller) => Some(OrderStatus::Active),

        // ── Fiat sent ───────────────────────────────────────────────────
        (OrderStatus::Active, Action::FiatSent, TradeRole::Buyer) => Some(OrderStatus::FiatSent),

        // ── Release (seller confirms fiat received) ─────────────────────
        (OrderStatus::FiatSent, Action::Release, TradeRole::Seller) => Some(OrderStatus::SettledHoldInvoice),

        // ── Cancellation ────────────────────────────────────────────────
        (OrderStatus::Pending, Action::Cancel, _) => Some(OrderStatus::Canceled),

        // Cooperative cancel — either party can request.
        (OrderStatus::Active, Action::CooperativeCancel, _) => Some(OrderStatus::Active),
        (OrderStatus::Active, Action::AcceptCooperativeCancel, _) => Some(OrderStatus::CooperativelyCanceled),
        (OrderStatus::FiatSent, Action::CooperativeCancel, _) => Some(OrderStatus::FiatSent),
        (OrderStatus::FiatSent, Action::AcceptCooperativeCancel, _) => Some(OrderStatus::CooperativelyCanceled),

        // ── Dispute ─────────────────────────────────────────────────────
        (OrderStatus::Active, Action::Dispute, _) => Some(OrderStatus::Dispute),
        (OrderStatus::FiatSent, Action::Dispute, _) => Some(OrderStatus::Dispute),

        // ── Admin actions ───────────────────────────────────────────────
        (OrderStatus::Dispute, Action::AdminTakeDispute, _) => Some(OrderStatus::InProgress),
        (OrderStatus::Dispute, Action::AdminCancel, _) => Some(OrderStatus::CanceledByAdmin),
        (OrderStatus::Dispute, Action::AdminSettle, _) => Some(OrderStatus::SettledByAdmin),
        (OrderStatus::Dispute, Action::AdminComplete, _) => Some(OrderStatus::CompletedByAdmin),
        (OrderStatus::InProgress, Action::AdminCancel, _) => Some(OrderStatus::CanceledByAdmin),
        (OrderStatus::InProgress, Action::AdminSettle, _) => Some(OrderStatus::SettledByAdmin),
        (OrderStatus::InProgress, Action::AdminComplete, _) => Some(OrderStatus::CompletedByAdmin),

        _ => None,
    }
}

/// Check whether a given action is allowed for the role in the current status.
pub fn is_action_allowed(current: &OrderStatus, action: Action, role: TradeRole) -> bool {
    next_status(current, action, role).is_some()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sell_order_happy_path() {
        assert_eq!(next_status(&OrderStatus::Pending, Action::TakeBuy, TradeRole::Buyer), Some(OrderStatus::WaitingBuyerInvoice));
        assert_eq!(next_status(&OrderStatus::WaitingBuyerInvoice, Action::AddInvoice, TradeRole::Buyer), Some(OrderStatus::WaitingPayment));
        assert_eq!(next_status(&OrderStatus::WaitingPayment, Action::PayInvoice, TradeRole::Seller), Some(OrderStatus::Active));
        assert_eq!(next_status(&OrderStatus::Active, Action::FiatSent, TradeRole::Buyer), Some(OrderStatus::FiatSent));
        assert_eq!(next_status(&OrderStatus::FiatSent, Action::Release, TradeRole::Seller), Some(OrderStatus::SettledHoldInvoice));
    }

    #[test]
    fn buy_order_happy_path() {
        assert_eq!(next_status(&OrderStatus::Pending, Action::TakeSell, TradeRole::Seller), Some(OrderStatus::WaitingPayment));
    }

    #[test]
    fn cancel_pending_order() {
        assert_eq!(next_status(&OrderStatus::Pending, Action::Cancel, TradeRole::Buyer), Some(OrderStatus::Canceled));
        assert_eq!(next_status(&OrderStatus::Pending, Action::Cancel, TradeRole::Seller), Some(OrderStatus::Canceled));
    }

    #[test]
    fn dispute_from_active() {
        assert_eq!(next_status(&OrderStatus::Active, Action::Dispute, TradeRole::Buyer), Some(OrderStatus::Dispute));
        assert_eq!(next_status(&OrderStatus::Active, Action::Dispute, TradeRole::Seller), Some(OrderStatus::Dispute));
    }

    #[test]
    fn invalid_transitions_rejected() {
        assert_eq!(next_status(&OrderStatus::Pending, Action::FiatSent, TradeRole::Buyer), None);
        assert_eq!(next_status(&OrderStatus::Active, Action::Release, TradeRole::Seller), None);
        assert_eq!(next_status(&OrderStatus::Success, Action::TakeBuy, TradeRole::Buyer), None);
    }
}
