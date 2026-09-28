import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/rate/providers/rating_providers.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/features/trades/screens/trade_detail_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../support/fake_trades.dart';
import '../../support/load_app_fonts.dart';
import '../../support/provider_harness.dart';

/// The trade screen right after the seller released (#586), in Spanish:
/// the seller is asked to rate at once, the buyer still waits for the
/// payout. 360 × 760, dark.
void main() {
  setUpAll(loadAppFonts);

  for (final (side, isBuyer) in [('seller', false), ('buyer', true)]) {
    testWidgets('after the release · $side · es · dark', (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      const orderId = 'order-released';
      final trade = fakeTrade(
        id: 'released',
        orderId: orderId,
        status: OrderStatus.settledHoldInvoice,
        role: isBuyer ? TradeRole.buyer : TradeRole.seller,
        fiatCode: 'ARS',
        paymentMethod: 'Mercado Pago',
        amountSats: BigInt.from(21000),
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: createContainer(
            overrides: [
              rawTradesProvider.overrideWith((ref) async => [trade]),
              tradeRoleProvider.overrideWith((ref) => {orderId: isBuyer}),
              tradeStatusProvider(orderId).overrideWith(
                (ref) => Stream.value(OrderStatus.settledHoldInvoice),
              ),
              orderBookProvider.overrideWith((ref) => Stream.value(const [])),
              invoiceDeadlineProvider(
                orderId,
              ).overrideWith((ref) async => null),
              tradeRatingProvider(orderId).overrideWith((ref) async => null),
            ],
          ),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildDarkTheme(),
            locale: const Locale('es'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const TradeDetailScreen(orderId: orderId),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      await expectLater(
        find.byType(TradeDetailScreen),
        matchesGoldenFile('goldens/trade_after_release_${side}_es_dark.png'),
      );
    });
  }
}
