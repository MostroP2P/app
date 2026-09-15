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

    test('showBackupReminder(): arms the badge and clears prior state',
        () async {
      SharedPreferences.setMockInitialValues({
        kBackupReminderDismissedKey: true,
        kBackupCompletedKey: true,
        kBackupSnoozedUntilKey: _inFuture(const Duration(days: 1)),
      });

      var didReset = false;
      final notifier = BackupReminderNotifier(
        resetConfirmed: () async => didReset = true,
      );
      await notifier.showBackupReminder();

      expect(notifier.state, isTrue);
      // #141 review: re-arming the reminder clears the Rust backup-confirmed
      // flag, so the badge and the ritual banner can never contradict.
      expect(didReset, isTrue);
      final prefs = await _prefs();
      expect(prefs.getBool(kBackupReminderActiveKey), isTrue);
      expect(prefs.getBool(kBackupReminderDismissedKey), isFalse);
      // #141 review: reminder notifier no longer writes the backup-confirmed
      // flag; Rust owns it, so the seeded value is left untouched (not cleared).
      expect(prefs.getBool(kBackupCompletedKey), isTrue);
      expect(prefs.getInt(kBackupSnoozedUntilKey), isNull);
    });

    test('snoozeUntilTomorrow(): hides badge and persists a future snooze',
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
    });

    test('confirmBackupComplete(): permanently dismisses the reminder',
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
      // #141 review: the reminder notifier no longer writes the backup-confirmed
      // flag — Rust owns it (the screen calls markCompleted separately). Writing
      // it here would let the badge and the ritual banner disagree.
      expect(prefs.getBool(kBackupCompletedKey), isNull);
      expect(prefs.getInt(kBackupSnoozedUntilKey), isNull);
    });

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

  // BackupCompletedNotifier is backed by the Rust identity bridge on every
  // platform since #141 (web is durable via IndexedDB since #408). Tests inject
  // the three bridge calls so they run without a live Rust runtime.
  group('BackupCompletedNotifier (Rust bridge, #141)', () {
    test('load(): reads the confirmed flag from the bridge', () async {
      SharedPreferences.setMockInitialValues({'backupCompletedMigratedToRust': true});
      final notifier = BackupCompletedNotifier(
        getConfirmed: () async => true,
        setConfirmed: (_) async {},
        resetConfirmed: () async {},
      );
      await notifier.load();
      expect(notifier.state, isTrue);
    });

    test('load(): migrates a legacy SharedPreferences flag into Rust once',
        () async {
      SharedPreferences.setMockInitialValues({kBackupCompletedKey: true});
      var confirmed = false;
      final notifier = BackupCompletedNotifier(
        getConfirmed: () async => confirmed,
        setConfirmed: (v) async => confirmed = v,
        resetConfirmed: () async => confirmed = false,
      );
      await notifier.load();
      expect(confirmed, isTrue, reason: 'legacy flag copied into Rust');
      expect(notifier.state, isTrue);
      final prefs = await _prefs();
      expect(prefs.getBool('backupCompletedMigratedToRust'), isTrue, reason: 'marker set');
    });

    test('load(): legacy dismissed-only install migrates as confirmed',
        () async {
      SharedPreferences.setMockInitialValues({
        kBackupReminderDismissedKey: true,
      });
      var confirmed = false;
      final notifier = BackupCompletedNotifier(
        getConfirmed: () async => confirmed,
        setConfirmed: (v) async => confirmed = v,
        resetConfirmed: () async {},
      );
      await notifier.load();
      expect(confirmed, isTrue);
      expect(notifier.state, isTrue);
    });

    test('load(): concurrent calls run the migration write exactly once',
        () async {
      SharedPreferences.setMockInitialValues({kBackupCompletedKey: true});
      var setCount = 0;
      final notifier = BackupCompletedNotifier(
        getConfirmed: () async => true,
        setConfirmed: (_) async => setCount++,
        resetConfirmed: () async {},
      );
      await Future.wait([notifier.load(), notifier.load()]);
      expect(setCount, 1, reason: 'coalesced load migrates once');
    });

    test('markCompleted() writes true through the bridge', () async {
      SharedPreferences.setMockInitialValues({'backupCompletedMigratedToRust': true});
      bool? written;
      final notifier = BackupCompletedNotifier(
        getConfirmed: () async => false,
        setConfirmed: (v) async => written = v,
        resetConfirmed: () async {},
      );
      await notifier.markCompleted();
      expect(written, isTrue);
      expect(notifier.state, isTrue);
    });

    test('reset() clears the flag through the bridge', () async {
      SharedPreferences.setMockInitialValues({'backupCompletedMigratedToRust': true});
      var didReset = false;
      final notifier = BackupCompletedNotifier(
        getConfirmed: () async => true,
        setConfirmed: (_) async {},
        resetConfirmed: () async => didReset = true,
      );
      await notifier.reset();
      expect(didReset, isTrue);
      expect(notifier.state, isFalse);
    });
  });
}
