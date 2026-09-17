/// Build-time switches for web push (docs/PUSH_NOTIFICATIONS.md §2.6, T4.5).
library;

/// The FCM Web Push VAPID public key, from
/// `--dart-define=FCM_VAPID_KEY=<key>`. Public by design — the browser hands
/// it to its push service — and per Firebase project, so a fork sets its own
/// (docs/firebase-setup.md). A build that passes none has no web push.
const kFcmVapidKey = String.fromEnvironment('FCM_VAPID_KEY');

/// Web push on or off, from `--dart-define=PUSH_WEB_ENABLED=true`.
///
/// Off until the push server accepts `platform: "web"` and answers the
/// browser's CORS preflight (mostro-push-server#44, §3.5): before that every
/// registration from a tab is refused or blocked. Until it flips, Settings
/// shows web as a platform without push.
const kPushWebEnabled = bool.fromEnvironment('PUSH_WEB_ENABLED');

/// Whether this tab can be woken by a push: the switch is on, the build has
/// a VAPID key, and the browser exposes `Notification` and `PushManager`.
/// The browser half is a capability, not a user agent guess (§2.6).
bool webPushAvailable({
  required bool enabled,
  required String vapidKey,
  required bool browserSupportsPush,
}) =>
    enabled && vapidKey.isNotEmpty && browserSupportsPush;
