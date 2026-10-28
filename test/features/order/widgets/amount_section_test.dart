import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/amount_section.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';

import '../../../support/catalogue_fixtures.dart';
import '../../../support/provider_harness.dart';

/// Pump a single-amount [AmountSection] with [code] selected, and return its
/// amount controller.
Future<TextEditingController> _pump(WidgetTester tester, String code) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final amount = TextEditingController();
  addTearDown(amount.dispose);
  final container = createContainer(
    overrides: [
      catalogueOverride([
        ...kTestCatalogue,
        const FiatCurrency(code: 'RBTC', name: 'RBTC', peg: 'BTC'),
      ]),
      selectedFiatCodeProvider.overrideWith((ref) => code),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: AmountSection(
            amountController: amount,
            minController: TextEditingController(),
            maxController: TextEditingController(),
            symbols: (group: ',', decimal: '.'),
            fiatFormat: NumberFormat('#,##0.##', 'en'),
            quickAmounts: const [],
            onChanged: () {},
            onRangeChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return amount;
}

void main() {
  group('AmountSection', () {
    testWidgets('a BTC-pegged code is entered in whole sats (#907)', (
      tester,
    ) async {
      final amount = await _pump(tester, 'RBTC');

      await tester.enterText(find.byType(TextField).first, '100000.5');
      await tester.pump();

      // `fa` for RBTC counts sats, and sats are whole.
      expect(amount.text, '100,000');
      expect(find.text('sats'), findsOneWidget);
    });

    testWidgets('a fiat keeps its decimals and shows no sats unit', (
      tester,
    ) async {
      final amount = await _pump(tester, 'USD');

      await tester.enterText(find.byType(TextField).first, '25.5');
      await tester.pump();

      expect(amount.text, '25.5');
      expect(find.text('sats'), findsNothing);
    });
  });
}
