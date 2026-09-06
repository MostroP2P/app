import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/src/rust/api/types.dart' show TradeInfo, OrderStatus;

import '../../support/fake_trades.dart';
import '../../support/provider_harness.dart';

ProviderContainer _tradesWith(List<TradeInfo> trades) {
  return createContainer(overrides: [
    rawTradesProvider.overrideWith((ref) async => trades),
  ]);
}

Future<List<String>> _orderIds(
  ProviderContainer container, {
  TradeStatusFilter filter = TradeStatusFilter.all,
}) async {
  container.read(selectedStatusFilterProvider.notifier).state = filter;
  final items = await container.read(filteredTradesWithOrderStateProvider.future);
  return items.map((t) => t.orderId).toList();
}

void main() {
  group('filteredTradesWithOrderStateProvider', () {
    test('"All" returns every trade', () async {
      final container = _tradesWith([
        fakeTrade(id: 'a', status: OrderStatus.active),
        fakeTrade(id: 'b', status: OrderStatus.pending),
      ]);

      expect(await _orderIds(container), unorderedEquals(['order-a', 'order-b']));
    });

    test('status filter keeps only matching trades', () async {
      final container = _tradesWith([
        fakeTrade(id: 'active', status: OrderStatus.active),
        fakeTrade(id: 'pending', status: OrderStatus.pending),
      ]);

      expect(
        await _orderIds(container, filter: TradeStatusFilter.pending),
        ['order-pending'],
      );
    });

    test('terminal protocol statuses collapse into the success filter',
        () async {
      final container = _tradesWith([
        fakeTrade(id: 'success', status: OrderStatus.success),
        fakeTrade(id: 'settled', status: OrderStatus.settledByAdmin),
        fakeTrade(id: 'canceled', status: OrderStatus.canceled),
      ]);

      expect(
        await _orderIds(container, filter: TradeStatusFilter.success),
        unorderedEquals(['order-success', 'order-settled']),
      );
    });

    test('results are sorted newest-first by startedAt', () async {
      final container = _tradesWith([
        fakeTrade(id: 'older', startedAt: 1000),
        fakeTrade(id: 'newer', startedAt: 5000),
      ]);

      expect(await _orderIds(container), ['order-newer', 'order-older']);
    });
  });

  group('orderStatusToFilter', () {
    test('maps every protocol status to its bucket', () {
      const expected = {
        OrderStatus.pending: TradeStatusFilter.pending,
        OrderStatus.waitingBuyerInvoice: TradeStatusFilter.waitingInvoice,
        OrderStatus.waitingPayment: TradeStatusFilter.waitingPayment,
        OrderStatus.active: TradeStatusFilter.active,
        OrderStatus.inProgress: TradeStatusFilter.active,
        OrderStatus.fiatSent: TradeStatusFilter.fiatSent,
        OrderStatus.settledHoldInvoice: TradeStatusFilter.success,
        OrderStatus.success: TradeStatusFilter.success,
        OrderStatus.settledByAdmin: TradeStatusFilter.success,
        OrderStatus.completedByAdmin: TradeStatusFilter.success,
        OrderStatus.canceled: TradeStatusFilter.canceled,
        OrderStatus.expired: TradeStatusFilter.canceled,
        OrderStatus.cooperativelyCanceled: TradeStatusFilter.canceled,
        OrderStatus.canceledByAdmin: TradeStatusFilter.canceled,
        OrderStatus.dispute: TradeStatusFilter.dispute,
      };

      // Guards against an unmapped status silently slipping through.
      expect(expected.length, OrderStatus.values.length);
      expected.forEach((status, bucket) {
        expect(orderStatusToFilter(status), bucket, reason: '$status');
      });
    });
  });

  group('live status buckets the filter (issue #269)', () {
    // A trade whose persisted snapshot is Pending, but whose live status (the
    // one the row chip shows) has already moved to waitingBuyerInvoice. The
    // filter must follow the live status, not the stale snapshot.
    ProviderContainer staleSnapshotContainer() => createContainer(overrides: [
          rawTradesProvider.overrideWith(
            (ref) async => [fakeTrade(id: 'x', status: OrderStatus.pending)],
          ),
          tradeStatusProvider('order-x').overrideWith(
            (ref) => Stream.value(OrderStatus.waitingBuyerInvoice),
          ),
        ]);

    // Wait for the overridden tradeStatusProvider stream to emit its first
    // value, so the derived filter provider sees the live status rather than
    // racing the snapshot fallback (which only applies until live loads).
    Future<void> primeLiveStatus(ProviderContainer c) async {
      await c.read(tradeStatusProvider('order-x').future);
    }

    test('trade does NOT appear under the stale Pending bucket', () async {
      final container = staleSnapshotContainer();
      await primeLiveStatus(container);
      expect(
        await _orderIds(container, filter: TradeStatusFilter.pending),
        isEmpty,
      );
    });

    test('trade appears under the live Waiting Invoice bucket', () async {
      final container = staleSnapshotContainer();
      await primeLiveStatus(container);
      expect(
        await _orderIds(container, filter: TradeStatusFilter.waitingInvoice),
        ['order-x'],
      );
    });

    test('falls back to the snapshot bucket until live status loads', () async {
      // No tradeStatusProvider override: live is unavailable, so the snapshot
      // status (Pending) is used. This preserves behaviour before first poll.
      final container = createContainer(overrides: [
        rawTradesProvider.overrideWith(
          (ref) async => [fakeTrade(id: 'y', status: OrderStatus.pending)],
        ),
        tradeStatusProvider('order-y').overrideWith(
          (ref) => const Stream.empty(),
        ),
      ]);
      expect(
        await _orderIds(container, filter: TradeStatusFilter.pending),
        ['order-y'],
      );
    });

    test('re-buckets live when the status transitions', () async {
      // The core promise of #269: as a trade's live status changes, it moves
      // between filter buckets in step with its chip. Drive the live status
      // with a controllable stream and assert the trade leaves the old bucket
      // and enters the new one.
      final controller = StreamController<OrderStatus>();
      addTearDown(controller.close);
      final container = createContainer(overrides: [
        rawTradesProvider.overrideWith(
          (ref) async => [fakeTrade(id: 'z', status: OrderStatus.pending)],
        ),
        tradeStatusProvider('order-z').overrideWith((ref) => controller.stream),
      ]);

      // First live status: Pending. In the Pending bucket, not Waiting Invoice.
      controller.add(OrderStatus.pending);
      await container.read(tradeStatusProvider('order-z').future);
      expect(
        await _orderIds(container, filter: TradeStatusFilter.pending),
        ['order-z'],
      );
      expect(
        await _orderIds(container, filter: TradeStatusFilter.waitingInvoice),
        isEmpty,
      );

      // Transition to Waiting Invoice: leaves Pending, enters Waiting Invoice.
      controller.add(OrderStatus.waitingBuyerInvoice);
      await Future<void>.delayed(Duration.zero);
      expect(
        await _orderIds(container, filter: TradeStatusFilter.pending),
        isEmpty,
      );
      expect(
        await _orderIds(container, filter: TradeStatusFilter.waitingInvoice),
        ['order-z'],
      );
    });
    test(
        'a terminal trade keeps its snapshot bucket and ignores live status (#299)',
        () async {
      // A terminal trade must not spawn a live-status poller. Override its
      // tradeStatusProvider with a NON-terminal live status: if the guard
      // failed to skip the watch, the trade would follow that live status out
      // of the success bucket. Because terminal trades bucket by snapshot, the
      // override is never read, so it stays in success (#299 review).
      final container = createContainer(overrides: [
        rawTradesProvider.overrideWith(
          (ref) async => [fakeTrade(id: 'done', status: OrderStatus.success)],
        ),
        tradeStatusProvider('order-done').overrideWith(
          (ref) => Stream.value(OrderStatus.pending),
        ),
      ]);
      expect(
        await _orderIds(container, filter: TradeStatusFilter.success),
        ['order-done'],
      );
    });
  });
}
