import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/features/reputation/reputation_api.dart';
import 'package:mostro/features/reputation/screens/import_reputation_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/reputation_transfer.dart';

const _json = '{"id":"a","kind":38388}';

ReputationAttestationInfo _info() => ReputationAttestationInfo(
  id: 'a',
  issuer: 'b' * 64,
  destination: 'c' * 64,
  subject: 'acct',
  reviews: 214,
  rating: '4.87',
  since: 1696204800,
  createdAt: 1790899200,
  expiration: 1791504000,
  json: _json,
);

/// Stands in for the Rust core: parses only [_json], imports or refuses.
class _FakeApi extends ReputationApi {
  final List<String> imported = [];
  Object? refuse;

  @override
  ReputationAttestationInfo parse(String json) {
    if (json != _json) throw Exception('InvalidReputationAttestation: bad');
    return _info();
  }

  @override
  Future<ReputationAttestationInfo> import(String json) async {
    if (refuse != null) throw refuse!;
    imported.add(json);
    return _info();
  }

  @override
  Future<ReputationAttestationInfo?> pending() async => null;
}

Future<_FakeApi> _pump(WidgetTester tester) async {
  final api = _FakeApi();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [reputationApiProvider.overrideWithValue(api)],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ImportReputationScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the figures of a pasted attestation and imports it', (
    tester,
  ) async {
    final api = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'from the bot:\n$_json');
    await _tap(tester, 'Check');
    expect(
      find.textContaining('214 ratings received, 4.87 on average'),
      findsOneWidget,
    );
    await _tap(tester, 'Import into this Mostro');
    expect(api.imported, [_json]);
    expect(find.text('Your reputation was imported.'), findsOneWidget);
  });

  testWidgets('says why an attestation is refused', (tester) async {
    final api = await _pump(tester);
    await tester.enterText(find.byType(TextField), 'nothing useful');
    await _tap(tester, 'Check');
    expect(find.textContaining('not a valid reputation'), findsOneWidget);

    api.refuse = Exception('ReputationAlreadyImported: refused by the node');
    await tester.enterText(find.byType(TextField), _json);
    await _tap(tester, 'Check');
    await _tap(tester, 'Import into this Mostro');
    expect(find.textContaining('already imported'), findsOneWidget);

    api.refuse = Exception('PrivacyModeEnabled: needs the identity key');
    await _tap(tester, 'Import into this Mostro');
    expect(find.textContaining('full privacy mode'), findsOneWidget);
  });
}
