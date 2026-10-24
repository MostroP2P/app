import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/announcements.dart' as announcements_api;

/// The Announcements toggle (specs/006-announcement-channel §7).
///
/// Unlike its four neighbours, which are `shared_preferences` keys, this one
/// lives in the Rust settings table: the value decides whether Rust opens a
/// relay subscription, and the authority for that is on the side that opens
/// it. Off means the subscription is closed at the tap, not that arriving
/// notices are hidden.

/// The Rust side of the toggle. Injected so screen tests never reach the
/// bridge.
class AnnouncementsBridge {
  const AnnouncementsBridge();

  Future<bool> enabled() => announcements_api.getAnnouncementsEnabled();

  Future<void> setEnabled(bool enabled) =>
      announcements_api.setAnnouncementsEnabled(enabled: enabled);
}

final announcementsBridgeProvider = Provider<AnnouncementsBridge>(
  (ref) => const AnnouncementsBridge(),
);

class AnnouncementsEnabledNotifier extends StateNotifier<bool> {
  AnnouncementsEnabledNotifier({required AnnouncementsBridge bridge})
    : _bridge = bridge,
      // On until Rust says otherwise: the persisted default (§7).
      super(true) {
    _load();
  }

  final AnnouncementsBridge _bridge;

  /// Taps so far. A load that answers after one read the setting before its
  /// write, so its value is older than the screen's; a failed write reloads
  /// only when no newer tap has replaced it.
  int _taps = 0;

  /// Writes go one after another: two quick taps otherwise race to the
  /// store, and the older one can land last.
  Future<void> _writes = Future.value();

  Future<void> _load() async {
    try {
      final enabled = await _bridge.enabled();
      if (mounted && _taps == 0) state = enabled;
    } catch (e) {
      debugPrint('[announcements] reading the toggle failed: $e');
    }
  }

  /// Applies the change to the UI first and persists after, so the toggle
  /// answers the tap; a failed write is reported by returning false and the
  /// toggle going back to what Rust holds.
  Future<bool> set(bool value) {
    final tap = ++_taps;
    final before = state;
    state = value;
    final write = _writes.then((_) => _write(value, tap, before));
    _writes = write.then((_) {});
    return write;
  }

  Future<bool> _write(bool value, int tap, bool before) async {
    try {
      await _bridge.setEnabled(value);
      return true;
    } catch (e) {
      debugPrint('[announcements] saving the toggle failed: $e');
      if (mounted && tap == _taps) await _reload(tap, before);
      return false;
    }
  }

  /// After a refused write the screen shows a value Rust never took. What it
  /// showed before the tap may be stale too — the load can still be in
  /// flight — so Rust is asked again; a tap that lands meanwhile wins.
  Future<void> _reload(int tap, bool before) async {
    bool enabled;
    try {
      enabled = await _bridge.enabled();
    } catch (e) {
      debugPrint('[announcements] re-reading the toggle failed: $e');
      enabled = before;
    }
    if (mounted && tap == _taps) state = enabled;
  }
}

final announcementsEnabledProvider =
    StateNotifierProvider<AnnouncementsEnabledNotifier, bool>(
      (ref) => AnnouncementsEnabledNotifier(
        bridge: ref.watch(announcementsBridgeProvider),
      ),
    );
