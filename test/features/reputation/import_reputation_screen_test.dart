import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

import '../../support/load_app_fonts.dart';

final _en = AppLocalizationsEn();

const _json = '{"id":"a","kind":38388}';
const _npub = 'npub1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqq';
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
  List<String>? importIssuers;
  bool privacy;
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
  Object? launchError;
  Future<bool> Function()? readPrivacy;
  Future<String?> Function()? readIdentity;
  Completer<ReputationAttestationInfo>? importReply;
  Completer<ReputationAttestationInfo>? checkReply;

  @override
  String npub(String identity) => _npub;

  @override
  ReputationSupportInfo support() =>
      ReputationSupportInfo(importIssuers: importIssuers);

  @override
  Future<bool> privacyMode() async =>
      readPrivacy == null ? privacy : await readPrivacy!();

  @override
  Future<ReputationAttestationInfo> check(String json) async {
    checked.add(json);
    if (checkReply != null) return checkReply!.future;
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
    if (importReply != null) return importReply!.future;
    return _info(json: json);
  }

  /// Delays [pending] when set.
  Completer<ReputationAttestationInfo?>? pendingReply;

  @override
  Future<ReputationAttestationInfo?> pending() =>
      pendingReply?.future ?? Future.value(pendingInfo);

  @override
  Future<String?> identity() async =>
      readIdentity == null ? _identity : await readIdentity!();

  @override
  Future<bool> openExternal(Uri uri) async {
    opened.add(uri);
    if (launchError != null) throw launchError!;
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
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(text));
  await tester.pumpAndSettle();
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
  setUpAll(loadAppFonts);
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

  testWidgets('a capability change while the pending attestation is read '
      'does not lose its check', (tester) async {
    // Arrange: the pending read is still in flight when the timer fires.
    final api = _FakeApi()..pendingReply = Completer();
    await _pump(tester, api: api);
    api.importIssuers = null;
    await tester.pump(const Duration(seconds: 2));

    // Act
    api.pendingReply!.complete(_info());
    await tester.pumpAndSettle();

    // Assert: the prefilled attestation was checked by the load that read it.
    expect(find.text(_json), findsOneWidget);
    expect(api.checked, [_json]);
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

  // #883: on a cold start the node's info event can arrive after the screen
  // opened; until then the node reads as not importing.
  testWidgets('the screen picks up the capabilities when they arrive after '
      'it opened, without Retry', (tester) async {
    // Arrange
    final api = await _pump(tester, api: _FakeApi(importIssuers: null));
    expect(find.text(_en.reputationNodeDoesNotImport), findsOneWidget);

    // Act: the capability fetch lands.
    api.importIssuers = const [];
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Assert
    expect(find.text(_en.reputationNodeDoesNotImport), findsNothing);
    expect(_button(tester, _en.reputationCheck).enabled, isTrue);
    expect(find.widgetWithText(SelectableText, _npub), findsOneWidget);

    // And the other way: a fetch that retracts the capability.
    api.importIssuers = null;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text(_en.reputationNodeDoesNotImport), findsOneWidget);
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
    expect(find.textContaining('1 rating ·'), findsOneWidget);
  });

  // DS-L10N-5: an imported reputation reads like every other one.
  testWidgets('the figures read as a reputation does on every screen', (
    tester,
  ) async {
    await _pump(tester);

    await _paste(tester, _json);
    await _tap(tester, _en.reputationCheck);

    expect(find.text('★ 4.87 · 214 ratings · since Oct 2023'), findsOneWidget);
  });

  testWidgets('shows the full selectable npub for the bot confirmation', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.widgetWithText(SelectableText, _npub), findsOneWidget);
  });

  testWidgets('no action is enabled until privacy has been read', (
    tester,
  ) async {
    final privacy = Completer<bool>();
    final api = _FakeApi()..readPrivacy = () => privacy.future;
    await _pump(tester, api: api);
    expect(_button(tester, _en.reputationOpenLnp2pbot).enabled, isFalse);
    expect(_button(tester, _en.reputationCheck).enabled, isFalse);
    privacy.complete(true);
    await tester.pumpAndSettle();
    expect(api.opened, isEmpty);
  });

  testWidgets('a failed privacy read stays blocked and can be retried', (
    tester,
  ) async {
    final api =
        _FakeApi()..readPrivacy = () async => throw Exception('unavailable');
    await _pump(tester, api: api);
    expect(_button(tester, _en.reputationOpenLnp2pbot).enabled, isFalse);
    expect(_button(tester, _en.reputationCheck).enabled, isFalse);
    api.readPrivacy = null;
    await _tap(tester, _en.retry);
    expect(_button(tester, _en.reputationOpenLnp2pbot).enabled, isTrue);
  });

  testWidgets('the bot rechecks privacy before disclosing the identity', (
    tester,
  ) async {
    final api = await _pump(tester);
    api.privacy = true;
    await _tap(tester, _en.reputationOpenLnp2pbot);
    expect(api.opened, isEmpty);
    expect(find.text(_en.reputationIdentityRequired), findsOneWidget);
  });

  testWidgets('the bot rechecks node support before opening', (tester) async {
    final api = await _pump(tester);
    api.importIssuers = null;
    await _tap(tester, _en.reputationOpenLnp2pbot);
    expect(api.opened, isEmpty);
    expect(find.text(_en.reputationNodeDoesNotImport), findsOneWidget);
  });

  testWidgets('leaving during the identity read never opens Telegram', (
    tester,
  ) async {
    final api = await _pump(tester);
    final identity = Completer<String?>();
    api.readIdentity = () => identity.future;
    await tester.tap(find.text(_en.reputationOpenLnp2pbot));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    identity.complete(_identity);
    await tester.pumpAndSettle();
    expect(api.opened, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an identity change requires reviewing the displayed key again', (
    tester,
  ) async {
    final api = await _pump(tester);
    api.readIdentity = () async => 'cd' * 32;
    await _tap(tester, _en.reputationOpenLnp2pbot);
    expect(api.opened, isEmpty);
  });

  testWidgets('launcher exceptions are shown as a localized failure', (
    tester,
  ) async {
    final api = await _pump(tester);
    api.launchError = Exception('no handler');
    await _tap(tester, _en.reputationOpenLnp2pbot);
    expect(tester.takeException(), isNull);
    expect(find.text(_en.reputationOpenLnp2pbotFailed), findsOneWidget);
  });

  testWidgets('the input stays fixed while an import awaits its result', (
    tester,
  ) async {
    final api = await _pump(tester);
    await _paste(tester, _json);
    await _tap(tester, _en.reputationCheck);
    final reply = Completer<ReputationAttestationInfo>();
    api.importReply = reply;
    await _tap(tester, _en.reputationImportConfirm);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    reply.complete(_info());
    await tester.pumpAndSettle();
    expect(api.imported, [_json]);
    expect(find.text(_en.reputationImported), findsOneWidget);
  });

  testWidgets('editing during Check discards the delayed result', (
    tester,
  ) async {
    final api = await _pump(tester);
    final reply = Completer<ReputationAttestationInfo>();
    api.checkReply = reply;
    await _paste(tester, _json);
    await _tap(tester, _en.reputationCheck);
    await _paste(tester, _otherJson);
    reply.complete(_info());
    await tester.pumpAndSettle();
    expect(find.text(_en.reputationImportConfirm), findsNothing);
    expect(api.imported, isEmpty);
  });

  testWidgets('review counts use the locale number separators', (tester) async {
    await _pump(
      tester,
      api: _FakeApi(reviews: 12345),
      locale: const Locale('es'),
    );
    await _paste(tester, _json);
    await _tap(tester, 'Comprobar');
    expect(find.textContaining('12.345'), findsOneWidget);
    expect(find.textContaining('12345'), findsNothing);
  });

  testWidgets('a missing identity blocks actions with an actionable message', (
    tester,
  ) async {
    final api = _FakeApi()..readIdentity = () async => null;
    await _pump(tester, api: api);
    expect(find.text(_en.noIdentityFoundMessage), findsOneWidget);
    expect(_button(tester, _en.reputationOpenLnp2pbot).enabled, isFalse);
    expect(_button(tester, _en.reputationCheck).enabled, isFalse);
  });

  testWidgets('privacy enabled during the identity read cancels the handoff', (
    tester,
  ) async {
    final api = await _pump(tester);
    final identity = Completer<String?>();
    api.readIdentity = () => identity.future;
    await tester.tap(find.text(_en.reputationOpenLnp2pbot));
    await tester.pump();
    api.privacy = true;
    identity.complete(_identity);
    await tester.pumpAndSettle();
    expect(api.opened, isEmpty);
    expect(find.text(_en.reputationIdentityRequired), findsOneWidget);
  });

  for (final outcome in ['invalid', 'launch', 'imported']) {
    testWidgets('announces the $outcome result to screen readers', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();

      try {
        final api = await _pump(tester);
        late final String message;
        if (outcome == 'launch') {
          api.launches = false;
          await _tap(tester, _en.reputationOpenLnp2pbot);
          message = _en.reputationOpenLnp2pbotFailed;
        } else if (outcome == 'invalid') {
          await _paste(tester, 'not an attestation');
          await _tap(tester, _en.reputationCheck);
          message = _en.reputationInvalidAttestation;
        } else {
          await _paste(tester, _json);
          await _tap(tester, _en.reputationCheck);
          await _tap(tester, _en.reputationImportConfirm);
          message = _en.reputationImported;
        }
        expect(
          tester.getSemantics(find.text(message)),
          isSemantics(isLiveRegion: true),
        );
      } finally {
        semantics.dispose();
      }
    });
  }

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
      final label = de.reputationImportConfirm;
      final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
      final lines =
          paragraph
              .getBoxesForSelection(
                TextSelection(baseOffset: 0, extentOffset: label.length),
              )
              .map((box) => box.top)
              .toSet();
      expect(
        lines,
        hasLength(1),
        reason: 'Action labels must stay on one line',
      );
    });
  }
}
