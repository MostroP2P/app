import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/trade_touch.dart' as touch_api;
import 'package:mostro/src/rust/api/types.dart';

/// Maps `orderId` → whether the local user is the buyer in that trade.
///
/// Set this before navigating to [AddLightningInvoiceScreen] or
/// [TradeDetailScreen] so those screens know the user's role.
final tradeRoleProvider = StateProvider<Map<String, bool>>((ref) => const {});

/// How long a trade provider waits before re-reading state nothing touched.
///
/// The safety net, not the mechanism. Rust rings [tradeTouchProvider] on every
/// write to a trade's book entry or row, so a change reaches the screen at
/// once; this only bounds the damage of a write path that forgot to ring. It
/// used to be the mechanism — every provider here polled the bridge once or
/// twice a second, from every screen (docs/OPTIMIZATION_PLAN.md PR 3.4).
const tradeSafetyPollInterval = Duration(seconds: 30);

/// The trade doorbell pushed from Rust (`api::trade_touch`): "this order's
/// entry or row was written — read it again". It carries no status and drives
/// no notice. A touch without an order id is a resync: the stream fell behind
/// and every trade on screen must be re-read.
final tradeTouchProvider = StreamProvider.autoDispose<TradeTouch>((ref) async* {
  final stream = await touch_api.onTradeTouched();
  while (true) {
    final touch = await stream.next();
    if (touch == null) break;
    yield touch;
  }
});

/// Reads the persisted trades through the bridge; injectable for tests.
final tradeListReaderProvider = Provider<Future<List<TradeInfo>> Function()>(
  (ref) => orders_api.listTrades,
);

/// Reads one order's book entry through the bridge; injectable for tests.
final orderReaderProvider = Provider<Future<OrderInfo?> Function(String)>(
  (ref) => (orderId) => orders_api.getOrder(orderId: orderId),
);

/// Emits what [read] returns — at once, again whenever [orderId] is touched
/// (or a resync asks everyone to), and every [tradeSafetyPollInterval]
/// besides — until a value [isFinal].
///
/// With [keepGoingOnError] a failed read is logged and retried on the next
/// wake-up; without it the error ends the stream, so a screen can tell a
/// broken status subscription from a slow one.
Stream<T> _followTrade<T>(
  Ref ref,
  String orderId, {
  required Future<T> Function() read,
  required bool Function(T value) isFinal,
  bool keepGoingOnError = false,
}) async* {
  var wake = Completer<void>();
  Timer? poll;
  var disposed = false;
  void ring() {
    if (!wake.isCompleted) wake.complete();
  }

  ref.listen<AsyncValue<TradeTouch>>(tradeTouchProvider, (_, next) {
    if (next.hasError) {
      // Without the doorbell this provider is down to its safety poll.
      debugPrint('[trade-follow] touch stream failed: ${next.error}');
    }
    final touch = next.valueOrNull;
    if (touch == null) return;
    if (touch.orderId == null || touch.orderId == orderId) ring();
  });
  ref.onDispose(() {
    disposed = true;
    poll?.cancel();
    ring();
  });

  while (!disposed) {
    // Armed before the read: a touch landing while the read is in flight
    // re-reads right after it instead of being lost.
    wake = Completer<void>();
    try {
      final value = await read();
      if (disposed) return;
      yield value;
      if (isFinal(value)) return;
    } catch (e, st) {
      if (!keepGoingOnError) rethrow;
      debugPrint('[trade-follow] read failed for order=$orderId: $e\n$st');
    }
    poll = Timer(tradeSafetyPollInterval, ring);
    await wake.future;
    poll.cancel();
  }
}

/// The trade's sats amount: `null` until the order has one, then done.
///
/// Useful for the add-invoice screen which needs the sats amount before it
/// can submit a Lightning invoice.
final tradeAmountProvider = StreamProvider.family.autoDispose<BigInt?, String>((
  ref,
  orderId,
) {
  final readOrder = ref.watch(orderReaderProvider);
  return _followTrade<BigInt?>(
    ref,
    orderId,
    read: () async => (await readOrder(orderId))?.amountSats,
    isFinal: (sats) => sats != null,
  );
});

/// Reads current status through the bridge; injectable for polling tests.
final tradeStatusLookupProvider =
    Provider<Future<OrderStatus?> Function(String)>(
      (ref) => (orderId) async {
        final info = await orders_api.getOrder(orderId: orderId);
        if (info != null) return info.status;
        final trades = await orders_api.listTrades();
        return trades
            .where((t) => t.order.id == orderId)
            .firstOrNull
            ?.order
            .status;
      },
    );

