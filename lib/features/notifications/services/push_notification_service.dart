import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/notifications/services/token_handoff.dart';
import 'package:mostro/src/rust/api/push.dart' as push_api;
import 'package:mostro/src/rust/api/types.dart';

/// Background message handler — must be a top-level function.
///
/// Display-only, by rule (docs/PUSH_NOTIFICATIONS.md §6 principle 2, issue
/// #308): it must never initialise the Rust core, open the database or
/// decrypt anything. The push is a doorbell, not a courier — every state
/// change comes from the one Rust core, in the foreground, through the
/// resume resync. Phase 2 gives it the one thing it may do: note that a
/// wake arrived.
@pragma('vm:entry-point')
Future<void> _backgroundMessageHandler(RemoteMessage message) async {
  debugPrint('[push] background message: ${message.messageId}');
}

/// The device side of push notifications: Firebase, the OS permission, and
/// the device token, which is handed to Rust and nothing else.
///
/// Everything after the token — which trade pubkeys the push server holds
/// it for, when they are re-sent, what is let go on opt-out — is Rust's
/// (`rust/src/api/push.rs`, docs/PUSH_NOTIFICATIONS.md §7.1). This class
/// decides nothing about registration; it reports the token, and the token's
/// platform, and that is all the push server ever learns from Dart.
class PushNotificationService {
  PushNotificationService._();

  static final instance = PushNotificationService._();

  FirebaseMessaging? _fcmInstance;
  FirebaseMessaging get _fcm => _fcmInstance ??= FirebaseMessaging.instance;

  /// Guards [initialize] against a second run attaching duplicate listeners.
  bool _initStarted = false;

  /// Kept from the first [initialize] so [retryInitialize] can pass it on.
  ProviderContainer? _container;

  /// The bridge hand-over, with its retry while storage is not ready.
  final TokenHandoff _handoff = TokenHandoff(
    setToken:
        (token, platform) =>
            push_api.setPushToken(token: token, platform: platform),
  );

  /// Whether this platform can receive a push at all: a capability, decided
  /// here and read by Settings as its first branch (§9.1). Not "a token was
  /// obtained" — a denied permission also yields no token and must show the
  /// denied banner, not unsupported copy.
  ///
  /// Web is a capability the browser has, but the push server does not
  /// accept a web platform yet (§3.5), so it reads as unsupported until
  /// that lands (T4.5).
  bool get isSupported => platformFor(kIsWeb, defaultTargetPlatform) != null;

  Future<void> initialize({ProviderContainer? container}) async {
    _container = container ?? _container;
    if (!isSupported) return;
    // Steps below attach stream listeners that are never cancelled, so a
    // second run would double every token hand-over. This is a separate
    // flag from "a token was obtained" and must stay false on the paths
    // that bail out below, so a later grant can run this again.
    if (_initStarted) return;
    _initStarted = true;

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
      // Nothing is attached yet, so a later grant may run this again.
      _initStarted = false;
      return;
    }

    // 2. Register the display-only background handler.
    FirebaseMessaging.onBackgroundMessage(_backgroundMessageHandler);

    // 3. Hand the token to Rust — on every refresh, and now. The refresh
    //    listener is attached first: a rotation that lands while the first
    //    hand-over is in flight must not be missed.
    _fcm.onTokenRefresh.listen((token) {
      _handOver(token);
    });
    await _handOverToken();

    // 4. Foreground messages carry nothing to act on (§2.3): the foreground
    //    subscription already delivers the event and the in-app card.
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[push] foreground message: ${message.data['type']}');
    });
  }

  Future<void> _handOverToken() async {
    // TODO(#133): the real VAPID key, once the push server accepts web.
    const vapidKey = 'YOUR_VAPID_KEY';
    if (kIsWeb && vapidKey == 'YOUR_VAPID_KEY') {
      debugPrint('[push] VAPID key not configured — skipping web token');
      return;
    }
    final String? token;
    try {
      token = await _fcm.getToken(vapidKey: kIsWeb ? vapidKey : null);
    } catch (e) {
      debugPrint('[push] FCM getToken failed: $e');
      return;
    }
    if (token == null) return;
    debugPrint('[push] FCM token acquired (${token.length} chars)');
    await _handOver(token);
  }

  Future<void> _handOver(String token) async {
    final platform = platformFor(kIsWeb, defaultTargetPlatform);
    if (platform == null) return;
    await _handoff.offer(token, platform);
  }

  /// Runs [initialize] again after the user granted a permission they had
  /// denied: the first run stopped before acquiring a token or attaching
  /// listeners. Once a run has got past the permission step, only a token
  /// Rust could not take yet is worth retrying.
  Future<void> retryInitialize() async {
    if (_initStarted) {
      await _handoff.retryPending();
      return;
    }
    await initialize(container: _container);
  }

  /// Whether the OS is refusing to show this app's notifications.
  ///
  /// 10d needs to say so before the four toggles, since flipping them on
  /// while the system permission is denied changes nothing the user can see.
  /// Anything other than an explicit denial reads as false — a platform with
  /// no push (desktop), a build without Firebase, or a permission the user
  /// has not been asked for yet is not a setting for them to go and fix.
  Future<bool> isSystemPermissionDenied() async {
    if (!isSupported) return false;
    try {
      final settings = await _fcm.getNotificationSettings();
      return settings.authorizationStatus == AuthorizationStatus.denied;
    } catch (e) {
      debugPrint('[push] permission status unavailable: $e');
      return false;
    }
  }
}

/// The push server's platform for this build, or `null` where no push can
/// be received: desktop has no transport, and web is held back until the
/// server accepts it (docs/PUSH_NOTIFICATIONS.md §3.4, §3.5).
PushPlatform? platformFor(bool isWeb, TargetPlatform platform) {
  if (isWeb) return null;
  return switch (platform) {
    TargetPlatform.android => PushPlatform.android,
    TargetPlatform.iOS => PushPlatform.ios,
    _ => null,
  };
}
