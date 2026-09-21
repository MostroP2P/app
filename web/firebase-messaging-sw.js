// Firebase Cloud Messaging service worker (docs/PUSH_NOTIFICATIONS.md §2.6, T4.5).
//
// Registered by web/index.html and by the app (web_push_web.dart), relative to
// the base path, under its own scope — never the isolation shim's. It rings
// the bell and shows the notification. It never loads the wasm core, never
// opens IndexedDB and never decrypts: the tab resyncs when it next runs.
//
// The SDK version is the one firebase_core_web loads on the page, and the
// config is the web block of lib/firebase_options.dart;
// test/web/pages_bundle_test.dart holds both equal.
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/11.9.1/firebase-messaging-compat.js');
importScripts('push_worker_logic.js');

// A tap: tell an open tab to show Notifications and focus it, or open one
// there (pushWorkerLogic.openNotifications, tested under node). Added before
// the SDK's own listener, which stops propagation for the notifications it
// rendered.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(pushWorkerLogic.openNotifications(clients, self.location.href));
});

firebase.initializeApp({
  apiKey: 'AIzaSyCcKUG4IkZ51YfTjZSCqNdZmT5dVH_ebnA',
  appId: '1:375342057498:web:2cd68bf87a368a4886e9a3',
  messagingSenderId: '375342057498',
  projectId: 'mostro-mobile',
});

// A trade_update is shown by the SDK from the server's own block. A chat_wake
// has none, so the worker shows the content-free notice.
firebase.messaging().onBackgroundMessage((payload) => {
  const notice = pushWorkerLogic.noticeFor(payload, self.navigator.languages);
  if (!notice) return undefined;
  return self.registration.showNotification(notice.title, {
    body: notice.body,
    tag: 'mostro-chat',
    icon: 'icons/Icon-192.png',
  });
});
