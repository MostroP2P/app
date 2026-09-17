/// The browser side of push: the messaging service worker, the token bound
/// to it, and a tap on its notification (docs/PUSH_NOTIFICATIONS.md T4.5).
///
/// Off web every call is inert: Android and iOS take their token from
/// `firebase_messaging` directly.
library;

export 'web_push_stub.dart' if (dart.library.js_interop) 'web_push_web.dart';
