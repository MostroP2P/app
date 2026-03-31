import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart';

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
final ratingFilterProvider =
    StateProvider<({double min, double max})>((_) => defaultRatingRange);

/// Premium range filter. Default = full range.
final premiumRangeFilterProvider =
    StateProvider<({double min, double max})>((_) => defaultPremiumRange);

// ── Order model ───────────────────────────────────────────────────────────────

/// Lightweight Dart-side order model for the UI layer.
///
/// TODO(Phase 18+): Add `OrderItem.fromInfo(OrderInfo info)` factory once
/// `flutter_rust_bridge_codegen generate` has been run and the generated
/// `OrderInfo` type is available at `package:rust/src/rust/api/orders.dart`.
/// Field mapping: id, kind.name.toLowerCase(), fiatAmount, fiatAmountMin,
/// fiatAmountMax, fiatCode, paymentMethod, premium, creatorPubkey,
/// DateTime.fromMillisecondsSinceEpoch(createdAt * 1000), expiresAt.
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
  }) {
    final isFixed = fiatAmount != null &&
        fiatAmountMin == null &&
        fiatAmountMax == null;
    final isRange = fiatAmount == null &&
        fiatAmountMin != null &&
        fiatAmountMax != null;
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
        createdAt: DateTime.fromMillisecondsSinceEpoch(info.createdAt * 1000),
        expiresAt: info.expiresAt != null
            ? DateTime.fromMillisecondsSinceEpoch(info.expiresAt! * 1000)
            : null,
      );
}

/// Live order book backed by the Rust bridge Kind 38383 subscription.
///
/// Starts in loading state (shimmer shown) until the first emission arrives
/// from the Rust order cache. Each time [subscribe_orders()] upserts an order
/// the broadcast fires and this stream yields an updated snapshot.
final orderBookProvider = StreamProvider.autoDispose<List<OrderItem>>((ref) async* {
  final stream = await orders_api.onOrdersUpdated();
  while (true) {
    final orders = await stream.next();
    if (orders == null) break;
    yield orders.map(OrderItem.fromInfo).toList();
  }
});

/// Filtered orders based on active tab and all filter providers.
///
/// Unwraps the `AsyncValue` from [orderBookProvider]; returns `[]` while
/// loading or on error so that filter/tab logic is always well-typed.
final filteredOrdersProvider = Provider<List<OrderItem>>((ref) {
  final allOrders = ref.watch(orderBookProvider).valueOrNull ?? [];
  final orderType = ref.watch(homeOrderTypeProvider);
  final selectedCurrencies = ref.watch(currencyFilterProvider);
  final selectedPaymentMethods = ref.watch(paymentMethodFilterProvider);
  final ratingRange = ref.watch(ratingFilterProvider);
  final premiumRange = ref.watch(premiumRangeFilterProvider);

  // "BUY BTC" tab shows sell orders (taker buys); "SELL BTC" shows buy orders.
  final targetKind = orderType == OrderType.buy ? 'sell' : 'buy';

  return allOrders.where((o) {
    if (o.kind != targetKind) return false;

    if (selectedCurrencies.isNotEmpty &&
        !selectedCurrencies.contains(o.fiatCode)) {
      return false;
    }

    if (selectedPaymentMethods.isNotEmpty) {
      final tokens = o.paymentMethod
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
  }).toList();
});
