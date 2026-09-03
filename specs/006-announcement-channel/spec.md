# Feature Specification: Announcement Channel — authenticated, non-push notices

**Feature Branch**: `006-announcement-channel`
**Created**: 2026-08-26
**Status**: Draft — nothing is built
**Input**: Give the project one authenticated way to reach people already running the
app — "update to 2.1", "the node is down for maintenance", "this relay is gone" —
without a backend, an account, an email address, or a push token.
**Prior art**: the same channel, built end to end in a pure-Flutter app
([protolayer-io/choke#165 → #171](https://github.com/protolayer-io/choke/pull/165)).
This document is the Mostro v2 adaptation, and the adaptation is not cosmetic: in
choke everything below lived in Dart. Here almost all of it lives in Rust.

---

## 1. Context

### 1.1 What exists today

The app already has an in-app notification surface, and it is the reason this feature is
small:

| Piece | Where | What it already does |
|---|---|---|
| `NotificationModel` | `lib/features/notifications/models/notification_model.dart` | typed records with `isRead`, timestamp, optional detail map; `NotificationType.system` already exists |
| `SystemNotificationBanner` | `lib/features/notifications/widgets/system_notification_banner.dart` | the amber banner for notices that reference no trade — its own doc comment says "backup reminders, **announcements**, etc." |
| `NotificationBell` | `lib/shared/widgets/notification_bell.dart` | bell + unread dot in the top bar |
| `SembastNotificationsStore` | `lib/features/notifications/providers/notifications_provider.dart` | persistence, plus a `processed_events` tombstone ledger so a replay never resurrects a dismissed notice |
| `NotificationSettingsScreen` | `lib/features/settings/screens/notification_settings_screen.dart` | four per-category toggles (trade updates, messages, payments, disputes) |

So the surface is built. **What does not exist is any way for the project to put
something into it.** Every notification in the app today is generated locally from
daemon traffic about the user's own trades.

There is also `PushNotificationService` (FCM + Web Push) — but it is scaffolding: the
VAPID key is the literal string `YOUR_VAPID_KEY`, `firebase_options` is a placeholder,
and `_pushServerUrl` points at `https://push.mostro.network`, a service that has to
exist and hold a device token per install. That is a different feature with a different
trust model, and §11 says why this one does not wait for it.

### 1.2 The problem

There is no channel at all. Once a user installs, the only thing the project can say to
them is whatever fits in a store release note — read once, at update time, by whoever
reads them. On web and desktop there is not even that.

Concretely, things the project currently cannot say:

- "2.1 is out and fixes the invoice bug you are hitting."
- "The public Mostro node is down for maintenance for two hours."
- "This default relay is being retired; the app will pick a new one on update."

Every conventional answer needs something this app deliberately does not have: a server,
a user identity, an email address, a device token. The app has no accounts and captures
nothing about the user, and that is a property to preserve, not a gap to fill.

### 1.3 The solution

The app already speaks Nostr, and a Nostr event is signed. Publish announcements from
keys the project controls, compile those keys' `npub`s into the app, and read events
**only** from them.

The signature is the entire trust model. A hostile relay can withhold an announcement or
serve a stale one — §5 handles both — but it cannot forge one. Because no transport-level
trust is required, no server is either.

### 1.4 What this is not

Stated up front, because the idea invites all three:

- **Not push.** Nothing wakes the device. An announcement is seen the next time the app
  is open. See §11.
- **Not a message to a particular user.** It is a broadcast. Reaching one counterparty,
  or the users of one node, is a different mechanism with a different trust model.
- **Not two-way.** No reply path. Adding one puts an inbox in front of a maintainer with
  no moderation tooling behind it.

### 1.5 What is different from the choke implementation

Worth reading before §4, because it is where a straight port would go wrong:

| choke | here | why |
|---|---|---|
| Parsing, allowlist decoding, signature verification, freshness, storage — all in Dart | **all in Rust** | Golden rule: Nostr protocol, cryptography and business logic live in `rust/src/`; Dart is UI, navigation and device I/O. `.specify/ARCHITECTURE.md`, constitution Principle I |
| A new bell, a new screen, a new `shared_preferences` cache | **reuses `NotificationType.system`, `SystemNotificationBanner`, `NotificationBell` and the Sembast store** | They already exist and already render exactly this shape |
| 4 locales (`en`, `es`, `ja`, `pt`) | **5 locales** (`en`, `es`, `fr`, `de`, `it`) | `lib/l10n/app_{en,es,fr,de,it}.arb` |
| `tool/announce.dart` could not call the app's parser (plain Dart VM vs `dart:ui`), so constants were duplicated and pinned by a test | **the publisher tool is a Rust binary in the same crate and calls the real parser directly** | No duplication to drift; the tool literally cannot accept what the app would drop |
| Version from `package_info_plus` | `get_app_version()` in `rust/src/api/mod.rs` | already bridged, and fixed in this PR — §4.3 |

---

## 2. User scenarios

### User Story 1 — "There is a version that fixes your bug" (Priority: P1)

A user on 2.0.0 opens the app. The bell carries a dot. The announcement reads "Mostro 2.1
is out — it fixes the invoice timeout", with a button to the release page. A user already
on 2.1 sees nothing, because the announcement carries `max_version: 2.1` and the bound is
exclusive.

**Independent test**: publish one event with `max_version: 2.1` from an allowlisted key;
confirm it renders on a 2.0.0 build and is absent on a 2.1.0 build.

### User Story 2 — "The node is down tonight" (Priority: P1)

An outage notice is published with an `expiration` four hours out. It renders. Four hours
later it is gone from the list and from local storage — **including on a device that was
offline the whole time and received nothing to displace it** (§5.4).

**Independent test**: publish with a short expiry; confirm it renders, then confirm it is
swept on the next foreground with the clock advanced, both online and with relays
unreachable.

### User Story 3 — Someone else tries to use the channel (Priority: P1)

A relay serves an event of the announcement kind signed by a key that is not on the
allowlist, or an event from an allowlisted key whose content was tampered with in
transit. Neither is rendered, neither is counted, and neither produces a visible error.

**Independent test**: three events — wrong author, tampered content, tampered tag — all
dropped.

### User Story 4 — The user does not want the channel (Priority: P2)

The user turns **Announcements** off in notification settings. The subscription closes at
the tap. From the relay's point of view the app looks exactly like an app that was closed.

**Independent test**: toggle off while subscribed; assert the subscription is closed and
an event delivered immediately afterwards is not processed.

---

## 3. Event contract

This section is normative. It is the interface between the publisher tool (§8) and the
reader (§5), and nothing else in this document may contradict it.

| Part | Value |
|---|---|
| Kind | `38387` — addressable, **reserved in the Mostro protocol's `3838x` block for this and nothing else** |
| Author | one of the keys in §4.1, and nothing else |
| `d` tag | announcement id: stable, opaque, unique per announcement |
| `expiration` tag | NIP-40, **required** — see §5.5 |
| `content` | the JSON of §3.2 |

**On the kind.** The Mostro protocol allocates the `3838x` block sequentially
(`../protocol/src/order_event.md`, NIP-69), and it is currently full:

| Kind | Event | `z` tag |
|---|---|---|
| `38383` | Orders | `order` |
| `38384` | Ratings | `rating` |
| `38385` | Info | `info` |
| `38386` | Disputes | `dispute` |
| **`38387`** | **Announcements** | **`announcement`** |

`38387` is the next slot, and this feature **takes it deliberately**: the protocol is
maintained by the same project, so this is an allocation rather than a client squatting on
a number it does not own. It is reserved for the announcement event and nothing else, and
a `z` tag of `announcement` keeps it self-describing alongside its neighbours.

That consequence is discharged in **MostroP2P/protocol#56**, which registers the row above
and describes the event in `src/announcement_event.md`. A number reserved only in this
document would not be reserved — the registry is what stops the next Mostro client from
picking `38387` for something else. Where the two documents overlap, the protocol one is
the wire contract and this one is how this app implements it; §3.2's five-locale rule is
this app's policy, which the protocol document explicitly leaves to each project.

Being addressable (30000–39999) is the part that matters functionally: it is what makes
correcting a typo in a live announcement a republish under the same `d` rather than a
second announcement.

The event stays a **client-level** event in every other respect. It is authored by the
project keys of §4.1, not by a node; no daemon publishes it, no daemon reads it, and §11
says why a node-authored announcement would need a different allowlist rather than this
one.

### 3.1 Tags

| Tag | Required | Meaning |
|---|---|---|
| `d` | yes | announcement id |
| `expiration` | yes | unix seconds, NIP-40 |
| `min_version` | no | show only to app versions ≥ this — **inclusive** lower bound |
| `max_version` | no | show only to app versions < this — **exclusive** upper bound |
| `z` | yes | `announcement` — the block's convention, so the event is self-describing next to `order` / `dispute` / `info` |
| `y` | no | platform identifier, optionally with the publishing project's name |

`z` and `y` are required of the **publisher** (§8) for registry consistency. The reader
does not filter on them: it filters on kind and author, and an allowlisted key that omits
`z` is still the project talking. Validating a tag that carries no trust adds a way for a
correct announcement to be dropped and buys nothing.

The bounds exist for the announcement that is *about* the app. "2.1 is out, it fixes X"
must not reach someone already on 2.1 — which is why the upper bound is exclusive: the
sender writes the version the announcement is *about* (`max_version: 2.1`) and everyone
below it sees it. Any other reading forces the sender to name the previous version. The
lower bound is inclusive for the mirror case: "2.1 changed how X works" is for people who
have 2.1.

What a bound may contain:

| Form | Accepted | Note |
|---|---|---|
| `MAJOR.MINOR.PATCH` | yes | the form the app's own version takes |
| Fewer components (`2`, `2.1`) | yes | missing components are `0` |
| Pre-release (`2.1.0-beta.1`) | yes | orders before `2.1.0`, per semver |
| Build metadata (`2.1.0+1`) | **no** | rejected — semver excludes build metadata from precedence, so accepting it means silently ignoring part of what the sender wrote |

**An unparseable bound makes the announcement invalid, not unbounded.** A targeting
instruction nobody can read has failed, and showing the message to everyone is the wrong
way to fail it.

### 3.2 Content

```json
{
  "v": 1,
  "severity": "critical",
  "locales": {
    "en": { "title": "…", "body": "…" },
    "es": { "title": "…", "body": "…" },
    "fr": { "title": "…", "body": "…" },
    "de": { "title": "…", "body": "…" },
    "it": { "title": "…", "body": "…" }
  },
  "url": "https://mostro.network/…"
}
```

| Field | Required | Rule |
|---|---|---|
| `v` | yes | schema version, `1` today. An unknown `v` is **ignored**, never rendered best-effort |
| `severity` | yes | one of `info`, `warning`, `critical` — see §3.4 |
| `locales` | yes | must contain **exactly** `en`, `es`, `fr`, `de`, `it`. A missing one, or an unknown extra one, makes the announcement **invalid** |
| `locales[x].title` | yes | ≤ 80 characters after trimming |
| `locales[x].body` | yes | ≤ 500 characters after trimming |
| `url` | no | exactly one action link, `https` scheme only |

All five required is deliberately stricter than "must contain `en`". A fallback to English
is a bug that ships quietly: the Italian reader gets English, nothing is logged, and the
sender never finds out. Every announcement is written once, by hand — "translate all five
before publishing" is minutes paid at publish time by someone who can see the problem, and
§8's validator makes it a hard stop rather than a habit.

An unknown extra key is rejected for the same reason and not out of tidiness: it is the
shape a sixth locale takes, and quietly ignoring it leaves the sender believing they
reached a language the installed app cannot render. When the app gains a locale, this list
and `AppLocalizations.supportedLocales` change in the same release.

Both strings are **plain text**. No markup is parsed, no link is auto-detected inside
`body`, and `url` is the only tappable thing. The sender is trusted with authorship, not
with rendering arbitrary content inside a Bitcoin exchange client.

### 3.3 Why all locales ride in one event

The idiomatic Nostr alternative is one event per language tagged `["l", "es"]`. It is
worse here: it turns one publish into five, lets a user's relay set deliver two of them
and not the others, and leaves the app deciding whether three events are one announcement
or three. One event carrying every translation cannot half-arrive.

The cost is that this copy does not live in `lib/l10n/*.arb` and so is outside the l10n
workflow. That is inherent — the text is written after the build ships. The chrome around
it (screen title, empty state, the settings toggle) is localized normally, and per
CLAUDE.md the Rust side still translates nothing: it returns all five locales and Dart
picks.

### 3.4 Severity

"2.1 is out, it has a nicer order book" and "2.0.3 fixes a bug that can leak your trade
key — update now" are not the same message, and rendering them identically makes the
second one look like the first. Every announcement therefore declares one of three levels:

| `severity` | For | Rendered as |
|---|---|---|
| `info` | releases, new features, events | `blueAccent`, an info icon |
| `warning` | outages, a relay being retired, anything with a deadline | `warningAmber`, the warning icon the system banner already uses |
| `critical` | a security issue the user must act on now | `destructiveRed`, a shield icon, and the bell's dot turns red |

Three levels, not five: the publisher has to be able to pick one without deliberating, and
a level nobody can distinguish from its neighbour is a level that gets chosen at random.

**The publisher declares a severity, never a colour.** The mapping above lives in the app,
for three reasons: the palette differs between themes and the sender cannot know which one
the reader is in; `destructiveRed` on `backgroundCard` is a contrast pair the design system
has already checked and an arbitrary hex is not; and the sender is trusted with authorship,
not with rendering — the same rule that makes §3.2 plain text only. A content field that
carried a colour would hand an allowlisted key the ability to paint the app.

**An unrecognised `severity` renders as `warning`, and the announcement is not dropped.**
This is the one place where §3.2's "unknown means invalid" does not apply, and the
asymmetry is the reason: `v` and the locale set decide whether the message is
*intelligible*, while severity only decides how it is *painted*. Dropping a security notice
because a future release added a fourth level is the worst outcome available. It maps to
`warning` rather than `critical` because the app cannot know which direction an unknown
token sits in — and because "any unknown string paints the app red" is exactly the
escalation an allowlisted key with a typo, or a compromised one, would use.

**Colour is never the only signal.** Each level also carries its own icon and a localized
label (`Security update`, `Notice`, `Announcement`), so the distinction survives a reader
with colour-vision deficiency and a screen in direct sunlight.

Two consequences beyond colour:

- **`critical` sorts above everything**, then by `created_at`. Everything else is by date.
- **Dismissing a `critical` clears the badge but keeps it in the list** until it expires.
  For the other two levels, dismiss removes it. A user who swipes away "your trade key can
  leak" at a red light should still be able to find it.

**No modal, at any level** — §6.3 still holds. A takeover on launch is the single surface a
compromised publisher key would most want, and it blocks a user who opened the app to
release sats on a trade that is already running. A red banner above everything else, with a
red dot on the bell, already outranks every other thing on that screen. This is the
decision in this section most worth arguing with.

**And a policy, like §7's:** `critical` is for security. The moment it carries a release
announcement, users learn that red means nothing, and the level is worthless on the day it
is true. There is no technical enforcement of this and there cannot be — it is a rule for
whoever holds the key.

---

## 4. Trust model

### 4.1 The allowlist

A `const` list of `npub` strings compiled into the Rust crate
(`rust/src/nostr/announcements.rs`).

**A list, not a single value.** This is the one place the plural matters: a hardcoded
singular key that is lost or leaked kills the channel until a store review completes,
measured in days. A list lets a successor key ship *before* it is needed.

Three rules:

1. **Not a personal key, and not the Mostro node's key.** A dedicated key, kept offline,
   used for nothing else. The node key arbitrates trades; an announcement key that is also
   a node key means a compromise of one is a compromise of both. It must also not be any
   key the app derives (`m/44'/1237'/38383'/0/N`).
2. **The constant holds `npub`, not hex.** It is what a human checks against the value
   published on mostro.network or in the README. Decoding goes through `nostr-sdk`
   (`PublicKey::parse`) in Rust — never a Dart bech32 implementation, per the golden rule.
3. **An entry that fails to decode is dropped with a `log::warn!`, and the rest still
   work.** A typo in one constant must not silence the channel.

**The allowlist ships empty**, and an empty allowlist means no authors, which means §5.1
opens no subscription. Every phase of §10 can therefore merge without the channel being
live; turning it on is a one-line commit, reviewed on its own, with the npubs checked
against a source outside this repo.

The list cannot be updated over the wire, on purpose: a remotely updatable allowlist is a
channel for taking over the channel.

### 4.2 Verification is explicit

**Every announcement event is verified in Rust before it is trusted** — `event.verify()`,
called at the point of use, regardless of what the relay pool does or does not verify on
its own. `rust/src/nostr/transport.rs` already does exactly this for the chat envelope
(lines 276 and 288) and for the same reason: the pool's verification settings are a
transport detail that can change underneath us, and this is the only property the whole
feature rests on.

An event that fails verification is dropped silently — not shown, not counted, not
surfaced as an error. There is nothing a user could do about it, and "an announcement
failed to verify" is itself a message from an untrusted source.

### 4.3 The app version the bounds compare against

`get_app_version()` (`rust/src/api/mod.rs`) returns `env!("CARGO_PKG_VERSION")` — the
**Rust crate's** version. Until this PR that was `0.1.0` while `pubspec.yaml` said
`2.0.0+1`, so version-targeted announcements would have compared every bound against a
number no released build has ever carried, and the About screen showed `0.1.0` to users.

**Fixed here**, since the spec is worthless while it is true: `rust/Cargo.toml` now
carries the pubspec version, and `app_version_matches_pubspec` in `rust/src/api/mod.rs`
fails the suite when the two drift. One source of truth, and the About screen is repaired
as a side effect.

The alternative — passing the pubspec version from Dart into Rust at init — was rejected:
it leaves two versions in the app and does nothing for the About screen.

The version compared against is the **release version without the build number** —
`2.0.0`, never `2.0.0+1`. Semver excludes build metadata from precedence, so a bound
carrying one would silently compare equal to one without; `app_version_carries_no_build_number`
pins that end too.

### 4.4 Privacy

The subscription is opened on the shared relay pool, whose client is keyed with a
generated ephemeral key (`RelayPool::new`), and a Nostr `REQ` carries no author identity
unless a relay demands NIP-42. So the announcement subscription reveals to a relay that
the connection belongs to a Mostro client — which its kind-38383 subscription already
reveals — and nothing about the user.

It must stay that way: **the announcement filter must never be opened on a trade key's
connection or carry any tag derived from user state**, and nothing is ever published back
— no read receipt, no acknowledgement, no delivery report.

---

## 5. Reader behaviour (Rust)

### 5.1 Fetch

While the app is running and the setting of §7 is on:

```rust
Filter::new()
    .kind(Kind::from(38387u16))
    .authors(<decoded §4.1 keys>)
    .since(now - 30 days)
    .limit(20)
```

`Filter` already carries `kinds`, `authors`, `since` and `limit` — **no new capability is
needed on the relay pool.** With an empty allowlist the filter has no authors and the
subscription is not opened at all.

The subscription lives as long as the app is in the foreground and is closed when it
leaves, matching what the order-book subscription already does. There is no background
work of any kind (§11).

### 5.2 The single door

A cached announcement restored from disk and an announcement arriving from a relay go
through **the same function, in this order**:

1. author is on the allowlist (§4.1)
2. `event.verify()` succeeds (§4.2)
3. the §3 schema parses
4. `created_at` is not older than 30 days and not more than 5 minutes in the future (§5.3)
5. `expiration` has not passed (§5.5)
6. the app's version is inside `[min_version, max_version)` (§3.1)
7. it wins at its address (§5.3)

Only then does it exist as far as the rest of the app is concerned.

**The cache stores signed events, not parsed announcements.** A restore re-verifies rather
than trusting what a previous build parsed. It costs at most 20 signature checks at launch
and buys two things: a key dropped from the allowlist takes its cached announcements with
it, and there is exactly one definition of an acceptable announcement instead of two that
can drift.

### 5.3 Freshness and replay

A relay can serve an old event forever, and a fresh install subscribing with no history
would take last quarter's announcement as news.

| Rule | Value |
|---|---|
| Too old | `created_at` older than **30 days** → ignored |
| Future-dated | `created_at` more than **5 minutes** ahead of now → ignored |
| Already seen | same address at the same revision or older → not re-announced |
| Superseded | same address, newer revision → replaces, is re-announced, and its read state is cleared |

The 5-minute window is clock skew, not tolerance for post-dating: an announcement dated
next week must not sit at the top of every inbox until then.

**The address is `(kind, pubkey, d)`, never `d` alone.** `d` is chosen by the sender and
§4.1 is a list, so two keys can pick the same `d` — at which point a `d`-keyed seen set
lets a successor key's announcement be swallowed as "already seen", or lets one key's read
state mark another key's message read.

**The revision is `(created_at, event.id)`.** `created_at` alone does not order two events:
a correction republished within the same second is the ordinary outcome of fixing a typo
and hitting publish, and with a bare timestamp the winner is whichever relay answered
first — two phones, two different texts of the same announcement. Tie-break: strictly newer
`created_at` wins; on an exact tie, the **lowest** event id wins, compared
case-insensitively. Both halves are stored, because the comparison needs the held id and
not just the held timestamp.

**A re-announced correction is unread again.** Read state is keyed by address and stamped
with the revision that was read; a newer revision at that address clears it. The
alternative loses the correction in exactly the case it was published for — the user read
the wrong maintenance window, dismissed it, and the fix arrives already dismissed.

### 5.4 Storage, and the offline case

Verified events are persisted in the **protocol layer**, not the Dart layer: a new
`announcements` table in `rust/src/db/schema.rs` (SQLite native, IndexedDB web), bumping
`SCHEMA_VERSION` from 3 to 4. Capped at the **20 most recent** by `created_at`; each row
holds the raw signed event JSON plus its address, revision and read/dismissed state.

Cached announcements are shown offline. They are the last thing the project said, and that
stays true whether or not a relay answers today.

**But the cache is re-checked against the clock, not against the network.** On every
restore and every foreground, each cached event is re-run through §5.2 with the current
time. Anything now older than 30 days, or now past its `expiration`, is dropped from the
list *and deleted from the database* in the same pass.

This is the offline case specifically. The rules are otherwise enforced on arrival, and an
event that arrives is an event a relay answered — but a phone with no connectivity for five
weeks receives nothing to displace what it holds, and without this pass "the node is down
for maintenance tonight" survives its own `expiration` indefinitely *precisely because
nothing came in.* The expiry rule is a promise to the sender that nothing they publish
becomes permanent, and a promise that only holds while online is not one.

Dropping an announcement drops its read and dismissed state with it. Nothing may reference
an address that is no longer in the cache.

### 5.5 Expiry

`expiration` is required (§3) and NIP-40. Expired on arrival → dropped. Expiring while
cached → swept (§5.4). It is what keeps an outage notice from reading as news a month
later, and it means the sender cannot accidentally create something permanent.

### 5.6 Failure

Every failure mode here is silent: no relay, no announcements, bad JSON, failed signature,
unknown `v`, unparseable bound. A user who never receives an announcement must not be able
to tell that they did not, and none of it is worth a word of UI. Details go to `log::` in
Rust, per the logging convention already in the crate.

---

## 6. Surface (Dart)

The rule for this half: **Dart renders what Rust hands it and decides nothing.**

### 6.1 Bridge

A new `rust/src/api/announcements.rs` exposing:

| Function | Shape |
|---|---|
| `get_announcements()` | `Vec<Announcement>` — already filtered, ordered newest first |
| `on_announcements_changed()` | a stream of `Vec<Announcement>`, following the `SettingsStream` / order-stream pattern already in `api/` |
| `set_announcements_enabled(bool)` / `get_announcements_enabled()` | §7 |
| `mark_announcement_read(address)` / `dismiss_announcement(address)` | read/dismiss state, stored beside the event |

`Announcement` carries the address, the revision, `created_at`, `expiration`, the optional
`url`, and **all five locales**. Rust does not pick a language — CLAUDE.md, "Rust does not
translate."

Adding `rust/src/api/announcements.rs` means `./scripts/frb-generate.sh` must run, and the
generated `lib/src/rust/` is never hand-edited.

### 6.2 Rendering

Each announcement becomes a `NotificationModel`:

- `type: NotificationType.system` — which already routes to `SystemNotificationBanner`,
  whose amber is today hardcoded; it grows a severity parameter so the three levels of
  §3.4 map onto `blueAccent` / `warningAmber` / `destructiveRed` with their icons
- `id`: the address string, so the model's identity is the announcement's identity and the
  existing Sembast `processed_events` tombstone ledger works unchanged
- `title` / `message`: the locale block matching `Localizations.localeOf(context)`; there
  is no fallback path, because §3.2 guarantees every locale is present
- `timestamp`: `created_at`
- the `url`, when present, as a single button opening externally through `url_launcher`
  (already a dependency), never rendered inline in the body

Read and dismiss flow through the existing notifications provider, which then calls the
bridge so Rust holds the same state — it is Rust that has to know whether a superseding
revision should re-announce. A newer revision at a known address arrives as an unread item
at the same id, which is exactly what §5.3 asks for.

The bell, the unread dot and the notifications screen are unchanged. **This feature adds
no new navigation and no new screen.**

### 6.3 Nothing interrupts

No dialog, no snackbar, no takeover on launch. A user opening the app to release sats
mid-trade must reach the trade screen exactly as fast as before. The dot is the whole
notification.

---

## 7. Consent

A fifth toggle — **Announcements** — in `NotificationSettingsScreen`, beside trade updates,
messages, payments and disputes. Localized in all five languages.

Unlike its four neighbours, which are `shared_preferences` keys, this one is persisted in
the **Rust settings table** (`rust/src/api/settings.rs`, the existing key-value `settings`
table) — because the value controls whether Rust opens a relay subscription, and the
authority for that has to be on the side that opens it.

**Off means the subscription is never opened**, not that arriving events are hidden. A
relay must not be able to distinguish a user who opted out from a user who closed the app.

**Switching off takes effect at the tap.** The subscription is closed and any event already
queued behind it is discarded. Nothing waits for the next background transition: a user who
turns the channel off and stays on the settings screen — which is what a user who just
turned it off does — would otherwise keep an open subscription for as long as the app stays
open, which is the one thing this switch says does not happen. Deferred cleanup also
creates exactly the observable difference the paragraph above forbids.

Turning it back on reopens the subscription. The gap is not backfilled beyond what §5.1's
filter asks for on the next open — `since = now - 30 days` is the same window a fresh
install gets, so an announcement published while the switch was off is picked up if it is
still fresh, and is not if it is not.

**Default: on.** A judgement call, stated plainly: the channel is low-frequency and
product-related, and nothing here posts a system notification, so nothing escapes the app
the user just opened. The day it does post one, Android 13+ requires a runtime permission
and this default is re-argued rather than inherited.

Two constraints that are policy rather than code and belong in this document anyway:

- **Low frequency.** Releases, outages, node and relay changes. The moment the channel
  carries anything else, the switch above stops being theoretical.
- **The app's promise still holds.** No registration, no data capture, nothing sent about
  the user. The channel is one-way *toward* the app; the app reports nothing back, not even
  a read receipt.

---

## 8. Publishing

There is no admin UI and none is planned. Publishing is a signed event from a key in §4.1,
sent with any Nostr client.

What the sender owes:

1. A `d` that has never been used — unless deliberately correcting a live announcement, and
   a correction is a republish under the same `d` **from the same key**, since the address
   is `(kind, pubkey, d)`. Republishing from a different allowlisted key creates a second
   announcement, not a fix.
2. An `expiration` that is actually in the future.
3. All five locales, and no others. No partial publish, no fallback (§3.2).
4. A `severity` that is one of the three, and honestly chosen — §3.4's last paragraph.
5. A `url` that is `https`, if any.
6. Version bounds, if any, that parse: no build metadata, and `max_version` is the version
   the announcement is *about*, exclusive.

A validator is worth writing at the same time as the reader, because the reader's failure
mode is **silence** — publish a malformed announcement and nothing tells you, on either end.

Here that validator is a small **Rust binary in the same crate** (`rust/src/bin/announce.rs`,
native-only), which is strictly better than the Dart tool it is adapted from: it calls the
app's real parser, so it cannot accept anything the app would drop, and there is no second
copy of the schema constants to drift.

```sh
cargo run --bin announce -- --template > draft.json
# edit draft.json — all five locales, an expiry in the future
cargo run --bin announce -- draft.json --out event.json
nak event --sec <the offline key> wss://relay.mostro.network < event.json
```

**It does not sign and does not publish.** The key of §4.1 lives offline; signing stays
with `nak` or any client that holds it. Errors name the fix, not the rule: which locale is
missing, how many characters over the limit a title is, why build metadata is refused, and
that a `max_version` at or below `min_version` reaches nobody because the bound is
exclusive.

The procedure belongs in `docs/` once the tool exists, not only in this spec.

---

## 9. Testing

Rust unless stated otherwise. The pure-function layer needs no relay and no database.

| Area | Cases |
|---|---|
| Allowlist | allowed key accepted; any other key ignored; one undecodable entry does not disable the rest; an empty allowlist opens no subscription |
| Verification | tampered content, tampered tag, wrong signature — all dropped |
| Freshness | 31 days old ignored; dated 10 minutes ahead ignored; newer `created_at` at the same address replaces and re-announces; a redelivery does not re-announce; on an exact `created_at` tie the lower id replaces and the higher does not; the same `d` from two allowlisted keys are two announcements and neither marks the other read |
| Expiry | expired on arrival dropped; expiring while cached swept from the DB |
| Offline ageing | cached fresh, restored past the 30-day window → not rendered **and** gone from the DB; same for one that passes its `expiration` while offline; a still-valid neighbour in the same cache survives both sweeps |
| Re-announcement | a newer revision at a read address clears read state and the correction appears unread |
| Content | unknown `v` ignored; a missing locale ignored; an unknown sixth locale ignored; over-length title or body ignored; non-`https` `url` dropped **while the announcement still renders**; bounds in range, out of range, exactly at the exclusive `max_version`, with build metadata, and unparseable |
| Severity | each level renders its own colour, icon and label; a missing `severity` is invalid; an unrecognised value renders as `warning` **and still renders**; a `critical` sorts above a newer non-critical; dismissing a `critical` clears the badge and keeps the row, dismissing the other two removes it |
| Version source | the version the bounds compare against is the shipped release version, and drift between `rust/Cargo.toml` and `pubspec.yaml` fails the suite — **already covered** by `app_version_matches_pubspec` and `app_version_carries_no_build_number` (§4.3) |
| Consent | off ⇒ no subscription opened; switching off closes it at the tap and an event arriving immediately after is not processed; switching back on resumes delivery |
| Publisher tool | every §8 obligation rejected with a message naming the fix; the emitted event clears the app's own parser; a hand-built bad event does not, so the check has teeth |
| Dart widget | each of the five locales renders its own copy; the system banner shows title, body and the link button; read and dismiss persist across a restart; the dot appears only when something is unread |

Both suites gate this feature: `cd rust && cargo test && cargo clippy`, then
`flutter analyze && flutter test`.

---

## 10. Build order

The off switch ships **before** the surface, so the channel is never live without one. One
PR per step, per the workflow in CLAUDE.md.

| # | Step | Why here |
|---|---|---|
| 0 | ~~Fix the app-version source (§4.3)~~ — **done in this PR** | Version targeting is unusable while the version is not the shipped one, so it could not be left as a follow-up |
| 1 | §3 parsing and validation + the §4.1 allowlist, as pure Rust functions — no relay, no DB, no UI | Everything rests on it, and it is the cheapest thing to get wrong quietly. Ships with the allowlist **empty**, which is inert by construction |
| 2 | Fetch, verify, freshness, expiry, the `announcements` table and the schema bump (§4.2, §5) | Testable without a screen |
| 3 | The bridge surface + the Announcements toggle (§6.1, §7), then `./scripts/frb-generate.sh` | The off switch before the surface |
| 4 | Rendering into the existing notification surface, five locales of chrome (§6.2) | Last, when there is something to show |
| 5 | `rust/src/bin/announce.rs` + the publishing doc (§8) | With or just after step 1, sharing its validator |
| 6 | **Add the real npubs** — one line, its own PR, npubs checked against a source outside this repo | The only commit that makes the channel live |
| 7 | **Land MostroP2P/protocol#56** — the `38387` registration (§3) | A number reserved only in this repo is not reserved; it should land before the reader ships, and it depends on nothing here |

Steps 1–5 can all merge without the channel existing in production. That is the point.

---

## 11. Out of scope

- **Real push (FCM / Web Push).** The scaffolding is in the repo but it needs a service of
  ours holding a relay subscription and a device token per install — a backend, and a
  per-install identifier, which is the thing this app does not have. This channel works
  today on every platform including web and desktop, with no server; push, if it ever
  ships, can carry the same events without changing anything in §3.
- **Background relay subscriptions.** Doze kills them on Android and there is nothing to
  keep alive on web. A channel that works only while the phone is awake and charging is
  worse than one that is honestly foreground-only.
- **Targeted messages** to a particular user, node operator, or counterparty. Different
  trust model, different transport, separate spec. The allowlist built here is reusable on
  the reader side when that day comes.
- **Replies, reactions, or any inbound path.**
- **Node-authored announcements.** A Mostro node telling its own users something is a
  plausible next step and explicitly not this: it would be authored by the node key, not
  the project key, and §4.1 rule 1 says why those must not be the same list.
