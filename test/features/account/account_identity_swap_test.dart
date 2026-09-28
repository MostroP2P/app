import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/services/identity_service.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/account/restore/restore_run.dart';
import 'package:mostro/features/account/restore/restore_sheet.dart';
import 'package:mostro/features/account/screens/account_screen.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart'
    show FundsAtRisk, FundsAtRiskReason;

/// What the backup state is after an identity swap: generating a mnemonic
/// arms the reminder, importing one the user already holds must not (#530).
const _seed =
    'prefer olympic float negative alarm mechanic '
    'capital because sausage struggle travel trade';

/// The router of the last [_pumpAccount], for the tests that leave the
/// screen while a swap is in flight.
late GoRouter _router;

/// The screen under test, at `/key_management`, with the bridge-backed
/// identity work replaced by the seams and every other provider it reads
/// pinned to a synchronous value.
Future<ProviderContainer> _pumpAccount(
  WidgetTester tester, {
  required bool reminderArmed,
  required bool backedUp,
  Future<void> Function()? onRegenerate,
  Future<void> Function(List<String> words)? onImport,
  Future<RecoveryOutcome> Function(ProviderContainer container)? onRecover,
  Future<List<FundsAtRisk>> Function()? fundsAtRisk,
  bool privacyMode = false,
  Object? privacyError,
}) async {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer(
    overrides: [
      backupReminderProvider.overrideWith(
        (ref) => BackupReminderNotifier(initialValue: reminderArmed),
      ),
      backupCompletedProvider.overrideWith(
        (ref) => BackupCompletedNotifier(initialValue: backedUp),
      ),
      privacyModeProvider.overrideWith(
        (ref) => PrivacyModeNotifier(initialValue: false),
      ),
      // Memory-only: the sembast store does real I/O, which never completes
      // under the widget tester's fake clock.
      notificationsProvider.overrideWith((ref) => NotificationsNotifier()),
      // The trade list and the book the summary reads are bridge-backed.
      restoreSummaryProvider.overrideWith(
        (ref) => const RestoreSummary(inProgress: 0, needsAction: 0),
      ),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: AppRoute.keyManagement,
    routes: [
      GoRoute(
        path: AppRoute.home,
        builder: (_, __) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: AppRoute.keyManagement,
        builder:
            (_, __) => AccountScreen(
              debugWords: _seed.split(' '),
              debugPublicKey: () async => null,
              debugRegenerate: onRegenerate ?? () async {},
              debugImport: onImport ?? (_) async {},
              debugFundsAtRisk: fundsAtRisk ?? () async => const [],
              debugRecover:
                  () async =>
                      await onRecover?.call(container) ??
                      const RecoveryOutcome.skipped(),
              debugPrivacyMode: () async {
                if (privacyError != null) throw privacyError;
                return privacyMode;
              },
              debugRestartOrders: () async {},
              // The restore sheet runs the same recovery: its count on
              // success, an error when it failed.
              debugRestoreRun:
                  () => RestoreRun(
                    progress: () async => const Stream.empty(),
                    recover: () async {
                      final outcome = await onRecover?.call(container);
                      if (outcome?.isFailed ?? false) {
                        throw StateError('NoDaemonResponse');
                      }
                      return outcome?.count ?? 0;
                    },
                  ),
            ),
      ),
    ],
  );
  addTearDown(router.dispose);
  _router = router;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

NotificationModel _notice(String orderId) => NotificationModel.tradeStatus(
  orderId: orderId,
  status: 'active',
  at: DateTime.utc(2026),
);

/// Leave behind what a user who traded leaves: a notice, a per-order role
/// and a chat read mark.
Future<void> _seedPreviousUser(ProviderContainer container) async {
  await container.read(notificationsProvider.notifier).add(_notice('old'));
  container.read(tradeRoleProvider.notifier).state = {'old': true};
  container.read(chatReadStatusProvider.notifier).state = {'old': 1};
}

/// Import the seed, up to the restore sheet if one opens.
Future<void> _submitImport(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.bySemanticsIdentifier(AutomationIds.keysImport));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), _seed);
  await tester.tap(find.widgetWithText(FilledButton, l10n.importButtonLabel));
  await tester.pumpAndSettle();
}

