import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/shared/providers/nav_providers.dart';
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
  success('Success'),
  canceled('Canceled'),
  dispute('Dispute');

  const TradeStatusFilter(this.label);
  final String label;
}

// ── TradeRole ─────────────────────────────────────────────────────────────────

/// Whether the local user created this trade (maker) or took it (taker).
enum TradeRole { creator, taker }

// ── TradeListItem model ───────────────────────────────────────────────────────

/// Immutable UI-layer model for one trade row in the My Trades list.
@immutable
class TradeListItem {
  const TradeListItem({
    required this.orderId,
    required this.isSelling,
    required this.status,
    required this.role,
    required this.fiatAmount,
    required this.fiatCurrency,
    required this.paymentMethod,
    required this.createdAt,
  });

  /// Nostr event ID hex of the underlying order.
  final String orderId;

  /// true → "Selling Bitcoin"; false → "Buying Bitcoin".
  final bool isSelling;

  /// Trade status at the time the list was loaded. Live updates come via
  /// [tradeStatusProvider] watched directly in [TradesListItem].
  final TradeStatusFilter status;

  /// Whether the local user published the order (creator) or took it (taker).
  final TradeRole role;

  /// Human-readable fiat amount or range (e.g. "966" or "100 – 500").
  final String fiatAmount;

  /// ISO 4217 fiat currency code (e.g. "ARS").
  final String fiatCurrency;

  /// Payment method string (e.g. "Mercado Pago").
  final String paymentMethod;

  /// Unix timestamp (seconds) when this trade was started.
  final int createdAt;
}

// ── Status mapping ────────────────────────────────────────────────────────────

