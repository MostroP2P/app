import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart' show TradeUpdate;

Finder _semantics(String identifier) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == identifier,
);

/// The node's `invoice_expiration_window` rule reaches the row: an invoice
/// that is live but expires inside the window is refused with the minutes
/// the node needs, and submission stays shut.
void main() {
  testWidgets('an invoice expiring inside the node window is refused', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final submissions = <String>[];
    try {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isWalletConnectedProvider.overrideWithValue(false),
            tradeAmountProvider.overrideWith(
              (ref, orderId) => Stream.value(BigInt.from(250)),
            ),
            tradeUpdatesProvider.overrideWith(
              (ref) => const Stream<TradeUpdate>.empty(),
            ),
            tradeInfoProvider.overrideWith((ref, orderId) async => null),
            mostroNodeProvider.overrideWith((ref) async => null),
            invoiceCheckerProvider.overrideWithValue(
              (request) async => const InvoiceCheckError(
                InvoiceProblem.expiresTooSoon,
                minRemainingSecs: 3600,
              ),
            ),
          ],
          child: MaterialApp(
            theme: buildDarkTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: AddLightningInvoiceScreen(
              orderId: 'order-1',
              submitInvoice: (orderId, invoice, sats) async {
                submissions.add(invoice);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'lnbc2500u1soon');
      // Past the validation debounce and the checker's reply.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.textContaining('60 minutes'), findsOneWidget);

      await tester.tap(_semantics('invoice.submit'), warnIfMissed: false);
      await tester.pump();
      await tester.pump();
      expect(submissions, isEmpty, reason: 'a refused invoice is never sent');
    } finally {
      semantics.dispose();
    }
  });
}
