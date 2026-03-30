import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Push notification service — platform-gated FCM (Android/iOS) + Web Push.
///
/// TODO(firebase): Add firebase_core + firebase_messaging to pubspec.yaml,
/// run `flutterfire configure`, then replace stubs with real FCM setup:
///   - `FirebaseMessaging.instance.requestPermission()`
///   - `FirebaseMessaging.onBackgroundMessage(_handler)`
///   - `FirebaseMessaging.onMessage.listen(_handleForeground)`
///   - `FirebaseMessaging.onMessageOpenedApp.listen(_handleTap)`
///
/// TODO(web-push): Register 'firebase-messaging-sw.js' service worker.
///
/// Desktop: Mostro relay connection is maintained by a background Isolate
/// (wired in Phase 18+).
class PushNotificationService {
  PushNotificationService._();

  static final instance = PushNotificationService._();

  /// Initialize the push notification service.
  ///
  /// No-op on platforms without FCM support (desktop, web before firebase setup).
  Future<void> initialize() async {
    if (kIsWeb) {
      // TODO(web-push): Initialize Web Push service worker.
      return;
    }
    if (!_isMobile) return;
    // TODO(firebase): FirebaseMessaging.instance.requestPermission()
    // TODO(firebase): FirebaseMessaging.onBackgroundMessage(_backgroundHandler)
    // TODO(firebase): FirebaseMessaging.onMessage.listen(_handleForeground)
    // TODO(firebase): FirebaseMessaging.onMessageOpenedApp.listen(_handleTap)
  }

  /// Extract the GoRouter destination from a push payload.
  ///
  /// Payload keys: `type` (string), `orderId` (string?), `disputeId` (string?)
  String? routeFromPayload(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;
    final orderId = payload['orderId'] as String?;
    final disputeId = payload['disputeId'] as String?;

    return switch (type) {
      'trade_updated' when orderId != null => '/trade_detail/$orderId',
      'invoice_request' when orderId != null => '/add_invoice/$orderId',
      'payment_received' when orderId != null => '/pay_invoice/$orderId',
      'rating_received' when orderId != null => '/rate_user/$orderId',
      'dispute_update' when disputeId != null => '/dispute_details/$disputeId',
      _ => null,
    };
  }

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

/// Widget that wires push-tap payloads to GoRouter.
///
/// Wrap around the app root or a high-level widget so the navigator context
/// is available. Platform-gated: no-op on desktop/web until Firebase is wired.
class NotificationListenerWidget extends StatefulWidget {
  const NotificationListenerWidget({super.key, required this.child});

  final Widget child;

  @override
  State<NotificationListenerWidget> createState() =>
      _NotificationListenerWidgetState();
}

class _NotificationListenerWidgetState
    extends State<NotificationListenerWidget> {
  @override
  void initState() {
    super.initState();
    // TODO(firebase): Subscribe to FirebaseMessaging.onMessageOpenedApp here
    // and call _handlePayload with the message data map.
  }

  // ignore: unused_element
  void _handlePayload(Map<String, dynamic> payload) {
    final route =
        PushNotificationService.instance.routeFromPayload(payload);
    if (route != null && mounted) {
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
