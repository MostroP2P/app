import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/pay_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/types.dart';
import '../../../support/fake_trades.dart';

void main() {
  final en = AppLocalizationsEn();

  /// The maker of a range order `10,000 – 1,000,000 ARS`, taken for 219,500.
  TradeInfo takenRange() => fakeTrade(
    id: 'range',
    orderId: 'order-range',
    status: OrderStatus.waitingPayment,
    role: TradeRole.seller,
    fiatCode: 'ARS',
    paymentMethod: 'Mercado Pago',
    isMine: true,
    fiatAmount: 219500,
    fiatAmountMin: 10000,
    fiatAmountMax: 1000000,
    amountSats: BigInt.from(163069),
    holdInvoice: 'lnbc1630690n1holdinvoice',
  );

  testWidgets('the hold invoice of a taken range order names its fiat', (
    tester,
  ) async {
    // Arrange
    final trade = takenRange();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isWalletConnectedProvider.overrideWithValue(false),
          tradeAmountProvider.overrideWith(
            (ref, id) => Stream.value(BigInt.from(163069)),
          ),
          tradeInfoStreamProvider.overrideWith(
            (ref, id) => Stream.value(trade),
          ),
          tradeInfoProvider.overrideWith((ref, id) async => trade),
          tradeStatusProvider.overrideWith(
            (ref, id) => const Stream<OrderStatus>.empty(),
          ),
          tradeUpdatesProvider.overrideWith(
            (ref) => const Stream<TradeUpdate>.empty(),
          ),
          invoiceDeadlineProvider.overrideWith((ref, id) async => null),
          mostroNodeProvider.overrideWith((ref) async => null),
          activeNodeNameProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
          home: const PayLightningInvoiceScreen(orderId: 'order-range'),
        ),
      ),
    );

    // Act
    await tester.pumpAndSettle();

    // Assert
    expect(find.text(en.invoiceYouGetLabel), findsOneWidget);
    expect(find.text('219,500 ARS · Mercado Pago'), findsOneWidget);
    expect(find.textContaining('1,000,000'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