/// Reads the local user's role in a trade through the bridge; injectable so
/// screens that must know whether they already participate can be tested
/// without the Rust side.
final tradeRoleLookupProvider = Provider<Future<TradeRole?> Function(String)>(
  (ref) => (orderId) => orders_api.getTradeRole(orderId: orderId),
);

/// Takes an order through the bridge; injectable so the take screen's
/// outcomes (loading, already taken, rejected) can be tested without Rust.
final takeOrderActionProvider = Provider<
  Future<TradeInfo> Function({
    required String orderId,
    required TradeRole role,
    double? fiatAmount,
  })
>(
  (ref) =>
      ({required orderId, required role, fiatAmount}) => orders_api.takeOrder(
        orderId: orderId,
        role: role,
        fiatAmount: fiatAmount,
      ),
);

/// Publishes the seller release command; publication is not payout completion.
final releaseOrderActionProvider = Provider<Future<void> Function(String)>(
  (ref) => (orderId) => orders_api.releaseOrder(orderId: orderId),
);

/// Publishes a cancel for the order; the daemon's answer arrives later.
final cancelOrderActionProvider = Provider<Future<void> Function(String)>(
  (ref) => (orderId) => orders_api.cancelOrder(orderId: orderId),
);

/// Live order status for a single trade: re-read the moment Rust touches
/// the order, with [tradeSafetyPollInterval] as the net underneath.
///
/// The status is always read back, never taken from a pushed payload: a
/// history replay re-emits old transitions (#474) and the lookup corrects for
/// the bond window. The read is a local bridge call, so the change still
/// lands within the frame.
///
/// Starts with an immediate fetch so the first emission reflects the real
/// status. When the order is no longer in the in-memory order book (e.g. after
/// cancellation), the lookup falls back to the persisted trade DB so terminal
/// statuses like Canceled are reflected in the UI.
final tradeStatusProvider = StreamProvider.family
    .autoDispose<OrderStatus, String>((ref, orderId) {
      final lookup = ref.watch(tradeStatusLookupProvider);
      return _followTrade<OrderStatus?>(
        ref,
        orderId,
        read: () => lookup(orderId),
        isFinal: (status) => status != null && _isTerminal(status),
      ).where((status) => status != null).cast<OrderStatus>();
    });

/// Trade lifecycle updates pushed from Rust (daemon-driven cancellations).
///
/// The meaning [tradeStatusProvider] cannot give: a never-active trade is
/// wiped from the DB on the daemon's Canceled, and after a timeout republish
/// the order book reads `pending` again, so re-reading the status never shows
/// the cancellation. Screens filter by `orderId`.
final tradeUpdatesProvider = StreamProvider.autoDispose<TradeUpdate>((
  ref,
) async* {
  final stream = await orders_api.onTradeUpdated();
  while (true) {
    final update = await stream.next();
    if (update == null) break;
    yield update;
  }
});

/// Whether the UI can stop polling. Escrow settlement still awaits payout.
bool _isTerminal(OrderStatus s) => const {
  OrderStatus.success,
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
final tradeRoleFromDbProvider = FutureProvider.family
    .autoDispose<bool?, String>((ref, orderId) async {
      final role = await orders_api.getTradeRole(orderId: orderId);
      return switch (role) {
        TradeRole.buyer => true,
        TradeRole.seller => false,
        null => null,
      };
    });

/// The trade row for [orderId], re-read on every touch until it carries the
/// hold invoice. A failed read is retried: the stream stays subscribed across
/// reconnects and brief bridge failures.
Stream<TradeInfo?> _followTradeRow(Ref ref, String orderId) {
  final readTrades = ref.watch(tradeListReaderProvider);
  return _followTrade<TradeInfo?>(
    ref,
    orderId,
    read:
        () async =>
            (await readTrades())
                .where((t) => t.order.id == orderId)
                .firstOrNull,
    isFinal: (trade) => trade?.holdInvoice != null,
    keepGoingOnError: true,
  );
}

/// The hold invoice, `null` while waiting for it to arrive from the Mostro
/// node. Used by [PayLightningInvoiceScreen] to display the invoice as soon
/// as it becomes available, rather than relying on the one-shot
/// [tradeInfoProvider] which may return stale cached data.
final tradeHoldInvoiceProvider = StreamProvider.family
    .autoDispose<String?, String>(
      (ref, orderId) =>
          _followTradeRow(ref, orderId).map((trade) => trade?.holdInvoice),
    );

/// The full [TradeInfo] until it carries the hold invoice. Used by
/// [PayLightningInvoiceScreen] to get both the hold invoice and the sats
/// amount without relying on the cached [rawTradesProvider].
final tradeInfoStreamProvider = StreamProvider.family
    .autoDispose<TradeInfo?, String>(_followTradeRow);
