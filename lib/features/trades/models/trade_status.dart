import 'package:mostro/src/rust/api/types.dart';

/// Type-safe trade status for the trade screen.
///
/// The public order book only publishes NIP-69's coarse buckets, so most of
/// these come from daemon messages (see `tradeStatusProvider`); the two that
/// do not — [pendingRating] and [rated] — are overlaid locally (#327).
enum TradeStatus {
  /// Status not yet resolved (initial loading state — no actions shown).
  loading('Loading'),

  /// Order published but not yet taken by a counterpart.
  pending('Pending'),

  /// Buyer must submit Lightning invoice (waitingBuyerInvoice).
  waitingInvoice('Waiting Invoice'),

  /// Seller must pay hold invoice (waitingPayment).
  waitingPayment('Waiting Payment'),

  /// The user's anti-abuse bond is outstanding (waitingTakerBond /
  /// waitingMakerBond): the daemon parked the take, or holds the order
  /// unpublished, until the bond bolt11 is paid. See
  /// `docs/ANTI_ABUSE_BOND.md` §6.1 / §6.2.
  waitingBond('Waiting Bond'),

  /// Taken, real state unknown: the public order book only publishes NIP-69's
  /// coarse buckets, so `in-progress` says the order left the book — never
  /// that the escrow is locked. Offering the actions of [active] here is what
  /// the daemon rejects with `CantDo` (issue #203).
  inProgress('In Progress'),
  active('Active'),
  fiatSent('Fiat Sent'),

  /// Seller escrow settled; the buyer payout has not completed yet.
  payoutPending('Payout pending'),
  completed('Completed'),
  cancelled('Cancelled'),
  disputed('Disputed'),

  /// Trade completed; counterpart rating prompt shown.
  /// Maps to `Action.rate` / `Action.rateUser` from the Rust bridge.
  pendingRating('Rate'),

  /// Rating has been submitted (or skipped).
  /// Maps to `Action.rateReceived` — no further actions shown.
  rated('Rated');

  const TradeStatus(this.label);
  final String label;
}

/// Stable, locale-independent name of a trade status.
///
/// This is what the `order.status` readout exposes, and it is a product
/// contract: automation maps these names to protocol states and cannot use
/// the localized chip copy. See `docs/automation-contract.md`.
extension TradeStatusMachineName on TradeStatus {
  /// `TradeStatus.waitingInvoice` → `waiting-invoice`.
  String get machineName =>
      name.replaceAllMapped(RegExp(r'[A-Z]'), (m) => '-${m[0]!.toLowerCase()}');
}

/// Maps a protocol order status to the status the trade screen displays.
///
/// Public so `MyOrderScreen` exposes the same vocabulary from its own status
/// card: a pending order the user created is opened there, not on the trade
/// screen, and the two must not disagree about what state it is in.
TradeStatus tradeStatusFromOrderStatus(OrderStatus s) => switch (s) {
  OrderStatus.pending => TradeStatus.pending,
  OrderStatus.waitingBuyerInvoice => TradeStatus.waitingInvoice,
  OrderStatus.waitingPayment => TradeStatus.waitingPayment,
  OrderStatus.waitingTakerBond ||
  OrderStatus.waitingMakerBond => TradeStatus.waitingBond,
  OrderStatus.active => TradeStatus.active,
  OrderStatus.inProgress => TradeStatus.inProgress,
  OrderStatus.fiatSent => TradeStatus.fiatSent,
  OrderStatus.settledHoldInvoice => TradeStatus.payoutPending,
  OrderStatus.success ||
  OrderStatus.completedByAdmin ||
  OrderStatus.settledByAdmin => TradeStatus.pendingRating,
  OrderStatus.canceled ||
  OrderStatus.canceledByAdmin ||
  OrderStatus.cooperativelyCanceled ||
  OrderStatus.expired => TradeStatus.cancelled,
  OrderStatus.dispute => TradeStatus.disputed,
};

/// The status a trade shows to one side of it: [tradeStatusFromOrderStatus],
/// except once the seller has released (#586).
///
/// At `settled-hold-invoice` the seller's part is over — getting the sats to
/// the buyer is Mostro's job — and the daemon says so itself: it sends the
/// seller `rate` together with the release, and accepts the seller's rating
/// in that status (mostrod `release.rs`, `rate_user.rs`). So the seller goes
/// straight to rating instead of waiting on a payout they cannot affect, and
/// that may take long if it fails and retries. Nothing reaches the seller
/// after the release either — `purchase-completed` goes to the buyer only.
///
/// The buyer keeps [TradeStatus.payoutPending]: those are their sats in
/// flight, and the daemon refuses the buyer's rating until `success`.
///
/// Everything that decides a trade's step for the user — the trade screen,
/// the rating screen, the trades list and its "needs your action" count —
/// reads this, so none of them can disagree about whose turn it is.
TradeStatus tradeStatusFor(OrderStatus s, {required bool isBuyer}) =>
    s == OrderStatus.settledHoldInvoice && !isBuyer
        ? TradeStatus.pendingRating
        : tradeStatusFromOrderStatus(s);
