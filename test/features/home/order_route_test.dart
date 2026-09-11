import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/features/home/screens/home_screen.dart';

import '../../support/fake_orders.dart';

/// The route comes from the order, not from the tab: during the Buy/Sell
/// cross-fade the outgoing list is still tappable while the tab already names
/// the other side, so reading the tab would open the wrong take flow.
void main() {
  group('routeForOrder', () {
    test('a sell order opens the take-sell flow', () {
      expect(
        routeForOrder(fakeOrder(id: 's', kind: 'sell')),
        AppRoute.takeSellPath('s'),
      );
    });

    test('a buy order opens the take-buy flow', () {
      expect(
        routeForOrder(fakeOrder(id: 'b', kind: 'buy')),
        AppRoute.takeBuyPath('b'),
      );
    });

    test('our own order opens its own screen, whatever its side', () {
      for (final kind in ['sell', 'buy']) {
        expect(
          routeForOrder(fakeOrder(id: 'm', kind: kind, isMine: true)),
          AppRoute.myOrderPath('m'),
        );
      }
    });
  });
}
