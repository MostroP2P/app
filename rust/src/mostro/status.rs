//! Order-status mapping and reconciliation rules.
//!
//! Pure functions, all of them: they translate between the daemon's wire
//! vocabulary (`mostro_core` actions and statuses) and this client's
//! `OrderStatus`, and decide when an inbound status may overwrite what is
//! already stored locally.
//!
//! Not to be confused with [`crate::mostro::fsm`]: that module answers
//! "may this role take this action from this state"; this one answers
//! "what does the daemon's wire vocabulary mean, and may it overwrite
//! what we already have".
//!
//! Extracted from `api/orders.rs`, where they had no business living: nothing
//! here is callable from Dart, and `api/` is the FRB bridge surface (#120).
//! Being pure and dependency-free, they are also the cheapest part of the
//! protocol logic to test directly.

use crate::api::types::OrderStatus;

/// Map a daemon action to the order status it implies, for messages that
/// carry no explicit status payload (action-only progression replies).
///
/// Shared by the status-sync arm in `dispatch_mostro_message` and by
/// `classify_take_reply`, so a take whose first reply is action-only (e.g.
/// `waiting-seller-to-pay` after a take-sell with a pre-attached LN address)
/// still persists the status the daemon already advanced to.
pub(crate) fn status_for_action(action: &mostro_core::message::Action) -> Option<OrderStatus> {
    use mostro_core::message::Action;
    match action {
        Action::AddInvoice => Some(OrderStatus::WaitingBuyerInvoice),
        Action::WaitingSellerToPay => Some(OrderStatus::WaitingPayment),
        Action::WaitingBuyerInvoice => Some(OrderStatus::WaitingBuyerInvoice),
        Action::BuyerTookOrder
        | Action::HoldInvoicePaymentAccepted
        | Action::BuyerInvoiceAccepted => Some(OrderStatus::Active),
        Action::FiatSentOk => Some(OrderStatus::FiatSent),
        Action::HoldInvoicePaymentSettled | Action::Released => {
            Some(OrderStatus::SettledHoldInvoice)
        }
        // The daemon accepted a replacement payout invoice after a failed
        // payout: the escrow is still settled and the payout is pending
        // again on the new invoice.
        Action::InvoiceUpdated => Some(OrderStatus::SettledHoldInvoice),
        Action::PurchaseCompleted => Some(OrderStatus::Success),
        Action::HoldInvoicePaymentCanceled => Some(OrderStatus::Canceled),
        Action::CooperativeCancelAccepted => Some(OrderStatus::CooperativelyCanceled),
        // Status doesn't change yet for cancel initiations; Rate/PaymentFailed
        // don't move the order either.
        Action::CooperativeCancelInitiatedByPeer
        | Action::CooperativeCancelInitiatedByYou
        | Action::Rate
        | Action::RateUser
        | Action::RateReceived
        | Action::PaymentFailed => None,
        Action::DisputeInitiatedByYou | Action::DisputeInitiatedByPeer => {
            Some(OrderStatus::Dispute)
        }
        Action::AdminSettled => Some(OrderStatus::SettledByAdmin),
        Action::AdminCanceled => Some(OrderStatus::CanceledByAdmin),
        _ => None,
    }
}

/// Maps a `mostro_core::order::Status` to the local [`OrderStatus`] enum.
pub(crate) fn map_core_status(s: mostro_core::order::Status) -> Option<OrderStatus> {
    use mostro_core::order::Status as S;
    Some(match s {
        S::Pending => OrderStatus::Pending,
        S::WaitingBuyerInvoice => OrderStatus::WaitingBuyerInvoice,
        S::WaitingPayment => OrderStatus::WaitingPayment,
        S::Active => OrderStatus::Active,
        S::InProgress => OrderStatus::InProgress,
        S::FiatSent => OrderStatus::FiatSent,
        S::SettledHoldInvoice => OrderStatus::SettledHoldInvoice,
        S::Success => OrderStatus::Success,
        S::Canceled => OrderStatus::Canceled,
        S::CooperativelyCanceled => OrderStatus::CooperativelyCanceled,
        S::Expired => OrderStatus::Expired,
        S::CanceledByAdmin => OrderStatus::CanceledByAdmin,
        S::SettledByAdmin => OrderStatus::SettledByAdmin,
        S::CompletedByAdmin => OrderStatus::CompletedByAdmin,
        S::Dispute => OrderStatus::Dispute,
        // Anti-abuse bond is out of scope; these statuses have no local
        // OrderStatus mapping. No wildcard, so future Status variants keep
        // forcing this match to be revisited.
        S::WaitingTakerBond | S::WaitingMakerBond => return None,
    })
}

