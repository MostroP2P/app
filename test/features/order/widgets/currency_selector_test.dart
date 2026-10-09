import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import '../../../support/provider_harness.dart';

const _ars = FiatCurrency(code: 'ARS', name: 'Argentine Peso', flag: '🇦🇷');

Future<void> _pump(WidgetTester tester, Widget child) async {
  final container = createContainer(
    overrides: [
      fiatCurrenciesProvider.overrideWith((ref) async => const [_ars]),
      selectedFiatCodeProvider.overrideWith((ref) => 'ARS'),
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
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The value's own tap target: the [InkWell] inside [selector].
Size _target(WidgetTester tester, Type selector) => tester.getSize(
  find.descendant(of: find.byType(selector), matching: find.byType(InkWell)),
);

Color? _codeColor(WidgetTester tester) =>
    tester.widget<Text>(find.text('ARS')).style?.color;

void main() {
  // Issue #732, DS-CMP-27: an editable value says so, in lime with a
  // chevron, as a 48 dp target announced as a button; the same value
  // read-only is neutral and has no chevron.
  for (final selector in const [CurrencyInlineSelector, CurrencyRowSelector]) {
    group('$selector, editable', () {
      Widget build() =>
          selector == CurrencyInlineSelector
              ? const CurrencyInlineSelector()
              : const SizedBox(width: 320, child: CurrencyRowSelector());

      testWidgets('is a target of at least 48 × 48 dp', (tester) async {
        await _pump(tester, build());

        final size = _target(tester, selector);
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
      });

      testWidgets('shows its value in lime ink with a 16 chevron', (
        tester,
      ) async {
        await _pump(tester, build());
        final book = OrderBookPalette.of(tester.element(find.byType(selector)));

        expect(_codeColor(tester), book.limeInk);
        final chevron = tester.widget<Icon>(find.byIcon(Icons.expand_more));
        expect(chevron.size, 16);
      });

      testWidgets('is announced as a button that selects the currency', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, build());

        expect(
          tester.getSemantics(find.text('ARS')),
          isSemantics(isButton: true, hint: 'Select Currency'),
        );
        handle.dispose();
      });
    });
  }

  testWidgets('the read-only chip is neutral and has no chevron', (
    tester,
  ) async {
    await _pump(tester, const OrderCurrencyChip(flag: '🇦🇷', code: 'ARS'));
    final book = OrderBookPalette.of(
      tester.element(find.byType(OrderCurrencyChip)),
    );

    expect(_codeColor(tester), book.textStrong);
    expect(find.byIcon(Icons.expand_more), findsNothing);
  });
}
