import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/my_reputation_provider.dart';
import 'package:mostro/features/account/widgets/my_reputation_card.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/my_reputation.dart';

/// 2023-11-24, the protocol's own example.
const _nov2023 = 1700784000;

MyReputation _rep({
  double rating = 4.8,
  int reviews = 23,
  int? since = _nov2023,
  int days = 142,
}) => MyReputation(
  nodePubkey: 'node-a',
  rating: rating,
  reviews: reviews,
  since: since,
  operatingDays: days,
  fetchedAt: 1,
);

Future<void> _pump(
  WidgetTester tester, {
  bool privacyMode = false,
  MyReputationState state = const MyReputationState(),
  String? nodeName,
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MyReputationCard(
          privacyMode: privacyMode,
          state: state,
          nodeName: nodeName,
        ),
      ),
    ),
  );
}

void main() {
  late AppLocalizations l10n;

  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('shows rating, ratings received, since and the node', (
    tester,
  ) async {
    await _pump(
      tester,
      state: MyReputationState(reputation: _rep()),
      nodeName: 'Mostro P2P',
    );

    expect(find.text(l10n.myReputationTitle), findsOneWidget);
    expect(find.text('4.8'), findsOneWidget);
    expect(find.textContaining('23 ratings'), findsOneWidget);
    expect(find.textContaining('since Nov 2023'), findsOneWidget);
    expect(find.text(l10n.myReputationOnNode('Mostro P2P')), findsOneWidget);
  });

  testWidgets('formats since for the locale', (tester) async {
    await _pump(
      tester,
      state: MyReputationState(reputation: _rep()),
      locale: const Locale('es'),
    );

    expect(find.textContaining('desde nov 2023'), findsOneWidget);
  });

  testWidgets('formats the rating for the locale', (tester) async {
    await _pump(
      tester,
      state: MyReputationState(reputation: _rep()),
      locale: const Locale('es'),
    );

    expect(find.text('4,8'), findsOneWidget);
  });

  testWidgets('falls back to the day count when the node sends no since', (
    tester,
  ) async {
    await _pump(
      tester,
      state: MyReputationState(reputation: _rep(since: null, days: 142)),
    );

    expect(find.textContaining('142 days on Mostro'), findsOneWidget);
  });

  testWidgets('zero ratings is the empty state, never a 0.0 rating', (
    tester,
  ) async {
    await _pump(
      tester,
      state: MyReputationState(
        reputation: _rep(rating: 0, reviews: 0, since: null, days: 0),
      ),
    );

    expect(find.text(l10n.myReputationNoReviews), findsOneWidget);
    expect(find.text('0.0'), findsNothing);
  });

  testWidgets('full privacy explains why there is no reputation', (
    tester,
  ) async {
    await _pump(
      tester,
      privacyMode: true,
      state: MyReputationState(reputation: _rep()),
    );

    expect(find.text(l10n.myReputationPrivacyMode), findsOneWidget);
    expect(find.text('4.8'), findsNothing);
  });

  testWidgets('asking the node with nothing cached says so', (tester) async {
    await _pump(tester, state: const MyReputationState(loading: true));

    expect(find.text(l10n.myReputationLoading), findsOneWidget);
  });

  testWidgets('a node that never answered says so', (tester) async {
    await _pump(tester);

    expect(find.text(l10n.myReputationUnavailable), findsOneWidget);
  });
}
