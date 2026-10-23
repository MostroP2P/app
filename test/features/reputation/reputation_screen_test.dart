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
const _issuer =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

ReputationAttestationInfo _info() => const ReputationAttestationInfo(
  id: 'a',
  issuer: _issuer,
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
  String? issuer;
  int exports = 0;
  String? exportedWithRebind;
  final signedFor = <String>[];
  Object? refuse;

  _FakeApi(this.issuer);

  @override
  ReputationSupportInfo support() =>
      ReputationSupportInfo(issuer: issuer, importIssuers: const []);

  @override
  Future<String?> identity() async => _identity;

  /// Stands in for the Rust encoder: the one key in these tests, as hex or
  /// npub, and `InvalidPubkey` for anything else.
  @override
  String npub(String identity) {
    if (identity == _identity || identity == _npub) return _npub;
    throw Exception('InvalidPubkey: $identity');
  }

  @override
  Future<ReputationAttestationInfo> export({
    String? destination,
    String? rebind,
  }) async {
    exports++;
    exportedWithRebind = rebind;
    if (refuse != null) throw refuse!;
    return _info();
  }

  @override
  Future<String> signRebind({
    required String issuer,
    required String newIdentity,
  }) async {
    signedFor.add(newIdentity);
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
  Locale locale = const Locale('en'),
  double textScale = 1,
  Size size = const Size(1080, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _FakeApi(issuer);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        reputationApiProvider.overrideWithValue(api),
        privacyModeProvider.overrideWith((ref) => _Privacy(privacy)),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
        home: const ReputationScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return api;
}

Finder _exportButton() =>
    find.widgetWithText(FilledButton, 'Export my reputation');

Future<void> _exportConfirmed(WidgetTester tester) async {
  await tester.tap(_exportButton());
  await tester.pumpAndSettle();
  await tester.tap(find.text('Export'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('export asks to confirm the npub before binding it', (
    tester,
  ) async {
    final api = await _pump(tester, issuer: _issuer);
    await tester.tap(_exportButton());
    await tester.pumpAndSettle();
    expect(find.textContaining(_npub), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.exports, 0);

    await _exportConfirmed(tester);
    expect(api.exports, 1);
    expect(api.exportedWithRebind, isNull);
    expect(find.textContaining('Your reputation is ready'), findsOneWidget);
  });

  testWidgets('export sends the authorization pasted from the old identity', (
    tester,
  ) async {
    final api = await _pump(tester, issuer: _issuer);
    await tester.enterText(
      find.widgetWithText(
        TextField,
        'Authorization from your previous identity (optional)',
      ),
      '  {"kind":38388,"rebind":true}\n',
    );
    await _exportConfirmed(tester);
    expect(api.exportedWithRebind, '{"kind":38388,"rebind":true}');
  });

  testWidgets('a node that does not export says so', (tester) async {
    await _pump(tester);
    expect(
      find.text('This Mostro does not export reputation.'),
      findsOneWidget,
    );
    expect(_exportButton(), findsNothing);
  });

  testWidgets('the export card appears once the node turns out to export', (
    tester,
  ) async {
    final api = await _pump(tester);
    expect(_exportButton(), findsNothing);

    // The capability fetch of a cold start lands after the screen opened.
    api.issuer = _issuer;
    await tester.pump(const Duration(seconds: 2));
    expect(_exportButton(), findsOneWidget);
  });

  testWidgets('shows the node refusal of an export', (tester) async {
    final api = await _pump(tester, issuer: _issuer);
    api.refuse = Exception(
      'NotEligibleForReputationExport: refused by the node',
    );
    await _exportConfirmed(tester);
    expect(find.textContaining('at least 10 completed trades'), findsOneWidget);
  });

  // #882: the user is on the source, and nothing they pasted is involved, so
  // "This is not a valid reputation. Request it again from its source."
  // points them nowhere.
  testWidgets('an export that fails for a reason without a message of its own '
      'says this Mostro could not export', (tester) async {
    // Arrange
    final api = await _pump(tester, issuer: _issuer);
    api.refuse = Exception(
      'InvalidPayload: the node answered without an attestation',
    );

    // Act
    await _exportConfirmed(tester);

    // Assert
    expect(find.textContaining('could not export'), findsOneWidget);
    expect(find.textContaining('not a valid reputation'), findsNothing);
  });

  testWidgets('an answer signed by another key than the one the node '
      'announced says to refresh its info', (tester) async {
    // Arrange
    final api = await _pump(tester, issuer: _issuer);
    api.refuse = Exception(
      'ReputationIssuerKeyMismatch: signed by another key than announced',
    );

    // Act
    await _exportConfirmed(tester);

    // Assert
    expect(find.textContaining('other than the one it announced'), findsOne);
    expect(find.textContaining('not a valid reputation'), findsNothing);
  });

  testWidgets('refuses to sign a rebind for a value that is not a key', (
    tester,
  ) async {
    final api = await _pump(tester, issuer: _issuer);
    await tester.enterText(
      find.widgetWithText(TextField, 'New identity (npub or hex)'),
      'nope',
    );
    await tester.tap(find.text('Sign authorization'));
    await tester.pumpAndSettle();
    expect(find.text('That is not a valid npub or hex key.'), findsOneWidget);
    expect(find.text('Authorize this identity?'), findsNothing);
    expect(api.signedFor, isEmpty);
  });

  testWidgets('signs a rebind only after the npub is confirmed', (
    tester,
  ) async {
    final api = await _pump(tester, issuer: _issuer);
    // Typed as hex, confirmed as the npub it encodes.
    await tester.enterText(
      find.widgetWithText(TextField, 'New identity (npub or hex)'),
      _identity,
    );
    await tester.tap(find.text('Sign authorization'));
    await tester.pumpAndSettle();
    expect(find.text('Authorize this identity?'), findsOneWidget);
    expect(find.textContaining(_npub), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.signedFor, isEmpty);

    await tester.tap(find.text('Sign authorization'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign authorization').last);
    await tester.pumpAndSettle();
    expect(api.signedFor, [_npub]);
    expect(find.text('rebind:$_issuer:$_npub'), findsOneWidget);
  });

  testWidgets('privacy mode turns both directions off', (tester) async {
    await _pump(tester, issuer: _issuer, privacy: true);
    expect(find.textContaining('Turn off full privacy mode'), findsOneWidget);
    for (final label in [
      'Import reputation',
      'Export my reputation',
      'Sign authorization',
    ]) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      );
      expect(button, findsOneWidget, reason: label);
      expect(
        tester.widget<ButtonStyleButton>(button).onPressed,
        isNull,
        reason: label,
      );
    }
  });

  // DS-A11Y-4: German, 2× text, 320 dp wide, in every state the screen shows.
  group('fits at 2× text in German on 320 dp', () {
    for (final (name, issuer, privacy) in [
      ('exporting node', _issuer, false),
      ('node that does not export', null, false),
      ('privacy mode', _issuer, true),
    ]) {
      testWidgets(name, (tester) async {
        await _pump(
          tester,
          issuer: issuer,
          privacy: privacy,
          locale: const Locale('de'),
          textScale: 2,
          size: const Size(320, 640),
        );
        await tester.drag(find.byType(ListView), const Offset(0, -4000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
