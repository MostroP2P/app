import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart';

/// Maps `orderId` → whether the local user is the buyer in that trade.
///
/// Set this before navigating to [AddLightningInvoiceScreen] or
/// [TradeDetailScreen] so those screens know the user's role.
final tradeRoleProvider =
    StateProvider<Map<String, bool>>((ref) => const {});

/// Poll `getOrder()` every 2 s until `amountSats` is non-null, then stop.
///
/// Returns `null` while waiting.  Useful for the add-invoice screen which
/// needs the sats amount before it can submit a Lightning invoice.
final tradeAmountProvider =
    StreamProvider.family.autoDispose<BigInt?, String>((ref, orderId) async* {
  while (true) {
    final info = await orders_api.getOrder(orderId: orderId);
    final sats = info?.amountSats;
    yield sats;
    if (sats != null) return; // done — no need to keep polling
    await Future.delayed(const Duration(seconds: 2));
  }
});

/// Live order status for a single trade, polled from the order book every 2 s.
///
/// Starts with an immediate fetch (no initial delay) so the first emission
/// reflects the real relay status. When the order is no longer in the in-memory
/// order book (e.g. after cancellation), falls back to the persisted trade DB
/// so terminal statuses like Canceled are reflected in the UI.
final tradeStatusProvider =
    StreamProvider.family.autoDispose<OrderStatus, String>((ref, orderId) async* {
  while (true) {
    final info = await orders_api.getOrder(orderId: orderId);
    if (info != null) {
      yield info.status;
    } else {
      // Order removed from in-memory book — check the persisted trade DB.
      final trades = await orders_api.listTrades();
      final trade = trades.where((t) => t.order.id == orderId).firstOrNull;
      if (trade != null) {
        yield trade.order.status;
        // Terminal status — no need to keep polling.
        if (_isTerminal(trade.order.status)) return;
      }
    }
    await Future.delayed(const Duration(seconds: 2));
  }
});

/// Whether a status is terminal (no further changes possible).
bool _isTerminal(OrderStatus s) => const {
  OrderStatus.success,
  OrderStatus.settledHoldInvoice,
  OrderStatus.settledByAdmin,
  OrderStatus.completedByAdmin,
  OrderStatus.canceled,
  OrderStatus.expired,
  OrderStatus.cooperativelyCanceled,
  OrderStatus.canceledByAdmin,
}.contains(s);

/// Loads the buyer/seller role for a trade from the persistent DB.
///
/// Returns `true` when the local user is the buyer, `false` for seller, or
/// `null` while loading / when no record exists (trade was never taken on
/// this device, or [initDb] has not been called yet).
///
/// Consumed by [TradeDetailScreen] as a fallback when [tradeRoleProvider]
/// has no in-memory entry for the order — i.e. the app was restarted after
/// the trade was already taken in a previous session.
final tradeRoleFromDbProvider =
    FutureProvider.family.autoDispose<bool?, String>((ref, orderId) async {
  final role = await orders_api.getTradeRole(orderId: orderId);
  return switch (role) {
    TradeRole.buyer => true,
    TradeRole.seller => false,
    null => null,
  };
});
