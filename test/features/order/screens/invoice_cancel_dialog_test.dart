import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/order/screens/pay_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';

/// Both invoice screens only exist before the trade goes active, where
/// mostrod cancels at once: their cancel dialog must not announce the
/// cooperative request the counterparty has to accept, which is what it
/// said before.
void main() {
  final l10n = AppLocalizationsEn();

  for (final buyer in [true, false]) {
    testWidgets(
      '${buyer ? 'add' : 'pay'}-invoice cancel is announced as immediate',
      (tester) async {
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
              home:
                  buyer
                      ? const AddLightningInvoiceScreen(orderId: 'order-1')
                      : const PayLightningInvoiceScreen(orderId: 'order-1'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final cancelId =
            buyer ? AutomationIds.invoiceCancel : AutomationIds.payCancel;
        await tester.tap(
          find.byWidgetPredicate(
            (widget) =>
                widget is Semantics && widget.properties.identifier == cancelId,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text(l10n.cancelTradeDialogContentNotStarted),
          findsOneWidget,
        );
        expect(find.text(l10n.cancelTradeDialogContent), findsNothing);
      },
    );
  }
}
