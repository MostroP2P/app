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
