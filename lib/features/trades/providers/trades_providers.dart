import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart'
    show needsActionCountProvider;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart' as rust_types;

// ── TradeStatusFilter ─────────────────────────────────────────────────────────

/// Possible values for the My Trades status filter dropdown.
enum TradeStatusFilter {
  all('All'),
  pending('Pending'),
  waitingInvoice('Waiting Invoice'),
  waitingPayment('Waiting Payment'),
  active('Active'),
  fiatSent('Fiat Sent'),
  payoutPending('Payout pending'),
  success('Success'),
  canceled('Canceled'),
  dispute('Dispute');

  const TradeStatusFilter(this.label);
  final String label;
}

/// Localized display label for the status filter dropdown.
extension TradeStatusFilterL10n on TradeStatusFilter {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    TradeStatusFilter.all => l10n.tradeFilterAll,
    TradeStatusFilter.pending => l10n.tradeFilterPending,
    TradeStatusFilter.waitingInvoice => l10n.tradeFilterWaitingInvoice,
    TradeStatusFilter.waitingPayment => l10n.tradeFilterWaitingPayment,
    TradeStatusFilter.active => l10n.tradeFilterActive,
    TradeStatusFilter.fiatSent => l10n.tradeFilterFiatSent,
    TradeStatusFilter.payoutPending => l10n.tradeStatusPayoutPending,
    TradeStatusFilter.success => l10n.tradeFilterSuccess,
    TradeStatusFilter.canceled => l10n.tradeFilterCanceled,
    TradeStatusFilter.dispute => l10n.tradeFilterDispute,
  };
}

// ── Status mapping ────────────────────────────────────────────────────────────

/// Maps a Rust [rust_types.OrderStatus] to its [TradeStatusFilter] bucket.
TradeStatusFilter orderStatusToFilter(rust_types.OrderStatus status) {
  return switch (status) {
    rust_types.OrderStatus.pending => TradeStatusFilter.pending,
    rust_types.OrderStatus.waitingBuyerInvoice =>
      TradeStatusFilter.waitingInvoice,
    rust_types.OrderStatus.waitingPayment => TradeStatusFilter.waitingPayment,
    // A bond is a payment the user owes before the trade starts.
    rust_types.OrderStatus.waitingTakerBond ||
    rust_types.OrderStatus.waitingMakerBond => TradeStatusFilter.waitingPayment,
    rust_types.OrderStatus.active => TradeStatusFilter.active,
    rust_types.OrderStatus.inProgress => TradeStatusFilter.active,
    rust_types.OrderStatus.fiatSent => TradeStatusFilter.fiatSent,
    rust_types.OrderStatus.settledHoldInvoice =>
      TradeStatusFilter.payoutPending,
    rust_types.OrderStatus.success => TradeStatusFilter.success,
    rust_types.OrderStatus.settledByAdmin => TradeStatusFilter.success,
    rust_types.OrderStatus.completedByAdmin => TradeStatusFilter.success,
    rust_types.OrderStatus.canceled => TradeStatusFilter.canceled,
    rust_types.OrderStatus.expired => TradeStatusFilter.canceled,
    rust_types.OrderStatus.cooperativelyCanceled => TradeStatusFilter.canceled,
    rust_types.OrderStatus.canceledByAdmin => TradeStatusFilter.canceled,
    rust_types.OrderStatus.dispute => TradeStatusFilter.dispute,
  };
}

// ── Raw trade list from DB ────────────────────────────────────────────────────

/// Loads all trades from the Rust DB, sorted newest-first.
///
/// Exposed so callers (e.g. [refreshTrades]) can invalidate it when new trades
/// are added. Per-row live status comes from [tradeStatusProvider].
final rawTradesProvider = FutureProvider<List<rust_types.TradeInfo>>((ref) {
  // Refetch whenever Rust pushes a trade lifecycle change: a daemon cancel
  // wipes the row (it must leave My Trades no matter which screen is open)
  // and a sweep resync rewrites its status — pull-to-refresh must not be
  // the only way to observe either.
  ref.listen(tradeUpdatesProvider, (_, __) => ref.invalidateSelf());
  return orders_api.listTrades();
});

/// Returns the [rust_types.TradeInfo] for a given [orderId], or null if not found.
///
/// Used by screens that need trade-level fields (e.g. [holdInvoice], [timeoutAt])
/// that are not present on the order-book [OrderInfo].
final tradeInfoProvider = FutureProvider.autoDispose
    .family<rust_types.TradeInfo?, String>((ref, orderId) async {
      final trades = await ref.watch(rawTradesProvider.future);
      return trades.where((t) => t.order.id == orderId).firstOrNull;
    });

/// Invalidates the raw trades cache, forcing a fresh DB fetch on next read.
///
/// Call this after a trade is successfully saved (e.g. after [takeOrder]).
void refreshTrades(WidgetRef ref) => ref.invalidate(rawTradesProvider);

// ── Badge notification count ──────────────────────────────────────────────────

/// Badge of the trades tab: the trades whose next step is the user's — the
/// same figure as the `Requieren tu acción` counter (handoff 11a), not every
/// trade whose status moved.
final orderBookNotificationCountProvider = Provider<int>(
  (ref) => ref.watch(needsActionCountProvider),
);
