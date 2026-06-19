# Tasks: Transport v2 — NIP-44 Direct Messaging

**Input**: Design documents from `specs/005-transport-v2-migration/`
**Prerequisites**: spec.md ✅, plan.md ✅, research.md ✅

**Tests**: Existing `gift_wrap.rs` unit tests are updated (not new test tasks).

**Organization**: Two phases = two PRs. Phase 2 depends on Phase 1.

## Phase 1 — mostro-core bump (PR #1: `chore/mostro-core-0.13`)

- [ ] T001 Set `mostro-core = "0.13.1"` in `rust/Cargo.toml`; update `Cargo.lock`.
- [ ] T002 Fix `map_core_status` in `rust/src/api/orders.rs`: add explicit arm
      `S::WaitingTakerBond | S::WaitingMakerBond => return None` (no wildcard).
- [ ] T003 Run `cargo build && cargo test && cargo clippy`; resolve any residual
      fallout surfaced by the compiler. **Checkpoint**: green, app still on gift wrap.

## Phase 2 — transport switch (PR #2: `feat/transport-v2`)

- [ ] T004 `gift_wrap.rs::wrap_mostro_message` → `wrap_message_with(Transport::Nip44Direct,
      …, WrapOptions { pow, expiration: None, signed: true })`.
- [ ] T005 `gift_wrap.rs::unwrap_mostro_message` → `unwrap_incoming(event, trade_keys)`.
- [ ] T006 [P] `relay_pool.rs::subscribe_order_and_dm_feeds` dm_filter → kind 14 +
      `.author(mostro_pubkey)`.
- [ ] T007 [P] `orders.rs::subscribe_gift_wraps` filter → kind 14 + `.author(...)`
      (resolve `mostro_pubkey` via `config::active_mostro_pubkey()`).
- [ ] T008 [P] `orders.rs` global bulk `gw_filter` → kind 14 + `.author(...)`.
- [ ] T009 Update the three receive handlers in `orders.rs` (per-trade, global,
      event loop): kind-14 check + reject `event.pubkey != mostro_pubkey`.
- [ ] T010 Update `gift_wrap.rs` tests: assert kind 14 + author = trade key.
- [ ] T011 Leave local `wrap`/`unwrap` (peer/dispute chat, kind 1059) untouched —
      regression-verify peer chat still works.
- [ ] T012 `cargo test && cargo clippy` green; manual E2E order lifecycle vs the v2
      node. **Checkpoint**: full trade flow works on protocol v2.
