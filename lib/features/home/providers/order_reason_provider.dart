import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/home/providers/home_order_providers.dart';

/// Highlight chip of an order-book card (order-book handoff, variant 4b).
///
/// Each reason is awarded to at most one card in the visible list, and each
/// card carries at most one — a chip means something only because it is
/// rare. Priority when a card qualifies for both: best premium.
enum OrderReason {
  /// The premium most in the taker's favour. The card also gets the
  /// highlight border.
  bestPremium,

  /// The highest-rated maker among the other cards.
  mostReputable,
}

/// Computes the highlight chip for each order in [orders] (the currently
/// displayed, filtered list). Returns a map of order id -> reason.
///
/// Rules (deterministic):
/// - Best premium: the order with the highest
///   [OrderItemTakerView.takerPremiumAdvantage] — the cheapest sell order on
///   Buy BTC, the best-paying buy order on Sell BTC. Ties are broken by list
///   position (first wins). Awarded only when that order beats at least one
///   other: a lone order, or a list where every premium is equal, has no
///   "best".
/// - Most reputable: the order with the highest rating (must be > 0), ties
///   broken by higher tradeCount, then list position. Skips the card that
///   already won "best premium".
Map<String, OrderReason> computeOrderReasons(List<OrderItem> orders) {
  if (orders.isEmpty) return const {};
  final reasons = <String, OrderReason>{};

  // Best premium — most in the taker's favour, if it beats anything.
  var best = orders.first;
  var beatsAnother = false;
  for (final o in orders.skip(1)) {
    if (o.takerPremiumAdvantage > best.takerPremiumAdvantage) {
      best = o;
      beatsAnother = true;
    } else if (o.takerPremiumAdvantage < best.takerPremiumAdvantage) {
      beatsAnother = true;
    }
  }
  if (beatsAnother) reasons[best.id] = OrderReason.bestPremium;

  // Most reputable — highest rating (> 0), ties broken by tradeCount.
  OrderItem? reputable;
  for (final o in orders) {
    if (reasons.containsKey(o.id)) continue;
    if (o.rating <= 0) continue;
    if (reputable == null ||
        o.rating > reputable.rating ||
        (o.rating == reputable.rating && o.tradeCount > reputable.tradeCount)) {
      reputable = o;
    }
  }
  if (reputable != null) {
    reasons[reputable.id] = OrderReason.mostReputable;
  }

  return reasons;
}

/// Highlight chips for the currently displayed (filtered) order list.
///
/// autoDispose for the same reason as [filteredOrdersProvider]: watching it
/// from a provider that never disposes would keep the whole order-book
/// pipeline alive well after the list leaves the screen.
final orderReasonsProvider = Provider.autoDispose<Map<String, OrderReason>>((ref) {
  final orders = ref.watch(filteredOrdersProvider);
  return computeOrderReasons(orders);
});
