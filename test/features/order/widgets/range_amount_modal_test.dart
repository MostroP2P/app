import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/range_amount_modal.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// Opens the range dialog in [locale] and returns a reader for its result.
Future<double? Function()> _open(
  WidgetTester tester, {
  required Locale locale,
  double textScale = 1.0,
}) async {
  double? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      locale: locale,
      builder:
          (context, child) => MediaQuery(
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
      home: Builder(
        builder:
            (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showRangeAmountModal(
                    context: context,
                    min: 2000,
                    max: 998000,
                    currencyCode: 'ARS',
                  );
                },
                child: const Text('open'),
              ),
            ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

void main() {
  // Issue #730, DS-CMP-26: the dialog opens from "Take order" and answered
  // "Submit". Its answer repeats the opener, in every language.
  for (final locale in AppLocalizations.supportedLocales) {
    testWidgets('answers with the take button\'s verb in $locale', (
      tester,
    ) async {
      final l10n = lookupAppLocalizations(locale);
      await _open(tester, locale: locale);

      expect(
        find.descendant(
          of: find.byType(ModalFooter),
          matching: find.text(l10n.takeOrderButton),
        ),
        findsOneWidget,
      );
    });
  }

  // Issue #720: the dialog printed its bounds by hand (`2000 – 998000`)
  // right under a card that groups them (`2.000 – 998.000`).
  // DS-A11Y-4: the dialog's answer is a verb now, and German's is the
  // longest ("Order annehmen"). At 320 dp and 2x text the dialog must not
  // overflow, and the answer must not break onto a second line.
  testWidgets('fits at 320 dp and 2x text in German', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const locale = Locale('de');
    final l10n = lookupAppLocalizations(locale);

    await _open(tester, locale: locale, textScale: 2.0);

    expect(tester.takeException(), isNull);
    final answer = tester.renderObject<RenderParagraph>(
      find.text(l10n.rangeAmountTakeAction),
    );
    final line = answer.getFullHeightForCaret(const TextPosition(offset: 0));
    expect(answer.size.height, lessThan(line * 1.5), reason: 'one line');
  });

  testWidgets("shows the bounds with the locale's grouping", (tester) async {
    await _open(tester, locale: const Locale('es'));

    expect(find.text('Mín: 2.000 – Máx: 998.000 ARS'), findsOneWidget);
  });

  testWidgets('groups the typed amount and returns its value', (tester) async {
    final result = await _open(tester, locale: const Locale('es'));

    await tester.enterText(find.byType(TextField), '25000');
    await tester.pump();
    expect(find.text('25.000'), findsOneWidget);

    await tester.tap(find.text('Tomar orden'));
    await tester.pumpAndSettle();
    expect(result(), 25000);
  });

  // The take sends the amount as an integer (`Payload::Amount(amt as i64)`),
  // so a fraction would be truncated on the wire without the user knowing.
  // The field never accepts one.
  testWidgets('accepts no fraction, as the wire amount is whole', (
    tester,
  ) async {
    final result = await _open(tester, locale: const Locale('es'));

    await tester.enterText(find.byType(TextField), '2500,5');
    await tester.pump();
    expect(find.text('2.500'), findsOneWidget);

    await tester.tap(find.text('Tomar orden'));
    await tester.pumpAndSettle();
    expect(result(), 2500);
  });

  testWidgets('a zero amount still gets the range error', (tester) async {
    await _open(tester, locale: const Locale('en'));

    await tester.enterText(find.byType(TextField), '0');
    await tester.pump();

    expect(
      find.text('Amount must be between 2,000 and 998,000'),
      findsOneWidget,
    );
  });

  testWidgets('words the range error with grouped bounds', (tester) async {
    await _open(tester, locale: const Locale('en'));

    await tester.enterText(find.byType(TextField), '1000');
    await tester.pump();

    expect(
      find.text('Amount must be between 2,000 and 998,000'),
      findsOneWidget,
    );
  });
}
