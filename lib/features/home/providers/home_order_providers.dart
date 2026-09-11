import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart';

export 'package:mostro/src/rust/api/types.dart' show OrderStatus;

// ── Order type ────────────────────────────────────────────────────────────────

enum OrderType { buy, sell }

/// Which tab is active on the home screen.
/// "BUY BTC" → OrderType.buy (shows sell orders — taker buys).
/// "SELL BTC" → OrderType.sell (shows buy orders — taker sells).
final homeOrderTypeProvider = StateProvider<OrderType>((_) => OrderType.buy);

// ── Filter defaults & providers ──────────────────────────────────────────────

/// Canonical default range for the rating filter.
const defaultRatingRange = (min: 0.0, max: 5.0);

/// Canonical default range for the premium filter.
const defaultPremiumRange = (min: -10.0, max: 10.0);

/// Selected fiat currency codes (multi-select). Empty = no filter.
final currencyFilterProvider = StateProvider<List<String>>((_) => []);

/// Selected payment methods (multi-select). Empty = no filter.
final paymentMethodFilterProvider = StateProvider<List<String>>((_) => []);

/// Rating range filter. Default = full range.
final ratingFilterProvider = StateProvider<({double min, double max})>(
  (_) => defaultRatingRange,
);

/// Premium range filter. Default = full range.
final premiumRangeFilterProvider = StateProvider<({double min, double max})>(
  (_) => defaultPremiumRange,
);

/// Whether any filter currently narrows the order book.
final hasActiveOrderFiltersProvider = Provider<bool>((ref) {
  return ref.watch(currencyFilterProvider).isNotEmpty ||
      ref.watch(paymentMethodFilterProvider).isNotEmpty ||
      ref.watch(ratingFilterProvider) != defaultRatingRange ||
      ref.watch(premiumRangeFilterProvider) != defaultPremiumRange;
});

/// Resets every order-book filter to its default.
void clearOrderFilters(WidgetRef ref) {
  ref.read(currencyFilterProvider.notifier).state = const [];
  ref.read(paymentMethodFilterProvider.notifier).state = const [];
  ref.read(ratingFilterProvider.notifier).state = defaultRatingRange;
  ref.read(premiumRangeFilterProvider.notifier).state = defaultPremiumRange;
}

// ── Sort ──────────────────────────────────────────────────────────────────────

/// Criteria the order book can be sorted by.
enum OrderSort {
  /// Most recently published first.
  newest,

  /// The premium most in the taker's favour first — see
  /// [OrderItemTakerView.takerPremiumAdvantage].
  bestPremium,

  /// Highest maker rating first, then most trades.
  bestReputation,
}

/// Selected order-book sort. Newest first by default.
final orderSortProvider = StateProvider<OrderSort>((_) => OrderSort.newest);

/// Orders [OrderItem]s by [sort]. Every criterion falls back to newest first,
/// so orders with equal keys keep a meaningful order — `List.sort` is not
/// stable.
Comparator<OrderItem> orderComparator(OrderSort sort) {
  int newestFirst(OrderItem a, OrderItem b) =>
      b.createdAt.compareTo(a.createdAt);
  int thenNewest(int byKey, OrderItem a, OrderItem b) =>
      byKey != 0 ? byKey : newestFirst(a, b);

  return switch (sort) {
    OrderSort.newest => newestFirst,
    OrderSort.bestPremium =>
      (a, b) => thenNewest(
        b.takerPremiumAdvantage.compareTo(a.takerPremiumAdvantage),
        a,
        b,
      ),
    OrderSort.bestReputation => (a, b) {
      final byRating = b.rating.compareTo(a.rating);
      return thenNewest(
        byRating != 0 ? byRating : b.tradeCount.compareTo(a.tradeCount),
        a,
        b,
      );
    },
  };
}

// ── Order model ───────────────────────────────────────────────────────────────

/// Lightweight Dart-side order model for the UI layer.
class OrderItem {
  OrderItem({
    required this.id,
    required this.kind,
    this.fiatAmount,
    this.fiatAmountMin,
    this.fiatAmountMax,
    required this.fiatCode,
    required this.paymentMethod,
    required this.premium,
    required this.creatorPubkey,
    required this.createdAt,
    this.expiresAt,
    this.rating = 0.0,
    this.tradeCount = 0,
    this.daysActive = 0,
    this.status = OrderStatus.pending,
    this.amountSats,
    this.isMine = false,
  }) {
    final isFixed =
        fiatAmount != null && fiatAmountMin == null && fiatAmountMax == null;
    final isRange =
        fiatAmount == null && fiatAmountMin != null && fiatAmountMax != null;
    if (!isFixed && !isRange) {
      throw ArgumentError(
        'OrderItem requires exactly one shape: '
        'fiatAmount (fixed) or fiatAmountMin+fiatAmountMax (range)',
      );
    }
  }

