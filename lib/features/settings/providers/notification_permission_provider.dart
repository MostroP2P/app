import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:mostro/features/notifications/services/push_notification_service.dart';

/// Whether the OS is refusing this app's notifications.
///
/// Read once per visit to 10d and re-read whenever the app resumes — the
/// user coming back from the system settings, the only place the answer can
/// change. `openAppSettings()` returns as soon as that page opens, not when
/// the user returns, so re-reading after the call would read the old answer.
final notificationPermissionDeniedProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final listener = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(listener.dispose);
  final service = PushNotificationService.instance;
  final denied = await service.isSystemPermissionDenied();
  // Granted meanwhile: push init stopped at the denial, so it runs again now
  // instead of after an app restart.
  if (!denied) unawaited(service.retryInitialize());
  return denied;
});

/// Whether the browser has not been asked for the notification permission
/// yet. Its prompt only shows from a tap, so 10d offers one; until then no
/// push can arrive. False wherever the prompt needs no gesture.
final notificationPermissionUnaskedProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final listener = AppLifecycleListener(onResume: ref.invalidateSelf);
  ref.onDispose(listener.dispose);
  return PushNotificationService.instance.awaitsPermissionFromGesture();
});

/// Asks for the notification permission. Call it straight from the tap's
/// handler, before anything is awaited: the browser shows the prompt only
/// while the tap's user activation lasts. Both answers are read again after.
final requestNotificationPermissionProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    await PushNotificationService.instance.requestPermissionFromGesture();
    ref.invalidate(notificationPermissionUnaskedProvider);
    ref.invalidate(notificationPermissionDeniedProvider);
  },
);

/// Opens the OS settings page for this app, so the denied banner has
/// somewhere to send the user.
final openSystemSettingsProvider = Provider<Future<void> Function()>(
  (ref) => () async {
    try {
      await openAppSettings();
    } catch (e) {
      debugPrint('[notification_permission] openAppSettings failed: $e');
    }
  },
);
