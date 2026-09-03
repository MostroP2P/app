import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/src/rust/api/types.dart';

void main() {
  group('tradeStatusProvider push path', () {
    test('a pushed TradeUpdate for this order emits its status (#272)',
        () async {
      const orderId = 'order-x';
      final container = ProviderContainer(overrides: [
        // Drive the shared push stream directly. _currentStatus swallows the
        // bridge error into null without RustLib.init(), so the immediate
        // first emission is skipped and the pushed status is the first real one
        // — never reaching the 30 s fallback tick.
        tradeUpdatesProvider.overrideWith((ref) async* {
          yield const TradeUpdate(
            orderId: orderId,
            status: OrderStatus.waitingPayment,
          );
        }),
      ]);
      addTearDown(container.dispose);

      final completer = Completer<OrderStatus>();
      final sub = container.listen<AsyncValue<OrderStatus>>(
        tradeStatusProvider(orderId),
        (_, next) {
          final s = next.valueOrNull;
          if (s == OrderStatus.waitingPayment && !completer.isCompleted) {
            completer.complete(s);
          }
        },
        fireImmediately: true,
      );
      addTearDown(sub.close);

      final status =
          await completer.future.timeout(const Duration(seconds: 5));
      expect(status, OrderStatus.waitingPayment);
    });

    test('a pushed update for a different order does not surface here', () async {
      const orderId = 'order-x';
      final container = ProviderContainer(overrides: [
        tradeUpdatesProvider.overrideWith((ref) async* {
          yield const TradeUpdate(
            orderId: 'order-other',
            status: OrderStatus.waitingPayment,
          );
        }),
      ]);
      addTearDown(container.dispose);

      OrderStatus? seen;
      final sub = container.listen<AsyncValue<OrderStatus>>(
        tradeStatusProvider(orderId),
        (_, next) => seen = next.valueOrNull,
        fireImmediately: true,
      );
      addTearDown(sub.close);

      // Give the (filtered-out) push time to arrive; the orderId filter in the
      // ref.listen callback must drop it, so nothing surfaces on this stream.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(seen, isNull);
    });
  });
}
