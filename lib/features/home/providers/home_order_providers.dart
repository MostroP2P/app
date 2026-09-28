import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/features/home/providers/order_book_feed.dart';
import 'package:mostro/features/home/providers/order_filters_provider.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart';

// The order-book filters, kept across launches (issue #575): re-exported so a
// reader of the book needs one import.
export 'package:mostro/features/home/providers/order_filters_provider.dart';
export 'package:mostro/src/rust/api/types.dart' show OrderStatus;

// ── Order type ────────────────────────────────────────────────────────────────

enum OrderType { buy, sell }

/// Which tab is active on the home screen.
/// "BUY BTC" → OrderType.buy (shows sell orders — taker buys).
/// "SELL BTC" → OrderType.sell (shows buy orders — taker sells).
final homeOrderTypeProvider = StateProvider<OrderType>((_) => OrderType.buy);

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

  /// [paymentMethod] as the payment-method filter compares it: its
  /// comma-separated entries, trimmed and lower-cased. Computed on first use
  /// and kept — an order's methods never change, and the filter walks the
  /// whole book on every emission and every filter change.
  late final Set<String> paymentTokens =
      paymentMethod.split(',').map((t) => t.trim().toLowerCase()).toSet();

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

/// The Rust bridge as an [OrderDeltaSource]; injectable for tests.
final orderDeltaSourceProvider = Provider<OrderDeltaSource>(
  (ref) => const _BridgeOrderDeltas(),
);

class _BridgeOrderDeltas implements OrderDeltaSource {
  const _BridgeOrderDeltas();

  @override
  Future<Future<OrderDelta?> Function()> subscribe() async =>
      (await orders_api.onOrderDeltas()).next;

  @override
  Future<OrderBookSnapshot> snapshot() => orders_api.getOrderBookSnapshot();
}

/// Live order book, kept current from the Rust book's per-order deltas.
///
/// It used to receive the **whole book** on every change and re-map every
/// order of it; now a change crosses the bridge as the one order it concerns,
/// is mapped once, and the list is handed over at most once per
/// [orderBookFlushInterval]. See [OrderBookFeed] for the rules — the
/// revision boundary, the resync, and staying in the loading state on an
/// empty book until the relay's EOSE confirms it (so "no orders" never
/// flashes before the orders arrive, and a quiet node still leaves loading).
final orderBookProvider = StreamProvider.autoDispose<List<OrderItem>>((ref) {
  final feed = OrderBookFeed<OrderItem>(
    ref.watch(orderDeltaSourceProvider),
    map: OrderItem.fromInfo,
  );
  ref.onDispose(feed.dispose);
  return feed.stream;
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
  final filters = ref.watch(orderFiltersProvider);
  final selectedCurrencies = filters.currencies;
  final ratingRange = filters.rating;
  final premiumRange = filters.premium;
  final sort = ref.watch(orderSortProvider);
  final selectedMethods = {
    for (final method in filters.paymentMethods) method.toLowerCase(),
  };

  return allOrders.where((o) {
      if (!_isListedOnTab(o, orderType)) return false;

      if (selectedCurrencies.isNotEmpty &&
          !selectedCurrencies.contains(o.fiatCode)) {
        return false;
      }

      if (selectedMethods.isNotEmpty &&
          !o.paymentTokens.any(selectedMethods.contains)) {
        return false;
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
