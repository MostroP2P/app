import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the first-run flag.
const _kFirstRunComplete = 'firstRunComplete';

/// `true` once the user has completed (or skipped) the walkthrough.
///
/// Loaded asynchronously from SharedPreferences. Defaults to `false`
/// (first launch) when the key is absent.
final firstRunProvider =
    StateNotifierProvider<FirstRunNotifier, AsyncValue<bool>>(
  (ref) => FirstRunNotifier(),
);

class FirstRunNotifier extends StateNotifier<AsyncValue<bool>> {
  FirstRunNotifier() : super(const AsyncValue.loading()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = AsyncValue.data(prefs.getBool(_kFirstRunComplete) ?? false);
    } catch (e, st) {
      // Fail-safe: treat as completed so the user reaches the home screen.
      state = AsyncValue.error(e, st);
    }
  }

  /// Mark the walkthrough as completed. Called by both "Done" and "Skip".
  ///
  /// Also activates the backup reminder (red dot on notification bell).
  Future<void> markFirstRunComplete(WidgetRef ref) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFirstRunComplete, true);
    state = const AsyncValue.data(true);

    // Activate persistent backup reminder notification.
    ref.read(backupReminderProvider.notifier).showBackupReminder();
  }
}

// ── Backup reminder (stub — full implementation in Phase 4/US2) ──────────────

/// Tracks whether the backup reminder badge (red dot on bell) is active.
final backupReminderProvider =
    StateNotifierProvider<BackupReminderNotifier, bool>(
  (ref) => BackupReminderNotifier(),
);

class BackupReminderNotifier extends StateNotifier<bool> {
  BackupReminderNotifier() : super(false);

  /// Activate the persistent backup reminder. Called after walkthrough ends.
  void showBackupReminder() => state = true;

  /// Dismiss the reminder permanently (called after user views backup words).
  void dismissBackupReminder() => state = false;
}
