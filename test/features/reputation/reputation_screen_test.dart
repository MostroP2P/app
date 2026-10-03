import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/reputation/reputation_api.dart';
import 'package:mostro/features/reputation/screens/reputation_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/reputation_transfer.dart';

const _identity =
    '7e7e9c42a91bfef19fa929e5fda1b72e0ebc1a4c1141673e2794234d86addf4e';
const _npub = 'npub10elfcs4fr0l0r8af98jlmgdh9c8tcxjvz9qkw038js35mp4dma8qzvjptg';

ReputationAttestationInfo _info() => ReputationAttestationInfo(
  id: 'a',
  issuer: 'b' * 64,
  destination: _identity,
  subject: 'acct',
  reviews: 5,
  rating: '4.40',
  since: 1696204800,
  createdAt: 1790899200,
  expiration: 1791504000,
  json: '{"kind":38388}',
);

class _FakeApi extends ReputationApi {
  final String? issuer;
  int exports = 0;
  Object? refuse;

  _FakeApi(this.issuer);

  @override
  ReputationSupportInfo support() =>
      ReputationSupportInfo(issuer: issuer, importIssuers: const []);

  @override
  Future<String?> identity() async => _identity;

  @override
  Future<ReputationAttestationInfo> export({
    String? destination,
    String? rebind,
  }) async {
    exports++;
    if (refuse != null) throw refuse!;
    return _info();
  }

  @override
  Future<String> signRebind({
    required String issuer,
    required String newIdentity,
  }) async {
    if (!newIdentity.startsWith('npub1')) throw Exception('invalid key');
    return 'rebind:$issuer:$newIdentity';
  }
}

class _Privacy extends PrivacyModeNotifier {
  _Privacy(bool on) : super() {
    state = on;
  }
}

Future<_FakeApi> _pump(
  WidgetTester tester, {
  String? issuer,
  bool privacy = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _FakeApi(issuer);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reputationApiProvider.overrideWithValue(api),
        privacyModeProvider.overrideWith((ref) => _Privacy(privacy)),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ReputationScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('export asks to confirm the npub before binding it', (
    tester,
  ) async {
    final api = await _pump(tester, issuer: 'b' * 64);
    await tester.tap(find.widgetWithText(FilledButton, 'Export my reputation'));
    await tester.pumpAndSettle();
    expect(find.textContaining(_npub), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.exports, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Export my reputation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(api.exports, 1);
    expect(find.textContaining('Your reputation is ready'), findsOneWidget);
  });

  testWidgets('a node that does not export says so', (tester) async {
    await _pump(tester);
    expect(
      find.text('This Mostro does not export reputation.'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Export my reputation'),
      findsNothing,
    );
  });

  testWidgets('shows the node refusal of an export', (tester) async {
    final api = await _pump(tester, issuer: 'b' * 64);
    api.refuse = Exception(
      'NotEligibleForReputationExport: refused by the node',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Export my reputation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
    expect(find.textContaining('at least 10 completed trades'), findsOneWidget);
  });

  testWidgets('signs a rebind authorisation for a valid identity only', (
    tester,
  ) async {
    await _pump(tester, issuer: 'b' * 64);
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.tap(find.text('Sign authorization'));
    await tester.pumpAndSettle();
    expect(find.text('That is not a valid npub.'), findsOneWidget);
    await tester.enterText(find.byType(TextField), _npub);
    await tester.tap(find.text('Sign authorization'));
    await tester.pumpAndSettle();
    expect(find.text('rebind:${'b' * 64}:$_npub'), findsOneWidget);
  });

  testWidgets('privacy mode turns both directions off', (tester) async {
    await _pump(tester, issuer: 'b' * 64, privacy: true);
    expect(find.textContaining('Turn off full privacy mode'), findsOneWidget);
    final export = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Export my reputation'),
    );
    expect(export.onPressed, isNull);
  });
}
