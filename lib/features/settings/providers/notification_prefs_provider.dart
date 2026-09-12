import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which trade events raise a push notification.
///
/// Lifted out of the notification screen's local state because 10a shows the
/// tally (`Notificaciones push → 3 de 4`) on the settings list, so the same
/// preferences have to be readable from two places. The keys are the ones
/// `push_notification_service.dart` gates on — changing one here without the
/// other silently stops (or starts) delivering a class of notification.
enum NotificationEvent {
  tradeUpdates('notify_trade_updates'),
  newMessages('notify_new_messages'),
  paymentAlerts('notify_payments'),
  disputeUpdates('notify_disputes');

  const NotificationEvent(this.prefsKey);

  final String prefsKey;
}

@immutable
class NotificationPrefs {
  const NotificationPrefs(this._enabled);

  /// Every event on, which is what the app did before this screen existed.
  const NotificationPrefs.allEnabled() : _enabled = const {};

  final Map<NotificationEvent, bool> _enabled;

  bool isEnabled(NotificationEvent event) => _enabled[event] ?? true;

  int get enabledCount => NotificationEvent.values.where(isEnabled).length;

  int get total => NotificationEvent.values.length;

  bool get allDisabled => enabledCount == 0;

  NotificationPrefs withEvent(NotificationEvent event, bool value) =>
      NotificationPrefs({..._enabled, event: value});
}

class NotificationPrefsNotifier extends StateNotifier<NotificationPrefs> {
  NotificationPrefsNotifier({Future<SharedPreferences> Function()? prefs})
    : _prefs = prefs ?? SharedPreferences.getInstance,
      super(const NotificationPrefs.allEnabled()) {
    _load();
  }

  final Future<SharedPreferences> Function() _prefs;

  Future<void> _load() async {
    try {
      final prefs = await _prefs();
      if (!mounted) return;
      state = NotificationPrefs({
        for (final event in NotificationEvent.values)
          event: prefs.getBool(event.prefsKey) ?? true,
      });
    } catch (e) {
      debugPrint('[notification_prefs] load failed: $e');
    }
  }

  /// Applies the change to the UI first and persists after, so the toggle
  /// answers the tap; a failed write is reported by [setEvent] returning
  /// false and the state rolling back.
  Future<bool> setEvent(NotificationEvent event, bool value) async {
    final before = state;
    state = state.withEvent(event, value);
    try {
      final prefs = await _prefs();
      await prefs.setBool(event.prefsKey, value);
      return true;
    } catch (e) {
      debugPrint('[notification_prefs] save failed: $e');
      if (mounted) state = before;
      return false;
    }
  }
}

final notificationPrefsProvider =
    StateNotifierProvider<NotificationPrefsNotifier, NotificationPrefs>(
      (ref) => NotificationPrefsNotifier(),
    );
