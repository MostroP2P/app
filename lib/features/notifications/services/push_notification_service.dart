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

  /// Validates that a push payload ID contains only safe characters
  /// (alphanumeric, hyphens, underscores) to prevent route injection.
  static final _validIdPattern = RegExp(r'^[a-zA-Z0-9\-_]+$');

  bool _isValidId(String? id) =>
      id != null && id.isNotEmpty && _validIdPattern.hasMatch(id);

  /// Extract the GoRouter destination from a push payload.
  ///
  /// Payload keys: `type` (string), `orderId` (string?), `disputeId` (string?)
  ///
  /// Returns `null` if the payload type is unrecognised or the required ID
  /// fails validation (alphanumeric + hyphens/underscores only).
  String? routeFromPayload(Map<String, dynamic> payload) {
    final type = payload['type'] as String?;
    final orderId = payload['orderId'] as String?;
    final disputeId = payload['disputeId'] as String?;

    return switch (type) {
      'tradeUpdate' when _isValidId(orderId) => '/trade_detail/$orderId',
      'invoiceRequest' when _isValidId(orderId) => '/add_invoice/$orderId',
      'paymentReceived' when _isValidId(orderId) => '/pay_invoice/$orderId',
      'ratingReceived' when _isValidId(orderId) => '/rate_user/$orderId',
      'orderTaken' when _isValidId(orderId) => '/add_invoice/$orderId',
      'dispute' when _isValidId(disputeId) => '/dispute_details/$disputeId',
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
  // StreamSubscription<RemoteMessage>? _openedAppSubscription;

  @override
  void initState() {
    super.initState();
    // TODO(firebase): Uncomment when firebase_messaging is added
    // _openedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
    //   (message) => _handlePayload(message.data),
    // );
  }

  @override
  void dispose() {
    // _openedAppSubscription?.cancel();
    super.dispose();
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