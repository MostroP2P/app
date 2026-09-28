import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';
import 'package:mostro/features/home/widgets/order_list_item.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../support/fake_orders.dart';
import '../../support/load_app_fonts.dart';

/// The book from #584, in Spanish, with the chips as `computeOrderReasons`
/// hands them out: the user's own ARS order keeps only its "ESTÁS VENDIENDO"
/// pill, and both highlights go to orders the user can take.
Widget _book() {
  final orders = [
    fakeOrder(
      id: 'ars-mine',
      kind: 'sell',
      fiatAmount: null,
      fiatAmountMin: 10000,
      fiatAmountMax: 1000000,
      fiatCode: 'ARS',
      paymentMethod: 'Mercado Pago, CVU, CBU',
      premium: 0,
      rating: 5,
      tradeCount: 94,
      daysActive: 394,
      minutesAgo: 1,
      isMine: true,
    ),
    fakeOrder(
      id: 'usd',
      kind: 'sell',
      fiatAmount: null,
      fiatAmountMin: 10,
      fiatAmountMax: 650,
      fiatCode: 'USD',
      paymentMethod: 'USDT, USDC',
      premium: 3,
      rating: 4.91,
      tradeCount: 37,
      daysActive: 269,
      minutesAgo: 19,
    ),
    fakeOrder(
      id: 'eur',
      kind: 'sell',
      fiatAmount: null,
      fiatAmountMin: 100,
      fiatAmountMax: 500,
      fiatCode: 'EUR',
      paymentMethod: 'SEPA',
      premium: 5,
      rating: 4.6,
      tradeCount: 21,
      daysActive: 120,
      minutesAgo: 40,
    ),
  ];
  final reasons = computeOrderReasons(orders);
  return Padding(
    key: const ValueKey('reasons-book'),
    padding: const EdgeInsets.all(12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final o in orders) ...[
          OrderListItem(order: o, reason: reasons[o.id]),
          const SizedBox(height: 8),
        ],
      ],
    ),
  );
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('own orders win no highlight chip · es · dark', (tester) async {
    tester.view.physicalSize = const Size(404, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await withClock(Clock.fixed(kFakeNow), () async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildDarkTheme(),
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            backgroundColor: OrderBookPalette.dark.bg,
            body: Center(child: SizedBox(width: 380, child: _book())),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ESTÁS VENDIENDO'), findsOneWidget);
      expect(find.text('MEJOR REPUTADO'), findsOneWidget);
      await expectLater(
        find.byKey(const ValueKey('reasons-book')),
        matchesGoldenFile('goldens/order_reasons_book_es_dark.png'),
      );
    });
  });
}