/// Import the seed and close the restore sheet the way its final state
/// offers: `Cerrar` once restored, `Continuar sin restaurar` on failure.
Future<void> _import(WidgetTester tester, AppLocalizations l10n) async {
  await _submitImport(tester, l10n);
  for (final key in const ['restore.close', 'restore.continue']) {
    final button = find.byKey(Key(key));
    if (button.evaluate().isNotEmpty) {
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
  }
}

/// Tap `Generate`, up to whatever opens first: the funds-at-risk warning or
/// the usual confirmation.
Future<void> _tapGenerate(WidgetTester tester) async {
  await tester.tap(find.bySemanticsIdentifier(AutomationIds.keysGenerate));
  await tester.pumpAndSettle();
}

Future<void> _generate(WidgetTester tester) async {
  await _tapGenerate(tester);
  await tester.tap(
    find.bySemanticsIdentifier(AutomationIds.keysGenerateConfirm),
  );
  await tester.pumpAndSettle();
}

void main() {
  late AppLocalizations l10n;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      // What the walkthrough leaves behind on first run.
      kBackupReminderActiveKey: true,
      kBackupReminderDismissedKey: false,
    });
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  // design_handoff_restaurar_ordenes: the restore runs in a sheet (20a–20d)
  // over this screen, and the import finishes once the user closes it.
  group('the restore sheet', () {
    testWidgets('opens after an import and lands home once closed', (
      tester,
    ) async {
      var recoveries = 0;
      await _pumpAccount(
        tester,
        reminderArmed: false,
        backedUp: false,
        onRecover: (_) async {
          recoveries++;
          return const RecoveryOutcome.recovered(0);
        },
      );

      await _submitImport(tester, l10n);

      expect(recoveries, 1);
      expect(find.text(l10n.restoreDoneTitle), findsOneWidget);
      expect(find.text('home'), findsNothing, reason: 'the sheet is up');

      await tester.tap(find.byKey(const Key('restore.close')));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a failed restore keeps the import and lets the user go on', (
      tester,
    ) async {
      final container = await _pumpAccount(
        tester,
        reminderArmed: true,
        backedUp: false,
        onRecover: (_) async => const RecoveryOutcome.failed(),
      );

      await _submitImport(tester, l10n);
      expect(find.text(l10n.restoreFailedSubtitle), findsOneWidget);

      await tester.tap(find.byKey(const Key('restore.continue')));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
      expect(
        container.read(backupCompletedProvider),
        isTrue,
        reason: 'the words were imported, so they are backed up',
      );
    });

    testWidgets('Cancelar leaves the restore and the import stands', (
      tester,
    ) async {
      final never = Completer<RecoveryOutcome>();
      await _pumpAccount(
        tester,
        reminderArmed: false,
        backedUp: false,
        onRecover: (_) => never.future,
      );

      await tester.tap(find.bySemanticsIdentifier(AutomationIds.keysImport));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), _seed);
      await tester.tap(
        find.widgetWithText(FilledButton, l10n.importButtonLabel),
      );
      // The running stage spins, so the tree never settles.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text(l10n.restoreSheetTitle), findsOneWidget);

      await tester.tap(find.byKey(const Key('restore.cancel')));
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('privacy mode has nothing to restore', (tester) async {
      var recoveries = 0;
      await _pumpAccount(
        tester,
        reminderArmed: false,
        backedUp: false,
        privacyMode: true,
        onRecover: (_) async {
          recoveries++;
          return const RecoveryOutcome.recovered(0);
        },
      );

      await _submitImport(tester, l10n);

      expect(recoveries, 0);
      expect(find.text(l10n.restoreSheetTitle), findsNothing);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a privacy check that fails does not undo a refresh', (
      tester,
    ) async {
      await _pumpAccount(
        tester,
        reminderArmed: false,
        backedUp: true,
        privacyError: StateError('bridge busy'),
      );

      final refresh = find.byIcon(Icons.refresh_rounded);
      await tester.ensureVisible(refresh);
      await tester.pumpAndSettle();
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.refreshButtonLabel).last);
      await tester.pumpAndSettle();

      expect(find.text(l10n.orderBookRefreshedMessage), findsOneWidget);
      expect(find.text(l10n.refreshFailedMessage), findsNothing);
    });

    testWidgets('Actualizar runs the same restore', (tester) async {
      var recoveries = 0;
      await _pumpAccount(
        tester,
        reminderArmed: false,
        backedUp: true,
        onRecover: (_) async {
          recoveries++;
          return const RecoveryOutcome.recovered(0);
        },
      );

      final refresh = find.byIcon(Icons.refresh_rounded);
      await tester.ensureVisible(refresh);
      await tester.pumpAndSettle();
      await tester.tap(refresh);
      await tester.pumpAndSettle();
      // The dialog's confirm action carries the same label.
      await tester.tap(find.text(l10n.refreshButtonLabel).last);
      await tester.pumpAndSettle();

      expect(recoveries, 1);
      expect(find.text(l10n.restoreDoneTitle), findsOneWidget);
    });
  });

  group('importing a seed', () {
    testWidgets('clears the reminder armed by the walkthrough', (tester) async {
      final container = await _pumpAccount(
        tester,
        reminderArmed: true,
        backedUp: false,
      );

      await _import(tester, l10n);

      expect(container.read(backupReminderProvider), isFalse);
      expect(container.read(backupCompletedProvider), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kBackupReminderDismissedKey), isTrue);
      expect(prefs.getBool(kBackupCompletedKey), isTrue);
    });

    testWidgets('passes the typed words on and lands home', (tester) async {
      List<String>? imported;
      await _pumpAccount(
        tester,
        reminderArmed: true,
        backedUp: false,
        onImport: (words) async => imported = words,
      );

      await _import(tester, l10n);

      expect(imported, _seed.split(' '));
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('a failed import leaves the reminder alone', (tester) async {
      final container = await _pumpAccount(
        tester,
        reminderArmed: true,
        backedUp: false,
        onImport: (_) async => throw StateError('invalid mnemonic'),
      );

      await _import(tester, l10n);

      expect(container.read(backupReminderProvider), isTrue);
      expect(container.read(backupCompletedProvider), isFalse);
    });
  });

  // Issue #533: the next user must find the app as a fresh install leaves it.
  group('the previous identity\'s state', () {
    // The swap outlives the screen: on a real device the Account screen can
    // be gone by the time the bridge call returns, and the reset used to go
    // through its `ref` — "Cannot use ref after the widget was disposed",
    // logged and swallowed, and the old user stayed on screen until a
    // restart.
    testWidgets('is gone after a generation the screen did not outlive', (
      tester,
    ) async {
      final generated = Completer<void>();
      final container = await _pumpAccount(
        tester,
        reminderArmed: false,
        backedUp: true,
        onRegenerate: () => generated.future,
      );
      await _seedPreviousUser(container);
      await _generate(tester);

      _router.go(AppRoute.home);
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsNothing);
      generated.complete();
      await tester.pumpAndSettle();

      expect(container.read(notificationsProvider), isEmpty);
      expect(container.read(tradeRoleProvider), isEmpty);
      expect(container.read(chatReadStatusProvider), isEmpty);
      expect(container.read(backupReminderProvider), isTrue);
      expect(container.read(backupCompletedProvider), isFalse);
    });

    testWidgets('is gone after an import the screen did not outlive', (
      tester,
    ) async {
      final imported = Completer<void>();
      final container = await _pumpAccount(
        tester,
        reminderArmed: true,
        backedUp: false,
        onImport: (_) => imported.future,
      );
      await _seedPreviousUser(container);
      await _import(tester, l10n);

      _router.go(AppRoute.home);
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsNothing);
      imported.complete();
      await tester.pumpAndSettle();

      expect(container.read(notificationsProvider), isEmpty);
      expect(container.read(tradeRoleProvider), isEmpty);
      expect(container.read(chatReadStatusProvider), isEmpty);
      expect(container.read(backupReminderProvider), isFalse);
      expect(container.read(backupCompletedProvider), isTrue);
    });

    testWidgets('is gone after generating a new user', (tester) async {
      final container = await _pumpAccount(
        tester,
        reminderArmed: false,
        backedUp: true,
      );
      await _seedPreviousUser(container);

      await _generate(tester);

      expect(container.read(notificationsProvider), isEmpty);
      expect(container.read(tradeRoleProvider), isEmpty);
      expect(container.read(chatReadStatusProvider), isEmpty);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('is kept when the generation fails', (tester) async {
      final container = await _pumpAccount(
        tester,
        reminderArmed: false,
        backedUp: true,
        onRegenerate: () async => throw StateError('no entropy'),
      );
      await _seedPreviousUser(container);

      await _generate(tester);

      // Nothing was swapped, so nothing may be forgotten.
      expect(container.read(notificationsProvider), hasLength(1));
      expect(container.read(tradeRoleProvider), {'old': true});
    });

    testWidgets('is gone before an import recovers the new one\'s trades', (
      tester,
    ) async {
      var sawAtRecovery = -1;
      final container = await _pumpAccount(
        tester,
        reminderArmed: true,
        backedUp: false,
        onRecover: (container) async {
          sawAtRecovery = container.read(notificationsProvider).length;
          // What the recovery replay brings back is the imported identity's.
          await container
              .read(notificationsProvider.notifier)
              .add(_notice('recovered'));
          return const RecoveryOutcome.recovered(1);
        },
      );
      await _seedPreviousUser(container);

      await _import(tester, l10n);

      expect(sawAtRecovery, 0, reason: 'the wipe must run before recovery');
      final left = container.read(notificationsProvider);
      expect(left, hasLength(1), reason: 'recovered notices must survive');
      expect(container.read(tradeRoleProvider), isEmpty);
    });
  });

  // Issue #533: replacing an identity with sats in play must be warned about
  // before anything is written.
  group('with funds at risk', () {
    final risks = [
      FundsAtRisk(
        orderId: '308e1272-d5f4-47e6-bd97-3504baea9c23',
        reason: FundsAtRiskReason.sellerEscrowLocked,
        amountSats: BigInt.from(50000),
      ),
      const FundsAtRisk(
        orderId: '408e1272-d5f4-47e6-bd97-3504baea9c24',
        reason: FundsAtRiskReason.tradeInProgress,
      ),
    ];

    testWidgets('generate warns first, naming what is in play', (tester) async {
      var generated = false;
      await _pumpAccount(
        tester,
        reminderArmed: false,
        backedUp: true,
        fundsAtRisk: () async => risks,
        onRegenerate: () async => generated = true,
      );

      await _tapGenerate(tester);

      expect(find.text(l10n.fundsAtRiskTitle), findsOneWidget);
      expect(find.text(l10n.fundsAtRiskSellerEscrow), findsOneWidget);
      expect(find.text(l10n.fundsAtRiskTradeInProgress), findsOneWidget);
      expect(find.text(l10n.satsAmount('50,000')), findsOneWidget);
      // The usual confirmation has not opened, and nothing was written.
      expect(
        find.bySemanticsIdentifier(AutomationIds.keysGenerateConfirm),
        findsNothing,
      );
      expect(generated, isFalse);
    });

    testWidgets('keeping the user abandons the generation', (tester) async {
      var generated = false;
      final container = await _pumpAccount(
        tester,
        reminderArmed: false,
        backedUp: true,
        fundsAtRisk: () async => risks,
        onRegenerate: () async => generated = true,
      );
      await _seedPreviousUser(container);

      await _tapGenerate(tester);
      await tester.tap(
        find.bySemanticsIdentifier(AutomationIds.keysFundsAtRiskKeep),
      );
      await tester.pumpAndSettle();

      expect(generated, isFalse);
      expect(
        find.bySemanticsIdentifier(AutomationIds.keysGenerateConfirm),
        findsNothing,
      );
      expect(container.read(notificationsProvider), hasLength(1));
    });

    testWidgets('continuing anyway goes on to the usual confirmation', (
      tester,
    ) async {
      var generated = false;
      await _pumpAccount(
        tester,
        reminderArmed: false,
        backedUp: true,
        fundsAtRisk: () async => risks,
        onRegenerate: () async => generated = true,
      );

      await _tapGenerate(tester);
      await tester.tap(
        find.bySemanticsIdentifier(AutomationIds.keysFundsAtRiskContinue),
      );
      await tester.pumpAndSettle();
      // Still one more explicit step before the identity is replaced.
      expect(generated, isFalse);
      await tester.tap(
        find.bySemanticsIdentifier(AutomationIds.keysGenerateConfirm),
      );
      await tester.pumpAndSettle();

      expect(generated, isTrue);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('import warns before the seed dialog opens', (tester) async {
      await _pumpAccount(
        tester,
        reminderArmed: true,
        backedUp: false,
        fundsAtRisk: () async => risks,
      );

      await tester.tap(find.bySemanticsIdentifier(AutomationIds.keysImport));
      await tester.pumpAndSettle();

      expect(find.text(l10n.fundsAtRiskTitle), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(
        find.bySemanticsIdentifier(AutomationIds.keysFundsAtRiskContinue),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a check that fails does not lock the user out', (
      tester,
    ) async {
      var generated = false;
      await _pumpAccount(
        tester,
        reminderArmed: false,
        backedUp: true,
        fundsAtRisk: () async => throw StateError('db closed'),
        onRegenerate: () async => generated = true,
      );

      await _generate(tester);

      expect(find.text(l10n.fundsAtRiskTitle), findsNothing);
      expect(generated, isTrue);
    });
  });

  group('generating a new identity', () {
    testWidgets('still arms the reminder and clears the backed-up flag', (
      tester,
    ) async {
      final container = await _pumpAccount(
        tester,
        reminderArmed: false,
        backedUp: true,
      );

      await _generate(tester);

      expect(container.read(backupReminderProvider), isTrue);
      expect(container.read(backupCompletedProvider), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kBackupReminderActiveKey), isTrue);
      expect(prefs.getBool(kBackupReminderDismissedKey), isFalse);
      expect(prefs.getBool(kBackupCompletedKey), isFalse);
    });
  });
}
