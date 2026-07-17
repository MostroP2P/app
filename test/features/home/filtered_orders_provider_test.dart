import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';

import '../../support/fake_orders.dart';
import '../../support/order_book_harness.dart';

void main() {
  group('filteredOrdersProvider', () {
    test('BUY tab shows only pending sell orders', () async {
      final helper = await bookWith([
        fakeOrder(id: 'sell', kind: 'sell'),
        fakeOrder(id: 'buy', kind: 'buy'),
      ]);
      helper.setTab(OrderType.buy);

      expect(helper.ids(), ['sell']);
    });

    test('SELL tab shows only pending buy orders', () async {
      final helper = await bookWith([
        fakeOrder(id: 'sell', kind: 'sell'),
        fakeOrder(id: 'buy', kind: 'buy'),
      ]);
      helper.setTab(OrderType.sell);

      expect(helper.ids(), ['buy']);
    });

    test('own orders show regardless of the active tab', () async {
      final helper = await bookWith([
        fakeOrder(id: 'mine-buy', kind: 'buy', isMine: true),
        fakeOrder(id: 'other-buy', kind: 'buy'),
      ]);
      helper.setTab(OrderType.buy); // buy tab targets sell orders

      expect(helper.ids(), ['mine-buy']);
    });

    test('non-pending orders are excluded', () async {
      final helper = await bookWith([
        fakeOrder(id: 'pending', kind: 'sell'),
        fakeOrder(id: 'active', kind: 'sell', status: OrderStatus.active),
      ]);
      helper.setTab(OrderType.buy);

      expect(helper.ids(), ['pending']);
    });

    test('currency filter keeps only selected fiat codes', () async {
      final helper = await bookWith([
        fakeOrder(id: 'usd', kind: 'sell', fiatCode: 'USD'),
        fakeOrder(id: 'eur', kind: 'sell', fiatCode: 'EUR'),
      ]);
      helper.setTab(OrderType.buy);
      helper.container.read(currencyFilterProvider.notifier).state = ['EUR'];

      expect(helper.ids(), ['eur']);
    });

    test('payment method filter matches any comma-separated token', () async {
      final helper = await bookWith([
        fakeOrder(id: 'multi', kind: 'sell', paymentMethod: 'Wire, Revolut'),
        fakeOrder(id: 'cash', kind: 'sell', paymentMethod: 'Cash'),
      ]);
      helper.setTab(OrderType.buy);
      helper.container.read(paymentMethodFilterProvider.notifier).state =
          ['revolut'];

      expect(helper.ids(), ['multi']);
    });

    test('rating range excludes orders outside the bounds', () async {
      final helper = await bookWith([
        fakeOrder(id: 'low', kind: 'sell', rating: 2.0),
        fakeOrder(id: 'high', kind: 'sell', rating: 4.5),
      ]);
      helper.setTab(OrderType.buy);
      helper.container.read(ratingFilterProvider.notifier).state =
          (min: 4.0, max: 5.0);

      expect(helper.ids(), ['high']);
    });

    test('premium range excludes orders outside the bounds', () async {
      final helper = await bookWith([
        fakeOrder(id: 'cheap', kind: 'sell', premium: -5.0),
        fakeOrder(id: 'pricey', kind: 'sell', premium: 8.0),
      ]);
      helper.setTab(OrderType.buy);
      helper.container.read(premiumRangeFilterProvider.notifier).state =
          (min: 5.0, max: 10.0);

      expect(helper.ids(), ['pricey']);
    });

    test('results are sorted newest-first by createdAt', () async {
      final helper = await bookWith([
        fakeOrder(id: 'older', kind: 'sell', minutesAgo: 30),
        fakeOrder(id: 'newer', kind: 'sell', minutesAgo: 5),
      ]);
      helper.setTab(OrderType.buy);

      expect(helper.ids(), ['newer', 'older']);
    });

    test('default rating range does not filter out unrated orders', () async {
      final helper = await bookWith([
        fakeOrder(id: 'unrated', kind: 'sell', rating: 0.0),
      ]);
      helper.setTab(OrderType.buy);

      expect(helper.ids(), ['unrated']);
    });

    test('range orders pass through the filters', () async {
      final helper = await bookWith([
        fakeOrder(
          id: 'range',
          kind: 'sell',
          fiatAmount: null,
          fiatAmountMin: 50,
          fiatAmountMax: 150,
        ),
      ]);
      helper.setTab(OrderType.buy);

      expect(helper.ids(), ['range']);
    });
  });
}
