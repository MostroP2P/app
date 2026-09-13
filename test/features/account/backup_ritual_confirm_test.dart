import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/account/screens/backup_ritual_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../support/provider_harness.dart';

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

/// Confirms only when the test releases [gate], so the user can leave the
/// flow while the confirmation is still in flight.
class _SlowReminder extends BackupReminderNotifier {
  _SlowReminder(this.gate) : super(initialValue: true);

  final Completer<void> gate;

  @override
  Future<void> confirmBackupComplete() => gate.future;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'a confirmation that finishes after the user left still marks the backup',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final gate = Completer<void>();
      final container = createContainer(
        overrides: [
          backupReminderProvider.overrideWith((ref) => _SlowReminder(gate)),
          backupCompletedProvider.overrideWith(
            (ref) => BackupCompletedNotifier(initialValue: false),
          ),
        ],
      );
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildDarkTheme(),
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder:
                                (_) => const BackupRitualScreen(
                                  debugWords: _words,
                                ),
                          ),
                        ),
                    child: const Text('open'),
                  ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.wroteThemDownVerifyButton));
      await tester.pumpAndSettle();
      for (var i = 0; i < 3; i++) {
        final dynamic state = tester.state(find.byType(BackupRitualScreen));
        final correct = state.debugCorrectWordForActiveSlot as String;
        await tester.tap(find.widgetWithText(InkWell, correct).first);
        await tester.pumpAndSettle();
      }

      // Confirm, then leave before the confirmation completes.
      await tester.tap(find.text(l10n.confirmButtonLabel));
      await tester.pump();
      await tester.tap(find.text(l10n.reviewWordsButton));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      expect(find.byType(BackupRitualScreen), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(container.read(backupCompletedProvider), isTrue);
    },
  );
}
