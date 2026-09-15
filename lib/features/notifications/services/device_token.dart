import 'package:flutter/foundation.dart';

/// How many times, and how far apart, iOS looks for the APNs token before
/// asking FCM for its own.
const kApnsAttempts = 10;
const kApnsRetryDelay = Duration(seconds: 1);

/// The FCM device token, obtained the way the platform allows
/// (docs/PUSH_NOTIFICATIONS.md T4.4).
///
/// On iOS, FCM rides on APNs: until the OS has handed the app an APNs token,
/// `getToken` throws `apns-token-not-set`, and on a first launch that token
/// arrives moments after `registerForRemoteNotifications`. So iOS waits for
/// it first, a bounded number of times. Giving up returns `null` without
/// asking FCM: once APNs does register, FCM reports its token through
/// `onTokenRefresh`, which the push service already forwards to Rust.
///
/// A failing APNs lookup counts as "not there yet".
Future<String?> fetchDeviceToken({
  required bool waitsForApns,
  required Future<String?> Function() getApnsToken,
  required Future<String?> Function() getToken,
  Duration retryDelay = kApnsRetryDelay,
  int apnsAttempts = kApnsAttempts,
}) async {
  if (waitsForApns &&
      !await _apnsTokenArrives(getApnsToken, retryDelay, apnsAttempts)) {
    debugPrint('[push] no APNs token yet — FCM token deferred to refresh');
    return null;
  }
  return getToken();
}

Future<bool> _apnsTokenArrives(
  Future<String?> Function() getApnsToken,
  Duration retryDelay,
  int attempts,
) async {
  for (var attempt = 1; attempt <= attempts; attempt++) {
    try {
      if (await getApnsToken() != null) return true;
    } catch (e) {
      debugPrint('[push] APNs token lookup failed: $e');
    }
    if (attempt < attempts) await Future<void>.delayed(retryDelay);
  }
  return false;
}
