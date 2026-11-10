import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/shared/widgets/currency_group_header.dart';
import 'package:mostro/shared/widgets/currency_mark.dart';
import 'package:mostro/shared/widgets/currency_picker_dialog.dart';

import '../../support/catalogue_fixtures.dart';

/// Opens the picker over the whole catalogue, as Settings does.
Future<void> _pump(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [catalogueOverride()],
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCurrencyPickerDialog(
                context,
                currencies: fiatCurrenciesProvider,
                selected: null,
                onSelect: (_) {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('currency picker', () {
    testWidgets('lists the catalogue with the stablecoins under a header', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('US Dollar'), findsOneWidget);
      expect(find.text('Tether USD'), findsOneWidget);
      expect(find.byType(StablecoinsGroupHeader), findsOneWidget);
      expect(find.text('STABLECOINS'), findsOneWidget);
      // The coin is drawn, the fiats keep their flags.
      expect(find.byType(StablecoinCoin), findsOneWidget);
      expect(find.text('🇺🇸'), findsOneWidget);
      // The header sits after the last fiat and before the coin.
      final header = tester.getTopLeft(find.byType(StablecoinsGroupHeader));
      expect(
        header.dy,
        greaterThan(tester.getTopLeft(find.text('Argentine Peso')).dy),
      );
      expect(header.dy, lessThan(tester.getTopLeft(find.text('USDT')).dy));
    });

    testWidgets('searching by name narrows to the coin, header kept', (
      tester,
    ) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'teth');
      await tester.pumpAndSettle();

      expect(find.text('Tether USD'), findsOneWidget);
      expect(find.text('US Dollar'), findsNothing);
      expect(find.byType(StablecoinsGroupHeader), findsOneWidget);
    });

    // DS-A11Y-4: a changed modal fits at 320 dp and 2x text in German.
    testWidgets('fits at 320 dp and 2x text in German', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester, locale: const Locale('de'), textScale: 2.0);

      expect(tester.takeException(), isNull);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('searching a fiat shows no stablecoins header', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField), 'euro');
      await tester.pumpAndSettle();

      expect(find.text('Euro'), findsOneWidget);
      expect(find.byType(StablecoinsGroupHeader), findsNothing);
    });
  });
}
