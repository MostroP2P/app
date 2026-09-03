import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/peer_reputation_card.dart';

/// The counterpart reputation card (issue #305) is where the maker learns who
/// took their order. Its contract: it names the taker's role (derived from the
/// user's own) and shows the raw numbers — including all-zeros, since a
/// brand-new user and a full-privacy taker are indistinguishable on the wire.
void main() {
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
          body: PeerReputationCard(
            rating: rating,
            reviews: reviews,
            days: days,
            counterpartIsBuyer: counterpartIsBuyer,
          ),
        ),
      ),
    );
  }

  testWidgets('titles the card for the buyer when the taker is the buyer',
      (tester) async {
    await pump(tester,
        rating: 4.375, reviews: 4, days: 64, counterpartIsBuyer: true);

    expect(find.text('Buyer reputation'), findsOneWidget);
    expect(find.text('Seller reputation'), findsNothing);
  });

  testWidgets('titles the card for the seller when the taker is the seller',
      (tester) async {
    await pump(tester,
        rating: 4.375, reviews: 4, days: 64, counterpartIsBuyer: false);

    expect(find.text('Seller reputation'), findsOneWidget);
    expect(find.text('Buyer reputation'), findsNothing);
  });

  testWidgets('rounds the rating to one decimal and shows reviews and days',
      (tester) async {
    await pump(tester,
        rating: 4.375, reviews: 4, days: 64, counterpartIsBuyer: true);

    expect(find.text('4.4'), findsOneWidget); // 4.375 → one decimal
    expect(find.text('4'), findsOneWidget); // reviews
    expect(find.text('64'), findsOneWidget); // days
  });

  testWidgets('shows all-zeros verbatim rather than hiding a new/private taker',
      (tester) async {
    await pump(tester,
        rating: 0.0, reviews: 0, days: 0, counterpartIsBuyer: true);

    expect(find.text('0.0'), findsOneWidget); // rating, not blank
    // Two zero stats (reviews + days) render the same string.
    expect(find.text('0'), findsNWidgets(2));
  });
}
