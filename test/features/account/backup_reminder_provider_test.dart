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

      final notifier = BackupReminderNotifier();
      await notifier.showBackupReminder();

      expect(notifier.state, isTrue);
      final prefs = await _prefs();
      expect(prefs.getBool(kBackupReminderActiveKey), isTrue);
      expect(prefs.getBool(kBackupReminderDismissedKey), isFalse);
      expect(prefs.getBool(kBackupCompletedKey), isFalse);
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
      expect(prefs.getBool(kBackupCompletedKey), isTrue);
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

  group('BackupCompletedNotifier (backed by the Rust bridge, #141)', () {
    // A fake identity-bridge backing store so the notifier is exercised without
    // a live Rust runtime.
    BackupCompletedNotifier makeNotifier({required bool initial}) {
      var confirmed = initial;
      return BackupCompletedNotifier(
        getConfirmed: () async => confirmed,
        setConfirmed: (v) async => confirmed = v,
        resetConfirmed: () async => confirmed = false,
      );
    }

    test('load(): reads the confirmed flag from the bridge', () async {
      SharedPreferences.setMockInitialValues(
          {'backupCompletedMigratedToRust': true});

      final notifier = makeNotifier(initial: true);
      await notifier.load();

      expect(notifier.state, isTrue);
    });

    test('load(): migrates a legacy SharedPreferences flag into the bridge once',
        () async {
      // Legacy install: completed flag set, no migration marker. load() copies
      // it into the bridge, marks the migration done, then reads the bridge.
      SharedPreferences.setMockInitialValues({kBackupCompletedKey: true});

      var confirmed = false;
      final notifier = BackupCompletedNotifier(
        getConfirmed: () async => confirmed,
        setConfirmed: (v) async => confirmed = v,
        resetConfirmed: () async => confirmed = false,
      );
      await notifier.load();

      expect(confirmed, isTrue, reason: 'legacy flag copied into the bridge');
      expect(notifier.state, isTrue);
      final prefs = await _prefs();
      expect(prefs.getBool('backupCompletedMigratedToRust'), isTrue);
    });

    test('markCompleted() writes true through the bridge', () async {
      SharedPreferences.setMockInitialValues(
          {'backupCompletedMigratedToRust': true});

      // Track the fake bridge's backing value so we assert the write reached it,
      // not only that notifier.state flipped.
      var confirmed = false;
      final notifier = BackupCompletedNotifier(
        getConfirmed: () async => confirmed,
        setConfirmed: (v) async => confirmed = v,
        resetConfirmed: () async => confirmed = false,
      );
      await notifier.markCompleted();

      expect(confirmed, isTrue, reason: 'markCompleted must write to the bridge');
      expect(notifier.state, isTrue);
    });

    test('reset() clears the flag through the bridge', () async {
      SharedPreferences.setMockInitialValues(
          {'backupCompletedMigratedToRust': true});

      var confirmed = true;
      final notifier = BackupCompletedNotifier(
        getConfirmed: () async => confirmed,
        setConfirmed: (v) async => confirmed = v,
        resetConfirmed: () async => confirmed = false,
      );
      await notifier.reset();

      expect(confirmed, isFalse, reason: 'reset must clear the bridge value');
      expect(notifier.state, isFalse);
    });
  });
}
