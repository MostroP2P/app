import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart';

/// Maps `orderId` → whether the local user is the buyer in that trade.
///
/// Set this before navigating to [AddLightningInvoiceScreen] or
/// [TradeDetailScreen] so those screens know the user's role.
final tradeRoleProvider = StateProvider<Map<String, bool>>((ref) => const {});

/// Poll `getOrder()` every 2 s until `amountSats` is non-null, then stop.
///
/// Returns `null` while waiting.  Useful for the add-invoice screen which
/// needs the sats amount before it can submit a Lightning invoice.
final tradeAmountProvider = StreamProvider.family.autoDispose<BigInt?, String>((
  ref,
  orderId,
) async* {
  while (true) {
    final info = await orders_api.getOrder(orderId: orderId);
    final sats = info?.amountSats;
    yield sats;
    if (sats != null) return; // done — no need to keep polling
    await Future.delayed(const Duration(seconds: 2));
  }
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

/// The local user's role in an order they still take part in
/// ([participatingRole]), read through the bridge; injectable so screens that
/// must know whether they already participate can be tested without the Rust
/// side.
final tradeRoleLookupProvider = Provider<Future<TradeRole?> Function(String)>(
  (ref) =>
      (orderId) async =>
          participatingRole(await orders_api.listTrades(), orderId),
);

/// The role of the user's trade on [orderId] among [trades], or null when
/// they no longer take part in it: no row at all, or only a take that has
/// ended ([isEndedTake]).
///
/// Every row for the order is read, not just one: a database from before
/// takes replaced their order's earlier row can hold two, and a live one
/// among them still makes the user a participant.
TradeRole? participatingRole(Iterable<TradeInfo> trades, String orderId) {
  for (final trade in trades) {
    if (trade.order.id == orderId && !isEndedTake(trade)) return trade.role;
  }
  return null;
}

/// Whether [trade] is a take whose row has ended, which leaves the user
/// nothing to follow on its order.
///
/// A trade that truly ended leaves its order in a status mostrod never takes
/// it out of: a take needs `Pending`, and only a waiting state goes back to
/// it. So once the order can be taken again, such a row is what a take that
/// never went active left behind: older builds marked it `Canceled` as soon
/// as its cancel went out. Holding on to it sent the user to that dead trade
/// instead of letting them take the order again (#434). Rust already takes
/// over such a row: the confirmed take replaces every earlier row of its
/// order.
///
/// Never a maker's row: its order is theirs, and the take screen is not
/// where they manage it.
bool isEndedTake(TradeInfo trade) =>
    !trade.order.isMine && isTerminalTradeStatus(trade.order.status);

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

/// Live order status for a single trade, polled from the order book every 2 s.
///
/// Starts with an immediate fetch (no initial delay) so the first emission
/// reflects the real relay status. When the order is no longer in the in-memory
/// order book (e.g. after cancellation), falls back to the persisted trade DB
/// so terminal statuses like Canceled are reflected in the UI.
final tradeStatusProvider = StreamProvider.family
    .autoDispose<OrderStatus, String>((ref, orderId) async* {
      final lookup = ref.watch(tradeStatusLookupProvider);
      while (true) {
        final status = await lookup(orderId);
        if (status != null) {
          yield status;
          if (isTerminalTradeStatus(status)) return;
        }
        await Future.delayed(const Duration(seconds: 2));
      }
    });

/// Trade lifecycle updates pushed from Rust (daemon-driven cancellations).
///
/// Complements [tradeStatusProvider]'s polling, which cannot observe a
/// cancellation anymore: a never-active trade is wiped from the DB on the
/// daemon's Canceled, and after a timeout republish the order book reads
/// `pending` again. Screens filter by `orderId`.
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

/// Whether a trade in [s] has ended: nothing moves it out again, so the UI
/// can stop polling. Escrow settlement still awaits payout.
bool isTerminalTradeStatus(OrderStatus s) => const {
  OrderStatus.success,
  OrderStatus.settledByAdmin,
  OrderStatus.completedByAdmin,
  OrderStatus.canceled,
  OrderStatus.expired,
  OrderStatus.cooperativelyCanceled,
  OrderStatus.canceledByAdmin,
}.contains(s);

/// The status a trade shows: its [row]'s persisted one, or the [live] one
/// from [tradeStatusProvider], which reads the order book first.
///
/// The row wins in two cases:
/// * **It has ended** ([isTerminalTradeStatus]). Whatever the book says about
///   the order later is no longer this trade. The one way such a row can be
///   wrong is the cancel's optimistic write on an active trade: a cooperative
///   cancel the peer never accepts, on a trade that then completes.
/// * **It is a take ([isTake]) and the book says `pending`.** A public
///   `pending` means nobody holds the order, so it is never a take's status.
///   Older builds marked a take `Canceled` as soon as its cancel went out,
///   even before it went active; once the daemon put the order back in the
///   book, that `pending` read as the user's own order, with a Cancel the
///   daemon refuses (`IsNotYourOrder`). A take parked at `WaitingTakerBond`
///   is another: publicly its order is still `pending`.
///
/// Otherwise the live status, or the row's while there is none yet.
OrderStatus shownTradeStatus({
  required OrderStatus row,
  required OrderStatus? live,
  required bool isTake,
}) {
  if (live == null || isTerminalTradeStatus(row)) return row;
  if (isTake && live == OrderStatus.pending) return row;
  return live;
}

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

/// Poll `listTrades()` every 1 s until `holdInvoice` is non-null, then stop.
///
/// Returns `null` while waiting for the hold invoice to arrive from the
/// Mostro node.  Used by [PayLightningInvoiceScreen] to display the invoice
/// as soon as it becomes available, rather than relying on the one-shot
/// [tradeInfoProvider] which may return stale cached data.
final tradeHoldInvoiceProvider = StreamProvider.family
    .autoDispose<String?, String>((ref, orderId) async* {
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
final tradeInfoStreamProvider = StreamProvider.family
    .autoDispose<TradeInfo?, String>((ref, orderId) async* {
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
