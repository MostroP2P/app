# Transport v2 — NIP-44 Direct Messaging (Protocol Migration)

How this app (appv2) adopts the Mostro **protocol-v2 transport** (NIP-44 direct,
kind `14`), replacing protocol-v1 gift wrap (kind `1059`). This document is the
**behavioural reference**: it explains the protocol change, how the canonical
client (`mostro-cli`) implemented it on top of `mostro-core`, why `mostro-cli`
— not the mobile app — is our reference, and why this app targets **protocol v2
only** with no v1 compatibility.

> **Two "v1/v2" axes — do not conflate them.** This folder documents *app* v1
> (Mostro Mobile) as a reference for *app* v2 (this Rust + Flutter client).
> This document instead concerns the *protocol* transport: *protocol* v1 (gift
> wrap) → *protocol* v2 (NIP-44 direct). Throughout, "v1"/"v2" mean the
> **protocol transport** unless prefixed with "app".

> **Reference exception (deliberate).** Every other doc in this folder derives
> from Mostro Mobile v1. This one derives from **`mostro-cli`** instead — see
> §4 for why. Mobile's transport implementation is *not* a useful reference for
> us because mobile does not use `mostro-core`.

> **Status — pending in v2.** This app is still on `mostro-core 0.10` and speaks
> protocol v1 today. This document is the parity/design reference for the
> migration; the concrete, repo-specific implementation plan lives in the specs
> (`specs/005-transport-v2-migration/`).

> **Scope.** The transport is a **protocol-level** change to the *envelope only*.
> The logical Mostro messages, the action set, payload shapes and key derivation
> are identical across v1 and v2. NIP-17 peer-to-peer chat and dispute-admin chat
> are **out of scope** — they stay on gift wrap (§7).

---

## 1. Why the protocol is changing

Mostro historically used NIP-59 gift wrap (kind `1059`) as its only transport.
Gift wraps give strong metadata privacy but are *opaque*: the outer event is
signed by a random throwaway key, so neither relays nor the daemon can tell
legitimate traffic from spam without paying the full NIP-44 decrypt cost. That
exposes Mostro to spam floods relays cannot rate-limit by sender ("Gift Wrap
Apocalypse").

Protocol **v2** trades a bounded amount of metadata for abuse-resistance: a
signed kind-`14` event whose content is NIP-44 encrypted, **authored by the
trade key**. Because trade keys are already single-trade and rotated, exposing
one leaks little — while it lets relays rate-limit by sender and lets the daemon
pre-validate cheaply before decrypting.

- **Official source:** https://mostro.network/protocol/transport_migration.html
- **Daemon spec:** mostro issue #626; `mostro-core#152` (the `transport` module,
  released in **mostro-core 0.13.0**; this app pins **0.13.1**, the latest patch).

## 2. Wire format: v1 vs v2

| | protocol v1 (`gift-wrap`) | protocol v2 (`nip44`) |
|---|---|---|
| event kind | `1059` | `14` |
| outer author | throwaway ephemeral key | **the trade key** (signature load-bearing) |
| layers | rumor (k1) → seal (k13) → wrap (k1059) | single k14 event, NIP-44 encrypted content |
| inner payload | 2-tuple `[message, tradeSig?]` | 3-tuple `[message, tradeSig?, identityProof?]` |
| identity proof | carried inside the seal | carried **inside** the NIP-44 ciphertext |
| `message.version` | `1` | `2` |
| expiration | none | NIP-40 `expiration` tag (default 30 days) |

The v2 **identity proof** (3rd tuple element) is `["<identity pubkey>",
"<identity sig>"]`, or `null` for full-privacy mode. The signature is over a
domain-tagged payload binding the proof to the authoring trade key:

```text
mostro-transport-v2-identity:<trade pubkey hex>:<message JSON>
```

**All of the above is implemented by `mostro-core` 0.13.0** — tuple building,
identity proof, NIP-44 encryption, event signing, and signature verification on
receive. A client on `mostro-core` does not write any of it (this is the crux
of §4).

## 3. Capability discovery (and why we don't use it)

Nodes advertise their transport in the kind-`38385` instance-info event:

```text
["protocol_version", "1"]   → gift wrap (kind 1059), DEPRECATED
["protocol_version", "2"]   → NIP-44 direct (kind 14)
(tag absent)                → legacy daemon → treat as v1
```

Clients meant to bridge the migration window read this tag and pick the wire
format per node. **This app does not** — it is v2-only (§5), so it neither
parses `protocol_version` nor resolves a per-node transport.

## 4. Why `mostro-cli` is the reference, not mobile

| | uses `mostro-core`? | what its transport code is |
|---|---|---|
| **this app (appv2)** | **yes** (Rust core) | thin wiring over `mostro-core` |
| **`mostro-cli`** | **yes** (Rust) | thin wiring over `mostro-core` — *our analogue* |
| **mobile** | **no** | hand-rolled crypto in Dart |

