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

      expect(await _orderIds(container), containsAll(['order-a', 'order-b']));
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
        containsAll(['order-success', 'order-settled']),
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
}
