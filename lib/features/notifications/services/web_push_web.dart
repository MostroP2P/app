/// Web implementation of `web_push.dart`.
///
/// `firebase_messaging` 15 cannot say where the messaging worker lives, and
/// the Firebase JS SDK's default is `/firebase-messaging-sw.js` at the origin
/// root — a 404 under the deployed `/app/` base path. So the worker is
/// registered here, relative to the base path, and the token is asked of the
/// JS SDK the plugin already loaded, bound to that registration.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

/// The worker script and its scope, both relative to `<base href>`. Equal to
/// what `web/index.html` registers; `test/web/pages_bundle_test.dart` holds
/// the two together.
const kMessagingWorkerScript = 'firebase-messaging-sw.js';
const kMessagingWorkerScope = 'firebase-cloud-messaging-push-scope';

/// What the worker posts to an open tab when its notification is tapped.
/// Equal to `OPEN_NOTIFICATIONS` in `web/push_worker_logic.js`.
const kOpenNotificationsMessage = 'mostro-open-notifications';

/// How long a freshly installed worker gets to activate before the token is
/// asked for anyway (the SDK then reports what is wrong).
const _kActivationTimeout = Duration(seconds: 10);

@JS('firebase_messaging.getMessaging')
external JSObject _getMessaging();

@JS('firebase_messaging.getToken')
external JSPromise<JSString> _getToken(
  JSObject messaging,
  _TokenOptions options,
);

extension type _TokenOptions._(JSObject _) implements JSObject {
  external factory _TokenOptions({
    String vapidKey,
    web.ServiceWorkerRegistration serviceWorkerRegistration,
  });
}

/// `Notification`, `PushManager` and service workers — what a push needs,
/// read from the browser rather than guessed from its user agent (§2.6).
bool browserSupportsPush() =>
    globalContext.has('Notification') &&
    globalContext.has('PushManager') &&
    (web.window.navigator as JSObject).has('serviceWorker');

/// Register the messaging worker under the base path and return the FCM
/// token bound to it. Registering again is a no-op for the browser.
Future<String?> webPushToken(String vapidKey) async {
  final registration =
      await web.window.navigator.serviceWorker
          .register(
            kMessagingWorkerScript.toJS,
            web.RegistrationOptions(scope: kMessagingWorkerScope),
          )
          .toDart;
  await _activated(registration);
  final token =
      await _getToken(
        _getMessaging(),
        _TokenOptions(
          vapidKey: vapidKey,
          serviceWorkerRegistration: registration,
        ),
      ).toDart;
  return token.toDart;
}

Future<void> _activated(web.ServiceWorkerRegistration registration) async {
  if (registration.active != null) return;
  final worker = registration.installing ?? registration.waiting;
  if (worker == null) return;
  final done = Completer<void>();
  worker.onstatechange =
      ((web.Event _) {
        if (worker.state == 'activated' && !done.isCompleted) done.complete();
      }).toJS;
  await done.future.timeout(
    _kActivationTimeout,
    onTimeout: () => debugPrint('[push] messaging worker slow to activate'),
  );
}

/// Run [open] when the worker reports a tap on its notification while this
/// tab is open. A tab it had to open itself lands on the route directly.
void onWebNotificationTap(void Function() open) {
  final container = web.window.navigator.serviceWorker;
  container.addEventListener(
    'message',
    ((web.MessageEvent event) {
      if (event.data.dartify() == kOpenNotificationsMessage) open();
    }).toJS,
  );
  container.startMessages();
}
