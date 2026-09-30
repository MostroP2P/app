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

import '../../support/fake_orders.dart';
import '../../support/fake_trades.dart';
import '../../support/load_app_fonts.dart';
import '../../support/provider_harness.dart';

/// The maker of a range order `10.000 – 1.000.000 ARS`, taken for 219.500,
/// asked to lock the sats: the step card says what is being sold, in fiat
/// and sats, while the book still holds the range. 360 × 760, dark, es.
void main() {
  setUpAll(loadAppFonts);

  testWidgets('a taken range order · seller · es · dark', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const orderId = 'order-range';
    final trade = fakeTrade(
      id: 'range',
      orderId: orderId,
      status: OrderStatus.waitingPayment,
      role: TradeRole.seller,
      fiatCode: 'ARS',
      paymentMethod: 'Mercado Pago',
      isMine: true,
      fiatAmount: 219500,
      fiatAmountMin: 10000,
      fiatAmountMax: 1000000,
      amountSats: BigInt.from(163069),
    );
    final book = fakeOrder(
      id: orderId,
      fiatAmountMin: 10000,
      fiatAmountMax: 1000000,
      fiatCode: 'ARS',
      paymentMethod: 'Mercado Pago',
      isMine: true,
      status: OrderStatus.waitingPayment,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: createContainer(
          overrides: [
            rawTradesProvider.overrideWith((ref) async => [trade]),
            tradeRoleProvider.overrideWith((ref) => {orderId: false}),
            tradeStatusProvider(
              orderId,
            ).overrideWith((ref) => Stream.value(OrderStatus.waitingPayment)),
            orderBookProvider.overrideWith((ref) => Stream.value([book])),
            invoiceDeadlineProvider(orderId).overrideWith((ref) async => null),
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
      matchesGoldenFile('goldens/trade_range_taken_seller_es_dark.png'),
    );
  });
}
