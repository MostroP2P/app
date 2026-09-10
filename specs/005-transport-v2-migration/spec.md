# Feature Specification: Transport v2 — NIP-44 Direct Messaging

**Feature Branch**: `005-transport-v2-migration` (impl. across git branches `chore/mostro-core-0.13` → `feat/transport-v2`)
**Created**: 2026-06-19
**Status**: Draft
**Input**: Adopt the Mostro protocol-v2 transport (NIP-44 direct, kind 14), replacing
protocol-v1 gift wrap (kind 1059). This app targets **protocol v2 only** — no dual
support. Behavioural reference: `.specify/v1-reference/TRANSPORT_V2_MIGRATION.md`.

> **Scope note (post-005)**: this feature deliberately migrated the *daemon*
> channel only and left peer/dispute chat on gift wrap. #246 later moved chat to
> the kind 14 chat envelope, so no channel uses kind 1059 any more. The chat
> carve-out below (User Story 2, FR-004) is a record of 005's scope; the live
> chat contract is `specs/004-mostro-p2p-client/contracts/messages.md`.

---

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Trade against a protocol-v2 node (Priority: P1)

A user creates, takes, and progresses orders against a Mostro node running protocol
v2. Every Mostro-protocol message (commands sent and daemon replies received) travels
as a signed kind-14 NIP-44 event authored by the trade key, instead of a kind-1059
gift wrap. The user experiences no functional difference — the same orders, actions,
and chat work end to end.

**Why this priority**: The target node speaks only protocol v2. Without this, the app
cannot send to or receive from the daemon at all — it is non-functional.

**Independent Test**: Run a full order lifecycle (new-order → take → pay → fiat-sent →
release) against a v2 node and confirm every command is delivered and every reply is
received and parsed.

**Acceptance Scenarios**:

1. **Given** a v2 node, **When** the app sends any Mostro command, **Then** it is
   published as a kind-14 event authored by the trade key, NIP-44 encrypted to the
   node, with `version: 2` in the message and a `p` tag to the node.
2. **Given** a v2 node, **When** the daemon replies, **Then** the app receives the
   kind-14 event (authored by the node, `p`-tagged to the trade key), decrypts it,
   and routes the message exactly as it did under gift wrap.
3. **Given** an incoming kind-14 event **not** authored by the node, **When** received
   on a trade-key subscription, **Then** it is ignored as a Mostro reply (it is peer
   chat, handled separately).

### User Story 2 — Peer-to-peer chat is unaffected (Priority: P1)

> **Superseded by #246.** This story scoped the migration: chat was deliberately
> left alone so the daemon transport could move on its own. Chat has since moved
> too — to the **chat envelope**, not to the daemon's form — so the requirement
> below is a record of 005's scope, not a live one. See
> `specs/004-mostro-p2p-client/contracts/messages.md`.

A user in an active trade exchanges encrypted chat messages with the counterparty and
(if disputed) with an admin. At the time of this migration that traffic used NIP-59
gift wrap (kind 1059) and was unchanged by it.

**Why this priority**: Regression guard. The migration must not break existing chat.

**Independent Test**: Exchange peer-chat messages during an active trade; confirm
delivery and decryption are unchanged.

**Acceptance Scenarios**:

1. **Given** an active trade, **When** a peer chat message is sent, **Then** it is
   delivered and decrypted as before — under 005, still wrapped as a kind-1059
   gift wrap; since #246, as a kind-14 chat envelope.

---

## Requirements *(mandatory)*

- **FR-001**: All Mostro-protocol traffic (typed `Message`) MUST use protocol v2
  (kind 14, NIP-44 direct) on both send and receive.
- **FR-002**: The app MUST NOT retain any protocol-v1 (gift-wrap) path for Mostro
  traffic, and MUST NOT resolve a per-node transport. **Diagnostic exception**:
  the app MAY parse `protocol_version` from the node's Kind 38385 event — never
  to select a transport, only to refuse sending to an incompatible node with an
  explicit error (`UnsupportedNodeProtocol:{advertised}`) instead of the silent
  timeout a v1 node otherwise produces. Only an explicit `protocol_version = 2`
  proves compatibility: an absent tag means a pre-tag daemon speaking legacy v1
  (per the protocol migration guide) and MUST be refused too. The verdict is
  tagged with the node it was fetched from and, like FR-007's PoW snapshot,
  senders MUST wait for the active node's fetch and fail closed (retryable
  `NodeCapabilitiesUnknown`) rather than apply another node's — or no —
  verdict.
- **FR-003**: Incoming kind-14 Mostro replies MUST be disambiguated from NIP-17 peer
  chat by author = node pubkey (subscription author-pin + per-event re-check).
- **FR-004**: Peer-to-peer chat and dispute-admin chat MUST NOT be changed by this
  migration. *(As written in 005 this read "MUST remain on gift wrap (kind 1059)".
  **Superseded by #246**, which moved both to the chat envelope — a kind 14 outer
  event signed with `K_sign`, carrying a NIP-44-encrypted inner kind 1 signed by
  the trade key — to close a gift-wrap flood attack. This client now reads and
  writes no kind 1059 in either direction; the live contract is
  `specs/004-mostro-p2p-client/contracts/messages.md`.)*
- **FR-005**: Outgoing v2 events MUST carry no NIP-40 expiration tag (`expiration:
  None`), mirroring the reference client; the daemon fills its own.
- **FR-006**: Full-privacy mode MUST behave as today (identity key = trade key).
- **FR-007**: Outgoing v2 events MUST be mined (NIP-13) to the difficulty the
  connected node advertises in its Kind 38385 event: `pow` for every event, and
  `pow_first_contact` for **first-contact** events — ones whose visible sender is
  a trade key the node does not yet associate with an active order or dispute:
  creating an order, taking one, or a restore under a fresh trade key. Selection
  rules (issue #177):
  - An absent `pow_first_contact` tag means *unknown* — not zero and not `pow`;
    first-contact events then fall back to mining at `pow`.
  - A published `pow_first_contact` lower than `pow` MUST be clamped up to `pow`
    (the protocol states it is never lower; a node advertising otherwise is
    clamped rather than trusted).
  - Both difficulties MUST be refreshed together from the same Kind 38385 fetch
    and published to senders as a single snapshot, tagged with the node it was
    fetched from, so a wrap in flight during a refresh can never mix values
    from two generations.
  - First-contact events MUST only be mined against a snapshot fetched from the
    node they are addressed to: before the first fetch completes (startup) and
    right after a node switch no such snapshot exists, and the sender MUST wait
    for the fetch and fail closed (an explicit, retryable error) rather than
    mine at a default or at the previous node's difficulty.
  - An under-powered event is dropped before the node decrypts anything, with no
    `cant-do` and no reply of any kind — the caller sees only a timeout.

## Out of Scope

- Dual v1/v2 support, `protocol_version` auto-detection, transport selection UI.
- Peer / dispute chat transport.
- Mostro message logic, action set, payload shapes, key derivation (unchanged).
- Anti-abuse bond (separate feature; see `ANTI_ABUSE_BOND.md`).
