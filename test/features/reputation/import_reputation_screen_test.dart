import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/reputation/reputation_api.dart';
import 'package:mostro/features/reputation/screens/import_reputation_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_de.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/reputation_transfer.dart';

final _en = AppLocalizationsEn();

const _json = '{"id":"a","kind":38388}';
const _otherJson = '{"id":"b","kind":38388}';
const _identity =
    'ab1db593a4d1196eb07335fdc702a314712ed29c631ceaebd84708a17d3bc2f7';

ReputationAttestationInfo _info({
  String json = _json,
  int reviews = 214,
  String rating = '4.87',
}) => ReputationAttestationInfo(
  id: json == _json ? 'a' : 'b',
  issuer: 'b' * 64,
  destination: _identity,
  subject: 'acct',
  reviews: reviews,
  rating: rating,
  since: 1696204800,
  createdAt: 1790899200,
  expiration: 1791504000,
  json: json,
);

/// Stands in for the Rust core and the launcher.
class _FakeApi extends ReputationApi {
  _FakeApi({
    this.importIssuers = const [],
    this.privacy = false,
    this.pendingInfo,
    this.reviews = 214,
  });

  /// `null`: the node does not import.
  final List<String>? importIssuers;
  final bool privacy;
  final ReputationAttestationInfo? pendingInfo;
  final int reviews;

  final List<String> checked = [];
  final List<String> imported = [];
  final List<Uri> opened = [];

  /// Thrown by [check] when set.
  Object? refuseCheck;

  /// Thrown by [import] when set.
  Object? refuseImport;

  /// What the launcher answers.
  bool launches = true;

  @override
  ReputationSupportInfo support() =>
      ReputationSupportInfo(importIssuers: importIssuers);

  @override
  Future<bool> privacyMode() async => privacy;

  @override
  Future<ReputationAttestationInfo> check(String json) async {
    checked.add(json);
    if (refuseCheck != null) throw refuseCheck!;
    if (json != _json && json != _otherJson) {
      throw Exception('InvalidReputationAttestation: bad');
    }
    return _info(json: json, reviews: reviews);
  }

  @override
  Future<ReputationAttestationInfo> import(String json) async {
    if (refuseImport != null) throw refuseImport!;
    imported.add(json);
    return _info(json: json);
  }

  @override
  Future<ReputationAttestationInfo?> pending() async => pendingInfo;

  @override
  Future<String?> identity() async => _identity;

  @override
  Future<bool> openExternal(Uri uri) async {
    opened.add(uri);
    return launches;
  }
}