/// Statuses no daemon message may leave: mostrod never reopens a canceled
/// or completed trade. `SettledHoldInvoice` and `Dispute` are deliberately
/// NOT here — they still progress (to `Success` / admin resolutions).
pub(crate) fn is_hard_terminal(status: &OrderStatus) -> bool {
    matches!(
        status,
        OrderStatus::Canceled
            | OrderStatus::CanceledByAdmin
            | OrderStatus::CooperativelyCanceled
            | OrderStatus::Expired
            | OrderStatus::Success
            | OrderStatus::SettledByAdmin
            | OrderStatus::CompletedByAdmin
    )
}

fn is_terminal_status(s: &OrderStatus) -> bool {
    matches!(
        s,
        OrderStatus::Success
            | OrderStatus::SettledHoldInvoice
            | OrderStatus::SettledByAdmin
            | OrderStatus::CompletedByAdmin
            | OrderStatus::Canceled
            | OrderStatus::CanceledByAdmin
            | OrderStatus::CooperativelyCanceled
            | OrderStatus::Expired
    )
}

pub(crate) fn wire_status_applies(local: Option<&OrderStatus>, wire: &OrderStatus) -> bool {
    match local {
        None | Some(OrderStatus::Pending) => true,
        Some(_) => is_terminal_status(wire),
    }
}

/// Whether a daemon `canceled` should wipe the local trade record instead of
/// keeping a Canceled history row.
///
/// True only while the trade never reached Active — no peer pubkey, no chat,
/// no exchange happened (typically a waiting-state timeout, or a maker
/// canceling their own pending order). Anything further along keeps its row
/// (and chat) as history. `InProgress` is deliberately NOT wiped: mostrod
/// never sends it over kind-14 — it only lands in a maker row via the Kind
/// 38383 sync, where it masks both waiting AND active phases (mostrod
/// nip33.rs publishes taken orders as `in-progress`), so it is ambiguous.
pub(crate) fn cancellation_wipes_history(status: &OrderStatus) -> bool {
    matches!(
        status,
        OrderStatus::Pending | OrderStatus::WaitingBuyerInvoice | OrderStatus::WaitingPayment
    )
}

/// Extracts the status and calculated sats to persist from an inbound
/// `add-invoice` payload.
///
/// Returns `None` when the payload carries no order data — notably the
/// daemon's follow-up `add-invoice` with a `Peer` payload (counterparty
/// reputation), which is deliberately not consumed yet.
pub(crate) fn add_invoice_sync(
    payload: &Option<mostro_core::message::Payload>,
) -> Option<(OrderStatus, Option<u64>)> {
    match payload {
        Some(mostro_core::message::Payload::Order(so)) => {
            let status = match so.status.and_then(map_core_status) {
                // After exhausting its payout retries the daemon asks the
                // buyer for a new invoice while the order itself still reads
                // `settled-hold-invoice` (mostro `check_failure_retries`). The
                // message is a request for action, so the trade must show
                // the buyer that an invoice is wanted, exactly as a first
                // `add-invoice` does; keeping the settled status would hide
                // the request and strand the payout.
                Some(OrderStatus::SettledHoldInvoice) | None => OrderStatus::WaitingBuyerInvoice,
                Some(status) => status,
            };
            let amount = if so.amount > 0 {
                Some(so.amount as u64)
            } else {
                None
            };
            Some((status, amount))
        }
        _ => None,
    }
}