Mobile reimplements the entire transport by hand in Dart — building the 3-tuple,
computing the identity proof, signing, NIP-44 encrypting, verifying event
signatures. None of that maps to this app, because `mostro-core` already does
it. Copying mobile would mean reimplementing the library.

`mostro-cli` solved the *same* problem we have: it consumes `mostro-core`'s
`transport` module and only wires it into send/receive. Its code shows the exact
APIs and call patterns we will use.

## 5. Decision: protocol v2 only (no dual v1/v2 support)

`mostro-cli` and mobile both implement **dual** v1+v2 support and auto-detect per
node. That is a **transition safeguard for real users** who may connect to a not-
yet-upgraded daemon. This app has no such constraint:

- it is **in development with no users**, and
- the Mostro node it targets **already runs protocol v2**.

So dual support would be dead code. This app implements **protocol v2 only**,
which is also where the ecosystem lands at mostrod **v0.19.0** (v1 removed
entirely). Consequences vs. the dual design:

| Dual-support concern | In this app (v2-only) |
|---|---|
| `Transport` enum + per-node resolution | **removed** — always v2 |
| `protocol_version` parse (kind 38385) | **removed** |
| version-skew guard / downgrade logging | **removed** |
| dual subscription / re-subscribe | subscribe to kind `14` only, author-pinned |
| `version` field derived from transport | constant `2` |

No log/guard for a v1 node is kept: the target node only speaks v2 (decision
confirmed with the maintainer).

## 6. How `mostro-cli` implemented it (the reference)

All transport APIs come from `mostro_core::prelude::*`. The wiring:

| Concern | `mostro-cli` location | `mostro-core` API |
|---|---|---|
| Send (wrap + publish) | `src/util/messaging.rs` (`publish_wrapped`) | `wrap_message_with(transport, msg, identity_keys, trade_keys, receiver, WrapOptions { pow, expiration, signed })` |
| Receive (unwrap) | `src/parser/dms.rs` (`parse_dm_events`) | `unwrap_incoming(event, keys)` → `UnwrappedMessage` (dispatches by kind) |
| Subscription kind | `src/util/messaging.rs` (`wait_for_dm`) | `transport.event_kind()` (1059 / 14) |
| Transport selection | `src/cli.rs` (`resolve_transport`) | `Transport::from_str`, default `GiftWrap` |
| `protocol_version` probe | `src/util/events.rs` (`fetch_protocol_version_with`) | reads kind-38385 tag |

Two patterns from `mostro-cli` matter to us even though we drop its dual logic:

1. **v2 kind-14 must pin the author.** kind `14` is shared with NIP-17 peer chat,
   so the receive filter pins `authors = [mostro_pubkey]` and re-checks
   `event.pubkey == mostro_pubkey` on each event (`wait_for_dm`). A v2 Mostro
   reply is authored by Mostro and `p`-tagged to the trade key.
2. **Mostro traffic and peer chat are unwrapped on separate paths.**
   `parse_dm_events` routes Mostro messages through `unwrap_incoming`, but peer
   chat through its own decrypt path — never `unwrap_incoming`. This keeps peer
   chat from being misparsed as a Mostro message now that both are kind 14.

For full-privacy mode, `mostro-cli` passes the same `Keys` for both identity and
trade — identical to v1 and to this app's current behaviour.

## 7. What stays on gift wrap (unchanged)

NIP-17 peer-to-peer chat and dispute-admin chat are **not** part of this
migration. In this app these are the local `wrap` / `unwrap` helpers in
`rust/src/nostr/gift_wrap.rs` (used by `api/messages.rs` and `api/disputes.rs`).
They keep using kind `1059`. v2 Mostro kind-14 traffic is disambiguated from
peer chat by **author = Mostro pubkey** + `p` tag (§6). All three clients
(mobile, `mostro-cli`, this app) agree chat is out of scope.

## 8. What this means for this app (high level)

The detailed, ordered implementation plan lives in the specs
(`specs/005-transport-v2-migration/`). At a glance, the work is almost entirely
Rust-side and small once `mostro-core` is current:

1. **Bump `mostro-core` 0.10 → 0.13.1** — the real bulk (the `0.10`→`0.13`
   breaking changes), independent of the transport switch.
2. **Switch the two Mostro-protocol functions** in `rust/src/nostr/gift_wrap.rs`
   (`wrap_mostro_message` / `unwrap_mostro_message`) to the `mostro-core` v2
   path (`wrap_message_with` / `unwrap_incoming`), with a NIP-40 expiration.
3. **Make the subscription kind-14 + author-pinned** in
   `rust/src/nostr/relay_pool.rs` (today hard-codes `KIND_GIFT_WRAP = 1059`).
4. **Leave the peer-chat `wrap`/`unwrap` helpers untouched** (§7).

The Dart layer is essentially untouched: with v2-only there is no
`protocol_version` parsing or transport resolution to add.

---

**Sources**
- Official: https://mostro.network/protocol/transport_migration.html
- Daemon: mostro issue #626; `mostro-core#152` (transport module, 0.13.0)
- Reference client: `MostroP2P/mostro-cli` (PRs #176–#178)
