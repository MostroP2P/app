import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kBackupReminderDismissedKey = 'backupReminderDismissed';
const kBackupReminderActiveKey = 'backupReminderActive';

/// Tracks whether the backup reminder (red dot on notification bell) is active.
///
/// Active = user has not yet viewed and confirmed their secret words.
/// Dismissed permanently after `confirmBackupComplete()` is called.
final backupReminderProvider =
    StateNotifierProvider<BackupReminderNotifier, bool>(
  (ref) => BackupReminderNotifier(),
);

class BackupReminderNotifier extends StateNotifier<bool> {
  /// When [initialValue] is provided the notifier starts with the correct
  /// state synchronously so the bell badge renders correctly on first frame.
  BackupReminderNotifier({bool? initialValue}) : super(initialValue ?? false) {
    if (initialValue == null) {
      load();
    } else {
      _loaded = true;
    }
  }

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(kBackupReminderDismissedKey) ?? false;
    final active = prefs.getBool(kBackupReminderActiveKey) ?? false;
    state = active && !dismissed;
    _loaded = true;
  }

  /// Activate the backup reminder badge. Called after walkthrough completes.
  Future<void> showBackupReminder() async {
    // Ensure load() has finished before reading the dismissed flag to avoid
    // a race where load() overwrites the state we are about to set.
    await load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kBackupReminderActiveKey, true);
    final dismissed = prefs.getBool(kBackupReminderDismissedKey) ?? false;
    if (!dismissed) state = true;
  }

  /// Permanently dismiss the reminder. Called when user views their secret words.
  Future<void> confirmBackupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kBackupReminderDismissedKey, true);
    state = false;
  }
}