  final String id;
  final String kind; // "buy" or "sell"
  final double? fiatAmount;
  final double? fiatAmountMin;
  final double? fiatAmountMax;
  final String fiatCode;
  final String paymentMethod;
  final double premium;
  final String creatorPubkey;
  final DateTime createdAt;
  final DateTime? expiresAt;
  final double rating;
  final int tradeCount;
  final int daysActive;

  /// Current order status from the Mostro protocol.
  final OrderStatus status;

  /// Sats amount. On a published order it is the Kind 38383 `amt` tag: `0`
  /// when the order is priced at market when taken, the fixed amount
  /// otherwise. Once Mostro accepts a take it carries the resolved amount.
  final BigInt? amountSats;

  /// True when this order was created by the current user.
  final bool isMine;

  bool get isRange => fiatAmountMin != null && fiatAmountMax != null;

  String get displayAmount {
    if (isRange) {
      return '${_fmt(fiatAmountMin!)} – ${_fmt(fiatAmountMax!)}';
    }
    return _fmt(fiatAmount!);
  }

  static String _fmt(double v) {
    return v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
  }

  /// Value equality, so a screen watching one order can tell whether *its*
  /// order actually moved. Every book emission rebuilds every [OrderItem],
  /// so identity comparison always reports a change and
  /// [orderByIdProvider]'s `select` would never filter anything out.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderItem &&
          other.id == id &&
          other.kind == kind &&
          other.fiatAmount == fiatAmount &&
          other.fiatAmountMin == fiatAmountMin &&
          other.fiatAmountMax == fiatAmountMax &&
          other.fiatCode == fiatCode &&
          other.paymentMethod == paymentMethod &&
          other.premium == premium &&
          other.creatorPubkey == creatorPubkey &&
          other.createdAt == createdAt &&
          other.expiresAt == expiresAt &&
          other.rating == rating &&
          other.tradeCount == tradeCount &&
          other.daysActive == daysActive &&
          other.status == status &&
          other.amountSats == amountSats &&
          other.isMine == isMine;

  @override
  int get hashCode => Object.hashAll([
    id,
    kind,
    fiatAmount,
    fiatAmountMin,
    fiatAmountMax,
    fiatCode,
    paymentMethod,
    premium,
    creatorPubkey,
    createdAt,
    expiresAt,
    rating,
    tradeCount,
    daysActive,
    status,
    amountSats,
    isMine,
  ]);

  /// Map a Rust-bridge [OrderInfo] to an [OrderItem] for display.
  factory OrderItem.fromInfo(OrderInfo info) => OrderItem(
    id: info.id,
    kind: info.kind == OrderKind.buy ? 'buy' : 'sell',
    fiatAmount: info.fiatAmount,
    fiatAmountMin: info.fiatAmountMin,
    fiatAmountMax: info.fiatAmountMax,
    fiatCode: info.fiatCode,
    paymentMethod: info.paymentMethod,
    premium: info.premium,
    creatorPubkey: info.creatorPubkey,
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      platformInt64ToInt(info.createdAt) * 1000,
    ),
    expiresAt:
        info.expiresAt != null
            ? DateTime.fromMillisecondsSinceEpoch(
              platformInt64ToInt(info.expiresAt!) * 1000,
            )
            : null,
    status: info.status,
    amountSats: info.amountSats,
    isMine: info.isMine,
    rating: info.rating,
    tradeCount: info.totalReviews,
    daysActive: info.daysActive,
  );
}

/// How an order reads from the side of whoever takes it.
extension OrderItemTakerView on OrderItem {
  /// Premium points in the taker's favour — higher is always better.
  ///
  /// Taking a sell order means buying BTC, where a lower premium is cheaper;
  /// taking a buy order means selling it, where a higher premium pays more.
  /// (`0 - premium` rather than `-premium` so a zero premium stays `0.0`:
  /// `-0.0` sorts below `0.0`.)
  double get takerPremiumAdvantage => kind == 'sell' ? 0 - premium : premium;

  /// Whether the maker fixed the sats amount (`amt` > 0), as opposed to an
  /// order priced at market when it is taken.
  bool get hasFixedSats => (amountSats ?? BigInt.zero) > BigInt.zero;
}

