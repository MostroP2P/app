import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/pay_lightning_invoice_screen.dart';
import 'package:mostro/features/order/widgets/invoice_widgets.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';

Future<void> _pump(WidgetTester tester, {bool onWeb = false}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isWalletConnectedProvider.overrideWithValue(false),
        invoiceOnWebProvider.overrideWithValue(onWeb),
        tradeAmountProvider.overrideWith(
          (ref, id) => Stream.value(BigInt.from(1000)),
        ),
        tradeInfoStreamProvider.overrideWith(
          (ref, id) => Stream.value(
            fakeTrade(
              id: id,
              holdInvoice: 'lnbc1000n1holdinvoice',
              amountSats: BigInt.from(1000),
            ),
          ),
        ),
        tradeStatusProvider.overrideWith(
          (ref, id) => const Stream<OrderStatus>.empty(),
        ),
        tradeUpdatesProvider.overrideWith(
          (ref) => const Stream<TradeUpdate>.empty(),
        ),
        tradeInfoProvider.overrideWith((ref, id) async => null),
        invoiceDeadlineProvider.overrideWith((ref, id) async => null),
        mostroNodeProvider.overrideWith((ref) async => null),
        activeNodeNameProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PayLightningInvoiceScreen(orderId: 'order-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final onWeb in [false, true]) {
    testWidgets(
      '13b: ${onWeb ? 'on the web Copy' : 'off the web the wallet'} leads',
      (tester) async {
        await _pump(tester, onWeb: onWeb);

        final (lead, second) =
            onWeb
                ? ('Copy', 'Open in my wallet')
                : ('Open in my wallet', 'Copy');
        expect(find.widgetWithText(InvoicePrimaryButton, lead), findsOneWidget);
        expect(
          find.widgetWithText(InvoiceSecondaryButton, second),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(InvoiceSecondaryButton, 'Share'),
          findsOneWidget,
        );
      },
    );
  }
}
