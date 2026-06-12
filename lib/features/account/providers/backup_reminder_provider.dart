import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const kBackupReminderDismissedKey = 'backupReminderDismissed';
const kBackupReminderActiveKey = 'backupReminderActive';

/// Set to `true` once the user completes the backup ritual (or the legacy
/// "I have written down my secret words" checkbox).
const kBackupCompletedKey = 'backupCompleted';

/// Epoch millis until which the backup reminder is snoozed
/// ("Remind me tomorrow" in the backup trigger sheet).
const kBackupSnoozedUntilKey = 'backupSnoozedUntilMillis';

/// Tracks whether the backup reminder (red dot on notification bell) is active.
///
/// Active = user has not yet confirmed their secret words are backed up and
/// the reminder is not currently snoozed.
/// Dismissed permanently after `confirmBackupComplete()` is called.
final backupReminderProvider =
    StateNotifierProvider<BackupReminderNotifier, bool>(
  (ref) => BackupReminderNotifier(),
);

/// Whether the user has ever completed a backup of the current identity.
///
/// Drives the "Backed up" badge on the Account screen. Reset when a new
/// identity is generated or imported.
final backupCompletedProvider =
    StateNotifierProvider<BackupCompletedNotifier, bool>(
  (ref) => BackupCompletedNotifier(),
);

class BackupReminderNotifier extends StateNotifier<bool> {
  /// When [initialValue] is provided the notifier starts with the correct
  /// state synchronously so the bell badge renders correctly on first frame.
  BackupReminderNotifier({bool? initialValue}) : super(initialValue ?? false) {
    if (initialValue == null) {
      load();
    } else {
      _loaded = true;
      // The synchronous boot value (main.dart) only knows active/dismissed.
      // Asynchronously clear the badge if a snooze is still in effect.
      if (initialValue) _reconcileSnooze();
    }
  }

  bool _loaded = false;

  static bool _isSnoozed(SharedPreferences prefs) {
    final until = prefs.getInt(kBackupSnoozedUntilKey) ?? 0;
    return until > DateTime.now().millisecondsSinceEpoch;
  }

  Future<void> _reconcileSnooze() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_isSnoozed(prefs)) state = false;
    } catch (_) {
      // Prefs unavailable (e.g. tests without a platform channel) — keep
      // the synchronous initial value.
    }
  }

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getBool(kBackupReminderDismissedKey) ?? false;
    final active = prefs.getBool(kBackupReminderActiveKey) ?? false;
    state = active && !dismissed && !_isSnoozed(prefs);
    _loaded = true;
  }

  /// Activate the backup reminder badge. Called after the walkthrough
  /// completes and whenever a new identity is generated or imported.
  ///
  /// Re-arms the reminder even if a previous identity's backup was confirmed:
  /// a fresh mnemonic is, by definition, not backed up yet.
  Future<void> showBackupReminder() async {
    // Ensure load() has finished before writing so a pending load() can't
    // overwrite the state we are about to set.
    await load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kBackupReminderActiveKey, true);
    await prefs.setBool(kBackupReminderDismissedKey, false);
    await prefs.setBool(kBackupCompletedKey, false);
    await prefs.remove(kBackupSnoozedUntilKey);
    state = true;
  }

  /// Snooze the reminder for ~24 hours ("Remind me tomorrow").
  ///
  /// The reminder stays active in storage and reappears once the snooze
  /// window has elapsed.
  Future<void> snoozeUntilTomorrow() async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    final until = DateTime.now().add(const Duration(days: 1));
    await prefs.setInt(kBackupSnoozedUntilKey, until.millisecondsSinceEpoch);
    state = false;
  }

  /// Permanently dismiss the reminder. Called when the user confirms their
  /// secret words are backed up (ritual verification or legacy checkbox).
  Future<void> confirmBackupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kBackupReminderDismissedKey, true);
    await prefs.setBool(kBackupCompletedKey, true);
    await prefs.remove(kBackupSnoozedUntilKey);
    state = false;
  }
}

class BackupCompletedNotifier extends StateNotifier<bool> {
  BackupCompletedNotifier({bool? initialValue}) : super(initialValue ?? false) {
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
    // Legacy installs only have the dismissed flag, which was set exclusively
    // by the explicit "I have written down my secret words" confirmation —
    // treat it as a completed backup.
    state = prefs.getBool(kBackupCompletedKey) ??
        prefs.getBool(kBackupReminderDismissedKey) ??
        false;
    _loaded = true;
  }

  /// Persist that the current identity has been backed up.
  Future<void> markCompleted() async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kBackupCompletedKey, true);
    state = true;
  }

  /// Clear the backed-up flag (new identity generated or imported).
  Future<void> reset() async {
    await load();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kBackupCompletedKey, false);
    state = false;
  }
}
