# Push Notifications — Client Implementation Spec & Phased Plan

**Status:** Draft — planning document; no epic yet (candidates to close or fold in: [#147](https://github.com/MostroP2P/app/issues/147) background wake-up, [#308](https://github.com/MostroP2P/app/issues/308) app lifecycle, [#133](https://github.com/MostroP2P/app/issues/133) web VAPID key)
**Goal:** let this client be woken by [`mostro-push-server`](https://github.com/MostroP2P/mostro-push-server) when a daemon message, a payout claim or a peer's chat message reaches one of its trade keys while the app is in the background or not running, with the same privacy properties the server was designed for: nobody outside the device ever sees message content, sender or order
**Audience:** contributors implementing push support in this client (appv2), human and AI reviewers of the PRs that land it
**Upstream reference:** [`MostroP2P/mostro-push-server`](https://github.com/MostroP2P/mostro-push-server) — `docs/api.md`, `docs/architecture.md`, `SECURITY.md` (the server-side contract, the single source of truth for what a push carries); [MIP-05](https://github.com/MostroP2P/MIPs) (the privacy model it is inspired by)
**Parity reference:** [`MostroP2P/mobile`](https://github.com/MostroP2P/mobile) — `lib/services/fcm_service.dart`, `lib/services/push_notification_service.dart`, `lib/background/`, `docs/architecture/FCM_IMPLEMENTATION.md`, `docs/plans/CHAT_NOTIFICATIONS_PLAN.md` (how the v1 client did it — consulted for completeness, **not** copied: v1 runs a second Dart isolate that re-implements the protocol; here the protocol lives in Rust, once)

---

## Table of contents

1. [Goal and scope](#1-goal-and-scope)
2. [How Mostro push works](#2-how-mostro-push-works)
3. [The wire contract](#3-the-wire-contract)
4. [How the v1 client does it](#4-how-the-v1-client-does-it)
5. [Where this client stands today](#5-where-this-client-stands-today)
6. [Design principles for the v2 implementation](#6-design-principles-for-the-v2-implementation)
7. [Client flows](#7-client-flows)
8. [Data model](#8-data-model)
9. [UI surfaces](#9-ui-surfaces)
10. [Lifecycle, restart and resilience](#10-lifecycle-restart-and-resilience)
11. [Implementation plan — phases, tasks, PRs](#11-implementation-plan--phases-tasks-prs)
12. [Testing strategy](#12-testing-strategy)
13. [Comparison with the v1 client](#13-comparison-with-the-v1-client)
14. [Open questions and assumptions to verify](#14-open-questions-and-assumptions-to-verify)
15. [References](#15-references)

---

## 1. Goal and scope

### 1.1 What push is, in one paragraph

A Mostro client only learns about a trade event by holding a relay subscription and
decrypting what arrives. A mobile OS suspends that subscription minutes after the app
leaves the screen. The push server closes the gap without learning anything: the client
registers each **trade pubkey** it wants to be woken for, together with a device token;
the server watches the relays for kind 14 events `p`-tagged to a registered pubkey and,
when one appears, asks Firebase Cloud Messaging (FCM) to deliver a **content-free** push
to that device — "Mostro: you have an update on your trade". The push is a doorbell,
never a courier: it carries no event id, no order, no sender, no ciphertext. The app then
reconnects, replays what it missed from the relays, and decides locally what to show.

### 1.2 What the client does — and does not — decide

The client decides:

- **which trade pubkeys** are registered, and for how long (§7.1) — the server has no
  idea what a trade is; it only maps pubkeys to tokens;
- **when to re-register** — the server forgets every token after 48 h and on every
  restart, silently (§2.5);
- **what to do on a wake** in each app state (§7.2) — the push says nothing, so the
  client must fetch, decrypt and render everything itself;
- **when to ask the server to wake a peer** — a peer's chat message is not addressed to
  the peer's trade pubkey, so the server cannot see it (§2.4); the *sender* asks;
- **what the user can turn off**, and what turning it off must clean up (§7.4).

The client does not decide:

- whether a push is delivered, when, or how many times — FCM and the OS do;
- whether the server is running at all: a push server outage must be invisible to trading;
- anything about message content: the server never sees it, and the push never carries it.

### 1.3 Non-goals

- **Rich background notifications** ("Payment received for order 7c1b…") produced while
  the app is not in the foreground. v1 does this by booting a second Dart isolate that
  opens its own relay connections and decrypts. Here that would mean a second copy of the
  Rust core writing the same database while the foreground's in-memory state goes stale
  — exactly the bug class #308 documents from v1. It is scoped as an **explicit later
  phase** (Phase 5), only after the resume-resync path exists, and only if the generic
  notification proves insufficient in the field.
- **Encrypted token registration** (MIP-05 style ECDH + ChaCha20-Poly1305). The server
  has the decryptor as dead code, publishes `encryption_enabled: false` and no public
  key; there is nothing to encrypt to yet (§14).
- **Web Push without the server.** Web is in scope (§2.6, T4.5), but it is the one
  platform that cannot ship from this repository alone: the server must accept
  `platform: web` and answer the browser's CORS preflight (§3.5). The client work is
  specified and built behind that; until the server lands, web shows the same
  "not available" row desktop does.
- **Desktop.** No push transport exists for Linux, macOS or Windows; those builds keep
  their foreground subscriptions, as today.
- **UnifiedPush.** The server supports it behind an opt-in flag that is off in
  production. Listed as an optional extension (§11, Phase 6), not a goal.
- **Server changes.** Where the server would need to change (encrypted tokens, a
  solver wake path), this document records the gap and stops. The two web changes
  (§3.5) are the exception: small, listed precisely, and asked for upstream.

---

## 2. How Mostro push works

### 2.1 Actors and what each one learns

| Actor | Sees | Never sees |
|---|---|---|
| The app | everything, on the device | — |
| `mostro-push-server` | `trade_pubkey → device token` in memory; timing of events `p`-tagged to registered pubkeys; the caller's IP | message content, sender, order, which user owns which token |
| Firebase / Google | that a push went to a device, and the device's Google identity | any Mostro data — the payload is a fixed string |
| Relays | what they already see: kind 14 ciphertext and its `p` tag | — |

The server's own invariants (its `docs/architecture.md`): the relay filter never pins
`authors`; `/api/notify` answers `202` whether the pubkey is registered or not; no
authentication, sender field or idempotency key is accepted on `/api/notify`; per-IP
and per-pubkey rate-limit responses are byte-identical; pubkeys are logged only as a
salted hash. A client must not undermine these — in particular it must **never send an
`Authorization`, `X-Request-Id` or sender field**.

**Registration takeover is an accepted limitation, not an oversight.** Because
`/api/register` and `/api/unregister` take nothing but a `trade_pubkey` — and trade
pubkeys are public, every kind-14 `p` tag on the relays names one — anyone can
overwrite a mapping with their own token or delete it. The consequence is bounded: the
attacker receives content-free pushes ("you have an update on your trade") for a key
they already knew was trading, and the victim stops being woken until their next
refresh re-installs the mapping (12 h while the app runs, the OS job of T1.5
otherwise). No message, order or identity leaks, and trading itself is unaffected: the
push is a doorbell, the relays are the delivery. The upstream fix is an ownership
proof on both endpoints (a signature by the trade key over a server nonce); it is
recorded as an ask in §14. Until it lands, this document and the Settings privacy
footnote say what a push is and is not, and never promise delivery.

### 2.2 The server, end to end

```text
   app ──POST /api/register {trade_pubkey, token, platform, mostro_pubkey}──▶ server
                                                                              │ stores in memory (48 h TTL, lost on restart)
   daemon / peer ──kind 14, p = trade_pubkey──▶ relay ──────────────────────▶ server: first p tag ∈ registered? ──▶ FCM ──▶ device
                                                                              │
   sender app ──POST /api/notify {trade_pubkey}──────────────────────────────▶ server: silent wake, always 202
```

Two ingress paths feed one dispatcher:

1. **Listener path.** The server subscribes to kinds 1059 and 14 on its relays
   (`NOSTR_RELAYS`, production `wss://relay.mostro.network`) with `since = now − 60 s`
   and **no** `authors` or `#p` filter; it matches the **first `p` tag** of every event
   against its map. A match sends a **visible** push (`type = trade_update`).
2. **Sender-triggered path.** `POST /api/notify` sends a **silent** push
   (`type = chat_wake`) to whoever is registered for the pubkey. Meant for peer-to-peer
   events the listener cannot match (§2.4).

### 2.3 What a push can carry

Nothing that varies per event. The FCM payloads (§3.2) contain a fixed title and body,
`data.type ∈ { trade_update, chat_wake }`, `data.source`, and the server's own
`data.timestamp`. There is no event id, no kind, no order id, no trade pubkey. **Every
design that keys behaviour on push payload fields beyond `type` is wrong by
construction** — including this client's current `routeFromPayload` (§5).

### 2.4 Which events reach which pubkey

This is the crux, and it differs from v1 because this client speaks protocol v2 only.

| Channel | Kind 14 `p` tag | Server can match? | Wake path |
|---|---|---|---|
| Daemon → user (every trade action, `pay-bond-invoice`, `add-bond-invoice` and the claim acks, `bond-slashed`, `restore-session` reply) | our **trade pubkey** | yes | listener |
| Peer chat (chat envelope, `mostro.network/protocol/chat.html`) | `pub(K_conv)` — an HKDF derivation of the two trade keys' ECDH secret | **no** | sender calls `/api/notify` with the **peer's trade pubkey** |
| Dispute chat (same envelope keyed to the solver's pubkey) | `pub(K_conv)` of (our trade key, solver key) | **no** | the solver's client would have to call `/api/notify` — **mostrix does not** (§14) |
| Announcements (kind 38387, #319) | none | no | not a push case |

v1 had a third case: dispute admin DMs arrived as kind 1059 `p`-tagged to the trade
pubkey, so the listener matched them. That transport is gone here (#246), which is why
dispute chat is now a documented gap rather than a working path.

### 2.5 Duplicates, loss and forgetting

- **Duplicates are normal.** The server has no event-id dedup and no per-pubkey
  cooldown; two relays delivering one event produce two pushes, and every listener
  reconnect replays the last 60 s. The wake handler must be idempotent.
- **Loss is normal.** FCM `high` priority is best effort; the OS may drop or delay. The
  push is never the only path: the resume-resync of §10 replays from relays regardless.
- **Forgetting is silent.** Tokens live 48 h from their *last registration* and vanish
  on every server restart. The client cannot observe either. Re-registration is
  therefore periodic and idempotent (§7.1), not event-driven.
- **One token per pubkey.** Registering a trade pubkey from a second device evicts the
  first. Multi-device is out of scope; a restore on a new device simply takes over.

### 2.6 Web

The browser is the one platform where the doorbell can ring with the app closed
**and** something can answer it: a service worker. FCM Web Push delivers through the
browser's push service (VAPID-keyed), to `web/firebase-messaging-sw.js`, whether the
tab is open, backgrounded or closed. What the worker may do is narrow by design:

- **Visible push (`trade_update`).** The Firebase SDK in the worker shows the
  server's `notification` block as an OS notification when no tab has focus; a
  focused tab receives `onMessage` instead, like the foreground case on mobile.
- **Silent push (`chat_wake`).** Data-only reaches the worker with no `notification`
  block, and Chrome requires a push event to end in a visible notification or it
  revokes the subscription after a few silent ones. The worker therefore shows its own
  content-free "New message" for `chat_wake` — the one place the client renders a push
  itself.
- **Tap.** The worker focuses an existing tab (or opens one) at the app's
  notifications route under the deployed base path (`/app/#/notifications`), and
  the tab's resume path does the rest. The worker never routes on payload fields:
  there are none (§2.3), and the current worker's `routeFromPayload` mirror is dead
  code to delete.
- **Never a courier.** The worker never loads the wasm core, never opens IndexedDB,
  never decrypts. Principle 2 holds on web exactly as on mobile; the tab, when it
  next runs, resyncs (§10).

Three facts shape the plan:

- **Token = Firebase token.** A web token is an ordinary FCM registration token; the
  server sends to it with the same v1 API call. What the server lacks is only the
  `platform` value and the CORS headers a browser needs to reach `/api/*` at all
  (§3.5).
- **The page is cross-origin isolated** (`SharedArrayBuffer`, `CLAUDE.md`). Every
  `fetch` from the page to the push server runs under COEP `require-corp`, so the
  server's responses must carry CORS headers for the app's origin; the worker's
  `importScripts` from `gstatic.com` are worker-scoped and not subject to the
  document's COEP, but this is one of the things T4.5 verifies against the real
  bundle rather than assumes. The worker also coexists with the isolation shim
  (`coi-serviceworker.min.js`): Firebase registers its own worker under its own scope
  (`firebase-cloud-messaging-push-scope`), and the shim's `clients.claim()` claims
  pages, not other workers — verified the same way.
- **No OS job.** There is no `workmanager` on the web. `periodicSync` exists in
  Chromium only, for installed PWAs, at the browser's discretion, so the refresh of
  §7.1 that outlives the process has nothing to run on. A web registration lives
  48 h past the last time a tab ran the app; the Settings copy on web says so.

Browser support: Chrome, Edge and Firefox on desktop and Android; Safari 16.4+ on
macOS and iOS only for an installed (home-screen) PWA, which the deployed bundle is
not today (`--pwa-strategy=none`). Safari is therefore "not available" until that
changes, and the capability check reads the `Notification` and `PushManager` APIs,
not the user agent.

---

## 3. The wire contract

Verified against `mostro-push-server` at `1ccf425` (crate 0.2.0). Production instance:
Fly.io app `mostro-push-server`, `https://mostro-push-server.fly.dev`. `push.mostro.network`
— the host this client currently points at — appears nowhere in that repository (§14).

### 3.1 HTTP endpoints

All bodies are JSON. Pubkeys are **64 lowercase hex characters**: the server stores them
byte-exact and Nostr `p` tags are lowercase, so an upper-case registration succeeds and
never matches.

**`POST /api/register`** — JSON limit 8 KiB.

```json
{ "trade_pubkey": "<64 hex>", "token": "<FCM token>", "platform": "android" | "ios",
  "mostro_pubkey": "<64 hex, optional today>" }
```

Responses: `200 {"success":true,"message":"Token registered successfully","platform":"android"}`;
`400` on a bad pubkey, empty or > 4096-byte token, non-`https`/private endpoint, or a
platform other than `android`/`ios`; `403 "Mostro instance pubkey required"` /
`403 "Mostro instance not trusted"` once the operator enables the trusted-node whitelist
(off today; the client must already send `mostro_pubkey` so that day is a no-op);
`429 {"success":false,"message":"rate limited"}` + `Retry-After`. Overwrites silently.

**`POST /api/unregister`** — `{ "trade_pubkey": "<64 hex>" }`. `200` whether the token
existed or not (`"Token not found (may have already been unregistered)"` is still
`success: true`); `400` on a bad pubkey.

**`POST /api/notify`** — JSON limit 1 KiB — `{ "trade_pubkey": "<64 hex>" }`. Always
`202 {"accepted": true}` on a parse-valid body, registered or not; `400` on a bad
pubkey; `429` as above. Fire-and-forget: `202` ≠ delivered.

**`GET /api/health`** → `{"status":"ok"}`. **`GET /api/info`** →
`{"version":"0.2.0","encryption_enabled":false,"note":"…"}` — the flag a future client
polls to learn that encrypted registration exists. **`GET /api/status`** → token counts.

### 3.2 Push payloads

Listener path (visible), as the server hands it to FCM:

```json
{ "message": { "token": "…",
  "notification": { "title": "Mostro", "body": "You have an update on your trade" },
  "data": { "type": "trade_update", "source": "mostro-push-server", "timestamp": "1736208000" },
  "android": { "priority": "high",
               "notification": { "tag": "mostro-trade", "channel_id": "mostro_notifications",
                                 "default_vibrate_timings": true } },
  "apns": { "headers": { "apns-priority": "10", "apns-collapse-id": "mostro-trade" },
            "payload": { "aps": { "alert": { "title": "Mostro", "body": "You have an update on your trade" },
                                  "content-available": 1, "mutable-content": 1, "thread-id": "mostro-trade" } } } } }
```

`/api/notify` path (silent):

```json
{ "message": { "token": "…",
  "data": { "type": "chat_wake", "source": "mostro-push-server", "timestamp": "1736208000" },
  "android": { "priority": "high" },
  "apns": { "headers": { "apns-priority": "5", "apns-push-type": "background" },
            "payload": { "aps": { "content-available": 1 } } } } }
```

Consequences the client must design around:

- The visible push names Android channel **`mostro_notifications`** and tag
  `mostro-trade`. If the app never creates that channel, Android 8+ renders the push on a
  default channel with the default importance — and a user who has muted or deleted the
  channel silences every trade update. The app must create it at startup with the
  importance it wants (§9).
- The visible push is rendered by the OS when the app is not running: **Android shows
  "You have an update on your trade" even if nothing else happens.** That is the
  fallback MIP-05 asks for, and it is what makes Phase 2 useful before any background
  processing exists.
- The silent push renders nothing anywhere. If the app process is dead, Android may or
  may not start it for a data-only high-priority message (OEM dependent); iOS only
  delivers `content-available` opportunistically. A chat wake is therefore best effort
  by design.
- No `ttl` / `collapse_key` on Android: stale pushes can arrive in a burst when the
  device comes online; the wake handler must coalesce.

### 3.3 Limits

| | Value |
|---|---|
| Token TTL | 48 h from last `register`, not refreshed by traffic |
| `register` + `unregister` | 120/min per IP, burst 100 |
| `notify` | 30/min per pubkey (burst 10); 120/min per IP (burst 30) |
| Timeouts | none server-side; the client should use ~10 s |
| Persistence | none: a restart drops every registration |

### 3.4 Platform matrix (this client)

| Platform | Transport | Status after this plan |
|---|---|---|
| Android | FCM (`google-services.json` for `foundation.mostro.app` is committed) | full |
| iOS | APNs via FCM — needs an APNs key in the Firebase project, `aps-environment`, `GoogleService-Info.plist` | full, once configured (T4.4) |
| Web | FCM Web Push (VAPID) via `web/firebase-messaging-sw.js`; Chrome, Edge, Firefox; Safari only as an installed PWA | full for the visible wake and the chat wake, once the server accepts `web` and answers CORS (§3.5, T4.5); no refresh outlives the tab |
| Linux / macOS / Windows | — | none; foreground subscriptions only |

### 3.5 Server changes web needs

Both are small, and both are prerequisites this client cannot work around. Proposed
upstream as [mostro-push-server#44](https://github.com/MostroP2P/mostro-push-server/issues/44):

1. **Accept `platform: "web"`** in `/api/register` (`Platform` enum, the
   `android`/`ios` validation in `routes.rs`, the `/api/status` counts). The FCM v1
   send is unchanged; optionally add a `webpush` block with
   `notification.tag = "mostro-trade"` so repeated pushes collapse in the browser
   the way `apns-collapse-id` does on iOS.
2. **CORS for the app's origin** on `/api/register`, `/api/unregister` and
   `/api/notify`: answer `OPTIONS` preflights and send `Access-Control-Allow-Origin`
   for `https://mostro.network` (and a configurable list for forks and local runs),
   with `Content-Type` as an allowed header. Without it the browser blocks the call
   before it leaves, and the isolated page's COEP makes the block absolute. The
   server today has no CORS layer (`actix-web` without `actix-cors`).

---

## 4. How the v1 client does it

Verified on `MostroP2P/mobile` at `637fd43` (v1.4.2). File paths below are v1's.

### 4.1 Setup

FlutterFire config for project `mostro-mobile` (`firebase.json`,
`lib/firebase_options.dart`, `android/app/google-services.json` — committed, "public
credentials"). `firebase_core 4.3`, `firebase_messaging 16.1`,
`flutter_local_notifications 19.4`, `flutter_background_service 5.1`. Android manifest
declares `POST_NOTIFICATIONS`, `FOREGROUND_SERVICE(_DATA_SYNC)`, `WAKE_LOCK`,
`REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, `RECEIVE_BOOT_COMPLETED`, the background
service (`foregroundServiceType="dataSync"`) and the local-notifications receiver.
**iOS is not wired**: no entitlements file, no `GoogleService-Info.plist`, no
`FirebaseApp.configure()`; only `UIBackgroundModes` is set. Linux is gated out in three
places (`firebase_options.dart` throws for it).

### 4.2 Startup order (`lib/core/app_bootstrap.dart`)

permissions prompt → prefs/DBs → settings → `initializeNotifications()` (local) →
background service `init()` → **`FCMService.initialize()`** (Firebase init, permission
request, `getToken()` stored under `fcm_token`, refresh listener, foreground listener,
`onBackgroundMessage` registered last) → `PushNotificationService.initialize()`
(`GET /api/health` must return 200) → `onTokenRefresh = reRegisterAllTokens` →
`runApp`. Every Firebase failure is swallowed; the app continues without push.

### 4.3 Registration (`lib/services/push_notification_service.dart`)

- Server URL: `String.fromEnvironment('PUSH_SERVER_URL', 'https://mostro-push-server.fly.dev')`.
- `registerToken(tradePubkey)` posts `{trade_pubkey, token, platform, mostro_pubkey?}`,
  10 s timeout, accepts `202` unconditionally and `200` with `success: true`; on any
  failure logs and returns `false` — **no retry, no persistence**. Gated on the
  settings toggle. Keeps registered pubkeys in an **in-memory set**.
- **When:** only from `SessionNotifier` — on every `saveSession` (take, create
  confirmation, restore writes), on child-order sessions (range orders) and their id
  link. `SessionNotifier.init()` (app start) registers nothing, so restored sessions
  are only re-registered when something saves them again.
- **Unregister:** `unregisterAllTokens()` is called only when the user turns the
  toggle off. Nothing unregisters on trade end, session deletion or expiry.
- `reRegisterAllTokens()` on token refresh loops the in-memory set — empty after a
  restart.
- Plaintext tokens; the class doc and the docs defer encryption to a "Phase 5" that
  the server has not shipped either.

### 4.4 Chat wake (`notifyPeer`)

`ChatRoomNotifier.sendMessage` → after a successful publish,
`unawaited(notifyPeer(session.peer.publicKey))` — the **counterparty's trade pubkey**,
5 s timeout, `202`/`400`/`429`/errors all logged and ignored. Not gated on the receive
toggle (it is the peer's setting that matters). Dispute chat does not call it: in v1 the
admin's DM was a kind 1059 the listener matched.

### 4.5 The background handler and isolate

`firebaseMessagingBackgroundHandler` (`@pragma('vm:entry-point')`,
`lib/services/fcm_service.dart`): records `fcm.last_wake_timestamp` (never read), then
if `flutter_background_service` is running, `invoke('fcm-wake')` (a no-op log);
otherwise starts it, waits for `handlers-registered`, sends `start` with the persisted
settings, waits for `service-ready` (5 s + 3 s retry, then `stop`). ≈ 8–13 s of awaits,
near Android's budget for a background handler.

The service isolate (`lib/background/background.dart`) is a **second copy of the
protocol stack**: its own `NostrService`, `SessionStorage`, `KeyManager`, DB handles
and a TTL session cache (no Riverpod). It restores the relay filters the foreground
persisted on pause (`kinds:[14], authors:[mostro], #p: tradeKeys, since` for orders;
`kinds:[14], authors:[K_sign]` for chat), decrypts each event (admin envelope → peer
envelope → trade-key DM, in that order), dedups against `events.db`, learns the peer
from `buyerTookOrder`/`holdInvoicePaymentAccepted` and opens a chat subscription from
the background, persists chat markers for cross-restart dedup, and shows a
`flutter_local_notifications` heads-up on channel `mostro_notifications`
(`Importance.max`, tag/group `mostro-trade`, id = event id hash). Localized copy is
hand-switched per language inside the isolate. Tap payloads `{"type":"peer_chat"|"admin_dm", orderId, disputeId}`
route to `/chat_room/:id`, `/dispute_details/:id` or `/trade_detail/:id`; a cold-start
tap is consumed once in `app.dart`.

`LifecycleManager` debounces 2 s, persists the active filters, suspends foreground
subscriptions and starts the service on pause; on resume it clears the filters and stops
the service. `isAppForeground` defaults to `false` in the isolate.

### 4.6 Settings

`pushNotificationsEnabled` (default `true`), sound and vibration toggles, a
platform-unsupported banner and a privacy card. Disabling unregisters every pubkey in
the in-memory set and deletes the FCM token; re-enabling registers nothing until the
next `saveSession`. Sound/vibration are persisted but the isolate hardcodes both on.

### 4.7 What v1 gets wrong (and this plan must not repeat)

| # | v1 gap | Where |
|---|---|---|
| 1 | Registered set is in memory: after a restart, token refresh re-registers nothing and opt-out unregisters nothing | `push_notification_service.dart:60` |
| 2 | Restored sessions are never registered; a failed registration is never retried | `session_notifier.dart:171-198,426-432` |
| 3 | Nothing unregisters on trade end; the server keeps waking the device for finished trades until the TTL | only `settings_notifier.dart:182-186` |
| 4 | iOS unconfigured while `platform: "ios"` is still sent | `AppDelegate.swift`, no entitlements |
| 5 | Privacy copy claims "Device tokens are encrypted before registration"; they are not | `intl_en.arb:1585` |
| 6 | Two protocol stacks (foreground + isolate) with hand-wired resume refresh — the dispute-chat bug of mobile#675 | `lib/background/`, `lifecycle_manager.dart` |
| 7 | Sound/vibration settings are dead; disabling push does not stop local notifications | `background_notification_service.dart:183-184` |
| 8 | `initialize()` needs `/api/health` = 200 at startup; `notifyPeer` bypasses it | `push_notification_service.dart:107-134` |
| 9 | Background handler start handshake ≈ 13 s of awaits; `invoke('stop')` on a missing-settings path can tear down a service another caller started | `fcm_service.dart:79-128` |
| 10 | `isAppForeground` defaults to `false` in the isolate: a wake while foregrounded double-notifies | `background.dart:28` |

---

## 5. Where this client stands today

Verified on `main` at the time of writing.

| Area | State | Where |
|---|---|---|
| Firebase deps | `firebase_core ^3.6`, `firebase_messaging ^15.1`, `flutter_local_notifications ^17.2` (unused) | `pubspec.yaml` |
| Firebase config | `lib/firebase_options.dart` generated; `android/app/google-services.json` for `foundation.mostro.app` committed; **no** iOS plist, entitlements or APNs; `firebase_options.dart` carries real **web** options (`1:375342057498:web:…`) but `web/firebase-messaging-sw.js` has `REPLACE_ME` config, a `routeFromPayload` mirror for fields the server never sends, and no base-path awareness, and the VAPID key is a placeholder (#133) | `lib/`, `android/app/`, `web/firebase-messaging-sw.js` |
| Init | `Firebase.initializeApp` in `app_bootstrap.dart` (failure logged, push disabled); `PushNotificationService.initialize()` after the first frame in `app.dart` | `lib/core/app_bootstrap.dart:56-64`, `lib/core/app.dart:30-36` |
| Permission | `requestPermission` in `initialize()`; denied-banner + retry via `notificationPermissionDeniedProvider` (10d) | `push_notification_service.dart`, `notification_permission_provider.dart` |
| Token | `getToken()` on Android/iOS, skipped on web (placeholder VAPID); refresh → `reRegisterAllTokens()` over an **in-memory set** | `push_notification_service.dart:75-110` |
| Registration | `registerToken` / `unregisterToken` post the v1 shapes to `https://push.mostro.network` — **no caller anywhere**; `mostro_pubkey` not sent | `push_notification_service.dart:41,180-220` |
| Foreground message | builds an in-app `NotificationModel` from `data.type` / `data.orderId` / `data.disputeId` and gates it on the four event toggles | `_handleForeground` |
| Background message | `debugPrint` no-op (`_backgroundMessageHandler`) | `push_notification_service.dart:16-19` |
| Tap routing | `routeFromPayload` maps `tradeUpdate` / `invoiceRequest` / … + `orderId` to routes — **fields the server never sends**; dead code against this server | `push_notification_service.dart:305-340` |
| `/api/notify` | absent | — |
| Settings | 10d screen: four event toggles (`notify_trade_updates`, `notify_new_messages`, `notify_payments`, `notify_disputes`), denied banner, privacy footnote ("Notifications carry no amounts and no counterparties…"). **No master push toggle**; toggles gate in-app cards, and "Choose which events trigger push notifications" over-promises | `notification_settings_screen.dart`, `notification_prefs_provider.dart` |
| In-app notifications | fed from Rust streams in the foreground (trade updates, bond slashed, claims, …) | `app_bootstrap.dart`, `notifications_provider.dart` |
| App lifecycle | none — no `WidgetsBindingObserver`, no resume resync (#308) | — |
| Rust | `reqwest` (rustls on native, JSON on web) already a dependency; `global_dm_keys` holds every derived trade key; `status_cursor:` / `chat_cursor:` cursors persisted; `flush_message_queue()` exists; no `resync()`, no push module | `rust/Cargo.toml:81`, `rust/src/api/orders.rs:6605-6680`, `rust/src/api/nostr.rs:341` |
| Spec | `contracts/nostr.md` lists `register_push_token(token, platform)` as a Rust bridge call — never implemented | `specs/004-…/contracts/nostr.md:209-217` |

Summary: Firebase is wired up to the point of holding a token, and nothing after that
exists. The parts that do exist (`routeFromPayload`, per-type push gating) were written
against an imagined typed payload and must be retired, not built on.

---

## 6. Design principles for the v2 implementation

1. **Rust owns the registration state; Dart owns the device.** Which pubkeys are
   registered, when they are re-registered, what is unregistered on opt-out and what
   survives a restart is protocol-adjacent state that lives next to `global_dm_keys` and
   the trade rows — in Rust, persisted in the settings store, with the HTTP calls made
   by the `reqwest` client the crate already has. Dart's job is the device: obtain the
   FCM token, forward it (`set_push_token`), receive the wake, show the OS notification,
   report lifecycle events. No Dart code decides *which* pubkey to register.
2. **The push is a doorbell, never a courier** (#308). The FCM background handler
   stays display-only: it never initialises the Rust core, never opens the database,
   never decrypts. Every state change comes from the one Rust core, in the foreground,
   through the resume-resync path. Phase 5 may revisit this deliberately; until then a
   review rule and a test enforce it.
3. **Register what the DM filter covers, no more — and make the filter cover what is
   registered.** The set of registered pubkeys is derived from the same facts the
   kind-14 filter is built from: the trade keys of non-terminal trade rows and the
   `trade_index` of non-terminal payout claims. A live dispute adds nothing: its row
   reads `Dispute`, which is not terminal, and an admin outcome ends both; the
   in-memory dispute record is not consulted, since one never marked resolved would
   keep a finished trade's key registered for good. A key drops off when its row turns
   hard-terminal (plus a grace period, §7.1). Never "all keys `1..=trade_key_index`": the server keeps one token per
   pubkey and every registration costs a request. The converse holds too: a wake for a
   key whose daemon the filter no longer listens to is a wake the app cannot act on,
   so the filter's `authors` must include the **issuing node of every registered
   key**, not only the active node and the claim nodes it pins today (§7.1).
4. **Re-registration is periodic and idempotent, not event-driven.** The server forgets
   silently (§2.5); the client re-registers on start, on resume after a threshold, on
   token refresh, and on a timer, and treats every `200` as an overwrite. Failures
   are retried with backoff and never surfaced as errors — a push server outage must
   not touch trading.
5. **Content-free in both directions.** Nothing in a wake handler reads payload fields
   other than `type`. Nothing the client sends carries a sender, an order or an auth
   header. The privacy footnote in Settings must state exactly what is true.
6. **Opt-out is complete and durable.** Turning push off unregisters every pubkey the
   persisted state knows about — including those registered before the last restart —
   deletes the FCM token, and stops re-registration until turned on again; turning it
   on re-registers the current set immediately.
7. **Peer wake is the sender's duty, gated only by support.** After publishing a chat
   message the client calls `/api/notify` for the peer's trade pubkey whether or not
   *our* push is enabled: it is the peer's setting that decides if anything is shown.
8. **Fail open, log everything.** No push failure is fatal, none is shown to the user
   except the two `403`s (the operator refusing this node), which become a persistent,
   dismissible in-app notice.
9. **Atomic PRs.** Each PR in §11 compiles, passes `cargo test && cargo clippy`,
   `flutter analyze && flutter test`, and leaves the app fully functional with push
   disabled, unsupported, or with the server down.

---

## 7. Client flows

### 7.1 Flow 1 — Registration lifecycle

**Inputs.** The FCM token and platform (Dart → `set_push_token(token, platform)`), the
push-enabled setting, the active node pubkey, and the **registration set** computed in
Rust:

```text
wanted = { trade key of every trade row whose order.status is not hard-terminal }
       ∪ { key(trade_index) of every BondClaim whose phase is not terminal }
       ∪ { trade key of every trade with an open dispute }
```

plus, from the registration state itself, every key that left that set less than
**GRACE (24 h)** ago. The grace covers what still arrives after a terminal status:
`rate-received`, a late `bond-slashed`, an admin outcome, the daemon's `Success` after
`SettledHoldInvoice`. Its clock is **not** the trade row: `TradeInfo.completed_at` is
never written by the status syncs, and a terminal timestamp added to every write
path would be one more thing to keep atomic. Instead the registration records when
the key first went unwanted (`unwanted_since`, below); a key seen unwanted for longer
than the grace is unregistered and forgotten. Restart-safe, because the registration
map is persisted. A key that turned terminal before this feature existed has no
timestamp and gets the full grace from the first reconcile that sees it.

**State.** Per pubkey, persisted: `registered_at` (the **client's** clock when the
`200` arrived — the response carries no server time, and the same clock is `now` in
every rule below; a clock that reads earlier than `registered_at` is a rollback, and
the key is due for refresh at once rather than "in 12 h from a future date"),
`token_hash` (which token it was registered with), `mostro_pubkey` (the issuing node
it was filed under), `unwanted_since` (when it first dropped out of the wanted set,
`None` while wanted), `attempts` and `next_attempt_at` for backoff. Settings key `push_registrations` (one JSON map), plus `push_token` /
`push_platform` (so a restart can unregister before the device hands a token over
again) and `push_enabled`.

**Reconcile** (`push::reconcile()`, idempotent, single-flight):

1. If disabled or no token: unregister everything still marked registered, stop.
2. For each `wanted` pubkey: register if never registered, registered with another
   token, or `registered_at` older than **REFRESH = 12 h** (a quarter of the server
   TTL), or `next_attempt_at` has passed after a failure.
3. For each registered pubkey not in `wanted`: set `unwanted_since` if unset; once
   `now − unwanted_since > GRACE`, unregister, then forget. A key that comes back
   into `wanted` (a restore, a re-taken order on the same key) clears the timestamp.
4. Every request: 10 s timeout, lowercase hex, `mostro_pubkey` = the **issuing node
   of that key**, read from the owning row or claim: `order.creator_pubkey` for a
   trade row, `claim.node_pubkey` for a claim. The field only gates the operator's
   whitelist, it does not route — but a registration filed under the wrong node is
   refused, or accepted, under the wrong policy, and a refusal must be recorded
   against the node that earned it. Backoff on failure: 1 min → 5 → 30 → 2 h, capped;
   `429` honours `Retry-After`; `403` marks **that node** refused
   (`push_node_refused:<node>` = now) and reconcile skips its keys. The refusal
   **clears** on the first of: 24 h since it was recorded (the next reconcile retries
   once, and a repeated `403` re-arms it for another 24 h), the user turning the
   master toggle on, or the user selecting that node as the active one — the two
   explicit "try again" gestures. A refusal survives a restart until one of those;
   nothing else reads or writes the key, so there is no implicit clear.

**The issuing node is on the row.** A taken order's row already carries the node in
`order.creator_pubkey` (the 38383 author, #334). A maker's row does **not** today:
`create_order` and the restore placeholder write an empty `creator_pubkey`, and a
maker trade on node A becomes anonymous after a switch to B — its daemon events are
then unreachable, push or no push. T1.2 therefore seeds `creator_pubkey` with the
active node on both paths (consistent with the book, where the user's own order is
also authored by the node) and treats a legacy row with an empty `creator_pubkey` as
the active node's. The same value feeds the DM filter's `authors` (next paragraph).

**Triggers.** App start (after the DB and identity are up), `set_push_token`,
`set_push_enabled(true)`, every trade row write that changes `wanted` (take, create
confirmation, restore, terminal status, claim upsert), resume (Flow 2), and a timer
every 6 h while the app runs. Coalesced: a burst of triggers runs one reconcile.

**The refresh must outlive the process.** None of those triggers fires while the app
is suspended or not running, and the OS suspends Dart timers with it. The server
forgets a token 48 h after its last registration; a user who does not open the app
for two days is then unreachable for every later event — including a payout claim
whose window is 15 days. That defeats the "not running" case the whole feature
exists for, so the refresh gets an **OS-scheduled job** (T1.5): `workmanager` on
Android (periodic, ≥ 15 min granularity, run every 12 h), `BGAppRefreshTask` on iOS
(opportunistic; the OS decides, so the 12 h is a request). The job does one thing:
re-POST every registration in the persisted map with the persisted token. It does
**not** boot the Rust core, open the database or touch protocol state — it reads a
small JSON mirror Rust writes next to the settings store (`push_registrations` and
`push_token`, nothing else) and calls the same HTTP endpoints. That keeps principle 2
intact: the job is HTTP plumbing, not a second writer. Until T1.5 lands, the
limitation is stated in Settings (*"Pushes stop 48 h after the app was last
opened"*) and in §14; the durable fix is a longer server TTL or persistence, which
is an upstream ask (§14 item 10).

**Node switch.** `wanted` is node-agnostic: a trade or claim from node A stays wanted
after a switch to B, and nothing is unregistered on a switch. For that to mean
anything the DM filter must still hear A. Today `replace_global_dm_filter` pins
`authors` to the active node plus the nodes with open claims (`orders.rs`), so a
non-terminal trade from A is deaf after a switch — a wake for it would land on a
subscription that drops A's events. T1.2 extends `authors` with the issuing node of
every non-terminal trade row (the same set `wanted` is built from), so registration
and delivery coverage are computed from one source and cannot drift.

### 7.2 Flow 2 — A wake, per app state

| App state | What arrives | What the client does |
|---|---|---|
| Foreground | `onMessage` | nothing visible: the foreground subscription already delivers the event and the in-app card. Bump a `last_push_at` diagnostic; if the relay pool is not `Connected`, nudge a reconnect. |
| Background, process alive | `onBackgroundMessage` (`trade_update` also rendered by the OS) | handler is **display-only**: record `wake_pending = true` in prefs; nothing else. On resume the lifecycle service runs `resync()` (§10) and hydrates. The OS notification is the user's cue. |
| Not running | OS renders the visible push; tap launches the app | cold start → normal startup already replays everything; the launch-from-notification is consumed as "open `/notifications`" after the first frame. |
| `chat_wake` while backgrounded | silent; may not start a dead process | same as above minus the OS cue: `wake_pending`, resync on resume. If the process is alive and Android allows it, the handler may show a **local** "New message" notification — still content-free (Phase 3). |
| **Web**, tab focused | `onMessage` | as Foreground. |
| **Web**, tab open but hidden, or closed | the service worker's push event | the worker shows the OS notification (`trade_update`: the server's block; `chat_wake`: its own content-free "New message"); a tap focuses or opens the app at `/app/#/notifications`; the tab's `hidden → resumed` (or cold start) resyncs. Nothing is written by the worker. |

Tap routing: with no payload to route on, a tap opens the app on **`/notifications`**
(cold) or brings it to the foreground (warm); the in-app notifications list — fed by the
resync — is where the specific event appears. `routeFromPayload` and `_typeFromString`
are deleted.

### 7.3 Flow 3 — Waking a peer after a chat message

In `send_message` (Rust, after `publish` succeeds and the outbox marks it sent): if push
is supported on this platform, `POST /api/notify { trade_pubkey: peer_trade_pubkey }` —
5 s timeout, one attempt, result ignored except `400` (a client bug, logged at warn).
Not gated on our own `push_enabled`. Debounced per order: at most one notify per
**10 s** per peer, so a burst of short messages costs one wake and stays far under the
30/min per-pubkey limit. The peer's trade pubkey is `TradeInfo.counterparty_pubkey`,
which is empty before the peer reveal (#334) — no reveal, no notify.

Dispute chat: **not wired**. The solver's envelope is `p`-tagged to `pub(K_conv)`, and
the solver client does not call `/api/notify`. Recorded in §14 as an upstream ask; the
user's own evidence sends do not need a wake (the solver is not a push client).

### 7.4 Flow 4 — Opt-out and permission

- **Master toggle off** → `set_push_enabled(false)`: reconcile unregisters every
  persisted registration (whatever run made it), then Dart calls `deleteToken()` and
  forgets `push_token`. The four event toggles stay as they are: they gate the **in-app
  cards**, and their subtitle says so.
- **Master toggle on** → `set_push_enabled(true)`, Dart re-acquires the token,
  `set_push_token`, reconcile registers the current set.
- **OS permission denied** (10d banner, exists): no token is requested; the Rust side
  sees no token and keeps nothing registered. When the user grants it in system
  settings, the existing `retryInitialize()` path produces a token and reconcile runs.
- **Unsupported platform** (desktop; web when the browser lacks `Notification` /
  `PushManager`, or until the server accepts `web`): `set_push_token` is never
  called; the settings screen shows the unsupported state instead of the toggle.
  Capability is a **Dart fact** (the platform, and on web the APIs the browser
  exposes), read from `PushNotificationService.isSupported` (made public), never
  inferred from "no token": a denied permission also yields no
  token and must show the denied banner, not unsupported copy.

### 7.5 Flow 5 — Token refresh

`onTokenRefresh` → `set_push_token(new)`. Reconcile sees every registration bound to
the old `token_hash` and re-registers all of them (one request each, rate limit is
120/min — the set is small by construction). The old token is not unregistered: the
server overwrites per pubkey.

### 7.6 Flow 6 — Restore session and reinstall

After `restore_session` writes its rows, `wanted` changes and reconcile registers
them. A fresh device registering a pubkey the old device still holds simply takes over
(one token per pubkey). Identity deletion (`delete_identity`) unregisters everything
first, then clears the push settings — a key the user no longer holds must not keep
waking the device.

---

## 8. Data model

### 8.1 Rust — `rust/src/api/push.rs` (new) and `rust/src/mostro/push.rs` (new)

```rust
/// One registered trade pubkey, as persisted in `push_registrations`.
pub struct PushRegistration {
    pub trade_pubkey: String,     // 64 lowercase hex
    pub registered_at: i64,       // unix seconds of the last 200
    pub token_hash: String,       // blake3/sha256 of the token it was registered with
    pub mostro_pubkey: String,    // the issuing node it was filed under
    pub unwanted_since: Option<i64>, // first reconcile that found it unwanted; the grace clock
    pub attempts: u32,
    pub next_attempt_at: i64,
}

pub enum PushPlatform { Android, Ios, Web }   // Web: wire value "web" (§3.5)

/// What Settings shows (docs/PUSH_NOTIFICATIONS.md §9).
pub struct PushStatus {
    pub enabled: bool,
    pub has_token: bool,          // a device token is held (Dart handed one over)
    pub registered: u32,          // pubkeys currently registered
    pub wanted: u32,
    pub last_success_at: Option<i64>,
    pub last_error: Option<String>,   // stable marker, never prose
    pub node_refused_until: Option<i64>, // a 403 for the active node, and when it clears
}
```

Three states, three sources, never conflated: **capability** (can this platform
push at all) is Dart's `PushNotificationService.isSupported`; **permission** is the
existing `notificationPermissionDeniedProvider`; **token** is `PushStatus.has_token`.
Settings picks its branch in that order (§9.1).

Settings keys (`db/mod.rs::settings_keys`): `push_enabled` (`"true"`/`"false"`,
default true), `push_token`, `push_platform`, `push_registrations` (JSON map keyed by
pubkey), `push_node_refused:<node>` (unix seconds of the 403; cleared per §7.1).

Pure functions in `mostro/push.rs`, unit-tested without I/O: `wanted_pubkeys(trades,
claims, disputes, now)`, `plan(wanted, registrations, token_hash, now) → Vec<Action>`
(`Register` / `Unregister` / `Forget`), `backoff(attempts) → Duration`,
`notify_allowed(last_notify_at, now)`.

HTTP in `api/push.rs` behind a `PushServer` trait (`register`, `unregister`,
`notify`) so tests inject a fake and the wasm build compiles a stub.

### 8.2 Bridge surface — `rust/src/api/push.rs`

| Function | Purpose |
|---|---|
| `set_push_token(token: String, platform: PushPlatform)` | Dart hands the device token over; persists it; triggers reconcile |
| `clear_push_token()` | after `deleteToken()` |
| `set_push_enabled(enabled: bool)` | the master toggle; triggers reconcile (which unregisters on `false`) |
| `get_push_status() → PushStatus` | Settings screen |
| `reconcile_push() → ()` | explicit trigger (resume, debug) |
| `on_push_status_changed() → Stream<PushStatus>` | keeps the screen live |
| `resync() → ()` | **#308**: reconnect nudge, resubscribe from cursors, flush outbox, then reconcile; idempotent |

`register_push_token(token, platform)` in `contracts/nostr.md` is superseded by the
first row and the contract is rewritten (T1.4).

### 8.3 Dart

- `PushNotificationService` shrinks to the device side: Firebase init, permission,
  `getToken`/`onTokenRefresh` → `set_push_token`, `deleteToken`, the display-only
  background handler, the launch-from-notification hook. The in-memory pubkey set,
  `registerToken`/`unregisterToken`, `routeFromPayload`, `_typeFromString`,
  `_defaultTitle/Body` and `_isTypeEnabled` are deleted.
- `AppLifecycleService` (#308): `WidgetsBindingObserver` with injected platform
  predicate and handlers; `paused → resumed` (debounced, latched) calls `resync()` and
  then every registered `hydrate()`.
- Local notification channel `mostro_notifications` created at startup
  (`flutter_local_notifications`, already a dependency) with `Importance.high`, so the
  server's visible push lands on a channel the app owns.
- Settings: `pushEnabledProvider` backed by `get_push_status()` / `set_push_enabled`.

---

## 9. UI surfaces

### 9.1 Notification settings (10d, exists)

- **New master row** "Push notifications" with the toggle, above the four event rows.
  Subtitle states the fact: *"Wakes the app when a trade or chat message arrives. The
  notification itself carries nothing."*
- The four event rows keep working as they do (in-app cards). Their header changes
  from "Choose which events trigger push notifications" to *"Choose which events show
  a notification in the app"* — the current copy promises per-type push filtering that
  a content-free push cannot deliver.
- **Status line** under the toggle from `PushStatus`: *"Registered for N trades"*,
  *"Last registered 3 h ago"*, or one of the markers mapped to copy:
  `PushServerUnreachable` (*"Push server unreachable — retrying"*), `PushNodeRefused`
  (*"This Mostro node is not accepted by the push server"*), `PushRateLimited`.
- The **denied banner** (exists) is unchanged.
- **Unsupported platform** (desktop, or a browser without push, from `isSupported`,
  checked first): the master row is replaced by an info row *"Push notifications are
  not available on this platform"*; the event rows stay. On a supported browser the
  row is the normal toggle, with one extra line: *"Stops 48 h after this tab last
  ran Mostro"* — the refresh has nothing to run on when the tab is closed (§2.6). Checked before permission and before the
  token, so a denied permission on a phone keeps its banner and a phone that has
  not handed a token over yet shows the toggle, not unsupported copy.
- The **privacy footnote** (exists) is kept and extended with the one true sentence
  about transport: *"A push travels through Google's servers and says only that there
  is something to see."* No sentence about token encryption.

### 9.2 Notifications screen

Launch-from-notification lands here. No new card type: what the wake was about shows up
as the ordinary in-app cards produced by the resync (trade update, new message, claim,
slash…).

### 9.3 The OS notification

Rendered by Android/iOS from the server's payload, not by the app. The app owns only
the **channel** (`mostro_notifications`, name "Mostro", high importance, default
sound/vibration) and, in Phase 3, an optional local *"New message"* on a `chat_wake`
while the process is alive. Neither ever names an order, an amount or a counterparty.

---

## 10. Lifecycle, restart and resilience

- **Resume** (#308): `AppLifecycleService` → `resync()` in Rust: nudge the relay pool
  out of backoff, re-issue the global DM filter and every chat/dispute subscription from
  their persisted cursors (`status_cursor:`, `chat_cursor:`), flush the outbox, run
  `reconcile_push()`, return. Dart then re-hydrates every protocol-state notifier from
  bridge queries. `wake_pending` is cleared. This path is what makes the doorbell
  sufficient: whatever the push was about is replayed here, once, by the one core.
- **Restart:** `push_registrations` is loaded before the first reconcile; a token
  refresh or an opt-out after a restart therefore acts on the full set — v1 gap #1.
  Startup runs reconcile after identity and DB init and **after** the DM filter is
  seeded, never before (a registration for a key the filter does not cover is a wake
  the app cannot act on).
- **Server restart / TTL:** the 12 h refresh bounds the blind window to 12 h while
  the app runs; the resume trigger shortens it to "the next time the app is opened";
  the OS-scheduled job of T1.5 keeps it bounded while the app is suspended or not
  running, within what the OS grants. A server restart is the one case nothing
  shortens: every registration is gone until the next refresh, whichever fires
  first. All of it is invisible to the user.
- **Server down at startup:** no `/api/health` gate (v1 gap #8). Reconcile fails
  its first request, backs off, and the app trades normally.
- **Duplicate and stale pushes:** `wake_pending` is a flag, not a counter; ten pushes
  cost one resync.
- **Web:** `resync()` runs on `visibilitychange` through the same lifecycle events,
  which is also what runs after a notification tap focuses the tab. The service
  worker rings the bell and shows the notification; the tab does every write. A
  closed tab has no refresh (§2.6): the registration ages out 48 h after the last
  run, and the next run re-registers.

---

## 11. Implementation plan — phases, tasks, PRs

Conventions:

- One PR per line in the "PR" column; several low-complexity tasks may share a PR
  **only when they touch the same layer and the PR description argues why**. Every PR
  description carries Summary, Test plan and a numbered **Manual testing** section.
- Branch names `feat/push-<phase>-<short>`; commits `feat(push): …` / `fix(push): …`;
  every PR links this document and the issue it closes.
- Order of landing is the order below unless stated "orthogonal".
- After every phase the app must be fully functional with push disabled, on an
  unsupported platform, and with the push server unreachable.
- The Rust half of a phase is always mergeable before its Dart half.

### Phase 0 — Lifecycle foundation (closes #308)

Nothing push-specific; the prerequisite that makes a doorbell enough.

| Task | Scope | Files |
|---|---|---|
| T0.1 | `resync()` in Rust: reconnect nudge, re-issue the global DM filter and chat/dispute subscriptions from persisted cursors, `flush_message_queue`; single-flight, idempotent; unit tests with a fake pool | `rust/src/api/nostr.rs`, `rust/src/api/orders.rs`, `rust/src/api/messages.rs` |
| T0.2 | `AppLifecycleService`: `WidgetsBindingObserver`, injected platform predicate, `paused → resumed` latch + debounce, calls `resync()` then the registered `hydrate()` hooks; registered in `app_bootstrap.dart`; widget test driving `AppLifecycleState` | `lib/core/lifecycle/app_lifecycle_service.dart`, `lib/core/app_bootstrap.dart` |
| T0.3 | `hydrate()` on the notifiers that hold protocol state today (trades, notifications, disputes, chat), reusing their cold-start query path; regression test: events seeded into a fake bridge between `paused` and `resumed` are visible after resume | `lib/features/*/providers/` |

- **PR-0a** — T0.1 (Rust). One task, one PR.
- **PR-0b** — T0.2 + T0.3 (Dart). Justification: the service is untestable without at
  least one hydration hook, and the hooks are meaningless without the service.

Acceptance: backgrounding the app during a trade and resuming after the daemon moved it
shows the new status without a restart; the same on web after a throttled tab.

### Phase 1 — Registration, Rust-owned

| Task | Scope | Files |
|---|---|---|
| T1.1 | `mostro/push.rs`: `PushRegistration` (with `mostro_pubkey`, `unwanted_since`), `wanted_pubkeys`, `plan`, `backoff`, `notify_allowed`, settings keys; unit tests for every rule in §7.1 (grace from `unwanted_since` and its reset, legacy key with no timestamp, refresh, token change, per-node 403 refusal, node-agnostic wanted set, `mostro_pubkey` from the owning row or claim) | `rust/src/mostro/push.rs`, `rust/src/db/mod.rs` |
| T1.2 | `api/push.rs`: `PushServer` trait + `reqwest` impl (10 s timeout, lowercase hex, `mostro_pubkey`, `Retry-After`), wasm stub; `reconcile_push` single-flight with the triggers of §7.1 (trade row writes, claim upserts, restore, timer); `set_push_token`, `clear_push_token`, `set_push_enabled`, `get_push_status`, `on_push_status_changed`; `delete_identity` unregisters first; `resync()` calls reconcile. **Issuing node on every row**: `create_order` and the restore placeholder seed `order.creator_pubkey` with the active node, an empty legacy value reads as the active node; **DM filter `authors`** extended with the issuing node of every non-terminal trade row, so a registered key is always one the filter can hear; the JSON mirror of §7.1 written on every reconcile | `rust/src/api/push.rs`, `rust/src/api/orders.rs`, `rust/src/api/bond.rs`, `rust/src/api/identity.rs` |
| T1.3 | Dart: `PushNotificationService` reduced to the device side; `set_push_token` on token and refresh; delete `routeFromPayload`, `_typeFromString`, `_isTypeEnabled`, `registerToken`, `unregisterToken`, the in-memory set; push server URL moves to Rust config (`PUSH_SERVER_URL`, default the Fly host — §14 item 1) | `lib/features/notifications/services/push_notification_service.dart`, `rust/src/config.rs` |
| T1.4 | `contracts/nostr.md`: replace `register_push_token`; new `contracts/push.md`; `data-model.md` settings keys | `specs/004-mostro-p2p-client/` |

| T1.5 | OS-scheduled refresh that outlives the process (§7.1): `workmanager` periodic task on Android and `BGAppRefreshTask` on iOS, both re-POSTing the persisted registration map with the persisted token from the JSON mirror, no Rust core, no database; a test asserts the job's file imports no bridge or database code; the Settings limitation copy is removed when it lands | `lib/features/notifications/services/push_refresh_job.dart`, `android/app/src/main/AndroidManifest.xml`, `ios/Runner/Info.plist` (`BGTaskSchedulerPermittedIdentifiers`), `pubspec.yaml` |

- **PR-1a** — T1.1 (Rust, pure). One PR: the rules are the reviewable content.
- **PR-1b** — T1.2 (Rust, I/O). Requires `frb-generate.sh`.
- **PR-1c** — T1.3 + T1.4 (Dart + docs). Justification: the docs describe exactly the
  surface this PR starts calling.
- **PR-1d** — T1.5 (Dart + platform config). One task, one PR: the background-job
  boundary is the reviewable content.

Acceptance: on an Android device, taking an order registers its trade pubkey (visible in
the server log as a hashed pubkey and in `get_push_status`); killing the server makes no
difference to trading; a restart followed by opt-out unregisters the pubkeys registered
before the restart.

### Phase 2 — Wake handling (closes #147's mobile half)

| Task | Scope | Files |
|---|---|---|
| T2.1 | Notification channel `mostro_notifications` created at startup (Android), APNs presentation options on iOS; `flutter_local_notifications` initialised once | `lib/features/notifications/services/local_notifications.dart`, `lib/core/app_bootstrap.dart` |
| T2.2 | Display-only background handler: sets `wake_pending`, nothing else; a test asserts the file imports no bridge or DB code; `onMessage` in the foreground nudges reconnect when the pool is not connected; launch-from-notification → `/notifications` after the first frame; delete `_handleForeground`'s card synthesis | `push_notification_service.dart`, `lib/core/app.dart`, `test/features/notifications/` |
| T2.3 | Resume path consumes `wake_pending` (diagnostic only — `resync()` runs on every resume regardless) | `app_lifecycle_service.dart` |

- **PR-2** — T2.1 + T2.2 + T2.3, one PR. Justification: ~150 lines of Dart that only
  make sense together; the handler rule is the reviewable content.

Acceptance: with the app backgrounded, a daemon message for an open trade shows the OS
notification "You have an update on your trade"; tapping it opens the app on
Notifications with the corresponding in-app card already present.

### Phase 3 — Peer chat wake

| Task | Scope | Files |
|---|---|---|
| T3.1 | `notify_peer` after a successful `send_message` publish: `POST /api/notify` with `counterparty_pubkey`, 10 s per-order debounce, not gated on `push_enabled`, one attempt; unit tests (no reveal → no call; debounce; 400 logged) | `rust/src/api/messages.rs`, `rust/src/api/push.rs` |
| T3.2 | Optional local "New message" notification on a `chat_wake` while the process is alive (content-free, channel `mostro_notifications`, collapsed by tag); off when `notify_new_messages` is off | `push_notification_service.dart`, `local_notifications.dart` |

- **PR-3a** — T3.1 (Rust). **PR-3b** — T3.2 (Dart), orthogonal to 3a.

Acceptance: two devices in a trade; a chat message from A while B is backgrounded
produces a silent wake on B within seconds when B's process is alive, and B's chat is
current on resume without a restart.

### Phase 4 — Settings, platforms, copy

| Task | Scope | Files |
|---|---|---|
| T4.1 | Master toggle row + status line + unsupported-platform row on 10d; header copy of the event rows corrected; footnote extended; `PushStatus` markers mapped in `daemon_errors.dart`-style; 5 locales | `notification_settings_screen.dart`, providers, l10n |
| T4.2 | Opt-out flow end to end (§7.4): toggle off unregisters all + `deleteToken`; toggle on re-acquires and reconciles; widget tests with a fake bridge | same, `push_notification_service.dart` |
| T4.3 | Golden for the settings screen states (enabled, disabled, refused, unsupported, denied) | `test/features/settings/goldens/` |
| T4.4 | iOS: APNs key in the Firebase project (operator task, documented), `Runner.entitlements` `aps-environment`, `GoogleService-Info.plist`, `FirebaseApp` registration in `AppDelegate`; `docs/firebase-setup.md` updated | `ios/Runner/`, `docs/firebase-setup.md` |
| T4.5 | Web (closes #133), behind the server's `web` platform and CORS (§3.5): real VAPID key read from a build-time define (`--dart-define=FCM_VAPID_KEY`, documented for forks), `firebase-messaging-sw.js` rewritten — real config from the same source as `firebase_options.dart`, no payload routing, `chat_wake` shown as a content-free "New message", tap focuses or opens `<base>#/notifications` — and registered through `getToken(serviceWorkerScriptPath:)` under the deployed base path; `PushPlatform::Web`; `isSupported` on web reads `Notification` + `PushManager` and a `pushWebEnabled` flag that stays off until the server ships; `pages_bundle_test.dart` guards the worker's placement next to the isolation shim, the base path and the absence of payload routing; the smoke test asserts the worker registers on the isolated page without errors and that `coi-serviceworker` still isolates; Settings copy for the 48 h limitation | `web/firebase-messaging-sw.js`, `web/index.html`, `push_notification_service.dart`, `rust/src/api/push.rs`, `test/web/`, `.github/workflows/web-build.yml`, l10n |

- **PR-4a** — T4.1 + T4.2 + T4.3 (Dart). Justification: one screen, one provider,
  its goldens.
- **PR-4b** — T4.4 (platform config + docs), orthogonal.
- **PR-4c** — T4.5 (web), orthogonal to 4b; mergeable before the server change lands
  because the capability flag keeps web on the "not available" row until then, and
  the smoke test exercises registration of the worker, not of a token.

### Phase 5 — Rich background notifications (deliberate, conditional)

Only if field feedback says the generic OS notification is not enough. Not scheduled.

| Task | Scope |
|---|---|
| T5.1 | Decide the writer model: (a) the background isolate boots the Rust core against the same database and relies on Phase 0's resync to re-hydrate the foreground; or (b) the foreground process is kept alive briefly by a foreground service on wake. Write the decision into this document before any code. |
| T5.2 | Implement the chosen model with the same status-cursor and dedup rules the foreground uses; local notifications built from `NotificationModel` copy; iOS `BGTask` equivalent or explicit non-support. |

### Phase 6 — Hardening and docs

| Task | Scope |
|---|---|
| T6.1 | `CLAUDE.md` gotchas: the push carries nothing; registration is Rust-owned and persisted; the background handler is display-only; dispute chat has no wake |
| T6.2 | `specs/004` contracts and data model final pass; this document's status line; `.specify/v1-reference/FCM_IMPLEMENTATION.md` gains a "how v2 differs" pointer |
| T6.3 | Optional: UnifiedPush as a distributor choice on Android (`token` = endpoint URL, `platform = android`), behind the same registration state — only if the operator turns `UNIFIEDPUSH_ENABLED` on |

**PR-6** — T6.1 + T6.2 (docs). T6.3 is its own PR if and when.

### Issue mapping

| Issue | Phase / PRs |
|---|---|
| #308 app lifecycle | Phase 0 (PR-0a, 0b) |
| #147 background wake-up | Phase 2 (PR-2) for the mobile half; the desktop half stays open |
| #133 web VAPID key | Phase 4 (PR-4c); the flag flips when the server accepts `web` and answers CORS (§3.5) |
| new epic (to open) | closed by PR-6 |

---

## 12. Testing strategy

Rust tests live inline (`#[cfg(test)]`), Dart tests mirror `lib/` under `test/`. Every
PR adds the tests for its own tasks; coverage target 80 % on new code.

**Rust unit:**

- `wanted_pubkeys`: the base set only — non-terminal rows in, hard-terminal rows
  out; claim `trade_index` in while the claim is open; node switch changes nothing;
  `None` trade index on an old claim falls back to the order's key. It has no
  registration state, so no grace assertion lives here.
- `plan`: never registered → register; older than 12 h → register; `registered_at`
  in the future (clock rollback) → register now; token hash differs → register; not
  wanted → `unwanted_since` set, kept while inside the grace, unregister then forget
  once past it, timestamp cleared when the key returns to `wanted`; a legacy
  registration with no `unwanted_since` gets the full grace; backoff sequence; `403`
  refuses that node's keys, the refusal clears after 24 h, on `set_push_enabled(true)`
  and on selecting the node, and a repeated `403` re-arms it; `429` uses
  `Retry-After`.
- `reconcile_push` with a fake `PushServer`: single-flight under concurrent triggers;
  disabled → unregisters everything; server error → no state change beyond backoff;
  restart (state reloaded from settings) → the same set is acted on.
- `notify_peer`: no counterparty → no request; debounce window; `400` logged, never
  retried; not gated on `push_enabled`.
- `resync`: idempotent when called twice; resubscribes from the persisted cursors;
  flushes the outbox; calls reconcile.

**Dart:**

- Background handler import guard (a test that reads the file and fails on any
  `src/rust` or database import).
- `AppLifecycleService`: `inactive` flaps do not fire; `paused → resumed` fires once;
  the seeded-events-visible-after-resume regression from #308.
- Settings widget tests per state; opt-out calls `set_push_enabled(false)` then
  `deleteToken`; goldens.
- Launch-from-notification lands on `/notifications` once, not on every frame.

**Web:**

- `pages_bundle_test.dart`: the messaging worker is referenced from `index.html`
  after the isolation shim, under the base path; it contains no `routeFromPayload`
  mirror and no `REPLACE_ME`; the VAPID define is wired.
- `smoke.mjs` (opt-in like the store probe): on the isolated page the worker
  registers, `navigator.serviceWorker.getRegistrations()` lists both the shim and
  the messaging worker, and `crossOriginIsolated` is still `true` afterwards.
- Unit: the worker's `notificationclick` handler (pure function extracted for the
  test) resolves to `<base>#/notifications` for every payload.

**Manual, per phase:** one Android device with the production server (or a local
`mostro-push-server` with `FCM_ENABLED=true` and a test Firebase service account), one
counterparty. Take an order, background the app, drive the trade from the other side,
confirm the OS notification and the state on resume; send chat both ways; toggle push
off and confirm the server log stops mentioning the (hashed) pubkey; kill the server
and trade anyway.

---

## 13. Comparison with the v1 client

Checked item by item against `MostroP2P/mobile` after drafting the above.

| v1 concern | Covered here | How v2 differs |
|---|---|---|
| Firebase project `mostro-mobile`, committed public config | §5 | Same project; v2's Android package is `foundation.mostro.app` |
| Register on every `saveSession` | §7.1 | Registration is derived from persisted rows and claims, in Rust; triggers include restore and claims, which v1 misses |
| In-memory registered set | §8.1 | Persisted `push_registrations`; restart-safe refresh and opt-out |
| No retry, no re-registration cadence | §7.1 | Backoff + 12 h refresh + resume + timer |
| Never unregisters on trade end | §7.1 | Unregister after a 24 h grace past a hard-terminal status |
| `/api/health` gate at startup | §10 | None; fail open per request |
| `notifyPeer` after a chat send | §7.3 | Same idea, moved to Rust next to the publish, debounced |
| Dispute admin DMs matched by the listener | §2.4 | Impossible on protocol v2; documented gap, upstream ask |
| FCM handler starts a second protocol isolate | §6 principle 2, §11 Phase 5 | Display-only; the one Rust core replays on resume; rich background is a conditional later phase |
| `LifecycleManager` with per-feature resume wiring | §10 | `resync()` + a uniform `hydrate()` (#308) |
| Local notifications built from decrypted events | §9.3 | The OS renders the server's generic push; in-app cards come from the resync |
| Sound/vibration toggles | §9.1 | Not ported (dead in v1); the OS channel owns them |
| Privacy copy claims encrypted tokens | §9.1 | Copy states only what is true |
| iOS unconfigured | §3.4, T4.4 | Configured in Phase 4 or explicitly unsupported |
| Web: gated out entirely (`isSupported = !kIsWeb`) | §2.6, T4.5 | In scope: the worker rings and renders, the tab resyncs; needs two server changes |
| `mostro_pubkey` on register | §7.1 | Sent from the first PR (the issuing node), so the whitelist flag is a no-op |

Items v1 did not have that this spec adds: the persisted registration model, the
grace period, the node-refused notice, the display-only handler rule with a test, the
resume resync, the master toggle on the settings screen, and the explicit platform
matrix.

---

## 14. Open questions and assumptions to verify

1. **Which host is production?** This client points at `https://push.mostro.network`;
   the server repo documents only `https://mostro-push-server.fly.dev`. Confirm with the
   operator before PR-1b which one is authoritative and whether the former is an alias.
   Until then the default is the Fly host, overridable by `PUSH_SERVER_URL`.
2. **Dispute chat wake.** The solver client (mostrix) would need to call `/api/notify`
   with the disputant's trade pubkey after each admin message. Open an upstream issue;
   until it lands, dispute messages while backgrounded are seen on resume only.
3. **Grace period length.** 24 h is a guess at "what still arrives after terminal".
   Verify against the daemon's post-`Success` traffic (`rate-received`, admin outcomes)
   during Phase 1 manual testing and adjust the constant.
4. **`mostro_pubkey` per trade vs active node.** Sending the issuing node's pubkey is
   correct for the whitelist; confirm the operator does not intend to use the field for
   anything else (the server code does not today).
5. **Android data-only delivery when the process is dead.** `chat_wake` is
   `priority: high` with no `notification` block; some OEMs never start the process for
   it. Measure on at least one restrictive OEM before promising anything in the settings
   copy (Phase 3).
6. **iOS provisioning.** Needs an Apple Developer account with an APNs key uploaded to
   the `mostro-mobile` Firebase project — an operator task outside this repo. Phase 4
   ships the client side either way and states iOS as pending if the key is missing.
7. **Web on the server.** Two changes (§3.5): accept `platform: "web"`, and CORS for
   the app's origin. Proposed upstream as
   [mostro-push-server#44](https://github.com/MostroP2P/mostro-push-server/issues/44);
   PR-4c's capability flag flips when it ships. Do not work around either (a proxy would put a third party between the browser and the
   token). Verify against the real bundle, not in isolation: the worker's
   `importScripts` from `gstatic.com` under the isolated page, its coexistence with
   `coi-serviceworker` (scopes, `clients.claim()`), and registration under the
   `/app/` base path through `serviceWorkerScriptPath`.
8. **Encrypted token registration.** When `/api/info` reports `encryption_enabled:
   true` and a public key, add the ECDH + HKDF + ChaCha20-Poly1305 client in Rust
   (`crypto/`), 281-byte format as in the server's `crypto/mod.rs`. Not before.
9. **`flutter_local_notifications ^17`** is two majors behind v1's 19; check the channel
   API before T2.1 and bump if needed (CI Flutter is 3.38.2).
10. **Server TTL and persistence.** The 48 h in-memory TTL is what forces T1.5 and
    what a server restart defeats regardless. Propose upstream a longer TTL
    (registrations are idempotent, so the cost of a stale one is a wasted push) or a
    persisted map; either would let T1.5 become a safety net rather than the
    mechanism.
11. **Background refresh grants.** Android's `workmanager` honours a 12 h period on
    stock builds but restrictive OEMs may stretch it; iOS grants `BGAppRefreshTask`
    on its own judgement of usage. Measure the real cadence on both during T1.5 and
    record it here; the Settings copy must promise no more than what was measured.
12. **Ownership proof on registration.** `/api/register` and `/api/unregister` accept
    any caller who knows a public trade pubkey (§2.1). Propose upstream a signature by
    the trade key over a server-issued nonce on both endpoints; until then the
    12 h refresh and the T1.5 job are the mitigation, and the limitation is stated.

---

## 15. References

- Server: <https://github.com/MostroP2P/mostro-push-server> — `docs/api.md`,
  `docs/architecture.md`, `docs/configuration.md`, `docs/unifiedpush.md`, `SECURITY.md`,
  `src/nostr/listener.rs`, `src/push/fcm.rs`, `src/api/routes.rs`, `src/api/notify.rs`.
- v1 client: <https://github.com/MostroP2P/mobile> — `lib/services/fcm_service.dart`,
  `lib/services/push_notification_service.dart`, `lib/background/background.dart`,
  `lib/services/lifecycle_manager.dart`,
  `lib/features/notifications/services/background_notification_service.dart`,
  `docs/architecture/FCM_IMPLEMENTATION.md`, `docs/plans/CHAT_NOTIFICATIONS_PLAN.md`,
  `docs/architecture/BACKGROUND_NOTIFICATIONS_FIX.md`; the v1 dispute-chat bug and fix,
  MostroP2P/mobile#675.
- This repo: `.specify/v1-reference/FCM_IMPLEMENTATION.md` (the v1 doc as copied here),
  `specs/004-mostro-p2p-client/contracts/nostr.md` (`register_push_token`),
  `contracts/messages.md` (chat envelope `p` tag), `contracts/orders.md` (kind-14
  delivery coverage), `docs/ANTI_ABUSE_BOND.md` (the claim key rules the wanted set
  reuses), issues #147, #308, #133, #319.
- Protocol: <https://mostro.network/protocol/chat.html>,
  <https://mostro.network/protocol/dispute_chat.html>; MIP-05
  <https://github.com/MostroP2P/MIPs>; FCM v1 API
  <https://firebase.google.com/docs/cloud-messaging/migrate-v1>; UnifiedPush
  <https://unifiedpush.org/developers/spec/>.
