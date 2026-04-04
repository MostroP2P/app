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