/// Live order book backed by the Rust bridge Kind 38383 subscription.
///
/// Immediately yields the current cached snapshot (empty on first run) so the
/// UI exits the shimmer/loading state right away.  Subsequent emissions arrive
/// as [subscribe_orders()] upserts orders from the relay stream.
final orderBookProvider = StreamProvider.autoDispose<List<OrderItem>>((
  ref,
) async* {
  // Subscribe first so no broadcast is missed between snapshot and loop.
  final stream = await orders_api.onOrdersUpdated();

  // Fast-exit shimmer only if the cache already has orders. If the cache is
  // empty we stay in loading state until the relay delivers the first update,
  // preventing an "No orders available" flash before any relay data arrives.
  // An empty book is confirmed by the relay's EOSE on the pending-book
  // subscription, which Rust publishes as an (empty) update — without that
  // this would wait forever whenever the book is empty, both on a cold start
  // and every time this provider is re-created after the last order left.
  final snapshot = await orders_api.getOrders(filters: null);
  debugPrint('[orderBook] initial snapshot: ${snapshot.length} orders');
  if (snapshot.isNotEmpty) {
    yield snapshot.map(OrderItem.fromInfo).toList();
  }

  // Stream live updates from the relay subscription.
  while (true) {
    final orders = await stream.next();
    if (orders == null) break;
    yield orders.map(OrderItem.fromInfo).toList();
  }
});

/// The live book indexed by order id, rebuilt once per emission.
///
/// Screens that care about a single order used to scan the whole list for it,
/// on every rebuild — an O(orders) walk per screen per relay event.
final orderBookIndexProvider = Provider.autoDispose<Map<String, OrderItem>>((
  ref,
) {
  final orders =
      ref.watch(orderBookProvider).valueOrNull ?? const <OrderItem>[];
  return {for (final order in orders) order.id: order};
});

/// One order from the live book, or null when it is not in it.
///
/// The `select` is what makes this worth having: a screen watching one order
/// rebuilds only when *that* order changes, not on every book emission. It
/// relies on [OrderItem]'s value equality.
final orderByIdProvider = Provider.autoDispose.family<OrderItem?, String>((
  ref,
  orderId,
) {
  return ref.watch(orderBookIndexProvider.select((index) => index[orderId]));
});

/// Whether [order] belongs on [tab] before any filter applies.
///
/// The book shows only pending orders, and "BUY BTC" lists sell orders (the
/// taker buys) while "SELL BTC" lists buy orders. Own orders follow the same
/// split as everyone else's — distinguished only by the "you are
/// selling/buying" pill (issue #290); managing them has its own place (My
/// Trades / MyOrderScreen on tap).
bool _isListedOnTab(OrderItem order, OrderType tab) =>
    order.status == OrderStatus.pending &&
    order.kind == (tab == OrderType.buy ? 'sell' : 'buy');

/// Whether the active tab has any order before filters apply — what tells
/// "the filters hide everything" apart from "there is nothing to show".
final tabHasOrdersProvider = Provider.autoDispose<bool>((ref) {
  final orders =
      ref.watch(orderBookProvider).valueOrNull ?? const <OrderItem>[];
  final tab = ref.watch(homeOrderTypeProvider);
  return orders.any((order) => _isListedOnTab(order, tab));
});

/// Filtered orders based on active tab, all filter providers and the selected
/// [OrderSort].
///
/// Unwraps the `AsyncValue` from [orderBookProvider]; returns `[]` while
/// loading or on error so that filter/tab logic is always well-typed.
///
/// `autoDispose` is load-bearing, not hygiene: [orderBookProvider] is itself
/// autoDispose, so a non-disposing watcher here would keep it — and this
/// filter and sort over the whole book — running on every relay event for the
/// rest of the session, including while the user is in Chat or Trades.
///
/// This only ends the pipeline when Home is actually unmounted: the bottom
/// nav replaces it (`context.go`), but Settings, About and key management are
/// pushed over it, so Home — and the book — stay alive underneath those.
final filteredOrdersProvider = Provider.autoDispose<List<OrderItem>>((ref) {
  final allOrders = ref.watch(orderBookProvider).valueOrNull ?? [];
  final orderType = ref.watch(homeOrderTypeProvider);
  final selectedCurrencies = ref.watch(currencyFilterProvider);
  final selectedPaymentMethods = ref.watch(paymentMethodFilterProvider);
  final ratingRange = ref.watch(ratingFilterProvider);
  final premiumRange = ref.watch(premiumRangeFilterProvider);
  final sort = ref.watch(orderSortProvider);

  return allOrders.where((o) {
      if (!_isListedOnTab(o, orderType)) return false;

      if (selectedCurrencies.isNotEmpty &&
          !selectedCurrencies.contains(o.fiatCode)) {
        return false;
      }

      if (selectedPaymentMethods.isNotEmpty) {
        final tokens =
            o.paymentMethod
                .split(',')
                .map((t) => t.trim().toLowerCase())
                .toSet();
        final selectedLower =
            selectedPaymentMethods.map((pm) => pm.toLowerCase()).toSet();
        if (tokens.intersection(selectedLower).isEmpty) return false;
      }

      if (ratingRange != defaultRatingRange) {
        if (o.rating < ratingRange.min || o.rating > ratingRange.max) {
          return false;
        }
      }

      if (premiumRange != defaultPremiumRange) {
        if (o.premium < premiumRange.min || o.premium > premiumRange.max) {
          return false;
        }
      }

      return true;
    }).toList()
    ..sort(orderComparator(sort));
});
