import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:mostro/features/notifications/services/push_notification_service.dart';

/// Whether the OS is refusing this app's notifications.
///
/// Read once per visit to 10d and re-read when the user comes back from the
/// system settings, which is the only place the answer can change.
final notificationPermissionDeniedProvider = FutureProvider.autoDispose<bool>(
  (ref) => PushNotificationService.instance.isSystemPermissionDenied(),
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
