import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/pay_lightning_invoice_screen.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';
import '../../../support/fake_trades.dart';

void main() {
  for (final buyer in [false, true]) {
    testWidgets(
      '${buyer ? 'buyer' : 'seller'} invoice exposes its order and ordinary back action',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                isWalletConnectedProvider.overrideWithValue(false),
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
              ],
              child: MaterialApp(
                theme: buildDarkTheme(),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                routes: {
                  '/pay':
                      (_) =>
                          buyer
                              ? const AddLightningInvoiceScreen(
                                orderId: 'order-1',
                              )
                              : const PayLightningInvoiceScreen(
                                orderId: 'order-1',
                              ),
                },
                home: Builder(
                  builder:
                      (context) => Scaffold(
                        body: TextButton(
                          onPressed:
                              () => Navigator.of(context).pushNamed('/pay'),
                          child: const Text('Open invoice'),
                        ),
                      ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open invoice'));
          await tester.pumpAndSettle();
          Finder id(String value) => find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.identifier == value,
          );
          expect(
            tester
                .getSemantics(id(buyer ? 'invoice.order_id' : 'pay.order_id'))
                .getSemanticsData()
                .label,
            'order-1',
          );
          expect(find.text('Order order-1'), findsOneWidget);
          expect(
            id(buyer ? 'invoice.text' : 'pay.invoice.text'),
            findsOneWidget,
          );
          expect(
            tester.getSemantics(id('appbar.back')),
            isSemantics(hasTapAction: true),
          );
          await tester.tap(id('appbar.back'));
          await tester.pumpAndSettle();
          expect(find.text('Open invoice'), findsOneWidget);
          expect(id(buyer ? 'invoice.text' : 'pay.invoice.text'), findsNothing);
        } finally {
          semantics.dispose();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }
}
