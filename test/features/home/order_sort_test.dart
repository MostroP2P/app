import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';

import '../../support/fake_orders.dart';
import '../../support/order_book_harness.dart';

void main() {
  group('takerPremiumAdvantage', () {
    test('taking a sell order (buying BTC) favours a lower premium', () {
      expect(fakeOrder(kind: 'sell', premium: -2).takerPremiumAdvantage, 2);
      expect(fakeOrder(kind: 'sell', premium: 3).takerPremiumAdvantage, -3);
    });

    test('taking a buy order (selling BTC) favours a higher premium', () {
      expect(fakeOrder(kind: 'buy', premium: 3).takerPremiumAdvantage, 3);
      expect(fakeOrder(kind: 'buy', premium: -2).takerPremiumAdvantage, -2);
    });
  });

  group('order-book sort', () {
    test('defaults to newest first', () async {
      final helper = await bookWith([
        fakeOrder(id: 'old', minutesAgo: 30),
        fakeOrder(id: 'new', minutesAgo: 1),
      ]);

      expect(helper.container.read(orderSortProvider), OrderSort.newest);
      expect(helper.ids(), ['new', 'old']);
    });

    test('best premium on Buy BTC lists the cheapest sell order first', () async {
      final helper = await bookWith([
        fakeOrder(id: 'plus5', kind: 'sell', premium: 5, minutesAgo: 1),
        fakeOrder(id: 'minus2', kind: 'sell', premium: -2, minutesAgo: 2),
        fakeOrder(id: 'zero', kind: 'sell', premium: 0, minutesAgo: 3),
      ]);
      helper.setTab(OrderType.buy);

      helper.container.read(orderSortProvider.notifier).state =
          OrderSort.bestPremium;

      expect(helper.ids(), ['minus2', 'zero', 'plus5']);
    });

    test('best premium on Sell BTC lists the best-paying buy order first',
        () async {
      final helper = await bookWith([
        fakeOrder(id: 'plus5', kind: 'buy', premium: 5, minutesAgo: 1),
        fakeOrder(id: 'minus2', kind: 'buy', premium: -2, minutesAgo: 2),
        fakeOrder(id: 'zero', kind: 'buy', premium: 0, minutesAgo: 3),
      ]);
      helper.setTab(OrderType.sell);

      helper.container.read(orderSortProvider.notifier).state =
          OrderSort.bestPremium;

      expect(helper.ids(), ['plus5', 'zero', 'minus2']);
    });

    test('equal premiums keep newest first', () async {
      final helper = await bookWith([
        fakeOrder(id: 'older', premium: 1, minutesAgo: 10),
        fakeOrder(id: 'recent', premium: 1, minutesAgo: 1),
      ]);

      helper.container.read(orderSortProvider.notifier).state =
          OrderSort.bestPremium;

      expect(helper.ids(), ['recent', 'older']);
    });

    test('best reputation ranks by rating, then by trade count', () async {
      final helper = await bookWith([
        fakeOrder(id: 'a', rating: 4.5, tradeCount: 50, minutesAgo: 1),
        fakeOrder(id: 'b', rating: 4.9, tradeCount: 3, minutesAgo: 2),
        fakeOrder(id: 'c', rating: 4.9, tradeCount: 20, minutesAgo: 3),
      ]);

      helper.container.read(orderSortProvider.notifier).state =
          OrderSort.bestReputation;

      expect(helper.ids(), ['c', 'b', 'a']);
    });
  });

  group('hasActiveOrderFiltersProvider', () {
    test('is false by default and true once a filter narrows the list',
        () async {
      final helper = await bookWith([]);
      expect(helper.container.read(hasActiveOrderFiltersProvider), isFalse);

      helper.container.read(premiumRangeFilterProvider.notifier).state =
          (min: -2.0, max: 10.0);

      expect(helper.container.read(hasActiveOrderFiltersProvider), isTrue);
    });
  });
}
