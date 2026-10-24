import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';
import 'package:mostro/features/home/widgets/order_list_item.dart';

import '../../support/catalogue_fixtures.dart';
import '../../support/fake_orders.dart';
import '../../support/golden_harness.dart';

/// A fixed-sats order and a market-price range order stacked, keyed for a
/// tight golden. The fixed card shows its price per BTC where the market card
/// shows its premium, and the market card is the best-premium one, so one
/// golden pair covers both the highlight border and the plain hairline.
Widget _gallery() {
  return ProviderScope(overrides: [catalogueOverride()], child: _cards());
}

Widget _cards() {
  return Padding(
    key: const ValueKey('order-gallery'),
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        OrderListItem(
          order: fakeOrder(
            id: 'fixed',
            kind: 'sell',
            fiatAmount: 100,
            fiatCode: 'USD',
            paymentMethod: 'Wire, Revolut',
            rating: 4.8,
            tradeCount: 16,
            daysActive: 219,
            amountSats: BigInt.from(163400),
            minutesAgo: 12,
          ),
        ),
        const SizedBox(height: 8),
        OrderListItem(
          order: fakeOrder(
            id: 'range',
            kind: 'buy',
            fiatAmount: null,
            fiatAmountMin: 50,
            fiatAmountMax: 150,
            fiatCode: 'EUR',
            paymentMethod: 'Cash',
            premium: -1.0,
            rating: 3.2,
            minutesAgo: 120,
          ),
          reason: OrderReason.bestPremium,
        ),
      ],
    ),
  );
}

void main() {
  group('OrderListItem goldens', () {
    testWidgets('dark theme', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await pumpForGolden(tester, _gallery(),
            brightness: Brightness.dark, width: 380);
        await expectLater(
          find.byKey(const ValueKey('order-gallery')),
          matchesGoldenFile('goldens/order_list_item_dark.png'),
        );
      });
    });

    testWidgets('light theme', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await pumpForGolden(tester, _gallery(),
            brightness: Brightness.light, width: 380);
        await expectLater(
          find.byKey(const ValueKey('order-gallery')),
          matchesGoldenFile('goldens/order_list_item_light.png'),
        );
      });
    });
  });
}
