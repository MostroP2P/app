// Firebase Cloud Messaging service worker.
// Keep in sync with the Firebase SDK version used in pubspec.yaml.
importScripts('https://www.gstatic.com/firebasejs/10.14.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.14.0/firebase-messaging-compat.js');

// Config is injected by flutterfire configure — replace with real values.
const firebaseConfig = {
  apiKey: "REPLACE_ME",
  authDomain: "REPLACE_ME",
  projectId: "REPLACE_ME",
  storageBucket: "REPLACE_ME",
  messagingSenderId: "REPLACE_ME",
  appId: "REPLACE_ME",
};

firebase.initializeApp(firebaseConfig);
const messaging = firebase.messaging();

// Handle background messages on web.
messaging.onBackgroundMessage((payload) => {
  const { title, body, icon } = payload.notification ?? {};
  if (!title) return;
  return self.registration.showNotification(title, {
    body: body ?? '',
    icon: icon ?? '/icons/Icon-192.png',
    data: payload.data,
  });
});

// Handle notification clicks — focus existing window or open new one.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();

  const data = event.notification.data;
  // Build a relative URL from the payload (mirrors routeFromPayload in Dart).
  let path = '/';
  if (data) {
    const type = data.type;
    const orderId = data.orderId;
    const disputeId = data.disputeId;
    if (type === 'tradeUpdate' && orderId) path = `/#/trade_detail/${orderId}`;
    else if (type === 'invoiceRequest' && orderId) path = `/#/add_invoice/${orderId}`;
    else if (type === 'paymentReceived' && orderId) path = `/#/pay_invoice/${orderId}`;
    else if (type === 'orderTaken' && orderId) path = `/#/add_invoice/${orderId}`;
    else if (type === 'dispute' && disputeId) path = `/#/dispute_details/${disputeId}`;
  }

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      // Focus an existing tab if one is open.
      for (const client of windowClients) {
        if (new URL(client.url).origin === self.location.origin && 'focus' in client) {
          client.postMessage({ type: 'notification_click', path });
          return client.focus();
        }
      }
      // No existing tab — open a new one.
      return clients.openWindow(path);
    })
  );
});
