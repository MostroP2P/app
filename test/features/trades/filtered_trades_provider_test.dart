import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
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

  group('rawTradesProvider invalidation (regenerate clean slate)', () {
    test('invalidating after the DB is cleared yields an empty list', () async {
      // The account screen calls ref.invalidate(rawTradesProvider) after
      // IdentityService.regenerate(); the Rust side has cleared the trades DB
      // by then (issue #273). Model that: a fetcher that first returns the old
      // identity's trades, then — once "cleared" — returns nothing.
      var trades = <TradeInfo>[
        fakeTrade(id: 'old', status: OrderStatus.active),
      ];
      final container = createContainer(overrides: [
        rawTradesProvider.overrideWith((ref) async => trades),
      ]);

      // Before regenerate: My Trades shows the previous identity's trades.
      expect(await container.read(rawTradesProvider.future), isNotEmpty);

      // delete_identity() cleared the DB; the account screen invalidates.
      trades = <TradeInfo>[];
      container.invalidate(rawTradesProvider);

      // After: the cached list is dropped and the empty DB is reflected.
      expect(await container.read(rawTradesProvider.future), isEmpty);
    });
  });
}
