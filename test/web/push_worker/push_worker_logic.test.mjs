// Unit tests for web/push_worker_logic.js, the decisions the messaging
// service worker makes (docs/PUSH_NOTIFICATIONS.md §2.6, T4.5).
//
// Usage:  node --test test/web/push_worker/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { readdirSync } from 'node:fs';

const require = createRequire(import.meta.url);
const {
  notificationTarget,
  noticeFor,
  openNotifications,
  CHAT_WAKE_BODIES,
  OPEN_NOTIFICATIONS,
} = require('../../../web/push_worker_logic.js');

const WORKER = 'https://mostro.network/app/firebase-messaging-sw.js';

// A stand-in for the worker's `clients`: records what the tap asked of it.
function fakeClients(urls) {
  const calls = { matchAll: [], openWindow: [], messages: [], focused: [] };
  const tabs = urls.map((url) => ({
    url,
    postMessage: (message) => calls.messages.push({ url, message }),
    focus: async () => {
      calls.focused.push(url);
      return 'focused';
    },
  }));
  return {
    calls,
    matchAll: async (options) => {
      calls.matchAll.push(options);
      return tabs;
    },
    openWindow: async (url) => {
      calls.openWindow.push(url);
      return 'opened';
    },
  };
}

test('a tap with the app open tells that tab to show Notifications and focuses it', async () => {
  const clients = fakeClients(['https://mostro.network/app/#/order_book']);

  const result = await openNotifications(clients, WORKER);

  assert.equal(result, 'focused');
  assert.deepEqual(clients.calls.messages, [
    { url: 'https://mostro.network/app/#/order_book', message: OPEN_NOTIFICATIONS },
  ]);
  assert.deepEqual(clients.calls.focused, ['https://mostro.network/app/#/order_book']);
  assert.deepEqual(clients.calls.openWindow, []);
  // Uncontrolled too: the app's tabs are controlled by the isolation shim.
  assert.deepEqual(clients.calls.matchAll, [{ type: 'window', includeUncontrolled: true }]);
});

test('a tap with no app tab open opens one on Notifications', async () => {
  const clients = fakeClients([]);

  const result = await openNotifications(clients, WORKER);

  assert.equal(result, 'opened');
  assert.deepEqual(clients.calls.openWindow, ['https://mostro.network/app/#/notifications']);
  assert.deepEqual(clients.calls.messages, []);
});

test('a tab of the same origin outside the base path is not the app', async () => {
  const clients = fakeClients(['https://mostro.network/', 'https://mostro.network/docs/']);

  await openNotifications(clients, WORKER);

  assert.deepEqual(clients.calls.focused, []);
  assert.deepEqual(clients.calls.openWindow, ['https://mostro.network/app/#/notifications']);
});

test('a tap opens Notifications under the deployed base path', () => {
  assert.equal(notificationTarget(WORKER), 'https://mostro.network/app/#/notifications');
});

test('a tap at the root deployment opens Notifications at the root', () => {
  assert.equal(
    notificationTarget('http://127.0.0.1:8080/firebase-messaging-sw.js'),
    'http://127.0.0.1:8080/#/notifications',
  );
});

test('the target never depends on the payload — there is nothing to route on', () => {
  // notificationTarget takes no payload at all: a field the server never
  // sends cannot become a route.
  assert.equal(notificationTarget.length, 1);
});

test('a visible trade update is left to the SDK, which renders its block', () => {
  const payload = {
    notification: { title: 'Mostro', body: 'You have an update on your trade' },
    data: { type: 'trade_update' },
  };
  assert.equal(noticeFor(payload, ['en-US']), null);
});

test('a chat wake renders a content-free notice of its own', () => {
  const payload = { data: { type: 'chat_wake', source: 'mostro-push-server' } };
  assert.deepEqual(noticeFor(payload, ['en-US']), {
    title: 'Mostro',
    body: 'You have a new message',
  });
});

test('the chat-wake notice follows the browser language', () => {
  const payload = { data: { type: 'chat_wake' } };
  assert.equal(noticeFor(payload, ['es-AR', 'en']).body, 'Tienes un mensaje nuevo');
  assert.equal(noticeFor(payload, ['fr-CA']).body, 'Vous avez un nouveau message');
  assert.equal(noticeFor(payload, ['pt-BR', 'de-DE']).body, 'Du hast eine neue Nachricht');
});

test('a language the app does not ship falls back to English', () => {
  const payload = { data: { type: 'chat_wake' } };
  assert.equal(noticeFor(payload, ['ja-JP']).body, 'You have a new message');
  assert.equal(noticeFor(payload, []).body, 'You have a new message');
});

test('a payload naming an order still yields the same content-free notice', () => {
  const payload = { data: { type: 'chat_wake', orderId: 'abc', disputeId: 'def' } };
  const notice = noticeFor(payload, ['en']);
  assert.ok(!JSON.stringify(notice).includes('abc'));
  assert.ok(!JSON.stringify(notice).includes('def'));
});

test('an unknown data-only push renders nothing', () => {
  assert.equal(noticeFor({ data: { type: 'something_else' } }, ['en']), null);
  assert.equal(noticeFor({}, ['en']), null);
});

test('the notice ships every app language', () => {
  // Derived from the translation files, so a new locale cannot be missed here.
  const l10n = new URL('../../../lib/l10n/', import.meta.url);
  const locales = readdirSync(l10n)
    .map((name) => /^app_([a-z]{2})\.arb$/.exec(name)?.[1])
    .filter(Boolean)
    .sort();
  assert.deepEqual(Object.keys(CHAT_WAKE_BODIES).sort(), locales);
});
