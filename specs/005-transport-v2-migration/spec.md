# Feature Specification: Transport v2 — NIP-44 Direct Messaging

**Feature Branch**: `005-transport-v2-migration` (impl. across git branches `chore/mostro-core-0.13` → `feat/transport-v2`)
**Created**: 2026-06-19
**Status**: Draft
**Input**: Adopt the Mostro protocol-v2 transport (NIP-44 direct, kind 14), replacing
protocol-v1 gift wrap (kind 1059). This app targets **protocol v2 only** — no dual
support. Behavioural reference: `.specify/v1-reference/TRANSPORT_V2_MIGRATION.md`.

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

A user in an active trade exchanges encrypted chat messages with the counterparty and
(if disputed) with an admin. This traffic continues to use NIP-59 gift wrap (kind 1059)
and is unchanged by the transport migration.

**Why this priority**: Regression guard. The migration must not break existing chat.

**Independent Test**: Exchange peer-chat messages during an active trade; confirm
delivery and decryption are unchanged.

**Acceptance Scenarios**:

1. **Given** an active trade, **When** a peer chat message is sent, **Then** it is
   still wrapped as a kind-1059 gift wrap and delivered/decrypted as before.

---

## Requirements *(mandatory)*

- **FR-001**: All Mostro-protocol traffic (typed `Message`) MUST use protocol v2
  (kind 14, NIP-44 direct) on both send and receive.
- **FR-002**: The app MUST NOT retain any protocol-v1 (gift-wrap) path for Mostro
  traffic, and MUST NOT parse `protocol_version` or resolve a per-node transport.
- **FR-003**: Incoming kind-14 Mostro replies MUST be disambiguated from NIP-17 peer
  chat by author = node pubkey (subscription author-pin + per-event re-check).
- **FR-004**: NIP-17 peer-to-peer chat and dispute-admin chat MUST remain on gift
  wrap (kind 1059), unchanged.
- **FR-005**: Outgoing v2 events MUST carry no NIP-40 expiration tag (`expiration:
  None`), mirroring the reference client; the daemon fills its own.
- **FR-006**: Full-privacy mode MUST behave as today (identity key = trade key).

## Out of Scope

- Dual v1/v2 support, `protocol_version` auto-detection, transport selection UI.
- Peer / dispute chat transport.
- Mostro message logic, action set, payload shapes, key derivation (unchanged).
- Anti-abuse bond (separate feature; see `ANTI_ABUSE_BOND.md`).
