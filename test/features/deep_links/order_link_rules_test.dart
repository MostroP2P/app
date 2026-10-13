import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/features/deep_links/models/order_link_rules.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../support/fake_trades.dart';

const _id = 'e215c07e-b1f9-45b0-9640-0295067ee99a';

OrderInfo _order({
  OrderKind kind = OrderKind.sell,
  OrderStatus status = OrderStatus.pending,
}) => fakeTrade(orderId: _id, kind: kind, status: status).order;

void main() {
  group('isOrderLink', () {
    test('takes a mostro: link in any case, with stray whitespace', () {
      expect(isOrderLink('mostro:$_id?relays=wss://nos.lol'), isTrue);
      expect(isOrderLink('  MOSTRO://$_id '), isTrue);
    });

    test('leaves every other link alone', () {
      expect(isOrderLink('https://mostro.network/app/'), isFalse);
      expect(isOrderLink('nostr:npub1abc'), isFalse);
      expect(isOrderLink('lightning:lnbc1'), isFalse);
      expect(isOrderLink(''), isFalse);
    });
  });

  group('orderLinkFailureOf', () {
    test('reads the core marker for a link it cannot read', () {
      expect(
        orderLinkFailureOf(Exception('InvalidOrderLink: order id is not')),
        OrderLinkFailure.invalidLink,
      );
    });

    test('takes everything else for an order not found, worth a retry', () {
      expect(
        orderLinkFailureOf(Exception('OrderLinkNotFound: $_id')),
        OrderLinkFailure.notFound,
      );
      expect(
        orderLinkFailureOf(StateError('bridge')),
        OrderLinkFailure.notFound,
      );
    });
  });

  group('orderLinkDestination', () {
    test('a pending sell order is taken by buying', () {
      expect(
        orderLinkDestination(_order(), participates: false),
        AppRoute.takeSellPath(_id),
      );
    });

    test('a pending buy order is taken by selling', () {
      expect(
        orderLinkDestination(_order(kind: OrderKind.buy), participates: false),
        AppRoute.takeBuyPath(_id),
      );
    });

    test('a participant goes to the trade, whatever the order says', () {
      for (final status in [OrderStatus.pending, OrderStatus.active]) {
        expect(
          orderLinkDestination(_order(status: status), participates: true),
          AppRoute.tradeDetailPath(_id),
          reason: '$status',
        );
      }
    });

    test('an order that left the book leads nowhere for anyone else', () {
      for (final status in [
        OrderStatus.inProgress,
        OrderStatus.canceled,
        OrderStatus.success,
        OrderStatus.expired,
      ]) {
        expect(
          orderLinkDestination(_order(status: status), participates: false),
          isNull,
          reason: '$status',
        );
      }
    });
  });
}