/// Maps a Rust [rust_types.OrderStatus] to its [TradeStatusFilter] bucket.
TradeStatusFilter orderStatusToFilter(rust_types.OrderStatus status) {
  return switch (status) {
    rust_types.OrderStatus.pending => TradeStatusFilter.pending,
    rust_types.OrderStatus.waitingBuyerInvoice => TradeStatusFilter.waitingInvoice,
    rust_types.OrderStatus.waitingPayment => TradeStatusFilter.waitingPayment,
    rust_types.OrderStatus.active => TradeStatusFilter.active,
    rust_types.OrderStatus.inProgress => TradeStatusFilter.active,
    rust_types.OrderStatus.fiatSent => TradeStatusFilter.fiatSent,
    rust_types.OrderStatus.settledHoldInvoice => TradeStatusFilter.success,
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

// ── Internal helpers ──────────────────────────────────────────────────────────

/// Converts a [rust_types.TradeInfo] to a [TradeListItem].
TradeListItem _tradeInfoToItem(rust_types.TradeInfo trade) {
  final fiatDisplay = _formatFiat(
    trade.order.fiatAmount,
    trade.order.fiatAmountMin,
    trade.order.fiatAmountMax,
  );

  // PlatformInt64 = `int` on native, `BigInt` on web. Web persistence is not
  // yet implemented; the BigInt branch guards future correctness.
  final createdAt = trade.startedAt is BigInt
      ? (trade.startedAt as BigInt).toInt()
      : trade.startedAt as int; // ignore: unnecessary_cast

  return TradeListItem(
    orderId: trade.order.id,
    // TradeRole.buyer = the user is buying Bitcoin (took a sell order or
    // created a buy order). TradeRole.seller = selling Bitcoin.
    isSelling: trade.role == rust_types.TradeRole.seller,
    status: orderStatusToFilter(trade.order.status),
    // order.isMine is true when the local user published this order (maker).
    role: trade.order.isMine ? TradeRole.creator : TradeRole.taker,
    fiatAmount: fiatDisplay,
    fiatCurrency: trade.order.fiatCode,
    paymentMethod: trade.order.paymentMethod.isEmpty
        ? 'Bank Transfer'
        : trade.order.paymentMethod,
    createdAt: createdAt,
  );
}

String _formatFiat(double? amount, double? min, double? max) {
  String fmt(double v) =>
      v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  if (amount != null && amount > 0) return fmt(amount);
  if (min != null && max != null) return '${fmt(min)} – ${fmt(max)}';
  return '—';
}

// ── Raw trade list from DB ────────────────────────────────────────────────────

/// Loads all trades from the Rust DB, sorted newest-first.
///
/// Exposed so callers (e.g. [refreshTrades]) can invalidate it when new trades
/// are added. Per-row live status comes from [tradeStatusProvider].
final rawTradesProvider = FutureProvider<List<rust_types.TradeInfo>>((ref) {
  return orders_api.listTrades();
});

/// Returns the [rust_types.TradeInfo] for a given [orderId], or null if not found.
///
/// Used by screens that need trade-level fields (e.g. [holdInvoice], [timeoutAt])
/// that are not present on the order-book [OrderInfo].
final tradeInfoProvider =
    FutureProvider.autoDispose.family<rust_types.TradeInfo?, String>(
  (ref, orderId) async {
    final trades = await ref.watch(rawTradesProvider.future);
    return trades.where((t) => t.order.id == orderId).firstOrNull;
  },
);

/// Invalidates the raw trades cache, forcing a fresh DB fetch on next read.
///
/// Call this after a trade is successfully saved (e.g. after [takeOrder]).
void refreshTrades(WidgetRef ref) => ref.invalidate(rawTradesProvider);

// ── Providers ─────────────────────────────────────────────────────────────────

/// Currently selected status filter for the My Trades dropdown.
final selectedStatusFilterProvider =
    StateProvider<TradeStatusFilter>((_) => TradeStatusFilter.all);

/// Filtered and sorted list of the user's trades.
///
/// Pulls persisted trades from the Rust DB via [rawTradesProvider] and
/// applies the active [selectedStatusFilterProvider].  Per-row status chips
/// update independently via [tradeStatusProvider] inside [TradesListItem].
final filteredTradesWithOrderStateProvider =
    FutureProvider<List<TradeListItem>>((ref) async {
  final filter = ref.watch(selectedStatusFilterProvider);
  final trades = await ref.watch(rawTradesProvider.future);

  final items = trades.map(_tradeInfoToItem).toList();

  final filtered = filter == TradeStatusFilter.all
      ? items
      : items.where((t) => t.status == filter).toList();

  // already sorted newest-first by list_trades() in Rust; re-sort after
  // filter to preserve order if filter removes some items.
  filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return filtered;
});

// ── Badge notification count ──────────────────────────────────────────────────

/// Tracks statuses seen when the user last had the My Trades tab open.
/// When a status differs from this snapshot, it counts as unseen.
final _lastSeenStatusesProvider =
    StateProvider<Map<String, rust_types.OrderStatus>>((_) => const {});

// Terminal order statuses — trades in these states cannot change further,
// so there is no need to create a polling watcher for them.
const _terminalOrderStatuses = {
  rust_types.OrderStatus.success,
  rust_types.OrderStatus.settledHoldInvoice,
  rust_types.OrderStatus.settledByAdmin,
  rust_types.OrderStatus.completedByAdmin,
  rust_types.OrderStatus.canceled,
  rust_types.OrderStatus.expired,
  rust_types.OrderStatus.cooperativelyCanceled,
  rust_types.OrderStatus.canceledByAdmin,
};

/// Counts trades whose live status differs from the last-seen snapshot.
///
/// Only non-terminal trades are polled to avoid creating O(N) long-lived
/// watchers for trades that can no longer change status.
/// Resets to 0 while the user is on the My Trades tab (index 1).
final orderBookNotificationCountProvider = Provider<int>((ref) {
  final currentIndex = ref.watch(bottomNavIndexProvider);

  // While the user is on the My Trades tab no badge is needed.
  if (currentIndex == 1) return 0;

  final tradesAsync = ref.watch(rawTradesProvider);
  return tradesAsync.when(
    data: (trades) {
      final lastSeen = ref.watch(_lastSeenStatusesProvider);
      int count = 0;
      for (final trade in trades) {
        // Skip terminal trades — they have no further status changes to show.
        if (_terminalOrderStatuses.contains(trade.order.status)) continue;
        final live =
            ref.watch(tradeStatusProvider(trade.order.id)).valueOrNull;
        if (live == null) continue;
        final seen = lastSeen[trade.order.id];
        // Only count as unseen when status changed from a known prior state.
        // No snapshot yet (seen == null) means the user hasn't visited the tab
        // in this session — don't treat existing trades as new notifications.
        if (seen != null && seen != live) count++;
      }
      return count;
    },
    loading: () => 0,
    error: (_, __) => 0,
  );
});

/// Call this when the My Trades tab becomes active to snapshot current
/// statuses and reset the badge to 0.
void resetTradeNotifications(WidgetRef ref) {
  final tradesAsync = ref.read(rawTradesProvider);
  tradesAsync.whenData((trades) {
    final snapshot = <String, rust_types.OrderStatus>{};
    for (final trade in trades) {
      final live =
          ref.read(tradeStatusProvider(trade.order.id)).valueOrNull;
      if (live != null) snapshot[trade.order.id] = live;
    }
    ref.read(_lastSeenStatusesProvider.notifier).state = snapshot;
  });
}
