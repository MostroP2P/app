# Contract: Push Notifications

**Module**: `rust/src/api/push.rs` (I/O), `rust/src/mostro/push.rs` (rules)

The bridge surface for push registration. The design, the server contract and
the phase plan live in `docs/PUSH_NOTIFICATIONS.md`; this file only pins the
API and the split of responsibilities.

**Dart owns the device; Rust owns the registration.** Dart obtains the FCM
token and hands it over with `set_push_token`; from there Rust decides which
trade pubkeys the push server holds it for, when each is re-sent and what is
let go, persisted in the settings store so a restart, a token refresh or an
opt-out act on the full set. No Dart code decides what to register.

**The push carries nothing.** The server sends a fixed, content-free wake-up
(`data.type ∈ { trade_update, chat_wake }`); there is no event id, order or
sender to route on. Everything the app shows comes from its own relay
subscriptions once awake.

Rust returns stable markers, never prose; Dart maps them to localized text.

## The registration set

What the server should hold right now (`mostro::push::wanted_pubkeys`): the
trade key of every trade row that is not hard-terminal, and the key each
open payout claim was addressed to (`BondClaim.trade_index`, falling back to
the order's key for a claim stored before the index was recorded). Never every
key ever derived. Each key is filed under its **issuing node**
(`order.creator_pubkey`, `claim.node_pubkey`; an empty legacy value reads as
the active node), and the kind-14 filter's `authors` include the issuing node
of every live trade row, so a registered key is always one the filter hears.

A key that leaves the set starts a 24 h grace (`unwanted_since` on the
registration, since `TradeInfo.completed_at` is never written), then is
unregistered. A registration older than 12 h, filed with another token or
under another node, or dated in the future (a clock rollback) is re-sent. A
failed request backs off (1 min → 5 → 30 → 2 h; `429` honours `Retry-After`).
A `403` refuses the node for 24 h, cleared early by the master toggle turned
on or by selecting that node.

## Triggers

Every trade row write (`persist_trade_row`), every trade update emission,
every claim upsert, the restore, `resync()`, a token or toggle change, and a
6 h timer started when the relay pool comes up. Coalesced: a burst runs one
pass after 2 s. `reconcile_push` is single-flight; a request that arrives
mid-pass runs it again rather than in parallel.

## Functions

### set_push_token(token: String, platform: PushPlatform) → ()
Dart hands the device token over, on the first token and on every refresh.
Persists it and reconciles. `PushPlatform = Android | Ios | Web` (wire values
`android`, `ios`, `web`; the server accepts the first two today).
**Errors**: `StorageUnavailable`, `InvalidToken`.

### clear_push_token() → ()
After `deleteToken()` on the device: nothing can be registered any more; the
reconcile unregisters what the server still holds. **Errors**:
`StorageUnavailable`.

### set_push_enabled(enabled: bool) → ()
The master toggle, default on. Off unregisters everything the persisted map
knows about, whichever run registered it; on clears every node refusal and
registers the current set. **Errors**: `StorageUnavailable`.

### get_push_status() → PushStatus
What Settings shows, from the persisted state — right after a restart, before
any reconcile ran. `PushStatus { enabled, has_token, registered, wanted,
last_success_at, last_error, node_refused_until }`. `last_error` is a marker:
`PushServerUnreachable`, `PushRateLimited`, `PushNodeRefused`,
`PushBadRequest`. Capability (can this platform push) and the OS permission
are Dart's to know and are read separately (`PushNotificationService.isSupported`,
`notificationPermissionDeniedProvider`). **Errors**: `StorageUnavailable`.

### reconcile_push() → ()
Explicit trigger. Never fails: every outcome is logged and reflected in the
status.

## Peer wake

Not a bridge call: `send_message` and `send_file` ring the counterparty
themselves once the chat envelope reached the relays
(`docs/PUSH_NOTIFICATIONS.md` §7.3). The envelope is `p`-tagged to
`pub(K_conv)`, which the push server's listener cannot match, so the sender
asks it to wake the peer's trade pubkey with `POST /api/notify`.

- Not gated on this device's own push toggle: the peer's setting decides
  what reaches them, and the server answers `202` either way.
- Debounced per peer (10 s): a burst of messages costs one wake, far under
  the server's 30/min per pubkey. Recorded before the request, so messages
  sent while one is in flight do not each ring.
- Fire-and-forget: spawned, never awaited by the send, never retried, never
  a reason for the send to fail. A `400` is logged as a client bug.
- Peer chat only. The dispute channel does not ring its solver.
- Not from the web build until the server answers CORS
  (mostro-push-server#44).
- No relay, no wake: an envelope every relay rejected (`send_event` is still
  `Ok` with an empty success set) reached no one, so it rings nobody and
  cannot debounce the wake of a retry that does land.
- No reveal, no wake: before the peer reveal (#334) there is no peer pubkey
  and the message stays local-only anyway.

## Streams

### on_push_status_changed() → Stream<PushStatus>
One status per reconcile. A lagging consumer skips ahead rather than ending.

## Server

`https://mostro-push-server.fly.dev`, overridable at build time with
`PUSH_SERVER_URL`. Requests carry only the JSON bodies of
`docs/PUSH_NOTIFICATIONS.md` §3.1 — no `Authorization`, request id or sender,
which the server refuses by design — with a 10 s timeout. Under `cargo test`
every production path talks to an unreachable stub.

## Persisted state

Settings keys: `push_enabled`, `push_token`, `push_platform`,
`push_registrations` (JSON map of pubkey → `PushRegistration { trade_pubkey,
registered_at, token_hash, mostro_pubkey, unwanted_since, attempts,
next_attempt_at }`), `push_node_refusals` (JSON map of node → unix seconds of
the `403`). On native, `push_mirror.json` next to the database holds the token
and the accepted registrations for the OS-scheduled refresh (T1.5); it is
removed when there is nothing to refresh.

## Identity and node changes

`delete_identity` unregisters everything first: a key the user no longer
holds must not keep waking the device. A node switch unregisters nothing (the
set is node-agnostic) and clears the selected node's refusal.
