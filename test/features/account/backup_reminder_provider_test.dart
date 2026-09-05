import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

int _inFuture(Duration d) => DateTime.now().add(d).millisecondsSinceEpoch;
int _inPast(Duration d) => DateTime.now().subtract(d).millisecondsSinceEpoch;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BackupReminderNotifier', () {
    test('load(): active and not dismissed nor snoozed → badge on', () async {
      SharedPreferences.setMockInitialValues({
        kBackupReminderActiveKey: true,
        kBackupReminderDismissedKey: false,
      });

      final notifier = BackupReminderNotifier();
      await notifier.load();

      expect(notifier.state, isTrue);
    });

    test('load(): dismissed suppresses the badge even when active', () async {
      SharedPreferences.setMockInitialValues({
        kBackupReminderActiveKey: true,
        kBackupReminderDismissedKey: true,
      });

      final notifier = BackupReminderNotifier();
      await notifier.load();

      expect(notifier.state, isFalse);
    });

    test('load(): an unexpired snooze suppresses the badge', () async {
      SharedPreferences.setMockInitialValues({
        kBackupReminderActiveKey: true,
        kBackupReminderDismissedKey: false,
        kBackupSnoozedUntilKey: _inFuture(const Duration(hours: 12)),
      });

      final notifier = BackupReminderNotifier();
      await notifier.load();

      expect(notifier.state, isFalse);
    });

    test('load(): an expired snooze does not suppress the badge', () async {
      SharedPreferences.setMockInitialValues({
        kBackupReminderActiveKey: true,
        kBackupReminderDismissedKey: false,
        kBackupSnoozedUntilKey: _inPast(const Duration(hours: 1)),
      });

      final notifier = BackupReminderNotifier();
      await notifier.load();

      expect(notifier.state, isTrue);
    });

    test(
      'showBackupReminder(): arms the badge and clears prior state',
      () async {
        SharedPreferences.setMockInitialValues({
          kBackupReminderDismissedKey: true,
          kBackupCompletedKey: true,
          kBackupSnoozedUntilKey: _inFuture(const Duration(days: 1)),
        });

        final notifier = BackupReminderNotifier();
        await notifier.showBackupReminder();

        expect(notifier.state, isTrue);
        final prefs = await _prefs();
        expect(prefs.getBool(kBackupReminderActiveKey), isTrue);
        expect(prefs.getBool(kBackupReminderDismissedKey), isFalse);
        expect(prefs.getBool(kBackupCompletedKey), isFalse);
        expect(prefs.getInt(kBackupSnoozedUntilKey), isNull);
      },
    );

    test(
      'snoozeUntilTomorrow(): hides badge and persists a future snooze',
      () async {
        SharedPreferences.setMockInitialValues({
          kBackupReminderActiveKey: true,
          kBackupReminderDismissedKey: false,
        });

        final notifier = BackupReminderNotifier();
        await notifier.snoozeUntilTomorrow();

        expect(notifier.state, isFalse);
        final prefs = await _prefs();
        final until = prefs.getInt(kBackupSnoozedUntilKey);
        expect(until, isNotNull);
        expect(until, greaterThan(DateTime.now().millisecondsSinceEpoch));
      },
    );

    test(
      'confirmBackupComplete(): permanently dismisses the reminder',
      () async {
        SharedPreferences.setMockInitialValues({
          kBackupReminderActiveKey: true,
          kBackupReminderDismissedKey: false,
          kBackupSnoozedUntilKey: _inFuture(const Duration(days: 1)),
        });

        final notifier = BackupReminderNotifier();
        await notifier.confirmBackupComplete();

        expect(notifier.state, isFalse);
        final prefs = await _prefs();
        expect(prefs.getBool(kBackupReminderDismissedKey), isTrue);
        expect(prefs.getBool(kBackupCompletedKey), isTrue);
        expect(prefs.getInt(kBackupSnoozedUntilKey), isNull);
      },
    );

    test('initialValue with a live snooze is reconciled to off', () async {
      SharedPreferences.setMockInitialValues({
        kBackupSnoozedUntilKey: _inFuture(const Duration(hours: 6)),
      });

      final notifier = BackupReminderNotifier(initialValue: true);
      // Constructor kicks off an async snooze reconciliation.
      await pumpEventQueue();

      expect(notifier.state, isFalse);
    });
  });

  group('BackupCompletedNotifier (backed by the Rust bridge, #141)', () {
    // A fake identity-bridge backing store so the notifier is exercised without
    // a live Rust runtime.
    BackupCompletedNotifier makeNotifier({required bool initial}) {
      var confirmed = initial;
      return BackupCompletedNotifier(
        getConfirmed: () async => confirmed,
        setConfirmed: (v) async => confirmed = v,
        resetConfirmed: () async => confirmed = false,
        isWebOverride: false,
      );
    }

    test('load(): reads the confirmed flag from the bridge', () async {
      SharedPreferences.setMockInitialValues({
        'backupCompletedMigratedToRust': true,
      });

      final notifier = makeNotifier(initial: true);
      await notifier.load();

      expect(notifier.state, isTrue);
    });

    test(
      'load(): migrates a legacy SharedPreferences flag into the bridge once',
      () async {
        // Legacy install: completed flag set, no migration marker. load() copies
        // it into the bridge, marks the migration done, then reads the bridge.
        SharedPreferences.setMockInitialValues({kBackupCompletedKey: true});

        var confirmed = false;
        final notifier = BackupCompletedNotifier(
          getConfirmed: () async => confirmed,
          setConfirmed: (v) async => confirmed = v,
          resetConfirmed: () async => confirmed = false,
          isWebOverride: false,
        );
        await notifier.load();

        expect(confirmed, isTrue, reason: 'legacy flag copied into the bridge');
        expect(notifier.state, isTrue);
        final prefs = await _prefs();
        expect(prefs.getBool('backupCompletedMigratedToRust'), isTrue);
      },
    );

    test(
      'load(): concurrent calls run the migration write exactly once',
      () async {
        // The constructor fires load() un-awaited; a caller may await load()
        // before it finishes. Both must share one in-flight future so the
        // one-time migration calls the bridge exactly once. (#141 review)
        SharedPreferences.setMockInitialValues({kBackupCompletedKey: true});
        var setCount = 0;
        final notifier = BackupCompletedNotifier(
          getConfirmed: () async => setCount > 0,
          setConfirmed: (v) async => setCount++,
          resetConfirmed: () async {},
          isWebOverride: false,
        );
        // Two overlapping loads (plus the un-awaited one from the constructor).
        await Future.wait([notifier.load(), notifier.load()]);
        expect(
          setCount,
          1,
          reason: 'migration must write through the bridge exactly once',
        );
        expect(notifier.state, isTrue);
      },
    );

    test('markCompleted() writes true through the bridge', () async {
      SharedPreferences.setMockInitialValues({
        'backupCompletedMigratedToRust': true,
      });

      // Track the fake bridge's backing value so we assert the write reached it,
      // not only that notifier.state flipped.
      var confirmed = false;
      final notifier = BackupCompletedNotifier(
        getConfirmed: () async => confirmed,
        setConfirmed: (v) async => confirmed = v,
        resetConfirmed: () async => confirmed = false,
        isWebOverride: false,
      );
      await notifier.markCompleted();

      expect(
        confirmed,
        isTrue,
        reason: 'markCompleted must write to the bridge',
      );
      expect(notifier.state, isTrue);
    });

    test('reset() clears the flag through the bridge', () async {
      SharedPreferences.setMockInitialValues({
        'backupCompletedMigratedToRust': true,
      });

      var confirmed = true;
      final notifier = BackupCompletedNotifier(
        getConfirmed: () async => confirmed,
        setConfirmed: (v) async => confirmed = v,
        resetConfirmed: () async => confirmed = false,
        isWebOverride: false,
      );
      await notifier.reset();

      expect(confirmed, isFalse, reason: 'reset must clear the bridge value');
      expect(notifier.state, isFalse);
    });
  });

  group('BackupCompletedNotifier — web (SharedPreferences authoritative, #233)', () {
    // On web the Rust identity store is a stub (#233), so SharedPreferences
    // (localStorage) is the durable source for the backup-confirmed flag.
    // These force the web path via isWebOverride and assert the flag round-trips
    // through SharedPreferences across a simulated reload. (#141 review)
    test(
      'web: markCompleted persists to SharedPreferences and survives reload',
      () async {
        SharedPreferences.setMockInitialValues({});
        final n1 = BackupCompletedNotifier(isWebOverride: true);
        await n1.load();
        expect(
          n1.state,
          isFalse,
          reason: 'fresh web install starts unconfirmed',
        );
        await n1.markCompleted();
        expect(n1.state, isTrue);
        final prefs = await _prefs();
        expect(
          prefs.getBool(kBackupCompletedKey),
          isTrue,
          reason: 'web write must reach SharedPreferences',
        );
        // Simulate a page reload: a brand-new notifier reads the durable value.
        final n2 = BackupCompletedNotifier(isWebOverride: true);
        await n2.load();
        expect(
          n2.state,
          isTrue,
          reason: 'a confirmed backup must survive a web reload',
        );
      },
    );

    test('web: reset clears the SharedPreferences flag', () async {
      SharedPreferences.setMockInitialValues({kBackupCompletedKey: true});
      final n = BackupCompletedNotifier(isWebOverride: true);
      await n.load();
      expect(n.state, isTrue);
      await n.reset();
      expect(n.state, isFalse);
      final prefs = await _prefs();
      expect(
        prefs.getBool(kBackupCompletedKey),
        isFalse,
        reason: 'web reset must clear the durable flag',
      );
    });

    test('web: load does not run the native migration', () async {
      // A legacy completed flag with no migration marker: on web we must NOT
      // consume it via migration; SharedPreferences stays authoritative and the
      // migration marker is never written.
      SharedPreferences.setMockInitialValues({kBackupCompletedKey: true});
      final n = BackupCompletedNotifier(isWebOverride: true);
      await n.load();
      expect(n.state, isTrue, reason: 'web reads the flag directly');
      final prefs = await _prefs();
      expect(
        prefs.getBool('backupCompletedMigratedToRust'),
        isNull,
        reason: 'web must not set the migration marker',
      );
    });
    test(
      'web: read falls back to the legacy dismissed flag (#141 B2)',
      () async {
        // A web install that confirmed before kBackupCompletedKey existed has
        // only kBackupReminderDismissedKey set. The web read must honor it, not
        // flip the user to unconfirmed — the regression this fixes.
        SharedPreferences.setMockInitialValues({
          kBackupReminderDismissedKey: true,
          // kBackupCompletedKey deliberately absent.
        });
        final n = BackupCompletedNotifier(isWebOverride: true);
        await n.load();
        expect(
          n.state,
          isTrue,
          reason: 'a legacy confirmed web install must not be flipped to false',
        );
      },
    );
  });
}
