import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/shared/widgets/counterpart_reputation_row.dart';

/// The one-row counterpart reputation of the trade screen (8b, 8c): the
/// grade on the avatar, the role, and the trades and age in one line. A
/// counterpart nobody has rated shows `New` rather than a fake 0.0.
void main() {
  final en = AppLocalizationsEn();

  Future<void> pump(
    WidgetTester tester, {
    required double rating,
    required int reviews,
    required int days,
    required bool counterpartIsBuyer,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CounterpartReputationRow(
            rating: rating,
            reviews: reviews,
            days: days,
            counterpartIsBuyer: counterpartIsBuyer,
          ),
        ),
      ),
    );
  }

  testWidgets('a rated buyer: grade, role and the summary line', (
    tester,
  ) async {
    await pump(
      tester,
      rating: 4.8,
      reviews: 2,
      days: 1,
      counterpartIsBuyer: true,
    );

    expect(find.text('4.8'), findsOneWidget);
    expect(find.text(en.tradeRoleBuyer), findsOneWidget);
    expect(find.text(en.reputationNew), findsNothing);
    expect(find.textContaining(en.reputationTradesCount(2)), findsOneWidget);
    expect(find.textContaining(en.reputationDaysOnMostro(1)), findsOneWidget);
  });

  testWidgets('a seller nobody rated reads New instead of a grade', (
    tester,
  ) async {
    await pump(
      tester,
      rating: 0,
      reviews: 0,
      days: 12,
      counterpartIsBuyer: false,
    );

    expect(find.text(en.reputationNew), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
    expect(find.text(en.tradeRoleSeller), findsOneWidget);
    expect(find.textContaining(en.reputationDaysOnMostro(12)), findsOneWidget);
  });

  test('highlightFigures styles every run of digits and nothing else', () {
    const strong = TextStyle(fontWeight: FontWeight.w500);
    final spans = highlightFigures('2 trades · 1,234 days', strong);

    expect(spans.map((s) => (s as TextSpan).text), [
      '2',
      ' trades · ',
      '1,234',
      ' days',
    ]);
    expect((spans[0] as TextSpan).style, strong);
    expect((spans[1] as TextSpan).style, isNull);
    expect((spans[2] as TextSpan).style, strong);
  });
}
