import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/account/screens/account_screen.dart';
import 'package:mostro/features/account/screens/backup_ritual_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../../support/provider_harness.dart';

/// Goldens of the Account and backup redesign (`design_handoff_cuenta_respaldo`):
/// 15a/15b Account, 15c its sheet, 16a–16d the backup, with the handoff's
/// words and its `#2 · #6 · #9` challenge. 360 × 760, `es`, dark and light.
/// PNGs are generated in CI only — see `docs/golden-tests.md`.

const _words = <String>[
  'prefer',
  'olympic',
  'float',
  'negative',
  'alarm',
  'mechanic',
  'capital',
  'because',
  'sausage',
  'struggle',
  'travel',
  'trade',
];

const _challenge = [1, 5, 8];

Widget _app(Brightness brightness, Widget home, {required bool backedUp}) {
  final container = createContainer(
    overrides: [
      backupCompletedProvider.overrideWith(
        (ref) => BackupCompletedNotifier(initialValue: backedUp),
      ),
      backupReminderProvider.overrideWith(
        (ref) => BackupReminderNotifier(initialValue: !backedUp),
      ),
      privacyModeProvider.overrideWith(
        (ref) => PrivacyModeNotifier(initialValue: false),
      ),
    ],
  );
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme:
          brightness == Brightness.dark ? buildDarkTheme() : buildLightTheme(),
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

Widget _ritual() => BackupRitualScreen(
  debugWords: _words,
  debugChallenge: _challenge,
  debugRandom: math.Random(7),
);

/// Answers every slot of the verification with its right word.
Future<void> _solveAll(WidgetTester tester) async {
  for (final i in _challenge) {
    await tester.tap(find.widgetWithText(InkWell, _words[i]).first);
    await tester.pumpAndSettle();
  }
}

void main() {
  late AppLocalizations l10n;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    l10n = await AppLocalizations.delegate.load(const Locale('es'));
  });

  for (final (name, brightness) in [
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    Future<void> golden(
      WidgetTester tester,
      String variant,
      Widget home, {
      bool backedUp = false,
      Future<void> Function()? drive,
    }) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_app(brightness, home, backedUp: backedUp));
      await tester.pumpAndSettle();
      if (drive != null) await drive();

      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/account_${variant}_$name.png'),
      );
    }

    Future<void> toVerify(WidgetTester tester) async {
      await tester.tap(find.text(l10n.wroteThemDownVerifyButton));
      await tester.pumpAndSettle();
    }

    testWidgets('15a account not backed up · $name', (tester) async {
      await golden(tester, '15a', const AccountScreen());
    });

    testWidgets('15b account backed up · $name', (tester) async {
      await golden(tester, '15b', const AccountScreen(), backedUp: true);
    });

    testWidgets('15c backup sheet · $name', (tester) async {
      await golden(
        tester,
        '15c',
        const AccountScreen(),
        drive: () async {
          await tester.tap(find.text(l10n.backupBannerTitle));
          await tester.pumpAndSettle();
        },
      );
    });

    testWidgets('16a write down · $name', (tester) async {
      await golden(tester, '16a', _ritual());
    });

    testWidgets('16b verify, unanswered · $name', (tester) async {
      await golden(tester, '16b', _ritual(), drive: () => toVerify(tester));
    });

    testWidgets('16c verify, all correct · $name', (tester) async {
      await golden(
        tester,
        '16c',
        _ritual(),
        drive: () async {
          await toVerify(tester);
          await _solveAll(tester);
        },
      );
    });

    testWidgets('16d done · $name', (tester) async {
      await golden(
        tester,
        '16d',
        _ritual(),
        drive: () async {
          await toVerify(tester);
          await _solveAll(tester);
          await tester.tap(find.text(l10n.confirmButtonLabel));
          await tester.pumpAndSettle();
        },
      );
    });
  }
}
