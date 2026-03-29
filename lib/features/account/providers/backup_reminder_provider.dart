import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kBackupReminderDismissed = 'backupReminderDismissed';

/// Tracks whether the backup reminder (red dot on notification bell) is active.
///
/// Active = user has not yet viewed and confirmed their secret words.
/// Dismissed permanently after `confirmBackupComplete()` is called.
final backupReminderProvider =
    StateNotifierProvider<BackupReminderNotifier, bool>(
  (ref) => BackupReminderNotifier()..load(),
);

class BackupReminderNotifier extends StateNotifier<bool> {
  BackupReminderNotifier() : super(false);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(_kBackupReminderDismissed) ?? false;
    // Active when a reminder was set but not yet dismissed.
    final active = prefs.getBool('backupReminderActive') ?? false;
    state = active && !dismissed;
  }

  /// Activate the backup reminder badge. Called after walkthrough completes.
  Future<void> showBackupReminder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('backupReminderActive', true);
    final dismissed = prefs.getBool(_kBackupReminderDismissed) ?? false;
    if (!dismissed) state = true;
  }

  /// Permanently dismiss the reminder. Called when user views their secret words.
  Future<void> confirmBackupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBackupReminderDismissed, true);
    state = false;
  }
}
