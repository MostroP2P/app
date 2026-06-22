# Implementation Plan: Transport v2 — NIP-44 Direct Messaging

**Branch**: `005-transport-v2-migration` | **Date**: 2026-06-19 | **Spec**: [spec.md](spec.md)
**Reference**: [`.specify/v1-reference/TRANSPORT_V2_MIGRATION.md`](../../.specify/v1-reference/TRANSPORT_V2_MIGRATION.md)

## Summary

Migrate this app's Mostro-protocol transport from gift wrap (kind 1059) to NIP-44
direct (kind 14), targeting **protocol v2 only**. The heavy lifting is in
`mostro-core` 0.13.x (the `transport` module); this app only re-wires its two
Mostro wrap/unwrap call paths and its three kind-1059 subscriptions. Peer chat stays
on gift wrap. Delivered as **two PRs**: (1) the `mostro-core` 0.10 → 0.13.1 bump,
(2) the transport switch.

## Technical Context

**Language/Version**: Rust stable 1.94+ (core); Dart 3.x / Flutter 3.x (UI shell)
**Key Dependency Change**: `mostro-core` 0.10.0 → **0.13.1**
**New APIs used** (from `mostro_core::prelude`): `Transport::Nip44Direct`,
`wrap_message_with`, `unwrap_incoming` (`WrapOptions` reused from nip59).
**Testing**: `cargo test && cargo clippy` (per CLAUDE.md)
**FRB**: No regen — changes are internal to `crate::nostr`, not `crate::api`.

## Constitution Check

| Principle | Status | Notes |
|-----------|--------|-------|
| **I. Rust Core, Flutter Shell** | ✅ PASS | All transport logic stays in Rust; Dart untouched. |
| **II. Privacy by Design** | ✅ PASS | Identity privacy unchanged (proof inside NIP-44 ciphertext). v2 exposes only the ephemeral trade key's activity — accepted, bounded by per-trade rotation. |
| **III. Protocol Compliance** | ⚠️ DEVIATION (justified) | v2-only means **not** interoperable with v1 daemons. Justified: no users, target node is v2, aligned with mostrod v0.19.0 (v1 removed). Recorded in reference doc §5. |
| **VI. Simplicity Over Features** | ✅ PASS | Dropping dual support removes an enum, per-node resolution, and the `protocol_version` parse path. |
| **VII. V1 UX is Non-Negotiable** | ✅ PASS | No UX change; transport is invisible to the user. |

## Phase 1 — Bump `mostro-core` 0.10.0 → 0.13.1 (PR #1)

Prerequisite, isolated from the transport feature. The gift-wrap path stays in place,
so the app compiles and tests pass; it is **not** E2E-functional against the v2 node
yet (acceptable: no users, dev). Audit findings in [research.md](research.md).

1. `rust/Cargo.toml` — `mostro-core = "0.13.1"`.
2. Fix the **only** compile breakage: `map_core_status` (`api/orders.rs`) is an
   exhaustive match; `order::Status` adds `WaitingTakerBond` / `WaitingMakerBond`
   (purely additive). Add an explicit arm `S::WaitingTakerBond | S::WaitingMakerBond
   => return None` (bond is out of scope; no wildcard, to keep exhaustiveness).
3. `cargo build && cargo test && cargo clippy` green. (Note: `PROTOCOL_VER` becomes 2
   automatically; messages are version 2 even while still gift-wrapped — irrelevant,
   the v2 node ignores kind 1059.)

## Phase 2 — Transport switch to v2 (PR #2)

Mechanical, ~2 files. Mirrors `mostro-cli` (the reference).

### Send

4. `rust/src/nostr/gift_wrap.rs` (`wrap_mostro_message`): replace `nip59::wrap_message`
   with `wrap_message_with(Transport::Nip44Direct, msg, identity_keys, trade_keys,
   *receiver, WrapOptions { pow, expiration: None, signed: true })`.

### Receive

5. `rust/src/nostr/gift_wrap.rs` (`unwrap_mostro_message`): replace `nip59::unwrap_message`
   with `unwrap_incoming(event, trade_keys)`.

### Subscriptions (kind 14 + author-pin) — three filters

6. `rust/src/nostr/relay_pool.rs` (`subscribe_order_and_dm_feeds`): dm_filter →
   `Kind::PrivateDirectMessage` (14) + `.author(mostro_pubkey)` (already available).
7. `rust/src/api/orders.rs` (`subscribe_gift_wraps`): filter → kind 14 + `.author(...)`;
   fetch `mostro_pubkey` via `crate::config::active_mostro_pubkey()`.
8. `rust/src/api/orders.rs` (global bulk sub): `gw_filter` → kind 14 + `.author(...)`
   (`mostro_pubkey` already in scope).

### Receive handlers (kind check + author re-check) — three sites

9. `api/orders.rs` per-trade handler, global handler, and the global event loop:
   change `event.kind == 1059` checks to kind 14 **and** reject events where
   `event.pubkey != mostro_pubkey` (disambiguate from peer chat).

### Untouched

10. `gift_wrap.rs` local `wrap`/`unwrap` (peer/dispute chat) stay on kind 1059.

### Verify

11. Update `gift_wrap.rs` tests (assert kind 14 + author = trade key instead of
    `Kind::GiftWrap`). `cargo test && cargo clippy` green. Manual E2E lifecycle vs
    the v2 node.

## Complexity Tracking

The only deliberate complexity/deviation is **Constitution III** (v2-only, not
v1-interoperable) — justified above and in the reference doc.
