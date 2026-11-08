# Publishing an announcement

The app reads signed Nostr events of kind `38387` from a short list of project keys and
shows them as cards in Notifications: "2.2 is out and fixes X", "the public node is down
for maintenance tonight", "this relay is being retired". No server, no account, no push
token — the signature is the whole trust model. The design is
[`specs/006-announcement-channel/spec.md`](../specs/006-announcement-channel/spec.md); the
wire contract is the protocol's
[`announcement_event.md`](https://github.com/MostroP2P/protocol/blob/main/src/announcement_event.md).
This page is the procedure.

## What you need

- **One of the announcement keys.** The app trusts only the `npub`s compiled into
  `rust/src/nostr/announcements.rs` (`ALLOWLIST`). They are dedicated keys, kept offline,
  used for nothing else — never a maintainer's personal key and never a node key. Adding or
  retiring one is a one-line pull request of its own, with the `npub` checked against a
  source outside this repository.
- **`nak`** (<https://github.com/fiatjaf/nak>), or any client that signs an event from a
  JSON on stdin. The validator below never sees the key.
- The repository, to run the validator: `cargo run --bin announce`, native only.

## The procedure

```sh
cd rust
cargo run --bin announce -- --template > draft.json
# edit draft.json — see "The draft" below
cargo run --bin announce -- draft.json --out event.json
nak event --sec <the offline key> \
  wss://relay.mostro.network wss://mostro-p2p.tech wss://relay.shadowbip.com < event.json
```

The validator calls the app's own parser, so it cannot accept what the app would drop. It
also refuses what the app merely tolerates — an unknown `severity`, a link that is not
`https` — because those reach the user wrong without anyone noticing. Every problem it
finds names the fix. It does not sign and does not publish.

Publish to **every relay the app ships with** (`rust/src/config.rs`, `DEFAULT_RELAYS`): the
app reads announcements through its own relay pool, and a relay it is not connected to is
a relay it never asks.

## The draft

```json
{
  "id": "2026-10-release-2-2",
  "expires_in_days": 14,
  "min_version": null,
  "max_version": "2.2",
  "severity": "info",
  "url": "https://mostro.network/",
  "locales": {
    "en": { "title": "Mostro 2.2 is out", "body": "It fixes the invoice timeout." },
    "es": { "title": "…", "body": "…" },
    "fr": { "title": "…", "body": "…" },
    "de": { "title": "…", "body": "…" },
    "it": { "title": "…", "body": "…" },
    "nl": { "title": "…", "body": "…" },
    "pt": { "title": "…", "body": "…" }
  }
}
```

| Field | Rule |
|---|---|
| `id` | The `d` tag. **Never used before** — unless you are correcting a live announcement, in which case the same `id` from the **same key** replaces it (see below). |
| `expires_in_days` / `expiration` | One of the two, required. When it passes, the card disappears from every device, online or not. An outage notice gets hours; a release, a couple of weeks. Nothing is permanent. |
| `min_version` | Show only to app versions **≥** this. For "2.2 changed how X works". |
| `max_version` | Show only to app versions **<** this: write the version the announcement is *about*. "2.2 is out" with `max_version: "2.2"` reaches everyone below 2.2 and nobody on it. Semver; no build metadata (`2.2.0+7`). |
| `severity` | `info` (releases, features, events), `warning` (outages, a relay retired, anything with a deadline), `critical` (a security issue the user must act on now). The app paints the level; you never choose a colour. **`critical` is for security.** Spend it on a release and users learn that red means nothing. |
| `url` | At most one link, `https` only. It is the only tappable thing on the card. |
| `locales` | **All seven, no others**: `en es fr de it nl pt` — the app's locales, and the only ones it can render. There is no fallback to English on purpose. Title ≤ 80 characters, body ≤ 500, plain text: no markup, no links in the body. |

The app shows the copy of the locale the phone is in. Write the English first, translate
the rest before publishing; the validator refuses a missing locale.

## Correcting a live announcement

Publish again with the **same `id`, from the same key**. The event is addressable, so the
new revision replaces the old one on the relays and in the app, where it shows up **unread
again** — the user who dismissed the wrong maintenance window sees the right one. A
different allowlisted key with the same `id` is a second announcement, not a correction.

To retract one, publish a correction with an `expiration` a minute ahead. There is no
delete.

## What the app does with it

- Reads only the allowlisted keys, verifies the signature itself, and drops without a word
  anything older than 30 days, dated more than 5 minutes ahead, expired, outside the
  version bounds, or not the contract. A user who never gets an announcement cannot tell.
- Caches the 20 newest. The cache is re-checked against the clock on every launch and
  resume, so an expiry holds offline.
- Shows it as a card in Notifications, painted by level, with the level's label and its
  link as a button. A `critical` sorts first, turns the bell's dot red, and stays listed
  (read) once swiped away, until it expires. The other levels leave on a swipe.
- Honours the **Announcements** toggle in Settings → Notifications: off closes the relay
  subscription at the tap. Nothing is ever published back — no read receipt, no
  acknowledgement.

## Checklist before `nak`

1. The validator printed the summary and `✓ unsigned event written`.
2. The seven titles in the summary are the right language each.
3. The expiry and the version bounds say what you mean (`reaches …`).
4. The `id` is new — or you mean to replace the announcement that already has it.
5. The key you sign with is on `ALLOWLIST` of the **released** app. A key merged to `main`
   but not yet shipped reaches nobody.
