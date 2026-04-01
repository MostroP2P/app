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
/// Returns [OrderStatus.pending] as the initial / fallback value while loading.
final tradeStatusProvider =
    StreamProvider.family.autoDispose<OrderStatus, String>((ref, orderId) async* {
  yield OrderStatus.pending; // immediate first emission so UI doesn't hang
  while (true) {
    await Future.delayed(const Duration(seconds: 2));
    final info = await orders_api.getOrder(orderId: orderId);
    if (info != null) yield info.status;
  }
});
