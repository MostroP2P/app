import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/my_order_screen.dart';
import 'package:mostro/features/order/screens/take_order_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';

import '../../../support/fake_orders.dart';
import '../../../support/provider_harness.dart';

/// The handoffs' approved states on their 360 × 760 dp canvas, in Spanish
/// like the mockups: 6a — the maker's own sell of 1 000 ARS at market,
/// waiting for a taker; 7a — the same order seen by a buyer, at a node rate
/// that makes it ≈ 8 420 sats.
const _id = '09150348-1a2b-4c3d-8e9f-0a1b2c3d99b5';

OrderItem _order({required bool isMine}) => fakeOrder(
  id: _id,
  kind: 'sell',
  fiatAmount: 1000,
  fiatCode: 'ARS',
  paymentMethod: 'Mercado Pago',
  premium: 0,
  rating: 4.8,
  tradeCount: 16,
  daysActive: 219,
  isMine: isMine,
  minutesAgo: 3,
  expiresAt: kFakeNow.add(const Duration(hours: 23, minutes: 12)),
);

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required OrderItem order,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = createContainer(
    overrides: [
      orderBookProvider.overrideWith((ref) => Stream.value([order])),
      tradeStatusProvider.overrideWith(
        (ref, id) => Stream.value(OrderStatus.pending),
      ),
      tradeRoleLookupProvider.overrideWithValue((_) async => null),
      // 1 000 ARS → 8 420 sats.
      exchangeRateProvider.overrideWith((ref, code) async => 11876484.0),
      fiatCurrenciesProvider.overrideWith(
        (ref) async => const [
          FiatCurrency(code: 'ARS', name: 'Peso argentino', flag: '🇦🇷'),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme:
            brightness == Brightness.dark ? buildDarkTheme() : buildLightTheme(),
        locale: const Locale('es'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  // Pumped by frames, never settled: the waiting dot pulses forever. The
  // extra frame lets the sats estimate finish its cross-fade.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

void main() {
  for (final (name, brightness) in [
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    testWidgets('6a own order waiting for a taker, $name', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          const MyOrderScreen(orderId: _id),
          order: _order(isMine: true),
          brightness: brightness,
        );
        await expectLater(
          find.byType(MyOrderScreen),
          matchesGoldenFile('goldens/my_order_6a_waiting_$name.png'),
        );
      });
    });

    testWidgets('7a take order as buyer, $name', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        await _pump(
          tester,
          const TakeOrderScreen(orderId: _id, isBuying: true),
          order: _order(isMine: false),
          brightness: brightness,
        );
        await expectLater(
          find.byType(TakeOrderScreen),
          matchesGoldenFile('goldens/take_order_7a_buyer_$name.png'),
        );
      });
    });
  }
}
