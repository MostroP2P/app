import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/shared/widgets/currency_mark.dart';

/// Every entry of the bundled catalogue, so the marks are checked against
/// what ships, not a fixture.
final _catalogue = parseFiatCatalogue(
  File('assets/data/fiat.json').readAsStringSync(),
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fiatCurrenciesProvider.overrideWith((ref) async => _catalogue),
      ],
      child: MaterialApp(
        theme: theme ?? buildDarkTheme(),
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CurrencyMark (DS-TYP-9)', () {
    testWidgets('draws a fiat as its flag, through the flags fallback', (
      tester,
    ) async {
      await _pump(tester, const CurrencyMark(code: 'ARS', size: 13));

      final paragraph = tester.renderObject<RenderParagraph>(
        find.text('🇦🇷', findRichText: true),
      );
      expect(
        paragraph.text.style?.fontFamilyFallback,
        contains(AppFonts.flags),
      );
      expect(find.byType(StablecoinCoin), findsNothing);
    });

    for (final coin in _catalogue.where((c) => c.isStablecoin)) {
      testWidgets('draws ${coin.code} as a coin, never as text', (
        tester,
      ) async {
        await _pump(tester, CurrencyMark(code: coin.code, size: 13));

        // A painted coin: no paragraph at all, so nothing can reach the
        // flags font or the OS emoji font.
        expect(find.byType(StablecoinCoin), findsOneWidget);
        expect(find.byType(Text), findsNothing);
        expect(find.byType(RichText), findsNothing);
      });
    }

    testWidgets('draws nothing for a code the catalogue lacks', (tester) async {
      await _pump(tester, const CurrencyMark(code: 'XXX', size: 13));

      expect(find.byType(Text), findsNothing);
      expect(find.byType(StablecoinCoin), findsNothing);
    });

    testWidgets('the gap variant collapses with the mark', (tester) async {
      await _pump(
        tester,
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CurrencyMarkGap(code: 'XXX', size: 13, gap: 6),
            Text('XXX'),
          ],
        ),
      );
      expect(tester.getSize(find.byType(CurrencyMarkGap)), Size.zero);

      await _pump(
        tester,
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CurrencyMarkGap(code: 'USDT', size: 13, gap: 6),
            Text('USDT'),
          ],
        ),
      );
      final coin = tester.getSize(find.byType(StablecoinCoin));
      expect(
        tester.getSize(find.byType(CurrencyMarkGap)).width,
        coin.width + 6,
      );
    });

    test('the coin carries its peg\'s sign', () {
      expect(pegSign('USD'), r'$');
      expect(pegSign('EUR'), '€');
      expect(pegSign('ARS'), 'A');
    });
  });
}
