import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

Finder _semantics(String identifier) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == identifier,
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required String? lightningAddress,
  required List<String> submissions,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isWalletConnectedProvider.overrideWithValue(false),
        settingsProvider.overrideWith(
          (ref) => SettingsNotifier(
            initial: AppSettingsState(
              defaultLightningAddress: lightningAddress,
            ),
          ),
        ),
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
          submitInvoice: (orderId, invoice, sats) async {
            submissions.add(invoice);
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  testWidgets(
    'prefills the Lightning address from settings but waits for the buyer to send',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final submissions = <String>[];
      try {
        await _pumpScreen(
          tester,
          lightningAddress: 'buyer@example.com',
          submissions: submissions,
        );

        final field = tester.widget<TextField>(find.byType(TextField));
        expect(field.controller!.text, 'buyer@example.com');
        // Prefilling is not consent: nothing is sent on its own.
        expect(submissions, isEmpty);

        await tester.tap(_semantics('invoice.submit'));
        await tester.pump();
        await tester.pump();
        expect(submissions, ['buyer@example.com']);
      } finally {
        semantics.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );

  testWidgets('leaves the field empty when no Lightning address is set', (
    tester,
  ) async {
    final submissions = <String>[];
    await _pumpScreen(tester, lightningAddress: null, submissions: submissions);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    expect(submissions, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('treats a blank saved Lightning address as unset', (
    tester,
  ) async {
    final submissions = <String>[];
    await _pumpScreen(tester, lightningAddress: '   ', submissions: submissions);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