/// Counterparty (taker) reputation from the daemon's follow-up `Peer` DM
/// (issue #305). The daemon rides it on the same `PayInvoice` / `AddInvoice`
/// action as the flow message, with an empty `pubkey` and the reputation
/// snapshot. Returns `(rating, reviews, operating_days)` when present.
///
/// `reputation` is `None` for a full-privacy taker; a brand-new user arrives
/// as all-zeros — the two are indistinguishable on the wire, so this only
/// reports whether a snapshot was carried, leaving the display to the UI.
pub(crate) fn peer_reputation(
    payload: &Option<mostro_core::message::Payload>,
) -> Option<(f64, u32, u32)> {
    match payload {
        Some(mostro_core::message::Payload::Peer(peer)) => peer.reputation.as_ref().map(|u| {
            // Saturate rather than wrap or zero out: reviews is an unconstrained
            // i64, so clamp negatives to 0 and anything past u32::MAX to u32::MAX
            // (defaulting overflow to 0 would turn a huge count into "no reviews").
            // operating_days is u64, so it only needs the upper bound.
            (
                u.rating,
                u.reviews.clamp(0, u32::MAX as i64) as u32,
                u.operating_days.min(u32::MAX as u64) as u32,
            )
        }),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mostro::test_fixtures::small_order_with;

    #[test]
    fn only_completed_payout_actions_imply_success() {
        use mostro_core::message::Action;
        assert_eq!(
            status_for_action(&Action::PurchaseCompleted),
            Some(OrderStatus::Success)
        );
        for action in [Action::Released, Action::HoldInvoicePaymentSettled] {
            assert_eq!(
                status_for_action(&action),
                Some(OrderStatus::SettledHoldInvoice)
            );
        }
        assert_eq!(status_for_action(&Action::PaymentFailed), None);
    }

    /// A replacement payout invoice the daemon accepted puts the trade back
    /// where it was before the failed payout: escrow settled, payout
    /// pending. Anything else would leave the buyer looking at
    /// `waiting-invoice` after the daemon already took the invoice.
    #[test]
    fn an_accepted_replacement_invoice_returns_the_trade_to_payout_pending() {
        use mostro_core::message::Action;
        assert_eq!(
            status_for_action(&Action::InvoiceUpdated),
            Some(OrderStatus::SettledHoldInvoice)
        );
    }

    /// After its payout retries are exhausted the daemon asks the buyer for
    /// a new invoice with an `add-invoice` whose order still reads
    /// `settled-hold-invoice`. That message is a request for action: it must
    /// move the trade to `WaitingBuyerInvoice`, which is what routes the buyer
    /// to the add-invoice screen. Keeping `SettledHoldInvoice` would make the
    /// request invisible and strand the payout.
    #[test]
    fn an_add_invoice_on_a_settled_escrow_asks_the_buyer_for_a_new_invoice() {
        use mostro_core::message::Payload;
        use mostro_core::order::Status;

        let so = small_order_with(Status::SettledHoldInvoice, 990);
        let (status, amount) =
            add_invoice_sync(&Some(Payload::Order(so))).expect("Order payload must sync");
        assert_eq!(status, crate::api::types::OrderStatus::WaitingBuyerInvoice);
        assert_eq!(amount, Some(990));
    }

    /// `SettledHoldInvoice` is terminal for status-sync purposes but not
    /// "hard" terminal: the escrow is settled and the payout may still be in
    /// flight, so history must survive it. Conflating the two would drop a
    /// trade the user is still waiting to be paid for.
    #[test]
    fn settled_hold_invoice_is_terminal_but_not_hard_terminal() {
        assert!(is_terminal_status(&OrderStatus::SettledHoldInvoice));
        assert!(!is_hard_terminal(&OrderStatus::SettledHoldInvoice));
        assert!(is_hard_terminal(&OrderStatus::Success));
        assert!(is_hard_terminal(&OrderStatus::Canceled));
    }

    /// The bond statuses have no local mapping on purpose, and `map_core_status`
    /// matches exhaustively so a new upstream variant fails the build rather
    /// than silently reading as something else.
    #[test]
    fn bond_statuses_map_to_nothing_rather_than_to_something_wrong() {
        use mostro_core::order::Status as S;
        assert_eq!(map_core_status(S::WaitingTakerBond), None);
        assert_eq!(map_core_status(S::WaitingMakerBond), None);
        assert_eq!(map_core_status(S::Active), Some(OrderStatus::Active));
    }

    /// Actions that carry no status change must return `None`, not a guess:
    /// a wrong `Some` here would move a trade on a message that never meant to.
    #[test]
    fn actions_without_a_status_change_return_none() {
        use mostro_core::message::Action;
        assert_eq!(status_for_action(&Action::Rate), None);
        assert_eq!(status_for_action(&Action::PaymentFailed), None);
        assert_eq!(
            status_for_action(&Action::CooperativeCancelInitiatedByPeer),
            None
        );
        assert_eq!(
            status_for_action(&Action::FiatSentOk),
            Some(OrderStatus::FiatSent)
        );
    }

    /// Both sides learn the escrow is locked from these two actions — the
    /// only signal that the trade reached Active, which is what the daemon
    /// requires before it accepts a dispute or a fiat-sent (issue #203).
    #[test]
    fn escrow_locked_actions_imply_active() {
        use mostro_core::message::Action;

        assert_eq!(
            status_for_action(&Action::BuyerTookOrder),
            Some(OrderStatus::Active)
        );
        assert_eq!(
            status_for_action(&Action::HoldInvoicePaymentAccepted),
            Some(OrderStatus::Active)
        );
    }

    /// The public event is NIP-69's coarse view and stops updating once the
    /// trade turns private, so it may only fill an unknown or still-pending
    /// status — or announce a terminal one (issue #203).
    #[test]
    fn the_public_status_never_replaces_a_finer_local_one() {
        use OrderStatus as S;

        assert!(wire_status_applies(None, &S::InProgress));
        assert!(wire_status_applies(Some(&S::Pending), &S::InProgress));

        for local in [
            S::WaitingPayment,
            S::WaitingBuyerInvoice,
            S::Active,
            S::FiatSent,
            S::Dispute,
        ] {
            assert!(
                !wire_status_applies(Some(&local), &S::InProgress),
                "in-progress must not overwrite {local:?}"
            );
            assert!(
                !wire_status_applies(Some(&local), &S::Pending),
                "pending must not overwrite {local:?}"
            );
            assert!(
                wire_status_applies(Some(&local), &S::Canceled),
                "a terminal wire status must reach {local:?}"
            );
            assert!(wire_status_applies(Some(&local), &S::Success));
        }
    }

    /// Inbound add-invoice (maker-buyer path): the Order payload carries the
    /// status and calculated sats to persist; anything else — notably the
    /// daemon's follow-up Peer payload with the counterparty's reputation —
    /// syncs nothing.
    #[test]
    fn add_invoice_sync_maps_payloads() {
        use mostro_core::message::Payload;
        use mostro_core::order::Status;

        // Real-world shape from the reproduction: status + calculated sats.
        let so = small_order_with(Status::WaitingBuyerInvoice, 484);
        match add_invoice_sync(&Some(Payload::Order(so))) {
            Some((status, amount)) => {
                assert_eq!(status, crate::api::types::OrderStatus::WaitingBuyerInvoice);
                assert_eq!(amount, Some(484));
            }
            None => panic!("expected Order payload to sync"),
        }

        // Unpriced amount must not persist as Some(0).
        let so = small_order_with(Status::WaitingBuyerInvoice, 0);
        let (_, amount) =
            add_invoice_sync(&Some(Payload::Order(so))).expect("Order payload must sync");
        assert_eq!(amount, None);

        // The daemon's follow-up Peer payload (counterparty reputation) must
        // sync nothing — it would otherwise clobber the just-written status.
        let peer = Payload::Peer(mostro_core::message::Peer {
            pubkey: String::new(),
            reputation: None,
        });
        assert!(add_invoice_sync(&Some(peer)).is_none());

        // No payload → nothing to sync.
        assert!(add_invoice_sync(&None).is_none());
    }

    /// The follow-up Peer payload that `add_invoice_sync` ignores is exactly
    /// what `peer_reputation` must pick up: the counterparty's reputation
    /// snapshot rides here (issue #305), with an empty pubkey.
    #[test]
    fn peer_reputation_reads_the_snapshot_add_invoice_sync_ignores() {
        use mostro_core::message::{Payload, Peer};
        use mostro_core::user::UserInfo;

        // Real-world shape from the reproduction: rating 4.375, 4 reviews, 64 days.
        let peer = Payload::Peer(Peer {
            pubkey: String::new(),
            reputation: Some(UserInfo {
                rating: 4.375,
                reviews: 4,
                operating_days: 64,
            }),
        });
        assert_eq!(peer_reputation(&Some(peer)), Some((4.375, 4, 64)));

        // A full-privacy taker carries no snapshot.
        let private = Payload::Peer(Peer {
            pubkey: String::new(),
            reputation: None,
        });
        assert_eq!(peer_reputation(&Some(private)), None);

        // A brand-new user is all-zeros but still a snapshot — not None.
        let fresh = Payload::Peer(Peer {
            pubkey: String::new(),
            reputation: Some(UserInfo {
                rating: 0.0,
                reviews: 0,
                operating_days: 0,
            }),
        });
        assert_eq!(peer_reputation(&Some(fresh)), Some((0.0, 0, 0)));

        // Non-Peer payloads and the empty case carry no reputation.
        let so = small_order_with(mostro_core::order::Status::WaitingBuyerInvoice, 484);
        assert_eq!(peer_reputation(&Some(Payload::Order(so))), None);
        assert_eq!(peer_reputation(&None), None);
    }

    /// `reviews` is an unconstrained i64 and `operating_days` a u64, so
    /// out-of-range values must saturate into u32, not wrap or collapse to 0 —
    /// a huge count reading as "no reviews" would be worse than clamping.
    #[test]
    fn peer_reputation_saturates_out_of_range_counts() {
        use mostro_core::message::{Payload, Peer};
        use mostro_core::user::UserInfo;

        let peer = |reviews: i64, operating_days: u64| {
            Payload::Peer(Peer {
                pubkey: String::new(),
                reputation: Some(UserInfo {
                    rating: 5.0,
                    reviews,
                    operating_days,
                }),
            })
        };

        // Above u32::MAX saturates to u32::MAX, not 0 / wraparound.
        assert_eq!(
            peer_reputation(&Some(peer(i64::MAX, u64::MAX))),
            Some((5.0, u32::MAX, u32::MAX))
        );
        // Exact boundary is preserved; one past it saturates.
        assert_eq!(
            peer_reputation(&Some(peer(u32::MAX as i64, u32::MAX as u64))),
            Some((5.0, u32::MAX, u32::MAX))
        );
        assert_eq!(
            peer_reputation(&Some(peer(u32::MAX as i64 + 1, u32::MAX as u64 + 1))),
            Some((5.0, u32::MAX, u32::MAX))
        );
        // A negative review count clamps to 0.
        assert_eq!(peer_reputation(&Some(peer(-7, 0))), Some((5.0, 0, 0)));
    }

    /// The hard-terminal set must match protocol finality: statuses mostrod
    /// never reopens block replayed syncs, while statuses that still
    /// progress (settled → success, dispute → admin resolution) must not.
    #[test]
    fn hard_terminal_matches_protocol_finality() {
        use crate::api::types::OrderStatus as S;
        for s in [
            S::Canceled,
            S::CanceledByAdmin,
            S::CooperativelyCanceled,
            S::Expired,
            S::Success,
            S::SettledByAdmin,
            S::CompletedByAdmin,
        ] {
            assert!(is_hard_terminal(&s), "{s:?} must be terminal");
        }
        for s in [
            S::Pending,
            S::WaitingBuyerInvoice,
            S::WaitingPayment,
            S::Active,
            S::FiatSent,
            S::SettledHoldInvoice,
            S::Dispute,
            S::InProgress,
        ] {
            assert!(!is_hard_terminal(&s), "{s:?} must not be terminal");
        }
    }

    /// Only never-active trades are wiped on a daemon `canceled`; anything
    /// that progressed (or is ambiguous, like InProgress) keeps its history row.
    #[test]
    fn cancellation_wipes_history_only_for_never_active_trades() {
        use crate::api::types::OrderStatus as S;
        for s in [S::Pending, S::WaitingBuyerInvoice, S::WaitingPayment] {
            assert!(cancellation_wipes_history(&s), "{s:?} must be wiped");
        }
        for s in [
            S::InProgress,
            S::Active,
            S::FiatSent,
            S::Dispute,
            S::Success,
            S::Canceled,
            S::CooperativelyCanceled,
            S::CanceledByAdmin,
        ] {
            assert!(!cancellation_wipes_history(&s), "{s:?} must keep history");
        }
    }

    /// Every `Prefix.name` in `text`, in order — `TradeStatus.pending` → `pending`.
    fn dotted_names<'a>(text: &'a str, prefix: &str) -> Vec<&'a str> {
        text.split(prefix)
            .skip(1)
            .map(|rest| {
                let end = rest
                    .find(|c: char| !c.is_ascii_alphanumeric())
                    .unwrap_or(rest.len());
                &rest[..end]
            })
            .collect()
    }

    /// The trade screen keeps its own copy of this predicate,
    /// `_cancelEndsTrade` in `trade_detail_screen.dart`: it picks the cancel
    /// dialog's copy and decides whether the screen leaves after a cancel.
    /// Asking Rust instead would be the bridge's first synchronous call. So
    /// this pins the two together, reading the Dart source: add or drop a
    /// status here and this fails, instead of the dialog promising an
    /// immediate cancel that the daemon runs as a cooperative request, or the
    /// screen staying open on a trade that was wiped.
    #[test]
    fn the_trade_screen_copy_of_cancellation_wipes_history_matches() {
        use crate::api::types::OrderStatus as S;
        use std::collections::{BTreeMap, BTreeSet};

        let all = [
            S::Pending,
            S::WaitingBuyerInvoice,
            S::WaitingPayment,
            S::Active,
            S::FiatSent,
            S::SettledHoldInvoice,
            S::Success,
            S::Canceled,
            S::Expired,
            S::CooperativelyCanceled,
            S::CanceledByAdmin,
            S::SettledByAdmin,
            S::CompletedByAdmin,
            S::Dispute,
            S::InProgress,
        ];
        // Exhaustive on purpose: a new status fails to compile here, which is
        // the reminder to add it to `all` above.
        for s in &all {
            match s {
                S::Pending
                | S::WaitingBuyerInvoice
                | S::WaitingPayment
                | S::Active
                | S::FiatSent
                | S::SettledHoldInvoice
                | S::Success
                | S::Canceled
                | S::Expired
                | S::CooperativelyCanceled
                | S::CanceledByAdmin
                | S::SettledByAdmin
                | S::CompletedByAdmin
                | S::Dispute
                | S::InProgress => {}
            }
        }
        // The Dart name flutter_rust_bridge gives each variant: lower camel case.
        let dart_order_status = |s: &S| {
            let debug = format!("{s:?}");
            let mut chars = debug.chars();
            let first = chars.next().expect("a variant name");
            format!("{}{}", first.to_ascii_lowercase(), chars.as_str())
        };

        // The screen's `OrderStatus` → `TradeStatus` mapping, read from source.
        let mapping_src = include_str!("../../../lib/features/trades/models/trade_status.dart");
        let body = mapping_src
            .split("TradeStatus tradeStatusFromOrderStatus(OrderStatus s) => switch (s) {")
            .nth(1)
            .and_then(|rest| rest.split("};").next())
            .expect("tradeStatusFromOrderStatus's switch in trade_status.dart");
        let mut to_trade_status = BTreeMap::new();
        for arm in body.split(',') {
            let Some((statuses, trade)) = arm.split_once("=>") else {
                continue;
            };
            let trade = dotted_names(trade, "TradeStatus.")
                .first()
                .copied()
                .expect("an arm maps to a TradeStatus");
            for status in dotted_names(statuses, "OrderStatus.") {
                to_trade_status.insert(status.to_string(), trade);
            }
        }

        // The screen's set, read from source.
        let screen_src =
            include_str!("../../../lib/features/trades/screens/trade_detail_screen.dart");
        let set = screen_src
            .split("static bool _cancelEndsTrade(TradeStatus status) => const {")
            .nth(1)
            .and_then(|rest| rest.split("}.contains(status)").next())
            .expect("_cancelEndsTrade's set in trade_detail_screen.dart");
        let listed: BTreeSet<&str> = dotted_names(set, "TradeStatus.").into_iter().collect();

        let mut expected = BTreeSet::new();
        for s in &all {
            let name = dart_order_status(s);
            let trade = *to_trade_status
                .get(&name)
                .unwrap_or_else(|| panic!("trade_status.dart maps no OrderStatus.{name}"));
            if cancellation_wipes_history(s) {
                expected.insert(trade);
            } else {
                assert!(
                    !listed.contains(trade),
                    "{s:?} keeps its history, yet the screen treats TradeStatus.{trade} \
                     as ending the trade"
                );
            }
        }
        assert_eq!(
            listed, expected,
            "_cancelEndsTrade in trade_detail_screen.dart must list exactly the \
             TradeStatus values of the statuses cancellation_wipes_history wipes"
        );
    }
}