Future<_FakeApi> _pump(
  WidgetTester tester, {
  _FakeApi? api,
  Locale locale = const Locale('en'),
  double textScale = 1,
  Brightness brightness = Brightness.dark,
  Size viewSize = const Size(400, 800),
}) async {
  tester.view.physicalSize = viewSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fake = api ?? _FakeApi();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [reputationApiProvider.overrideWithValue(fake)],
      child: MaterialApp(
        theme:
            brightness == Brightness.dark
                ? buildDarkTheme()
                : buildLightTheme(),
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
        home: const ImportReputationScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _tap(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(
    find.text(text),
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(find.text(text));
  await tester.pumpAndSettle();
}

Future<void> _paste(WidgetTester tester, String text) async {
  // At 2× text the field starts below the fold, not yet built by the list.
  await tester.scrollUntilVisible(
    find.byType(TextField),
    100,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}

/// The button whose label is [text], to read whether it is enabled.
ButtonStyleButton _button(WidgetTester tester, String text) =>
    tester.widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(text),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    );

void main() {
  testWidgets('shows the figures of a pasted attestation and imports it', (
    tester,
  ) async {
    // Arrange
    final api = await _pump(tester);

    // Act
    await _paste(tester, 'from the bot:\n$_json');
    await _tap(tester, _en.reputationCheck);
    await _tap(tester, _en.reputationImportConfirm);

    // Assert
    expect(api.checked, [_json]);
    expect(api.imported, [_json]);
    expect(find.text(_en.reputationImported), findsOneWidget);
  });

  testWidgets('says why an attestation is refused', (tester) async {
    // Arrange
    final api = await _pump(tester);

    // Act + Assert: no JSON at all.
    await _paste(tester, 'nothing useful');
    await _tap(tester, _en.reputationCheck);
    expect(find.text(_en.reputationInvalidAttestation), findsOneWidget);

    // Refused by the node on import.
    api.refuseImport = Exception(
      'ReputationAlreadyImported: refused by the node',
    );
    await _paste(tester, _json);
    await _tap(tester, _en.reputationCheck);
    await _tap(tester, _en.reputationImportConfirm);
    expect(find.text(_en.reputationAlreadyImported), findsOneWidget);
  });

  testWidgets('a refusal the local check can make shows on Check, '
      'and Import is never offered', (tester) async {
    // Arrange
    final api = await _pump(tester);
    api.refuseCheck = Exception(
      'UntrustedReputationIssuer: the node does not trust its issuer',
    );

    // Act
    await _paste(tester, _json);
    await _tap(tester, _en.reputationCheck);

    // Assert
    expect(find.text(_en.reputationUntrustedIssuer), findsOneWidget);
    expect(find.text(_en.reputationImportConfirm), findsNothing);
  });

  testWidgets('editing the text after Check withdraws the checked '
      'attestation, so Import never sends another one', (tester) async {
    // Arrange
    final api = await _pump(tester);
    await _paste(tester, _json);
    await _tap(tester, _en.reputationCheck);
    expect(find.text(_en.reputationImportConfirm), findsOneWidget);

    // Act
    await _paste(tester, _otherJson);

    // Assert: nothing to import until the new text is checked.
    expect(find.text(_en.reputationImportConfirm), findsNothing);
    await _tap(tester, _en.reputationCheck);
    await _tap(tester, _en.reputationImportConfirm);
    expect(api.imported, [_otherJson]);
  });

  testWidgets('an attestation exported from another Mostro is filled in '
      'and checked', (tester) async {
    // Arrange + Act
    final api = await _pump(tester, api: _FakeApi(pendingInfo: _info()));

    // Assert
    expect(find.text(_json), findsOneWidget);
    expect(api.checked, [_json]);
    expect(find.text(_en.reputationImportConfirm), findsOneWidget);
  });

  testWidgets('a node that does not import says so up front and offers '
      'neither the bot nor Check', (tester) async {
    // Arrange + Act
    await _pump(tester, api: _FakeApi(importIssuers: null));

    // Assert
    expect(find.text(_en.reputationNodeDoesNotImport), findsOneWidget);
    expect(_button(tester, _en.reputationOpenLnp2pbot).enabled, isFalse);
    expect(_button(tester, _en.reputationCheck).enabled, isFalse);
  });

  testWidgets('in full privacy mode the identity never goes to the bot', (
    tester,
  ) async {
    // Arrange
    final api = await _pump(tester, api: _FakeApi(privacy: true));

    // Act
    await tester.tap(find.text(_en.reputationOpenLnp2pbot));
    await tester.pumpAndSettle();

    // Assert
    expect(find.text(_en.reputationIdentityRequired), findsOneWidget);
    expect(_button(tester, _en.reputationOpenLnp2pbot).enabled, isFalse);
    expect(api.opened, isEmpty);
  });

  testWidgets('the bot link carries the identity; a failed launch says so', (
    tester,
  ) async {
    // Arrange
    final api = await _pump(tester);
    api.launches = false;

    // Act
    await _tap(tester, _en.reputationOpenLnp2pbot);

    // Assert
    expect(api.opened.single.toString(), startsWith('https://t.me/lnp2pbot'));
    expect(find.text(_en.reputationOpenLnp2pbotFailed), findsOneWidget);
  });

  testWidgets('the rating is formatted for the locale', (tester) async {
    // Arrange
    await _pump(tester, locale: const Locale('es'));

    // Act
    await _paste(tester, _json);
    await tester.ensureVisible(find.text('Comprobar'));
    await tester.tap(find.text('Comprobar'));
    await tester.pumpAndSettle();

    // Assert
    expect(find.textContaining('4,87'), findsOneWidget);
    expect(find.textContaining('4.87'), findsNothing);
  });

  testWidgets('one rating reads in the singular', (tester) async {
    // Arrange
    await _pump(tester, api: _FakeApi(reviews: 1));

    // Act
    await _paste(tester, _json);
    await _tap(tester, _en.reputationCheck);

    // Assert
    expect(find.textContaining('1 rating received,'), findsOneWidget);
  });

  // DS-A11Y-4: German, 320 dp wide, text at 2×, both themes.
  for (final brightness in Brightness.values) {
    testWidgets('fits 320 dp in German at 2× text ($brightness)', (
      tester,
    ) async {
      // Arrange
      final de = AppLocalizationsDe();
      await _pump(
        tester,
        locale: const Locale('de'),
        textScale: 2,
        brightness: brightness,
        viewSize: const Size(320, 640),
      );
      final emptyError = tester.takeException();

      // Act: the screen at its longest, with the figures shown.
      await _paste(tester, _json);
      await _tap(tester, de.reputationCheck);
      await tester.scrollUntilVisible(
        find.text(de.reputationImportConfirm),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Assert
      expect(emptyError, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
