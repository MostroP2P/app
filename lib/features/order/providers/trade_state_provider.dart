import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart';

/// Seam over the Rust bridge: the accessors below are read through providers so
/// tests can substitute them, since the bridge is uninitialised under
/// `flutter test`.
final bridgeListTradesProvider =
    Provider<Future<List<TradeInfo>> Function()>((ref) => orders_api.listTrades);

final bridgeGetOrderProvider = Provider<Future<OrderInfo?> Function(String)>(
  (ref) => (orderId) => orders_api.getOrder(orderId: orderId),
);

/// Maps `orderId` → whether the local user is the buyer in that trade.
///
/// Set this before navigating to [AddLightningInvoiceScreen] or
/// [TradeDetailScreen] so those screens know the user's role.
final tradeRoleProvider =
    StateProvider<Map<String, bool>>((ref) => const {});

/// Poll every 2 s until the trade's `amountSats` is non-null, then stop.
///
/// Sizes the buyer's add-invoice. A persisted trade row is authoritative: its
/// amount is the daemon's calculated per-role sats, so keep polling until it
/// arrives. The order book only answers when we follow no trade, since its
/// amount is the coarse public 38383 figure — emitting that would stop the
/// polling with the wrong invoice amount. See [tradeStatusProvider].
final tradeAmountProvider =
    StreamProvider.family.autoDispose<BigInt?, String>((ref, orderId) async* {
  final listTrades = ref.read(bridgeListTradesProvider);
  final getOrder = ref.read(bridgeGetOrderProvider);
  while (true) {
    try {
      final trades = await listTrades();
      final trade = trades.where((t) => t.order.id == orderId).firstOrNull;
      final sats =
          trade != null ? trade.order.amountSats : (await getOrder(orderId))?.amountSats;
      yield sats;
      if (sats != null) return; // done — no need to keep polling
    } catch (e, st) {
      debugPrint('[tradeAmountProvider] poll failed: $e\n$st');
    }
    await Future.delayed(const Duration(seconds: 2));
  }
});

/// Live protocol status for a single tracked trade, polled every 2 s.
///
/// Prefers the persisted trade row over the in-memory order book: the book
/// carries the daemon's coarse public NIP-69 status (Kind 38383), which
/// collapses fine-grained states (e.g. `WaitingTakerBond` → `pending`,
/// `WaitingBuyerInvoice`/`WaitingPayment` → `in-progress`), whereas the trade
/// row holds the authoritative gift-wrap status. Falls back to the book only
/// when no local trade row exists.
final tradeStatusProvider =
    StreamProvider.family.autoDispose<OrderStatus, String>((ref, orderId) async* {
  final listTrades = ref.read(bridgeListTradesProvider);
  final getOrder = ref.read(bridgeGetOrderProvider);
  while (true) {
    try {
      final trades = await listTrades();
      final trade = trades.where((t) => t.order.id == orderId).firstOrNull;
      if (trade != null) {
        yield trade.order.status;
        if (_isTerminal(trade.order.status)) return;
      } else {
        // No local trade row — fall back to the public order book.
        final info = await getOrder(orderId);
        if (info != null) {
          yield info.status;
          if (_isTerminal(info.status)) return;
        }
      }
    } catch (e, st) {
      debugPrint('[tradeStatusProvider] poll failed: $e\n$st');
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

/// Poll `listTrades()` every 1 s until `holdInvoice` is non-null, then stop.
///
/// Returns `null` while waiting for the hold invoice to arrive from the
/// Mostro node.  Used by [PayLightningInvoiceScreen] to display the invoice
/// as soon as it becomes available, rather than relying on the one-shot
/// [tradeInfoProvider] which may return stale cached data.
final tradeHoldInvoiceProvider =
    StreamProvider.family.autoDispose<String?, String>((ref, orderId) async* {
  while (true) {
    try {
      final trades = await orders_api.listTrades();
      final trade = trades.where((t) => t.order.id == orderId).firstOrNull;
      yield trade?.holdInvoice;
      if (trade?.holdInvoice != null) return;
    } catch (e, st) {
      // Transient DB/bridge error — log and keep polling so the stream
      // stays subscribed across reconnects and brief failures.
      debugPrint('[tradeHoldInvoiceProvider] listTrades failed: $e\n$st');
    }
    await Future.delayed(const Duration(seconds: 1));
  }
});

/// Poll `listTrades()` every 1 s until `holdInvoice` is non-null, then stop.
///
/// Returns the full [TradeInfo] when available.  Used by
/// [PayLightningInvoiceScreen] to get both the hold invoice and the sats
/// amount without relying on the cached [rawTradesProvider].
final tradeInfoStreamProvider =
    StreamProvider.family.autoDispose<TradeInfo?, String>((ref, orderId) async* {
  while (true) {
    try {
      final trades = await orders_api.listTrades();
      final trade = trades.where((t) => t.order.id == orderId).firstOrNull;
      yield trade;
      if (trade?.holdInvoice != null) return;
    } catch (e, st) {
      // Transient DB/bridge error — log and keep polling so the stream
      // stays subscribed across reconnects and brief failures.
      debugPrint('[tradeInfoStreamProvider] listTrades failed: $e\n$st');
    }
    await Future.delayed(const Duration(seconds: 1));
  }
});

/// Poll `listTrades()` every 1 s until `bondInvoice` is non-null, then stop.
///
/// Used by [PayBondInvoiceScreen]; separate from [tradeInfoStreamProvider]
/// (which keys on `holdInvoice`) because a taken bond order carries its invoice
/// in `bondInvoice` and leaves `holdInvoice` null until it advances.
final tradeBondInfoProvider =
    StreamProvider.family.autoDispose<TradeInfo?, String>((ref, orderId) async* {
  while (true) {
    try {
      final trades = await orders_api.listTrades();
      final trade = trades.where((t) => t.order.id == orderId).firstOrNull;
      yield trade;
      if (trade?.bondInvoice != null) return;
    } catch (e, st) {
      debugPrint('[tradeBondInfoProvider] listTrades failed: $e\n$st');
    }
    await Future.delayed(const Duration(seconds: 1));
  }
});
