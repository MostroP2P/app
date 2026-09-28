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

    group("the user's own orders never compete (#584)", () {
      test('an own order with the best premium does not win it', () {
        final reasons = computeOrderReasons([
          fakeOrder(id: 'mine', premium: -5, rating: 0, isMine: true),
          fakeOrder(id: 'a', premium: 3, rating: 0),
          fakeOrder(id: 'b', premium: 1, rating: 0),
        ]);

        expect(reasons, {'b': OrderReason.bestPremium});
      });

      test('an own order with the best reputation does not win it', () {
        final reasons = computeOrderReasons([
          fakeOrder(
            id: 'mine',
            premium: 0,
            rating: 5,
            tradeCount: 94,
            isMine: true,
          ),
          fakeOrder(id: 'a', premium: 0, rating: 4.9, tradeCount: 37),
          fakeOrder(id: 'b', premium: 0, rating: 4.2, tradeCount: 80),
        ]);

        expect(reasons, {'a': OrderReason.mostReputable});
      });

      test('the book in the report: own ARS order, USD and EUR to take', () {
        // Buy BTC: the user's 0% ARS order used to take "best premium" and
        // push "most reputable" onto USD. Both now go to takeable orders.
        final reasons = computeOrderReasons([
          fakeOrder(
            id: 'ars-mine',
            kind: 'sell',
            premium: 0,
            rating: 5,
            tradeCount: 94,
            isMine: true,
          ),
          fakeOrder(
            id: 'usd',
            kind: 'sell',
            premium: 3,
            rating: 4.91,
            tradeCount: 37,
          ),
          fakeOrder(id: 'eur', kind: 'sell', premium: 5, rating: 4.5),
        ]);

        expect(reasons.containsKey('ars-mine'), isFalse);
        expect(reasons, {
          'usd': OrderReason.bestPremium,
          'eur': OrderReason.mostReputable,
        });
      });

      test('a book of only own orders shows no chips', () {
        expect(
          computeOrderReasons([
            fakeOrder(id: 'a', premium: -1, rating: 5, isMine: true),
            fakeOrder(id: 'b', premium: 4, rating: 3, isMine: true),
          ]),
          isEmpty,
        );
      });

      test('one takeable order among own ones has nothing to beat', () {
        final reasons = computeOrderReasons([
          fakeOrder(id: 'mine', premium: 9, rating: 0, isMine: true),
          fakeOrder(id: 'other', premium: 1, rating: 0),
        ]);

        expect(reasons, isEmpty);
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
