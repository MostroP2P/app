import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/account/screens/backup_ritual_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';

const _words = <String>[
  'abandon', 'ability', 'able', 'about', 'above', 'absent',
  'absorb', 'abstract', 'absurd', 'abuse', 'access', 'accident',
];

Future<void> _pumpRitual(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // The backup-completed flag is persisted through the Rust identity
        // bridge (#141), which is unavailable under flutter_test — back it with
        // an in-memory fake so tapping "confirm" doesn't hit the real bridge.
        backupCompletedProvider.overrideWith((ref) {
          var confirmed = false;
          return BackupCompletedNotifier(
            initialValue: false,
            getConfirmed: () async => confirmed,
            setConfirmed: (v) async => confirmed = v,
            resetConfirmed: () async => confirmed = false,
          );
        }),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: BackupRitualScreen(debugWords: _words),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _correctWord(WidgetTester tester) {
  final dynamic state = tester.state(find.byType(BackupRitualScreen));
  final String? w = state.debugCorrectWordForActiveSlot as String?;
  expect(w, isNotNull, reason: 'verification should be active');
  return w!;
}

Finder _aWrongOption(WidgetTester tester) {
  final correct = _correctWord(tester);
  for (final w in _words) {
    if (w == correct) continue;
    // Scope to the option buttons (InkWell), so a filled answer chip with the
    // same text can't be matched instead once slots start filling.
    final f = find.widgetWithText(InkWell, w);
    if (f.evaluate().isNotEmpty) return f.first;
  }
  fail('no wrong option visible');
}

Future<void> _goToVerify(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.text(l10n.wroteThemDownVerifyButton));
  await tester.pumpAndSettle();
}

void main() {
  late AppLocalizations l10n;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('first wrong pick keeps the user on step 2 with feedback',
      (tester) async {
    await _pumpRitual(tester);
    await _goToVerify(tester, l10n);
    expect(find.text(l10n.tapCorrectWordsTitle), findsOneWidget);

    await tester.tap(_aWrongOption(tester));
    await tester.pumpAndSettle();

    expect(find.text(l10n.tapCorrectWordsTitle), findsOneWidget);
    expect(find.text(l10n.wrongPickMessage), findsOneWidget);
  });

  testWidgets(
      'second wrong pick on the same word returns to step 1 with the SnackBar',
      (tester) async {
    await _pumpRitual(tester);
    await _goToVerify(tester, l10n);

    await tester.tap(_aWrongOption(tester));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tapCorrectWordsTitle), findsOneWidget);

    await tester.tap(_aWrongOption(tester));
    await tester.pump();

    expect(find.text(l10n.backupRitualStep1Title), findsOneWidget);
    expect(find.text(l10n.backupRitualSecondFailureMessage), findsOneWidget);
  });

  testWidgets(
      'after restarting verification, one wrong pick is tolerated again',
      (tester) async {
    await _pumpRitual(tester);
    await _goToVerify(tester, l10n);

    await tester.tap(_aWrongOption(tester));
    await tester.pumpAndSettle();
    await tester.tap(_aWrongOption(tester));
    await tester.pump();
    expect(find.text(l10n.backupRitualStep1Title), findsOneWidget);

    // The failure SnackBar sits at the bottom over the verify button; clear it
    // so it can't intercept the restart tap.
    ScaffoldMessenger.of(tester.element(find.byType(BackupRitualScreen)))
        .clearSnackBars();
    await tester.pumpAndSettle();

    await _goToVerify(tester, l10n);
    expect(find.text(l10n.tapCorrectWordsTitle), findsOneWidget);

    await tester.tap(_aWrongOption(tester));
    await tester.pumpAndSettle();
    expect(find.text(l10n.tapCorrectWordsTitle), findsOneWidget);
    expect(find.text(l10n.backupRitualStep1Title), findsNothing);
  });

  testWidgets('answering all three words correctly confirms the backup',
      (tester) async {
    await _pumpRitual(tester);
    await _goToVerify(tester, l10n);

    // Answer each of the three challenge slots with its correct word.
    for (var i = 0; i < 3; i++) {
      final correct = _correctWord(tester);
      await tester.tap(find.widgetWithText(InkWell, correct).first);
      await tester.pumpAndSettle();
    }

    expect(find.text(l10n.allWordsCorrectMessage), findsOneWidget);
    await tester.tap(find.text(l10n.confirmButtonLabel));
    await tester.pumpAndSettle();

    expect(find.text(l10n.accountBackedUpTitle), findsOneWidget);
  });
}
