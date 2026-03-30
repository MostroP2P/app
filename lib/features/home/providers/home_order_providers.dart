import 'package:flutter_riverpod/flutter_riverpod.dart';

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

// ── Mock order data (until Rust bridge is wired) ─────────────────────────────

/// Lightweight Dart-side order model for the UI layer.
/// Will be replaced by the Rust-bridge `OrderInfo` in Phase 7.
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
    final hasFixed = fiatAmount != null;
    final hasRange = fiatAmountMin != null && fiatAmountMax != null;
    if (hasFixed == hasRange) {
      throw ArgumentError(
        'OrderItem must have either fiatAmount or both '
        'fiatAmountMin and fiatAmountMax, not ${hasFixed ? "both" : "neither"}',
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
}

/// Mock orders for UI development.
final _mockOrders = [
  OrderItem(
    id: 'order-1',
    kind: 'sell',
    fiatAmount: 50000,
    fiatCode: 'ARS',
    paymentMethod: 'Mercado Pago, Bank Transfer',
    premium: 5.0,
    creatorPubkey: 'abc123',
    createdAt: DateTime.now().subtract(const Duration(minutes: 12)),
    rating: 4.5,
    tradeCount: 23,
    daysActive: 45,
  ),
  OrderItem(
    id: 'order-2',
    kind: 'sell',
    fiatAmountMin: 10000,
    fiatAmountMax: 100000,
    fiatCode: 'ARS',
    paymentMethod: 'Mercado Pago',
    premium: 3.0,
    creatorPubkey: 'def456',
    createdAt: DateTime.now().subtract(const Duration(hours: 1)),
    rating: 4.8,
    tradeCount: 102,
    daysActive: 180,
  ),
  OrderItem(
    id: 'order-3',
    kind: 'sell',
    fiatAmount: 200,
    fiatCode: 'USD',
    paymentMethod: 'Zelle, Wise',
    premium: -2.0,
    creatorPubkey: 'ghi789',
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
    rating: 3.2,
    tradeCount: 5,
    daysActive: 10,
  ),
  OrderItem(
    id: 'order-4',
    kind: 'buy',
    fiatAmount: 500,
    fiatCode: 'EUR',
    paymentMethod: 'SEPA, Revolut',
    premium: 1.5,
    creatorPubkey: 'jkl012',
    createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
    rating: 4.0,
    tradeCount: 15,
    daysActive: 60,
  ),
  OrderItem(
    id: 'order-5',
    kind: 'buy',
    fiatAmount: 100000,
    fiatCode: 'ARS',
    paymentMethod: 'Bank Transfer',
    premium: 8.0,
    creatorPubkey: 'mno345',
    createdAt: DateTime.now().subtract(const Duration(hours: 2)),
    rating: 2.0,
    tradeCount: 2,
    daysActive: 3,
  ),
  OrderItem(
    id: 'order-6',
    kind: 'sell',
    fiatAmount: 1000,
    fiatCode: 'BRL',
    paymentMethod: 'Pix',
    premium: 4.0,
    creatorPubkey: 'pqr678',
    createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
    rating: 4.9,
    tradeCount: 300,
    daysActive: 365,
  ),
];

/// Provides the full (unfiltered) order list.
/// Will be replaced by a StreamProvider from Rust bridge.
final orderBookProvider = Provider<List<OrderItem>>((_) => _mockOrders);

/// Filtered orders based on active tab and all filter providers.
final filteredOrdersProvider = Provider<List<OrderItem>>((ref) {
  final allOrders = ref.watch(orderBookProvider);
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
