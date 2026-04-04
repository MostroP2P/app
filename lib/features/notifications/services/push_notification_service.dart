import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';

// Background message handler — must be a top-level function.
@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  debugPrint('[push] background message: ${message.messageId}');
}

/// Push notification service — platform-gated FCM (Android/iOS) + Web Push.
class PushNotificationService {
  PushNotificationService._();

  static final instance = PushNotificationService._();

  FirebaseMessaging? _fcmInstance;
  FirebaseMessaging get _fcm => _fcmInstance ??= FirebaseMessaging.instance;
  String? _token;
  bool _initialized = false;
  SharedPreferences? _cachedPrefs;
  final Set<String> _registeredTradePubkeys = {};

  // Push server base URL — update when the Mostro push server is deployed.
  static const _pushServerUrl = 'https://push.mostro.network';

  Future<void> initialize({ProviderContainer? container}) async {
    if (!_isSupported) return;

    // Bail out if Firebase hasn't been initialized (placeholder firebase_options).
    try {
      _fcmInstance = FirebaseMessaging.instance;
    } catch (e) {
      debugPrint('[push] Firebase not available: $e');
      return;
    }

    // 1. Request permission (required on iOS, shows dialog; Android 13+ also).
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[push] permission denied');
      return;
    }

    // 2. Register background message handler.
    FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);

    // 3. Get initial FCM token.
    // TODO: Replace 'YOUR_VAPID_KEY' with the real VAPID key from Firebase console.
    const vapidKey = 'YOUR_VAPID_KEY';
    if (kIsWeb && vapidKey == 'YOUR_VAPID_KEY') {
      debugPrint('[push] WARNING: VAPID key not configured — skipping web token');
    } else {
      try {
        _token = await _fcm.getToken(
          vapidKey: kIsWeb ? vapidKey : null,
        );
        debugPrint('[push] FCM token acquired (${_token?.length ?? 0} chars)');
      } catch (e) {
        debugPrint('[push] FCM getToken failed: $e');
      }
    }

    // 4. Handle foreground messages — create in-app notification.
    FirebaseMessaging.onMessage.listen((message) {
      _handleForeground(message, container: container);
    });

    // 5. Handle notification tap when app was in background (not terminated).
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleTap(message);
    });

    // 6. Handle notification tap when app was terminated.
    final initial = await _fcm.getInitialMessage();
    if (initial != null) _handleTap(initial);

    // 7. Listen for token refresh.
    _fcm.onTokenRefresh.listen((newToken) {
      _token = newToken;
      reRegisterAllTokens();
    });

    // 8. Cache SharedPreferences for synchronous notification gating.
    _cachedPrefs = await SharedPreferences.getInstance();

    _initialized = true;
  }

  void _handleForeground(RemoteMessage message, {ProviderContainer? container}) {
    final data = message.data;
    if (data.isEmpty) return;

    final type = data['type'] as String?;
    final orderId = data['orderId'] as String?;
    final disputeId = data['disputeId'] as String?;

    if (type == null) return;

    // Respect per-type notification preferences.
    if (!_isTypeEnabled(type)) return;

    final notification = NotificationModel(
      id: message.messageId ?? DateTime.now().toIso8601String(),
      type: _typeFromString(type),
      title: message.notification?.title ?? _defaultTitle(type),
      message: message.notification?.body ?? _defaultBody(type, orderId),
      timestamp: DateTime.now(),
      orderId: orderId,
      disputeId: disputeId,
    );

    container?.read(notificationsProviderWithDb.notifier).add(notification);
  }

  void _handleTap(RemoteMessage message) {
    _pendingRoute = routeFromPayload(message.data);
  }

  String? _pendingRoute;

  /// Consume and clear any pending deep-link route from a notification tap.
  String? consumePendingRoute() {
    final r = _pendingRoute;
    _pendingRoute = null;
    return r;
  }

  // ── Notification preferences gating ───────────────────────────────────────

  /// Check if a notification type is enabled in user preferences.
  /// Uses the same SharedPreferences keys as notification_settings_screen.dart.
  bool _isTypeEnabled(String type) {
    final prefs = _cachedPrefs;
    if (prefs == null) return true; // allow until prefs are loaded
    return switch (type) {
      'tradeUpdate' || 'orderTaken' => prefs.getBool('notify_trade_updates') ?? true,
      'invoiceRequest' || 'paymentReceived' => prefs.getBool('notify_payments') ?? true,
      'dispute' => prefs.getBool('notify_disputes') ?? true,
      _ => true,
    };
  }

  // ── Token registration with push server ──────────────────────────────────

  Future<void> registerToken(String tradePubkey) async {
    if (!_isSupported || _token == null) return;
    try {
      final response = await http.post(
        Uri.parse('$_pushServerUrl/api/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'trade_pubkey': tradePubkey,
          'token': _token,
          'platform': _platform,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _registeredTradePubkeys.add(tradePubkey);
        debugPrint('[push] registered $tradePubkey');
      } else {
        debugPrint('[push] register failed: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[push] register failed: $e');
    }
  }

  Future<void> unregisterToken(String tradePubkey) async {
    if (!_isSupported || _token == null) return;
    try {
      final response = await http.post(
        Uri.parse('$_pushServerUrl/api/unregister'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'trade_pubkey': tradePubkey,
          'token': _token,
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        _registeredTradePubkeys.remove(tradePubkey);
      } else {
        debugPrint('[push] unregister failed: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[push] unregister failed: $e');
    }
  }

  Future<void> reRegisterAllTokens() async {
    for (final pubkey in Set.of(_registeredTradePubkeys)) {
      await registerToken(pubkey);
    }
  }

  Future<void> unregisterAllTokens() async {
    for (final pubkey in Set.of(_registeredTradePubkeys)) {
      await unregisterToken(pubkey);
    }
    if (_initialized) {
      await _fcm.deleteToken();
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  bool get _isSupported => !_isDesktop;
  bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows);

  String get _platform {
    if (kIsWeb) return 'web';
    if (defaultTargetPlatform == TargetPlatform.android) return 'android';
    if (defaultTargetPlatform == TargetPlatform.iOS) return 'ios';
    return 'unknown';
  }

  NotificationType _typeFromString(String type) => switch (type) {
        'tradeUpdate' => NotificationType.tradeUpdate,
        'invoiceRequest' => NotificationType.invoiceRequest,
        'paymentReceived' => NotificationType.paymentReceived,
        'orderTaken' => NotificationType.orderTaken,
        'dispute' => NotificationType.dispute,
        _ => NotificationType.system,
      };

  String _defaultTitle(String type) => switch (type) {
        'tradeUpdate' => 'Trade updated',
        'invoiceRequest' => 'Invoice requested',
        'paymentReceived' => 'Payment received',
        'orderTaken' => 'Order taken',
        'dispute' => 'Dispute opened',
        _ => 'Mostro notification',
      };

  String _defaultBody(String type, String? orderId) {
    final id = orderId != null
        ? ' for order ${orderId.substring(0, math.min(8, orderId.length))}'
        : '';
    return switch (type) {
      'tradeUpdate' => 'Your trade status changed$id.',
      'invoiceRequest' => 'Add your Lightning invoice$id.',
      'paymentReceived' => 'You received a payment$id.',
      'orderTaken' => 'Your order was taken$id.',
      'dispute' => 'A dispute was opened$id.',
      _ => 'You have a new notification.',
    };
  }

  // ── Route resolution (DO NOT MODIFY) ───────────────────────────────────────

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
}

/// Widget that wires push-tap payloads to GoRouter.
///
/// Wrap around the app root so the navigator context is available.
/// Consumes any pending route from a notification tap on app launch.
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final route = PushNotificationService.instance.consumePendingRoute();
      if (route != null && mounted) context.push(route);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
