import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mostro/src/rust/api/identity.dart' as identity_api;

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
  BackupReminderNotifier({
    bool? initialValue,
    Future<void> Function()? resetConfirmed,
  })  : _resetConfirmed = resetConfirmed ?? identity_api.resetBackupConfirmation,
        super(initialValue ?? false) {
    if (initialValue == null) {
      load();
    } else {
      _loaded = true;
      // The synchronous boot value (main.dart) only knows active/dismissed.
      // Asynchronously clear the badge if a snooze is still in effect.
      if (initialValue) _reconcileSnooze();
    }
  }

  /// Clears the Rust backup-confirmed flag, injected for testability.
  final Future<void> Function() _resetConfirmed;

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
    await prefs.remove(kBackupSnoozedUntilKey);
    // Re-arming the reminder means the user is NOT backed up, so clear the Rust
    // flag too: the "Backed up" badge reads Rust, and without this a caller that
    // re-arms the reminder without a paired reset (e.g. the walkthrough) would
    // show the badge and the ritual banner at once (Catrya's #141 review). Rust
    // owns the flag now; this notifier no longer writes the dead kBackupCompletedKey.
    await _resetConfirmed();
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
    // The backup-confirmed flag is written to Rust by markCompleted() at the
    // call site; this notifier only dismisses the reminder (Rust owns the flag
    // since #141).
    await prefs.remove(kBackupSnoozedUntilKey);
    state = false;
  }
}

/// One-time marker: the legacy SharedPreferences backup-completed flag has been
/// copied into the Rust identity record. After this, Rust is the single source
/// of truth on every platform (#141; web is durable via IndexedDB since #408).
const _kMigratedKey = 'backupCompletedMigratedToRust';

class BackupCompletedNotifier extends StateNotifier<bool> {
  /// The three bridge calls are injectable so the notifier is testable without a
  /// live Rust runtime; they default to the real identity-bridge functions.
  BackupCompletedNotifier({
    bool? initialValue,
    Future<bool> Function()? getConfirmed,
    Future<void> Function(bool confirmed)? setConfirmed,
    Future<void> Function()? resetConfirmed,
  })  : _getConfirmed = getConfirmed ?? identity_api.getBackupConfirmed,
        _setConfirmed = setConfirmed ??
            ((confirmed) => identity_api.setBackupConfirmed(confirmed: confirmed)),
        _resetConfirmed = resetConfirmed ?? identity_api.resetBackupConfirmation,
        super(initialValue ?? false) {
    if (initialValue == null) {
      load();
    } else {
      _loaded = true;
    }
  }

  final Future<bool> Function() _getConfirmed;
  final Future<void> Function(bool confirmed) _setConfirmed;
  final Future<void> Function() _resetConfirmed;

  bool _loaded = false;
  Future<void>? _loading;

  /// Coalesced: overlapping callers share one in-flight load so the one-time
  /// migration runs its write exactly once.
  Future<void> load() => _loading ??= _load().whenComplete(() => _loading = null);

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      // One-time migration: copy the legacy SharedPreferences flag into Rust,
      // then read from Rust exclusively. Runs on every platform — the store is
      // durable everywhere since #408, so the marker is never burned against a
      // write that evaporates.
      if (prefs.getBool(_kMigratedKey) != true) {
        // Legacy installs may only have the dismissed flag, set exclusively by
        // the explicit "I wrote down my words" confirmation — treat it as done.
        final legacy = prefs.getBool(kBackupCompletedKey) ??
            prefs.getBool(kBackupReminderDismissedKey) ??
            false;
        if (legacy) {
          await _setConfirmed(true);
        }
        await prefs.setBool(_kMigratedKey, true);
      }
      state = await _getConfirmed();
      _loaded = true;
    } catch (e) {
      // The bridge threw (e.g. not yet initialised): fall back to unconfirmed so
      // the reminder stays armed, and leave _loaded false so the next load()
      // retries. (get_backup_confirmed returns Ok(false) rather than throwing
      // when no identity is loaded, so that case does not reach here — #141 review.)
      debugPrint('[backup] load() failed: $e');
      state = false;
    }
  }

  /// Persist that the current identity has been backed up (authoritative Rust
  /// write). Throws on failure so the caller can keep the reminder armed.
  Future<void> markCompleted() async {
    await load();
    await _setConfirmed(true);
    state = true;
  }

  /// Clear the backed-up flag (new identity generated or imported).
  Future<void> reset() async {
    await load();
    await _resetConfirmed();
    state = false;
  }
}
