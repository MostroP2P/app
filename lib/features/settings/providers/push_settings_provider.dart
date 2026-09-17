import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/notifications/services/push_notification_service.dart';
import 'package:mostro/src/rust/api/push.dart' as push_api;
import 'package:mostro/src/rust/api/types.dart' show PushStatus;

/// 10d's master push toggle and the status line under it
/// (docs/PUSH_NOTIFICATIONS.md §7.4, §9.1).
///
/// Three facts, three sources, never conflated (§8.1): whether this platform
/// can push at all is Dart's ([pushSupportedProvider]); whether the OS lets
/// the app notify is `notificationPermissionDeniedProvider`; everything about
/// registration — the setting, the token Rust holds, what the server has — is
/// Rust's, read here through [pushStatusProvider].

/// The Rust side of the toggle. Injected so screen tests never reach the
/// bridge.
class PushBridge {
  const PushBridge();

  Future<PushStatus> status() => push_api.getPushStatus();

  Future<void> setEnabled(bool enabled) =>
      push_api.setPushEnabled(enabled: enabled);

  /// A reader for the next status. Subscribed before the first [status]
  /// read, so an update landing in between is not missed.
  Future<Future<PushStatus> Function()> watch() async {
    final stream = await push_api.onPushStatusChanged();
    return stream.next;
  }
}

/// The device side of the toggle: the FCM token.
abstract interface class PushDevice {
  /// Delete the device token and stop handing new ones to Rust.
  Future<void> release();

  /// Acquire a token again and hand it to Rust.
  Future<void> reacquire();
}

class _ServiceDevice implements PushDevice {
  const _ServiceDevice();

  @override
  Future<void> release() => PushNotificationService.instance.release();

  @override
  Future<void> reacquire() => PushNotificationService.instance.reacquire();
}

final pushBridgeProvider = Provider<PushBridge>((ref) => const PushBridge());

final pushDeviceProvider = Provider<PushDevice>(
  (ref) => const _ServiceDevice(),
);

/// Whether this platform can receive a push at all — checked before the
/// permission and the token, so a phone that has not handed a token over
/// yet shows the toggle, not unsupported copy.
final pushSupportedProvider = Provider<bool>(
  (ref) => PushNotificationService.instance.isSupported,
);

/// One reader for the process lifetime. A pending Rust `next()` cannot be
/// cancelled from Dart, so screen disposal or a toggle must not recreate it.
/// Rust emits the resulting status before each mutation returns.
final pushStatusProvider = StreamProvider<PushStatus>((ref) async* {
  final bridge = ref.watch(pushBridgeProvider);
  final next = await bridge.watch();
  yield await bridge.status();
  while (true) {
    yield await next();
  }
});

/// The active transaction's target, shared across visits to Settings.
final pushTogglePendingProvider = StateProvider<bool?>((ref) => null);

/// Turns push on or off end to end (§7.4).
///
/// Rust goes first both ways. Off persists the preference and attempts every
/// unregister before releasing the device token; failed removals remain in
/// the status for retry. On clears refusals before acquiring a fresh token.
class PushToggle {
  PushToggle({
    required PushBridge bridge,
    required PushDevice device,
    ValueChanged<bool?>? onPendingChanged,
  }) : _bridge = bridge,
       _device = device,
       _onPendingChanged = onPendingChanged;

  final PushBridge _bridge;
  final PushDevice _device;
  final ValueChanged<bool?>? _onPendingChanged;
  Future<void> _tail = Future.value();

  /// False when the setting could not be saved, and nothing changed. A
  /// device-side failure after that does not undo the persisted preference.
  /// Queue the entire transaction, including device I/O, across callers.
  Future<bool> set(bool enabled) {
    final result = _tail.then((_) => _set(enabled));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<bool> _set(bool enabled) async {
    _onPendingChanged?.call(enabled);
    try {
      return await _apply(enabled);
    } finally {
      _onPendingChanged?.call(null);
    }
  }

  Future<bool> _apply(bool enabled) async {
    try {
      await _bridge.setEnabled(enabled);
    } catch (e) {
      debugPrint('[push_settings] setEnabled($enabled) failed: $e');
      return false;
    }
    try {
      if (enabled) {
        await _device.reacquire();
      } else {
        await _device.release();
      }
    } catch (e) {
      debugPrint('[push_settings] device side of the toggle failed: $e');
    }
    return true;
  }
}

final pushToggleProvider = Provider<PushToggle>(
  (ref) => PushToggle(
    bridge: ref.watch(pushBridgeProvider),
    device: ref.watch(pushDeviceProvider),
    onPendingChanged:
        (value) => ref.read(pushTogglePendingProvider.notifier).state = value,
  ),
);
