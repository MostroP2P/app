import 'dart:async';
import 'package:flutter/foundation.dart';
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

/// Live order status for a single trade.
///
/// Push-first: emits an immediate status from the order book (falling back to
/// the persisted trade DB when the order has left the in-memory book), then
/// reflects each `on_trade_updated` push for this `orderId` as it arrives, so
/// the UI reacts to daemon-driven status changes in real time instead of on a
/// fixed 2 s poll. A long reconnection-fallback poll runs only to reconcile a
/// push that was dropped or missed (app resumed from background, stream
/// reconnect); the daemon stays the authority either way.
final tradeStatusProvider =
    StreamProvider.family.autoDispose<OrderStatus, String>((ref, orderId) async* {
  // Push-first: a single event stream carries both push updates for THIS order
  // (bridged from the shared [tradeUpdatesProvider] via ref.listen, so one relay
  // subscription feeds every watched trade and tests can drive it through
  // `tradeUpdatesProvider.overrideWith`) and periodic reconnection-fallback
  // ticks. Merging both into one stream means a single subscription drains them
  // in order — no abandoned `moveNext()` futures, no busy-looping.
  final events = StreamController<_StatusEvent>();

  final sub = ref.listen<AsyncValue<TradeUpdate>>(tradeUpdatesProvider,
      (_, next) {
    final u = next.valueOrNull;
    if (u != null && u.orderId == orderId && !events.isClosed) {
      events.add(_PushEvent(u.status));
    }
  });

  final ticker = Timer.periodic(_reconnectPoll, (_) {
    if (!events.isClosed) events.add(const _FallbackTick());
  });

  // Tear down the listener, the fallback ticker and the controller. Idempotent,
  // so the terminal-status returns below can stop the ticker immediately rather
  // than leaving it waking every 30 s until the provider is disposed (#303
  // review) — which compounds with #299 watching every trade in the list.
  var stopped = false;
  void stop() {
    if (stopped) return;
    stopped = true;
    sub.close();
    ticker.cancel();
    if (!events.isClosed) events.close();
  }
  ref.onDispose(stop);

  // Immediate first emission — current status, same DB fallback as before for
  // orders already gone from the in-memory book.
  OrderStatus? last = await _currentStatus(orderId);
  if (last != null) {
    yield last;
    if (_isTerminal(last)) {
      stop();
      return;
    }
  }

  // Drain the merged stream. A push carries the new status directly; a fallback
  // tick triggers a reconciliation fetch. Only distinct statuses are emitted.
  await for (final event in events.stream) {
    final status = switch (event) {
      _PushEvent(:final status) => status,
      _FallbackTick() => await _currentStatus(orderId),
    };
    if (status != null && status != last) {
      last = status;
      yield status;
      if (_isTerminal(status)) {
        stop();
        return;
      }
    }
  }
});

/// Internal event type merged into [tradeStatusProvider]'s single stream: either
/// a pushed status or a periodic fallback tick that triggers a reconciliation
/// fetch.
sealed class _StatusEvent {
  const _StatusEvent();
}

class _PushEvent extends _StatusEvent {
  const _PushEvent(this.status);
  final OrderStatus status;
}

class _FallbackTick extends _StatusEvent {
  const _FallbackTick();
}

/// Long fallback interval for [tradeStatusProvider]: pushes carry the real-time
/// signal, so this only reconciles a dropped/missed update rather than driving
/// the UI (was a 2 s poll before the push-first migration).
const _reconnectPoll = Duration(seconds: 30);

/// Current status for [orderId]: the in-memory order book first, then the
/// persisted trade DB when the order has been removed from the book (e.g. after
/// a cancellation wipe). Returns null when neither knows the order.
///
/// A bridge/DB failure yields null rather than propagating: the reconciliation
/// fetch is best-effort, so a transient failure must not tear down the whole
/// status stream — the next push or fallback tick recovers. (This also lets the
/// provider run in tests without `RustLib.init()`, where these calls fail.)
Future<OrderStatus?> _currentStatus(String orderId) async {
  try {
    final info = await orders_api.getOrder(orderId: orderId);
    if (info != null) return info.status;
    final trades = await orders_api.listTrades();
    return trades.where((t) => t.order.id == orderId).firstOrNull?.order.status;
  } catch (e, st) {
    debugPrint('[tradeStatusProvider] status fetch failed for $orderId: $e\n$st');
    return null;
  }
}

/// Trade lifecycle updates pushed from Rust (daemon-driven cancellations).
///
/// Complements [tradeStatusProvider]'s polling, which cannot observe a
/// cancellation anymore: a never-active trade is wiped from the DB on the
/// daemon's Canceled, and after a timeout republish the order book reads
/// `pending` again. Screens filter by `orderId`.
final tradeUpdatesProvider =
    StreamProvider.autoDispose<TradeUpdate>((ref) async* {
  final stream = await orders_api.onTradeUpdated();
  while (true) {
    final update = await stream.next();
    if (update == null) break;
    yield update;
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
