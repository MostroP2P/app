# Research: Transport v2 Migration

Findings grounding [plan.md](plan.md). All verified against `mostro-core` tags
0.10.0 ↔ 0.13.1, `mostro-cli` (reference client), and this app's source.

## R1 — `mostro-core` 0.10.0 → 0.13.1 breaking-change audit

- **nip59 API is unchanged** across the range: `wrap_message`, `unwrap_message`,
  `WrapOptions`, `UnwrappedMessage`, `validate_response` keep identical signatures.
  → the existing gift-wrap path compiles untouched after the bump.
- **Only one compile breakage**: `map_core_status` (`api/orders.rs`). `order::Status`
  gains `WaitingTakerBond` + `WaitingMakerBond` (additive, no renames/removals); the
  exhaustive match without a wildcard fails until those arms are added.
- Other used symbols stable: `Payload::{Order,PaymentRequest,CantDo}` (same arity),
  `MostroError::MostroCantDo`, `new_order`/`new_dm`.
- **`PROTOCOL_VER`** = 1 through 0.12.1, → **2 at 0.13.0**. Stamped automatically by
  `MessageKind::new`; the app never sets `version` by hand.

## R2 — Why jump straight to 0.13.1 (not via 0.12.1)

The `transport` module exists **only from 0.13.0**; 0.12.1 lacks it and keeps
`PROTOCOL_VER = 1`, so it is a useless intermediate. nip59 API stability means no
risk-isolation benefit to stepping. Decision: **0.13.1** (latest patch).

## R3 — Transport API surface (0.13.1, via `mostro_core::prelude`)

`Transport { GiftWrap, Nip44Direct }`; `Transport::Nip44Direct.event_kind()` =
`Kind::PrivateDirectMessage` (kind 14). `wrap_message_with(transport, msg,
identity_keys, trade_keys, receiver, WrapOptions)`. `unwrap_incoming(event, keys)`
dispatches by event kind and returns `UnwrappedMessage` (same type as today).

## R4 — Subscription / receive sites in this app (Q1)

`mostro_pubkey` source: `crate::config::active_mostro_pubkey()`. Three kind-1059
subscriptions and three receive handlers to migrate:

| Site | File | mostro_pubkey present? |
|---|---|---|
| bulk DM sub | `relay_pool.rs` (`subscribe_order_and_dm_feeds`) | yes |
| per-trade sub | `orders.rs` (`subscribe_gift_wraps`) | add helper call |
| global bulk sub | `orders.rs` (global loop) | yes |
| 3 receive handlers | `orders.rs` (per-trade / global / event loop) | — change kind check + author re-check |

## R5 — Expiration on outgoing v2 events (Q2)

`mostro-cli` passes `expiration: None` for all command DMs to Mostro; the daemon fills
its own outgoing expiration from `dm_days`. The anti-spam gate does not require an
expiration on incoming events. Decision: **`expiration: None`**.

## R6 — flutter_rust_bridge (Q3)

FRB scans `rust_input: "crate::api"`. `gift_wrap.rs` / `relay_pool.rs` are in
`crate::nostr` and absent from `frb_generated.rs`. The transport switch changes only
function bodies in `crate::api`, not signatures, and the FRB boundary uses `api::types`
(not mostro-core types). → **No regen needed.**
