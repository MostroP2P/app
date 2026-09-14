import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';

import '../../support/fake_orders.dart';

void main() {
  group('computeOrderReasons', () {
    test('best premium on Buy BTC goes to the cheapest sell order', () {
      final reasons = computeOrderReasons([
        fakeOrder(id: 'a', kind: 'sell', premium: 3, rating: 0),
        fakeOrder(id: 'b', kind: 'sell', premium: -1, rating: 0),
      ]);

      expect(reasons, {'b': OrderReason.bestPremium});
    });

    test('best premium on Sell BTC goes to the best-paying buy order', () {
      final reasons = computeOrderReasons([
        fakeOrder(id: 'a', kind: 'buy', premium: 3, rating: 0),
        fakeOrder(id: 'b', kind: 'buy', premium: -1, rating: 0),
      ]);

      expect(reasons, {'a': OrderReason.bestPremium});
    });

    test('nothing is "best premium" when no order beats another', () {
      expect(
        computeOrderReasons([fakeOrder(id: 'lone', premium: 2, rating: 0)]),
        isEmpty,
      );
      expect(
        computeOrderReasons([
          fakeOrder(id: 'a', premium: 0, rating: 0),
          fakeOrder(id: 'b', premium: 0, rating: 0),
        ]),
        isEmpty,
      );
    });

    test('most reputable skips the best-premium card and needs a rating', () {
      final reasons = computeOrderReasons([
        fakeOrder(id: 'a', premium: -1, rating: 5, tradeCount: 10),
        fakeOrder(id: 'b', premium: 2, rating: 4.8, tradeCount: 50),
        fakeOrder(id: 'c', premium: 3, rating: 0),
      ]);

      expect(reasons, {
        'a': OrderReason.bestPremium,
        'b': OrderReason.mostReputable,
      });
    });

    test('only the two highlight chips from the design exist', () {
      expect(OrderReason.values, [
        OrderReason.bestPremium,
        OrderReason.mostReputable,
      ]);
    });
  });
}
