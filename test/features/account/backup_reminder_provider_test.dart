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

  group('BackupCompletedNotifier', () {
    test('load(): reads the explicit completed flag', () async {
      SharedPreferences.setMockInitialValues({kBackupCompletedKey: true});

      final notifier = BackupCompletedNotifier();
      await notifier.load();

      expect(notifier.state, isTrue);
    });

    test('load(): legacy installs fall back to the dismissed flag', () async {
      SharedPreferences.setMockInitialValues({
        kBackupReminderDismissedKey: true,
      });

      final notifier = BackupCompletedNotifier();
      await notifier.load();

      expect(notifier.state, isTrue);
    });

    test('markCompleted() persists and flips state on', () async {
      SharedPreferences.setMockInitialValues({});

      final notifier = BackupCompletedNotifier();
      await notifier.markCompleted();

      expect(notifier.state, isTrue);
      final prefs = await _prefs();
      expect(prefs.getBool(kBackupCompletedKey), isTrue);
    });

    test('reset() clears the backed-up flag', () async {
      SharedPreferences.setMockInitialValues({kBackupCompletedKey: true});

      final notifier = BackupCompletedNotifier();
      await notifier.reset();

      expect(notifier.state, isFalse);
      final prefs = await _prefs();
      expect(prefs.getBool(kBackupCompletedKey), isFalse);
    });
  });
}
