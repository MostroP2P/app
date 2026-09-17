// Stand-in for web/firebase-messaging-sw.js: a worker that installs and
// activates, which is all the smoke check asserts.
self.addEventListener('install', () => self.skipWaiting());
