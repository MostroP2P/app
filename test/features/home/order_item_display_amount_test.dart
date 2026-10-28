import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_orders.dart';

void main() {
  group('OrderItem.displayAmount', () {
    test('keeps fiat as it was', () {
      expect(fakeOrder(fiatAmount: 25).displayAmount, '25');
      expect(fakeOrder(fiatAmount: 25.5).displayAmount, '25.5');
      expect(
        fakeOrder(fiatAmountMin: 100, fiatAmountMax: 500).displayAmount,
        '100 – 500',
      );
    });

    test('reads a BTC-pegged code in the asset unit (#907)', () {
      expect(
        fakeOrder(fiatAmount: 100000, fiatCode: 'RBTC').displayAmount,
        '0.001',
      );
      expect(
        fakeOrder(
          fiatAmountMin: 50000,
          fiatAmountMax: 200000,
          fiatCode: 'BTC',
        ).displayAmount,
        '0.0005 – 0.002',
      );
    });
  });
}
