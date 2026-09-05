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
  /// The three bridge calls are injectable so the notifier is testable without
  /// a live Rust runtime; they default to the real identity-bridge functions
  /// (issue #141).
  BackupCompletedNotifier({
    bool? initialValue,
    Future<bool> Function()? getConfirmed,
    Future<void> Function(bool confirmed)? setConfirmed,
    Future<void> Function()? resetConfirmed,
    // Test seam: force the web (SharedPreferences-authoritative) path off-web.
    // Defaults to the real platform flag.
    bool? isWebOverride,
  }) : _getConfirmed = getConfirmed ?? identity_api.getBackupConfirmed,
       _setConfirmed =
           setConfirmed ??
           ((confirmed) =>
               identity_api.setBackupConfirmed(confirmed: confirmed)),
       _resetConfirmed = resetConfirmed ?? identity_api.resetBackupConfirmation,
       _isWeb = isWebOverride ?? kIsWeb,
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
  final bool _isWeb;

  // Web has no durable Rust identity store until #233, but SharedPreferences
  // (backed by localStorage) IS durable there. So on web the backup-confirmed
  // flag is read/written/cleared directly in kBackupCompletedKey, and the Rust
  // bridge is used only on native. This keeps a confirmed backup surviving a
  // page reload on web, instead of resetting to the session-only Rust default.
  // (#141 review — CodeRabbit)
  Future<bool> _readConfirmed() async {
    if (_isWeb) {
      final prefs = await SharedPreferences.getInstance();
      // Legacy web installs (before kBackupCompletedKey existed) only have the
      // dismissed flag; fall back to it so a user who confirmed pre-migration
      // isn't flipped to unconfirmed (#141 review). Matches main's non-web read
      // this PR otherwise replaced.
      return prefs.getBool(kBackupCompletedKey) ??
          prefs.getBool(kBackupReminderDismissedKey) ??
          false;
    }
    return _getConfirmed();
  }

  Future<void> _writeConfirmed(bool confirmed) async {
    if (_isWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kBackupCompletedKey, confirmed);
      return;
    }
    await _setConfirmed(confirmed);
  }

  Future<void> _clearConfirmed() async {
    if (_isWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kBackupCompletedKey, false);
      return;
    }
    await _resetConfirmed();
  }

  bool _loaded = false;

  /// Marks that the one-time SharedPreferences -> Rust migration has run, so
  /// the legacy key is only ever read once (issue #141).
  static const _kMigratedKey = 'backupCompletedMigratedToRust';

  // Coalesce concurrent load()s: the constructor fires load() un-awaited, and a
  // caller (or test) may await load() before it finishes. Without sharing the
  // in-flight future, both could pass the _loaded check, run the one-time
  // migration, and call _setConfirmed twice. Cleared on completion so a failed
  // load (which leaves _loaded false) can be retried. (#141 review — CodeRabbit)
  Future<void>? _loading;

  Future<void> load() {
    if (_loaded) return Future.value();
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<void> _load() async {
    // The backup-confirmed flag now lives in the Rust identity record. On the
    // first run after upgrading, copy the legacy SharedPreferences value into
    // Rust once, then read from Rust exclusively.
    try {
      // #141 review: skip the migration entirely on web. There, initDb is
      // never called (main.dart guards it with !kIsWeb), so set_backup_confirmed
      // has no store and returns Ok WITHOUT persisting. Running the migration
      // would burn the durable _kMigratedKey (localStorage) against that
      // non-durable write, consuming the legacy SharedPreferences value and
      // re-arming the reminder on every reload. Until IndexedDB save_identity
      // lands (#233), the legacy SharedPreferences flag stays authoritative on
      // web, so we neither migrate nor mark it migrated.
      if (!_isWeb) {
        final prefs = await SharedPreferences.getInstance();
        final migrated = prefs.getBool(_kMigratedKey) ?? false;
        if (!migrated) {
          // Legacy installs only have the dismissed flag, which was set
          // exclusively by the explicit "I have written down my secret words"
          // confirmation — treat it as a completed backup.
          final legacy =
              prefs.getBool(kBackupCompletedKey) ??
              prefs.getBool(kBackupReminderDismissedKey) ??
              false;
          if (legacy) {
            // Best-effort: if no identity is loaded yet, the bridge throws and
            // we simply leave Rust at its default (false); the reminder stays
            // armed, which is safe. The marker is only set once the copy
            // sticks — and on native the write is always durable here.
            await _setConfirmed(true);
          }
          await prefs.setBool(_kMigratedKey, true);
        }
      }
      state = await _readConfirmed();
      // Only mark loaded once the read succeeded. If the bridge was not
      // ready (no identity yet), leaving _loaded false lets the next load()
      // retry instead of pinning the UI to `false` for the whole session.
      _loaded = true;
    } catch (e) {
      // Rust unavailable (e.g. no identity yet, or tests without the bridge):
      // fall back to unconfirmed so the reminder stays armed, and let a later
      // load() retry (we deliberately do NOT set _loaded here).
      debugPrint('[backup] load() failed, reminder stays armed: $e');
      state = false;
    }
  }

  /// Persist that the current identity has been backed up (Rust identity
  /// record, #141).
  Future<void> markCompleted() async {
    await load();
    await _writeConfirmed(true);
    state = true;
  }

  /// Clear the backed-up flag (new identity generated or imported). The Rust
  /// side is also reset in `create_identity`; this keeps the UI in sync (#141).
  Future<void> reset() async {
    await load();
    await _clearConfirmed();
    state = false;
  }
}
