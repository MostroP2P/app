# Tasks: Transport v2 — NIP-44 Direct Messaging

> **Scope note (post-005)**: this feature migrated the *daemon* channel only and
> deliberately left peer/dispute chat on gift wrap (kind 1059). #246 later moved
> chat to the kind 14 chat envelope, so no channel uses kind 1059 any more. The
> "chat stays on gift wrap" steps below are a record of what 005 did, not a live
> requirement — see `specs/004-mostro-p2p-client/contracts/messages.md`.

**Input**: Design documents from `specs/005-transport-v2-migration/`
**Prerequisites**: spec.md ✅, plan.md ✅, research.md ✅

**Tests**: Existing `gift_wrap.rs` unit tests are updated (not new test tasks).

**Organization**: Two phases = two PRs. Phase 2 depends on Phase 1.

**Status: done.** Merged in #111 and verified end-to-end on a v2 node. The
plan below is kept as a historical record — do not use it as a map of the
current code. It has since been superseded by further refactors: `mostro-core`
is now `0.14.1` (past the `0.13.1` this plan targeted), `gift_wrap.rs` no
longer exists (`wrap_mostro_message`/`unwrap_mostro_message` now live in
`rust/src/nostr/transport.rs`), and T011's "leave gift wrap on peer/dispute
chat untouched" no longer holds — that chat also moved off gift wrap
entirely (kind-14 chat envelope) in #246/#254.

## Phase 1 — mostro-core bump (PR #1: `chore/mostro-core-0.13`)

- [x] T001 Set `mostro-core = "0.13.1"` in `rust/Cargo.toml`; update `Cargo.lock`.
- [x] T002 Fix `map_core_status` in `rust/src/api/orders.rs`: add explicit arm
      `S::WaitingTakerBond | S::WaitingMakerBond => return None` (no wildcard).
- [x] T003 Run `cargo build && cargo test && cargo clippy`; resolve any residual
      fallout surfaced by the compiler. **Checkpoint**: green, app still on gift wrap.

## Phase 2 — transport switch (PR #2: `feat/transport-v2`)

- [x] T004 `gift_wrap.rs::wrap_mostro_message` → `wrap_message_with(Transport::Nip44Direct,
      …, WrapOptions { pow, expiration: None, signed: true })`.
- [x] T005 `gift_wrap.rs::unwrap_mostro_message` → `unwrap_incoming(event, trade_keys)`.
- [x] T006 [P] `relay_pool.rs::subscribe_order_and_dm_feeds` dm_filter → kind 14 +
      `.author(mostro_pubkey)`.
- [x] T007 [P] `orders.rs::subscribe_gift_wraps` filter → kind 14 + `.author(...)`
      (resolve `mostro_pubkey` via `config::active_mostro_pubkey()`).
- [x] T008 [P] `orders.rs` global bulk `gw_filter` → kind 14 + `.author(...)`.
- [x] T009 Update the three receive handlers in `orders.rs` (per-trade, global,
      event loop): kind-14 check + reject `event.pubkey != mostro_pubkey`.
- [x] T010 Update `gift_wrap.rs` tests: assert kind 14 + author = trade key.
- [x] T011 Leave local `wrap`/`unwrap` (peer/dispute chat, kind 1059) untouched —
      regression-verify peer chat still works. _(Superseded: this chat later
      moved off gift wrap too, see status note above.)_
- [x] T012 `cargo test && cargo clippy` green; manual E2E order lifecycle vs the v2
      node. **Checkpoint**: full trade flow works on protocol v2.
