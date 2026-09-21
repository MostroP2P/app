/// Non-web implementation of `web_push.dart`: nothing to register.
library;

/// No browser, no push.
bool browserSupportsPush() => false;

/// No token off web through this path.
Future<String?> webPushToken(String vapidKey) async => null;

/// No worker to hear from off web.
void onWebNotificationTap(void Function() open) {}
