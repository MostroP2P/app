import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

Finder _semantics(String identifier) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == identifier,
);

void main() {
  testWidgets(
    'a daemon rejection keeps the form and exposes the reason as a readout',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final submissions = <String>[];
      final second = Completer<void>();
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              isWalletConnectedProvider.overrideWithValue(false),
              tradeAmountProvider.overrideWith(
                (ref, orderId) => Stream.value(BigInt.from(999)),
              ),
              tradeUpdatesProvider.overrideWith(
                (ref) => const Stream<TradeUpdate>.empty(),
              ),
              tradeInfoProvider.overrideWith((ref, orderId) async => null),
            ],
            child: MaterialApp(
              theme: buildDarkTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: AddLightningInvoiceScreen(
                orderId: 'order-1',
                submitInvoice: (orderId, invoice, sats) {
                  submissions.add(invoice);
                  if (submissions.length == 1) {
                    throw Exception(
                      'AnyhowException(Order rejected: invalid Lightning invoice.)',
                    );
                  }
                  return second.future;
                },
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();

        // No rejection yet: no readout.
        expect(_semantics('invoice.error'), findsNothing);

        await tester.enterText(find.byType(TextField), 'lnbc1short');
        await tester.pump();
        await tester.tap(_semantics('invoice.submit'));
        await tester.pump();
        await tester.pump();

        // The form is still there, with what was typed, and the reason is a
        // stable readout the harness can assert on.
        expect(submissions, ['lnbc1short']);
        expect(_semantics('invoice.text'), findsOneWidget);
        expect(find.text('lnbc1short'), findsOneWidget);
        final error = _semantics('invoice.error');
        expect(error, findsOneWidget);
        expect(
          tester.getSemantics(error).getSemanticsData().label,
          'The node rejected this invoice. Check its amount and expiry and add a new one.',
        );

        // A new submission clears the previous verdict before it is sent,
        // and a new rejection replaces it.
        await tester.enterText(find.byType(TextField), 'lnbc1next');
        await tester.pump();
        await tester.tap(_semantics('invoice.submit'));
        await tester.pump();
        expect(submissions, ['lnbc1short', 'lnbc1next']);
        expect(_semantics('invoice.error'), findsNothing);
        second.completeError(Exception('NoDaemonResponse'));
        await tester.pump();
        await tester.pump();
        expect(_semantics('invoice.error'), findsOneWidget);
        expect(_semantics('invoice.text'), findsOneWidget);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets(
    'a rejected wallet-generated invoice keeps its reason on screen too',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              isWalletConnectedProvider.overrideWithValue(true),
              tradeAmountProvider.overrideWith(
                (ref, orderId) => Stream.value(BigInt.from(999)),
              ),
              tradeUpdatesProvider.overrideWith(
                (ref) => const Stream<TradeUpdate>.empty(),
              ),
              tradeInfoProvider.overrideWith((ref, orderId) async => null),
            ],
            child: MaterialApp(
              theme: buildDarkTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: AddLightningInvoiceScreen(
                orderId: 'order-1',
                generateInvoice: (_) async => 'lnbc1generated',
                submitInvoice: (orderId, invoice, sats) async {
                  throw Exception(
                    'AnyhowException(Order rejected: invalid Lightning invoice.)',
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();

        final error = _semantics('invoice.error');
        expect(error, findsOneWidget);
        expect(
          tester.getSemantics(error).getSemanticsData().label,
          'The node rejected this invoice. Check its amount and expiry and add a new one.',
        );
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}
