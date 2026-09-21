// The decisions web/firebase-messaging-sw.js makes, kept apart from the
// browser so test/web/push_worker/ can run them under node
// (docs/PUSH_NOTIFICATIONS.md §2.6, T4.5).
//
// Content-free by rule (§2.3): nothing here reads a payload field other than
// `type` and whether the server sent its own notification block.

const CHAT_WAKE_TITLE = 'Mostro';

// `pushNewMessageBody` from lib/l10n/app_*.arb, which a worker cannot read;
// test/web/pages_bundle_test.dart keeps the copy equal to the source.
const CHAT_WAKE_BODIES = {
  en: 'You have a new message',
  es: 'Tienes un mensaje nuevo',
  fr: 'Vous avez un nouveau message',
  de: 'Du hast eine neue Nachricht',
  it: 'Hai un nuovo messaggio',
  nl: 'Je hebt een nieuw bericht',
};

// What the worker posts to an open tab on a tap. Equal to
// kOpenNotificationsMessage in lib/features/notifications/services/web_push_web.dart.
const OPEN_NOTIFICATIONS = 'mostro-open-notifications';

// Where a tap lands: Notifications, under the base path the worker was served
// from. It takes no payload, because a push carries nothing to route on.
function notificationTarget(workerUrl) {
  return new URL('./#/notifications', workerUrl).href;
}

// A tap on any notice: tell an open app tab to show Notifications and focus
// it, or open one there. `clients` is the worker's Clients, injected so the
// two branches run under node. Uncontrolled tabs count: the app's pages are
// controlled by the isolation shim, not by this worker. Returns the promise
// the worker hands to `event.waitUntil`.
async function openNotifications(clients, workerUrl) {
  const base = new URL('./', workerUrl).href;
  const tabs = await clients.matchAll({ type: 'window', includeUncontrolled: true });
  const tab = tabs.find((client) => client.url.startsWith(base));
  if (tab) {
    tab.postMessage(OPEN_NOTIFICATIONS);
    return tab.focus();
  }
  return clients.openWindow(notificationTarget(workerUrl));
}

// The notice the worker renders itself, or null. A trade_update carries the
// server's notification block, which the SDK renders. A chat_wake carries
// none, and Chrome revokes a subscription whose pushes show nothing.
function noticeFor(payload, languages) {
  if (payload?.notification) return null;
  if (payload?.data?.type !== 'chat_wake') return null;
  return { title: CHAT_WAKE_TITLE, body: CHAT_WAKE_BODIES[languageOf(languages)] };
}

function languageOf(languages) {
  for (const tag of languages ?? []) {
    const primary = String(tag).split('-')[0].toLowerCase();
    if (Object.hasOwn(CHAT_WAKE_BODIES, primary)) return primary;
  }
  return 'en';
}

const pushWorkerLogic = {
  CHAT_WAKE_BODIES,
  OPEN_NOTIFICATIONS,
  notificationTarget,
  noticeFor,
  openNotifications,
};

if (typeof module !== 'undefined') module.exports = pushWorkerLogic;
