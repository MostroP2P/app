import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/features/notifications/services/device_token.dart';
import 'package:mostro/features/notifications/services/local_notifications.dart';
import 'package:mostro/features/notifications/services/push_background_handler.dart';
import 'package:mostro/features/notifications/services/push_refresh_job.dart';
import 'package:mostro/features/notifications/services/web_push.dart';
import 'package:mostro/features/notifications/services/web_push_config.dart';
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;
import 'package:mostro/features/notifications/services/token_handoff.dart';
import 'package:mostro/src/rust/api/push.dart' as push_api;
import 'package:mostro/src/rust/api/types.dart';

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
  Future<void> _deviceTail = Future.value();

  /// Startup and permission recovery also acquire tokens, so they share the
  /// same device queue as the master toggle's release/reacquire operations.
  Future<void> _serialize(Future<void> Function() operation) {
    final result = _deviceTail.then((_) => operation());
    _deviceTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  /// Push is off in Settings: no token is handed to Rust until [reacquire].
  /// Without this, FCM regenerating a deleted token (or a refresh) would
  /// give Rust a token the user let go.
  bool _released = false;

  /// Token delivery is suspended until the OS permission has been checked.
  /// Kept separate from opt-out so a later permission grant can retry.
  bool _permissionDenied = true;

  /// Test seam — production pushes on the global [appRouter].
  @visibleForTesting
  void Function(String destination)? navigate;

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
  /// Web needs a browser with push, a VAPID key and the `PUSH_WEB_ENABLED`
  /// switch, which stays off until the push server accepts web (§3.5, T4.5);
  /// until then it reads as unsupported.
  bool get isSupported => _platform != null;

  /// The platform a token is registered under. One answer for the capability
  /// and for every hand-over: web tokens need [_webPush] passed through, or
  /// they are dropped before Rust ever sees them.
  PushPlatform? get _platform =>
      platformFor(kIsWeb, defaultTargetPlatform, webPush: _webPush);

  static bool get _webPush =>
      kIsWeb &&
      webPushAvailable(
        enabled: kPushWebEnabled,
        vapidKey: kFcmVapidKey,
        browserSupportsPush: browserSupportsPush(),
      );

  Future<void> initialize({ProviderContainer? container}) {
    return _serialize(_initialize);
  }

  Future<void> _initialize() async {
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
      _initStarted = false;
      return;
    }

    // 0. The channel the server's visible push names, with the importance
    //    the app wants (§3.2). Before the permission: the channel needs none.
    //    Its tap callback covers the chat-wake notice the app renders itself.
    // 1. Request permission (required on iOS, shows dialog; Android 13+ also).
    //    A failure here happens before any listener is attached, so the run
    //    is undone and [retryInitialize] can start it again.
    final NotificationSettings settings;
    try {
      await ensurePushNotificationChannel(onTap: _openNotifications);
      settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    } catch (e) {
      debugPrint('[push] setup failed before listeners, retryable: $e');
      _initStarted = false;
      return;
    }
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('[push] permission denied');
      // Nothing is attached yet, so a later grant may run this again.
      _initStarted = false;
      await _suspendForPermission();
      return;
    }

    // Apply the saved preference before a refresh listener can deliver any
    // token. An opt-out that happened during this await must stay in force.
    if (!await _enabledInRust()) _released = true;

    // 2. Register the display-only background handler.
    FirebaseMessaging.onBackgroundMessage(pushBackgroundHandler);

    // 3. Hand the token to Rust — on every refresh, and now. The refresh
    //    listener is attached first: a rotation that lands while the first
    //    hand-over is in flight must not be missed. Not awaited: on iOS the
    //    token waits for APNs (fetchDeviceToken), and nothing below needs it.
    //    The acquisition still checks the permission and the opt-out first.
    _fcm.onTokenRefresh.listen((token) {
      _handOver(token);
    });
    if (!_released) unawaited(_acquireIfAllowed());

    // 4. Foreground messages carry nothing to act on (§2.3): the foreground
    //    subscription already delivers the event and the in-app card. The
    //    one useful thing a push says while the app is up is that the
    //    relays had something for us — if the pool is not connected, that
    //    is a reason to reconnect now rather than on its own backoff.
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('[push] foreground message: ${message.data['type']}');
      unawaited(_nudgeIfOffline());
    });

    // 5. A tap on the OS notification. There is no payload to route on
    //    (§2.3): the app opens on Notifications, where the resync's in-app
    //    cards say what the wake was about. Warm (the app was in the
    //    background) and cold (the tap launched it) alike.
    FirebaseMessaging.onMessageOpenedApp.listen((_) => _openNotifications());
    //    On web the messaging worker handles the tap and tells an open tab.
    if (kIsWeb) onWebNotificationTap(_openNotifications);
    //    The chat-wake notice is the app's own, so FCM sees neither tap.
    final launch = await _fcm.getInitialMessage();
    if (launch != null || await launchedFromLocalNotification()) {
      _openNotifications();
    }

    // 5. The refresh that outlives the process: the OS re-POSTs the
    //    registrations Rust mirrored, every 12 h, app running or not. The web
    //    has no OS job to run it on (§2.6).
    if (!kIsWeb) await schedulePushRefresh();
  }

  Future<void> _nudgeIfOffline() async {
    try {
      final state = await nostr_api.getConnectionState();
      if (state == ConnectionState.online) return;
      final outcome = await nostr_api.resync();
      debugPrint('[push] foreground nudge: online=${outcome.online}');
    } catch (e) {
      debugPrint('[push] foreground nudge failed: $e');
    }
  }

  void _openNotifications() {
    final go = navigate ?? (destination) => appRouter.push(destination);
    try {
      go(AppRoute.notifications);
    } catch (e) {
      debugPrint('[push] could not open notifications: $e');
    }
  }

  Future<void> _handOverToken() async {
    final String? token;
    try {
      // Web binds the token to the messaging worker under the base path
      // (web_push_web.dart); the plugin would look for it at the origin root.
      token =
          kIsWeb
              ? await webPushToken(kFcmVapidKey)
              : await fetchDeviceToken(
                waitsForApns: defaultTargetPlatform == TargetPlatform.iOS,
                getApnsToken: _fcm.getAPNSToken,
                getToken: _fcm.getToken,
              );
    } catch (e) {
      debugPrint('[push] FCM getToken failed: $e');
      return;
    }
    if (token == null) return;
    debugPrint('[push] FCM token acquired (${token.length} chars)');
    await _handOver(token);
  }

  Future<void> _handOver(String token) async {
    if (_released || _permissionDenied) return;
    final platform = _platform;
    if (platform == null) return;
    await _handoff.offer(token, platform);
  }

  /// Runs [initialize] again after the user granted a permission they had
  /// denied: the first run stopped before acquiring a token or attaching
  /// listeners. Once a run has got past the permission step, only a token
  /// Rust could not take yet is worth retrying.
  Future<void> retryInitialize() => _serialize(_retryInitialize);

  Future<void> _retryInitialize() async {
    if (_initStarted) {
      if (_released) return;
      if (_permissionDenied) {
        await _acquireIfAllowed();
      } else {
        await _handoff.retryPending();
      }
      return;
    }
    await _initialize();
  }

  /// The persisted master toggle. Unknown — storage not up yet — reads as
  /// on: Rust gates every registration on the setting anyway, so handing a
  /// token over to a disabled Rust registers nothing.
  Future<bool> _enabledInRust() async {
    try {
      return (await push_api.getPushStatus()).enabled;
    } catch (e) {
      debugPrint('[push] push setting unavailable, assuming on: $e');
      return true;
    }
  }

  /// Push turned off in Settings (docs/PUSH_NOTIFICATIONS.md §7.4). Rust has
  /// already attempted to unregister everything. The device token goes too;
  /// FCM stops minting one, and none reaches Rust until [reacquire].
  Future<void> release() {
    // Block handoffs immediately, including a getToken already in flight.
    _released = true;
    final discarded = _handoff.discard();
    return _serialize(() async {
      await discarded;
      await _release();
    });
  }

  Future<void> _release() async {
    _released = true;
    // A hand-over still in flight must land before Rust's token is cleared.
    await _handoff.discard();
    if (!isSupported) return;
    try {
      await _fcm.setAutoInitEnabled(false);
      await _fcm.deleteToken();
    } catch (e) {
      debugPrint('[push] device token not deleted: $e');
    }
    await push_api.clearPushToken();
  }

  /// Push turned back on: a fresh token for Rust to register the current
  /// trades with. If the first [initialize] never got past the permission,
  /// it runs now.
  Future<void> reacquire() => _serialize(_reacquire);

  Future<void> _reacquire() async {
    if (!isSupported) return;
    _released = false;
    if (!_initStarted) {
      await _initialize();
      return;
    }
    await _acquireIfAllowed();
  }

  Future<void> _acquireIfAllowed() async {
    if (_released) return;
    // Gate refresh callbacks while the current permission is being read.
    _permissionDenied = true;
    if (await isSystemPermissionDenied()) {
      await _suspendForPermission();
      return;
    }
    if (_released) return;
    _permissionDenied = false;
    try {
      await _fcm.setAutoInitEnabled(true);
    } catch (e) {
      debugPrint('[push] FCM auto-init not re-enabled: $e');
    }
    if (_released) return;
    await _handOverToken();
  }

  Future<void> _suspendForPermission() async {
    _permissionDenied = true;
    await _handoff.discard();
    try {
      await push_api.clearPushToken();
    } catch (e) {
      debugPrint('[push] token not cleared after permission denial: $e');
    }
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
/// be received: desktop has no transport, and web only once [webPush] says
/// the tab can be woken (`webPushAvailable`, docs/PUSH_NOTIFICATIONS.md
/// §3.4, §3.5).
PushPlatform? platformFor(
  bool isWeb,
  TargetPlatform platform, {
  bool webPush = false,
}) {
  if (isWeb) return webPush ? PushPlatform.web : null;
  return switch (platform) {
    TargetPlatform.android => PushPlatform.android,
    TargetPlatform.iOS => PushPlatform.ios,
    _ => null,
  };
}
