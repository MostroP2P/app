import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Re-export so walkthrough_screen.dart can import backupReminderProvider
// from this file without a second import.
export 'package:mostro/features/account/providers/backup_reminder_provider.dart';

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
  /// Callers should separately activate the backup reminder:
  ///   `ref.read(backupReminderProvider.notifier).showBackupReminder()`
  Future<void> markFirstRunComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFirstRunComplete, true);
    state = const AsyncValue.data(true);
  }
}
