import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/home/providers/home_order_providers.dart';

/// "Reason to pick" badge for an order book card (UX proposal #3).
///
/// Each reason is awarded to at most one card in the visible list, and each
/// card carries at most one reason. Priority when a card qualifies for
/// several: best premium > most reputable > just published.
enum OrderReason { bestPremium, mostReputable, justPublished }

/// How recent an order must be to qualify as "Just published".
const justPublishedWindow = Duration(minutes: 10);

/// Computes the reason badge for each order in [orders] (the currently
/// displayed, filtered list). Returns a map of order id -> reason.
///
/// Rules (deterministic):
/// - Best premium: the single order with the lowest premium. Ties broken by
///   list position (first wins).
/// - Most reputable: the order with the highest rating (must be > 0), ties
///   broken by higher tradeCount, then list position. Skips the card that
///   already won "best premium".
/// - Just published: the most recently created order with
///   createdAt < 10 minutes ago, among cards not already awarded.
Map<String, OrderReason> computeOrderReasons(
  List<OrderItem> orders, {
  DateTime? now,
}) {
  if (orders.isEmpty) return const {};
  final reasons = <String, OrderReason>{};

  // Best premium — lowest premium in the visible list.
  OrderItem best = orders.first;
  for (final o in orders.skip(1)) {
    if (o.premium < best.premium) best = o;
  }
  reasons[best.id] = OrderReason.bestPremium;

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

  // Just published — newest order created < 10 minutes ago.
  final cutoff = (now ?? DateTime.now()).subtract(justPublishedWindow);
  OrderItem? fresh;
  for (final o in orders) {
    if (reasons.containsKey(o.id)) continue;
    if (!o.createdAt.isAfter(cutoff)) continue;
    if (fresh == null || o.createdAt.isAfter(fresh.createdAt)) {
      fresh = o;
    }
  }
  if (fresh != null) {
    reasons[fresh.id] = OrderReason.justPublished;
  }

  return reasons;
}

/// Reason badges for the currently displayed (filtered) order list.
final orderReasonsProvider = Provider<Map<String, OrderReason>>((ref) {
  final orders = ref.watch(filteredOrdersProvider);
  return computeOrderReasons(orders);
});
