# Anti-Abuse Bond — Client Implementation Spec & Phased Plan

**Status:** Draft — planning document for epic [#145](https://github.com/MostroP2P/app/issues/145)
**Goal:** let this client trade against a `mostrod` node that requires an anti-abuse bond, on every side the node enforces it (taker, maker, or both), including the payout claim and the forfeiture notice
**Audience:** contributors implementing bond support in this client (appv2), human and AI reviewers of the PRs that land it
**Upstream reference:** [`MostroP2P/mostro` — `docs/ANTI_ABUSE_BOND.md`](https://github.com/MostroP2P/mostro/blob/main/docs/ANTI_ABUSE_BOND.md) (the daemon-side spec, the single source of truth for the protocol)
**Parity reference:** [`MostroP2P/mobile` — `docs/architecture/ANTI_ABUSE_BOND.md`](https://github.com/MostroP2P/mobile/blob/main/docs/architecture/ANTI_ABUSE_BOND.md) (how the v1 client did it — consulted for completeness, **not** copied: v1 hand-rolls protocol state in Dart, here it lives in Rust)

---

## Table of contents

1. [Goal and scope](#1-goal-and-scope)
2. [How the anti-abuse bond works](#2-how-the-anti-abuse-bond-works)
3. [The wire contract](#3-the-wire-contract)
4. [Where this client stands today](#4-where-this-client-stands-today)
5. [Design principles for the v2 implementation](#5-design-principles-for-the-v2-implementation)
6. [Client flows](#6-client-flows)
7. [Data model](#7-data-model)
8. [UI surfaces](#8-ui-surfaces)
9. [Session, restore and restart resilience](#9-session-restore-and-restart-resilience)
10. [Implementation plan — phases, tasks, PRs](#10-implementation-plan--phases-tasks-prs)
11. [Testing strategy](#11-testing-strategy)
12. [Comparison with the v1 client](#12-comparison-with-the-v1-client)
13. [Open questions and assumptions to verify](#13-open-questions-and-assumptions-to-verify)
14. [References](#14-references)

---

## 1. Goal and scope

### 1.1 What the bond is, in one paragraph

An anti-abuse bond is a **second Lightning hold invoice**, separate from the trade
escrow, that a Mostro node may require a user to lock when entering a trade. It deters
griefing: a user who abandons or sabotages a trade can have the bond **slashed**; an
honest user always gets it **released** (the HTLC is cancelled and the sats never leave
their wallet). The feature is **opt-in, per node, off by default**. A node that does not
enable it produces zero behaviour change in this client.

### 1.2 What the client does — and does not — decide

The bond is a **daemon** feature. Economics, the slash decision, hold-invoice custody,
the payout scheduler and the dispute mechanics all live in `mostrod`. This client:

1. **Discovers** whether the active node enforces bonds, on which side, and at what
   cost, from the node's kind-38385 info event (§3.4) — and shows that *before* the
   user commits.
2. **Reacts** to the bond wire messages (§3.1): pays the bond bolt11 the daemon sends,
   tracks the bond state on the trade, submits a payout invoice when the user won a
   slashed bond, and renders the forfeiture notice when the user lost one.
3. **Survives** restarts, late messages and the daemon's retries without losing a claim
   or showing a stale state.

The client **never** computes whether a bond is due, never decides a slash, and never
decodes a bolt11 to find out what it is for — the daemon tells it by action type.

### 1.3 Non-goals

- No solver/admin tooling. `Payload::BondResolution` is emitted by solver clients
  (mostrix); this client neither builds nor reads it. A user on the losing side of a
  dispute only ever sees the ordinary `admin-settled` / `admin-canceled` followed by
  `bond-slashed`.
- No range-order maker bond specifics beyond what the wire exposes. The proportional
  child slashes of upstream Phase 6 are daemon-internal; the client sees the same
  `bond-slashed` (with the slice amount) and `add-bond-invoice` messages it sees for
  any other order.
- No change to any non-bond flow. Bond code is **additive and inert** unless the active
  node advertises `bond_enabled = true` and actually sends a bond message.
- No Cashu interaction. Bonds are Lightning-only upstream and mutually exclusive with
  Cashu escrow mode (upstream CF-1). A node in Cashu mode never sends bond messages.

---

## 2. How the anti-abuse bond works

This section condenses the upstream spec into what a client engineer must understand.
Nothing here is client behaviour; it is the model the client renders.

### 2.1 Economics

```text
bond_amount_sats = max(round(bond_amount_pct × order_amount_sats), bond_base_amount_sats)
```

- `bond_amount_pct` is a fraction (`0.01` = 1 %). `bond_base_amount_sats` is a floor so
  small orders still post a meaningful bond.
- For a **range order taken by a taker**, the amount is computed from the exact sats the
  taker's fiat amount converts to at take time.
- For a **maker bond on a range order**, the daemon sizes the bond against `max_amount`
  at publication price ("worst-case exposure") and does not reprice it later.
- The client never charges anything itself — the daemon always sends the exact bolt11.
  The formula matters only so the UI can **warn the user up front** ("this node will
  ask you to lock ≈ N sats").

### 2.2 Who posts a bond and when — `bond_apply_to`

The bond is a **posting-timing** switch on the maker/taker axis:

| `bond_apply_to` | Who locks a bond | When |
|---|---|---|
| `take` | the taker only | right after `take-buy` / `take-sell`, before the trade flow starts |
| `make` | the maker only | right after `new-order`, **before the order is published** to Nostr |
| `both` | both sides | each at their own moment above |

### 2.3 Two axes that must not be confused

- **Maker / taker** — *who posted the bond and when.* Controls the client flow (which
  screen, which request the reply correlates with).
- **Buyer / seller** — *whose failure justifies a slash.* Timeout responsibility is
  `WaitingBuyerInvoice → buyer`, `WaitingPayment → seller`. Solvers slash "the seller"
  or "the buyer", never "the maker" or "the taker".

The mapping is fixed by the order kind: on a `sell` order the maker is the seller and
the taker the buyer; on a `buy` order the maker is the buyer and the taker the seller.
The client only needs this to explain to the user *why* their bond was at risk.

### 2.4 Bond lifecycle (daemon-side states)

`Requested → Locked → { Released | PendingPayout → { Slashed | Forfeited | Failed } }`

- **Requested**: the daemon created the hold invoice and sent `pay-bond-invoice`. The
  user has not paid yet.
- **Locked**: the user paid; the HTLC is held. The trade flow resumes.
- **Released**: the HTLC was cancelled; sats return to the user. This is the outcome of
  *every* honest exit: normal completion, any cancel before a timeout elapses, and any
  dispute resolution where the solver does not direct a slash.
- **PendingPayout → Slashed / Forfeited / Failed**: the bond was slashed. The daemon
  settled the HTLC immediately (the sats are already in Mostro's wallet) and then runs
  the asynchronous payout to the winning counterparty (§2.6).

### 2.5 When a bond is slashed — only two, unambiguous causes

1. **Solver directive on dispute resolution.** The solver attaches a `BondResolution
   { slash_seller, slash_buyer }` payload to `admin-settle` / `admin-cancel`. The slash
   is **decoupled from the trade outcome**: the solver may cancel the trade *and* slash
   the seller (the party sabotaging a resolution), settle and slash the buyer, slash
   both, or slash neither. Absent payload ⇒ release both.
2. **Waiting-state timeout elapsed**, gated per node by `bond_slash_on_waiting_timeout`.
   Only the scheduler-driven expiry of `WaitingBuyerInvoice` / `WaitingPayment` slashes;
   a user-initiated or admin cancel at minute N−1 never does. So a malicious
   counterparty cannot steal a bond by cancelling early.

Guiding principle upstream: **"never slash unless the cause is unambiguous; when in
doubt, release."**

### 2.6 What happens to a slashed bond — the split and the payout

```text
node_share_sats         = floor(bond_amount_sats × bond_slash_node_share_pct)
counterparty_share_sats = bond_amount_sats − node_share_sats
```

- The node keeps `node_share_sats` (funds solver compensation and operations).
- The **winning counterparty** is asked for a bolt11 for `counterparty_share_sats` via
  `add-bond-invoice`. The daemon retries that request every
  `payout_invoice_window_seconds` while no invoice has been received.
- Once an invoice arrives the daemon answers `bond-invoice-accepted`, pays it (routing
  fee paid by the node, not deducted from the principal), and on success sends
  `bond-payout-completed`.
- If the payment cannot be routed after `payout_max_retries` attempts and the claim
  window is still open, the daemon discards that invoice and **re-prompts** with a fresh
  `add-bond-invoice` (upstream Phase 4.5).
- If the winner never submits an invoice within `bond_payout_claim_window_days` counted
  from `slashed_at`, the bond is **Forfeited** and the node keeps everything. A late
  invoice is refused with `CantDo(NotAllowedByStatus)`.
- When both parties are slashed in one dispute, nobody is paid out; when
  `bond_slash_node_share_pct = 1.0` there is no counterparty leg at all and the winner
  never receives `add-bond-invoice`.
- The **slashed party** receives a best-effort `bond-slashed` notice *after* the
  resolution message (`canceled` on a timeout, `admin-settled` / `admin-canceled` on a
  dispute). Upstream Phase 2.5 (#768) makes the dispute path send it too; the client
  must not assume it always arrives.

### 2.7 Non-blockability and concurrent taker bonds

While a taker's bond is `Requested`, the order **stays visible and takeable** in the
public book: the daemon parks it at `Status::WaitingTakerBond` internally but publishes
it as NIP-69 `pending`. Several takers may hold `Requested` bonds on the same order at
once; **the first to lock wins**. At lock time every other `Requested` bond is released
and its taker receives `Action::Canceled`. Re-sending `take-buy` / `take-sell` from the
same pubkey while its bond is still `Requested` is **idempotent**: the daemon re-sends
the same bolt11 rather than creating a second bond.

Consequences for a client:

- After sending a take and receiving `pay-bond-invoice`, the client must be prepared to
  receive `canceled` instead of the trade progressing — meaning "someone else locked
  first". Show it plainly; do not retry silently.
- Do not hide an order from the local book just because the user initiated a take on
  it.
- A taker who no longer wants to proceed may send `cancel` while at
  `WaitingTakerBond`; the daemon releases only that taker's bond.

### 2.8 Maker bond specifics

- The order is parked at `Status::WaitingMakerBond` and **no NIP-33 event exists** until
  the bond locks. The maker's client receives `pay-bond-invoice` on the same
  `request_id` as the `new-order`, and only once the bond locks does the usual
  `new-order` confirmation (the published order) arrive on that same `request_id`.
- The daemon **rejects `cancel` during `WaitingMakerBond`** (`NotAllowedByStatus`): the
  cancel handler only widens its pre-trade branch to `Pending | WaitingTakerBond`. A
  maker who changes their mind simply does not pay; the hold invoice expires and the
  order-expiry job marks the order `Expired` **without emitting any event or message**
  to the maker. The client therefore needs a local expiry (§6.2).
- When the bond locks, the daemon publishes the order (`WaitingMakerBond → Pending`)
  and answers `new-order` exactly as for an unbonded order.
- A `Locked` maker bond stays locked for the whole life of the order — including when a
  taker abandons and the order is republished — and is released only when the order
  itself terminates.

---

## 3. The wire contract

Everything below is already available in the pinned **`mostro-core` 0.14.6**
(`rust/Cargo.toml`); no crate bump is needed. Verified in
`~/.cargo/registry/src/*/mostro-core-0.14.6/src/{message,order}.rs`.

### 3.1 Actions

| Action (wire) | Direction | Payload | Client reaction |
|---|---|---|---|
| `pay-bond-invoice` | Mostro → bonded user | `PaymentRequest(Some(SmallOrder{amount = bond}), bolt11, None)` | Show the pay-bond screen; track bond `Requested` |
| `add-bond-invoice` | Mostro → winner | `BondPayoutRequest { order: SmallOrder{amount = counterparty share}, slashed_at }` | Persist a **claim**, show the payout banner / claim screen |
| `add-bond-invoice` | winner → Mostro | `PaymentRequest(None, bolt11, None)` | The reply the client sends with the payout invoice |
| `bond-invoice-accepted` | Mostro → winner | `Order(SmallOrder)` (status `null`) | Claim → *acknowledged*; stop asking for an invoice |
| `bond-payout-completed` | Mostro → winner | `Order(SmallOrder)` (status `null`) | Claim → *completed* |
| `bond-slashed` | Mostro → slashed user | `Order(SmallOrder{amount = slashed bond})` (status `null`) | Forfeiture notification + dialog; never touch the trade amount/status |

`MessageKind::verify` rules that matter to us: `pay-bond-invoice` requires an `id` and a
`PaymentRequest` payload; the outbound `add-bond-invoice` reply requires an `id` and a
`PaymentRequest`; `bond-slashed` and the two acks require an `id` (message.rs:812–891).

### 3.2 Payload shapes

```rust
pub struct BondPayoutRequest {
    pub order: SmallOrder, // order.amount = counterparty_share_sats
    pub slashed_at: i64,   // unix seconds, frozen at slash time, identical on every retry
}
```

`slashed_at` is the **anchor for the forfeit deadline**:
`deadline = slashed_at + bond_payout_claim_window_days × 86 400`. The client must compute
it from the anchor, never from message receipt time: a user offline for days must still
see the true deadline.

### 3.3 Statuses

| `mostro_core::order::Status` | Wire | Meaning for the client |
|---|---|---|
| `WaitingTakerBond` | `waiting-taker-bond` | matched, the taker's bond is outstanding; publicly still `pending` |
| `WaitingMakerBond` | `waiting-maker-bond` | order created but unpublished; the maker's bond is outstanding |

Both appear in a `SmallOrder.status` inside daemon messages (and in `RestoreData`), never
in a kind-38383 `s` tag — the public book only carries the four NIP-69 buckets, and
`waiting-taker-bond` maps to `pending` there.

### 3.4 Node policy — kind-38385 info-event tags

| Tag | Values | Emitted when |
|---|---|---|
| `bond_enabled` | `true` / `false` | **always** on a bond-aware daemon; absent ⇒ legacy daemon |
| `bond_apply_to` | `take` / `make` / `both` | enabled only |
| `bond_amount_pct` | fraction, e.g. `0.01` | enabled only |
| `bond_base_amount_sats` | integer sats | enabled only |
| `bond_slash_on_waiting_timeout` | `true` / `false` | enabled only |
| `bond_slash_node_share_pct` | fraction `0.0…1.0` | enabled only |
| `bond_payout_claim_window_days` | integer days | enabled only |

Three-state policy: **unsupported** (tag absent) / **disabled** / **enabled**. Also
relevant: the existing `hold_invoice_expiration_window` tag bounds how long a bond
bolt11 stays payable (§6.2).

### 3.5 Rejections the client can receive

- `CantDo(NotAllowedByStatus)` on an `add-bond-invoice` reply: the claim is already
  paid, a payout is already in flight, or the claim window expired. The reason carries
  **no text and no sub-reason**, so the client cannot tell which; it must re-derive the
  state from what it already knows (acks received, deadline passed) — §6.4.
- `CantDo(NotAllowedByStatus)` on `cancel` while the maker bond is outstanding (§2.8).
- `CantDo(PendingOrderExists)` on a take when another taker already **locked** a bond.

---

## 4. Where this client stands today

Verified on `main` at the time of writing. The epic's original "zero bond support"
framing is out of date; the situation is *partially implemented, deliberately refused*.

| Area | State | Where |
|---|---|---|
| Protocol vocabulary | complete (`mostro-core` 0.14.6) | `rust/Cargo.toml` |
| Node policy parsing, Rust | partial: only `bond_enabled` → `bond_required`, `bond_amount_pct` → `bond_pct` | `rust/src/api/node_stats.rs:67-70,155-158` |
| Node policy parsing, Dart | complete (all 7 tags, three-state `BondPolicy`) — used by the About screen only | `lib/features/about/models/mostro_instance.dart:12-135,171-296` |
| About screen bond section | done (#196) | `lib/features/about/…`, l10n `aboutBond*` |
| `bond-slashed` notice | done (#194): dispatch arm, cause inference, broadcast stream, persisted notification | `rust/src/api/orders.rs:3409`, `rust/src/api/bond.rs`, `lib/core/app_bootstrap.dart:166,280` |
| `pay-bond-invoice` | **refused**: hard-mapped to a stable `BondRequired` rejection | `rust/src/mostro/pending.rs:438-443` |
| Bond statuses | **unmapped**: `WaitingTakerBond \| WaitingMakerBond => None` | `rust/src/mostro/status.rs:83-86` |
| Node selector | bond nodes are **unselectable** (`NodeBlocker.bondUnsupported`) | `lib/features/settings/models/node_selector_rules.dart:92-96` |
| Take screen | shows "bond not supported yet" on `BondRequired` | `lib/features/order/screens/take_order_screen.dart:205-209`, l10n `bondRequired` |
| `add-bond-invoice`, the two acks | **unhandled** (fall into the `unhandled action` arm) | `rust/src/api/orders.rs` dispatch |
| Outgoing bond reply builder | **missing** | `rust/src/mostro/actions.rs` |
| `TradeInfo` bond fields | **missing** | `rust/src/api/types.rs:251` |
| Design mocks | payout banner, PAYOUT PENDING badge, bond-slashed dialog | `docs/design/145-*.png` |

Open sub-issues of #145: [#208](https://github.com/MostroP2P/app/issues/208) (taker
flow), [#191](https://github.com/MostroP2P/app/issues/191) (maker flow),
[#192](https://github.com/MostroP2P/app/issues/192) (`add-bond-invoice`),
[#193](https://github.com/MostroP2P/app/issues/193) (payout phases + acks),
[#195](https://github.com/MostroP2P/app/issues/195) (UI: banner, badge, dialog),
[#197](https://github.com/MostroP2P/app/issues/197) (session lifecycle). §10 maps every
phase to these.

---

## 5. Design principles for the v2 implementation

1. **Rust owns the bond state machine; Dart renders it.** Every transition (`Requested`,
   `Locked`, claim phases, deadlines) is decided in `rust/src/mostro/` and
   `rust/src/api/` and reaches Dart through `TradeInfo`, a stream, or a bridge call —
   exactly like the rest of the trade lifecycle. No pure-Dart helper re-implements
   protocol logic (the v1 `bond_*_helpers.dart` pattern is **not** ported).
2. **Dispatch on action type, never on bolt11 contents.** `pay-bond-invoice` *is* the
   bond; `pay-invoice` *is* the escrow. No memo parsing, no amount heuristics.
3. **A bond is not a trade status change for the UI amount.** The `SmallOrder` carried
   by bond messages has `amount = bond sats` and `status = null` (or a placeholder
   `Pending`). It must **never** overwrite the tracked order's amount or status. Only
   `pay-bond-invoice` moves the order status (to a waiting-bond status).
4. **Claims are independent of trade rows.** A payout claim (`add-bond-invoice`) can
   arrive for an order whose local trade row was **wiped** — the client wipes
   never-active cancellations locally (`cancellation_wipes_history`,
   `rust/src/mostro/status.rs:137`), and the timeout-slash of a `WaitingBuyerInvoice`
   / `WaitingPayment` order is exactly that case. Claims therefore get their **own
   persistent store** (§7.3), and the UI lists them even without a trade.
5. **Idempotent by construction.** The daemon retries `add-bond-invoice` on a cadence
   and re-sends `pay-bond-invoice` on an idempotent retake; both must be no-ops when
   nothing changed. Key on `order_id` (+ `slashed_at` for claims), not on event id or
   timestamp.
6. **Fail closed on the take, fail open on the notice.** A take must never be recorded
   as a trade before the daemon confirms it (existing rule). A `bond-slashed` or an ack
   that cannot be matched to anything local is still surfaced to the user — losing sats
   silently is the worst outcome.
7. **Feature flags are the node's, not ours.** There is no client-side "enable bonds"
   setting. The node's `bond_enabled` tag plus the actual arrival of a bond message is
   the only gate. The existing dev override pattern (`config.rs`) is not extended.
8. **Web parity from the first PR that persists anything.** Every new table has its
   IndexedDB counterpart in the same PR (`rust/src/db/indexeddb.rs`, `DB_VERSION` bump),
   with the same "log and ignore persistence failures" discipline the relay store uses.
9. **Atomic PRs.** Each PR in §10 must compile, pass `cargo test && cargo clippy`,
   `flutter analyze && flutter test`, and leave the app fully functional against a node
   without bonds. Rust and Dart halves of a phase ship as separate PRs when the Rust
   half is reviewable on its own.

---

## 6. Client flows

### 6.1 Flow 1 — Taker pays a bond (`bond_apply_to ∈ {take, both}`)

```text
user taps TAKE
  │  take_order() publishes take-buy / take-sell (request_id R), waits ≤ 10 s
  ▼
daemon → pay-bond-invoice (id = order, request_id R, PaymentRequest{bond bolt11, amount})
  │  classify_take_reply → DaemonReply::TakeAccepted { bond: Some(..) }
  │  persist TradeInfo { order.status = WaitingTakerBond, bond = Requested{amount, bolt11} }
  │  return to Dart → navigate to /pay_bond/:orderId
  ▼
user pays the bond HTLC (QR / copy / share / NWC "pay with wallet")
  │
  ├─ taker is the BUYER (sell order):  daemon → add-invoice / waiting-buyer-invoice …
  │                                     bond → Locked, status → WaitingBuyerInvoice
  └─ taker is the SELLER (buy order):  daemon → pay-invoice (the *trade* hold invoice)
                                        bond → Locked, status → WaitingPayment,
                                        navigate to /pay_invoice/:orderId (second HTLC)
```

Rules:

- `WaitingTakerBond` is left **only** by a subsequent daemon message. Any of
  `add-invoice`, `waiting-buyer-invoice`, `pay-invoice`, `waiting-seller-to-pay`,
  `buyer-took-order`, `hold-invoice-payment-accepted` for that order implies the bond
  locked ⇒ set `bond.state = Locked`, then apply the message's normal status effect.
- `canceled` while at `WaitingTakerBond` has **three possible causes** and the wire
  action carries none of them: the user's own cancel, a maker cancel, or a lost lock
  race. The trade row is wiped like any never-active cancel in all three cases; what
  differs is the local book and the copy, so the Rust side classifies the cause before
  emitting the `TradeUpdate` (`reason` field, §7.1):
  - `UserCanceled` — the client sent the `cancel` itself (the pending cancel request is
    still registered). Neutral copy, order left as the wire reports it.
  - `BondLostRace` — the order's last kind-38383 status is `in-progress` (the winner's
    lock moved it to `WaitingPayment` / `WaitingBuyerInvoice`, which publishes in that
    bucket) or still `pending`. Copy: "This order was taken by another user before your
    bond was paid." The local book keeps the order only while the wire still says
    `pending`.
  - `MakerCanceled` — the wire status is `canceled`. Copy: "The maker cancelled this
    order." The order leaves the local book.
  - When the book has no fresh status for the order, fall back to neutral copy ("This
    order is no longer available") and to whatever the wire says next. Never retry the
    take silently in any of the cases.
- The pay-bond screen offers **Cancel**: the daemon accepts a taker `cancel` at
  `WaitingTakerBond` and releases only that taker's bond. The screen reuses the existing
  `cancel_order` bridge call.
- **Bond expiry is the bolt11's own expiry.** The daemon sends no message when a bond
  hold invoice expires unpaid (upstream `on_bond_invoice_canceled` only releases the row
  and republishes), and `hold_invoice_expiration_window` is the daemon's window for
  paying the *escrow* / adding the buyer invoice, not the lifetime of a Lightning
  invoice. So the Rust core decodes the bond bolt11's `expiry` (a pure-Rust bolt11
  decoder such as `lightning-invoice`, native + wasm; §13) into `BondInfo.expires_at`
  and the screen counts down to it. **Local expiry sweep** (T1.2): when `expires_at`
  elapses without a lock, the row is set to `Expired`, a `TradeUpdate { status:
  Expired, reason: BondExpired }` is emitted **before** the row is wiped, and the order
  is restored to the local book only if the wire still reports it `pending`. If the
  bolt11 cannot be decoded, `expires_at` is `None`, **no local cleanup runs**, and the
  screen shows no countdown — the user can still cancel. The existing
  `timeout_at = now + 900` seeding is not applied to a trade at `WaitingTakerBond`.
- A seller-as-taker sees **two sequential pay screens** for the same order: first the
  bond (small, "locked, not spent"), then the trade escrow. They are independent HTLCs
  and the user must approve each. Copy must label the first one explicitly.

### 6.2 Flow 2 — Maker pays a bond on order creation (`bond_apply_to ∈ {make, both}`)

```text
user taps CREATE ORDER
  │  create_order() publishes new-order (request_id R), waits ≤ 10 s
  ▼
daemon → pay-bond-invoice (id = order, request_id R, PaymentRequest{bond bolt11})
  │  NewOrder-correlation sees PayBondInvoice on a Create record →
  │  DaemonReply::BondRequested { daemon_id, amount, bolt11 }
  │  persist maker TradeInfo { status = WaitingMakerBond, bond = Requested }
  │  keep the pending Create record ALIVE (the new-order ack is still to come)
  │  return OrderInfo{status = WaitingMakerBond} → navigate to /pay_bond/:orderId
  ▼
maker pays the bond HTLC
  ▼
daemon → new-order (id = order, request_id R, Order{status = Pending})
  │  correlates with the still-pending Create record → status WaitingMakerBond → Pending,
  │  bond → Locked, emit TradeUpdate → the pay-bond screen navigates to /my_order/:orderId
```

Rules:

- **Two replies on one `request_id`.** Today `create_order` consumes the pending record
  on the first reply. With a maker bond the first reply is `pay-bond-invoice` and the
  confirmation follows later — possibly minutes later, after the app was restarted. The
  pending-record kind gains a `bond_requested` flag and the record is **not** removed on
  the bond reply; the eventual `new-order` matches it or, if the process restarted,
  falls back to matching on `(trade pubkey, order id)` against the persisted
  `WaitingMakerBond` trade row.
- **No cancel.** The daemon refuses `cancel` at `WaitingMakerBond`. The pay-bond screen
  for a maker shows **Abandon** instead of Cancel: it wipes the local trade row and lets
  the hold invoice expire server-side. Copy explains that nothing was published and
  nothing was charged.
- **Local expiry.** The daemon expires an unpaid maker-bond order silently (§2.8). The
  client uses the decoded bolt11 expiry exactly as in §6.1; as a second bound it also
  uses the order's own `expires_at` (the daemon's pending-order expiry, which is what
  actually reaps a `WaitingMakerBond` row upstream). Whichever comes first ends the
  local row with the same `Expired` update-then-wipe sequence. With an undecodable
  bolt11 only the order expiry applies.
- **The invoice survives a restart.** `BondInfo.invoice` is persisted in the trade row
  (§7.1), so a maker who closes the app and comes back lands on the pay-bond screen with
  the same bolt11. The only case that loses it is a **fresh device / wiped database**
  restored via `restore-session`; there is no upstream re-request for a maker bond
  (§6.5), so that order can only be abandoned or left to expire. Proposed upstream
  follow-up in §13.
- **My Order screen** shows the maker-bond state as "Waiting for your bond — the order
  is not published yet", distinct from "Waiting for a taker".
- Pre-create warning: when the node's policy is `make`/`both`, the create form shows the
  estimated bond before the CTA (§8.1).

### 6.3 Flow 3 — Losing a bond (`bond-slashed`)

Already implemented for the notification (#194). Remaining behaviour:

- The notice arrives **after** the resolution message. Locally the resolution may have
  wiped the trade row (never-active cancel) or left it (`admin-*`). The dispatch arm is
  exempt from the trade-row gates already; the cause inference
  (`rust/src/api/bond.rs::infer_slash_cause`) reads the persisted status *if any* and
  defaults to `Timeout`.
- The bond amount must be shown from the notice, never from the trade.
- The detail dialog (`docs/design/145-bond-slashed.png`) explains cause and amount and
  links to the node's policy in About. A durable line in Trade Detail is shown for the
  dispute cause only (the trade row still exists there); on the timeout cause the row
  is gone and the notification is the record.

### 6.4 Flow 4 — Claiming a slashed bond's share (`add-bond-invoice`)

```text
daemon → add-bond-invoice (BondPayoutRequest{ order{amount = share}, slashed_at })   ← retried every payout_invoice_window_seconds
  │  upsert BondClaim{order_id, amount, slashed_at, phase = Pending, deadline}
  │  emit BondClaimUpdate → banner in Trade Detail, PAYOUT PENDING badge in My Trades,
  │  notification "You can claim N sats"
  ▼
user opens /bond_payout/:orderId, pastes a bolt11 (or generates one via NWC make_invoice)
  │  submit_bond_payout_invoice(order_id, bolt11) → actions::add_bond_invoice → publish
  │  claim.phase = Submitted (local, so the form does not re-arm on the next daemon retry)
  ▼
daemon → bond-invoice-accepted            → claim.phase = Acknowledged ("payout in progress")
daemon → bond-payout-completed            → claim.phase = Completed   ("paid")
daemon → add-bond-invoice again (retries exhausted, window open) → claim.phase = Pending again, keep slashed_at
daemon → cant-do(NotAllowedByStatus)      → see below
```

Rules:

- **Key = `(node_pubkey, order_id)`.** The claim records the daemon that issued it
  (§7.1) because the user can switch nodes while a claim is open and the inbound
  daemon filter is `author = active node` (`rust/src/api/orders.rs`, the `.author(
  mostro_pubkey)` filters). Submission always addresses `claim.node_pubkey`, never the
  active node, and the kind-14 subscription includes the pubkeys of every node holding
  a non-terminal claim so the daemon's retries and acks keep arriving after a switch.
- **Phase-aware upsert.** Every `add-bond-invoice` carries the same `order_id` and
  `slashed_at`, whether it is a cadence retry (no invoice received yet) or a re-prompt
  after the daemon accepted an invoice and then exhausted its payment retries
  (upstream Phase 4.5). The two must be told apart by the **claim's current phase**,
  not by the payload:

  | Current phase | On `add-bond-invoice` |
  |---|---|
  | none | create `Pending` |
  | `Pending` | no-op (cadence retry) |
  | `Submitted` | no-op (retry that crossed our reply in flight; the ack decides) |
  | `Acknowledged` | **re-prompt**: back to `Pending`, clear `submitted_invoice`, emit update, notify ("the payout could not be routed, add a new invoice") |
  | `Completed` | ignore and log (the daemon never re-prompts a paid bond) |
  | `Expired` | re-evaluate the deadline; stay `Expired` if still past it |

  A different `slashed_at` for the same order (theoretical: range parent re-anchor)
  replaces the claim outright.
- **Deadline** = `slashed_at + claim_window_days × 86 400`, with `claim_window_days`
  from the node stats (`bond_payout_claim_window_days`) at the moment the claim is
  **first** persisted, defaulting to **15** when the tag is absent. `deadline_at` is
  frozen in the claim and never recomputed from later stats, so a policy change after
  the slash cannot silently move a deadline the user was already shown. The daemon's
  own verdict stays authoritative: a `CantDo` after the frozen deadline resolves to
  `Expired` (below). `BondPayoutRequest` does not carry the window itself; an upstream
  proposal to ship `claim_window_days` / `deadline_at` in the payload is listed in §13.
  A request that is already past its deadline on arrival is persisted as `Expired` and
  not surfaced as actionable.
- **Invoice amount.** The bolt11 must be for exactly `order.amount` sats (the
  counterparty share); the daemon validates the principal with fee 0. The claim screen
  pre-fills that amount and, when NWC is connected, can create the invoice with
  `make_invoice` so the user never types an amount.
- **`CantDo(NotAllowedByStatus)`** in reply to the submission carries no detail. The
  client resolves it locally: if the deadline passed ⇒ `Expired` ("the claim window
  ended on <date>"); if an ack was already received ⇒ keep that phase ("already in
  progress / already paid"); otherwise show a generic "the node did not accept the
  invoice" and leave the claim `Pending` so the next daemon retry re-prompts.
- The winner's trade may be **completed, cancelled, or wiped**. The banner lives in
  Trade Detail when the row exists; the My Trades list renders a claim row from the
  claim store alone otherwise (§8.3).

### 6.5 Flow 5 — Restore session

Two different situations, with different recovery:

- **Ordinary restart** (local database intact): the trade row already holds
  `BondInfo.invoice` and `expires_at`; the pay-bond screen reopens with the same bolt11
  for taker and maker alike. Nothing to re-request.
- **Fresh device / wiped database**: `restore-session` returns `RestoreData` with every
  open order and its daemon-side status, including `waiting-taker-bond` /
  `waiting-maker-bond`, but **no bolt11**. Rebuilt trades in those statuses therefore
  have `invoice: None`:
  - Taker: the pay-bond screen shows "Request the bond invoice again"; tapping it
    re-emits `take-buy` / `take-sell` under the **retake identity contract** (§9) —
    same trade key and index, fresh `request_id` — which the daemon treats as an
    idempotent retry and answers with the same bolt11.
  - Maker: there is no idempotent re-request upstream (`new-order` would create a
    second order). The screen shows the state and the order-expiry countdown; if the
    user wants out, Abandon (§6.2).

Claims are not part of `RestoreData`; they are restored from the local claim store.
The daemon's cadence retry of `add-bond-invoice` re-creates any claim the device lost.

---

## 7. Data model

### 7.1 Rust — `rust/src/api/types.rs`

```rust
pub enum OrderStatus {
    // … existing …
    /// Taker bond outstanding. Publicly the order is still `pending`.
    WaitingTakerBond,
    /// Maker bond outstanding. The order is not published yet.
    WaitingMakerBond,
}

pub enum BondRole { Maker, Taker }

pub enum BondState {
    /// bolt11 received, not paid. `invoice` is `Some`.
    Requested,
    /// Paid; inferred from the first post-bond trade message.
    Locked,
    /// Trade ended without a slash notice.
    Released,
    /// `bond-slashed` received for this order.
    Slashed,
}

pub struct BondInfo {
    pub role: BondRole,
    pub amount_sats: u64,
    pub invoice: Option<String>,   // persisted; None only after a fresh-device restore
    pub state: BondState,
    pub requested_at: i64,
    pub expires_at: Option<i64>,   // decoded from the bolt11 `expiry`; None if undecodable
    pub locked_at: Option<i64>,
}

pub struct TradeInfo {
    // … existing fields …
    pub bond: Option<BondInfo>,
}

/// Why a status changed, when the wire action alone is ambiguous.
pub enum TradeUpdateReason { UserCanceled, MakerCanceled, BondLostRace, BondExpired }

pub struct TradeUpdate {
    pub order_id: String,
    pub status: OrderStatus,
    pub reason: Option<TradeUpdateReason>,   // new, `None` for every existing emitter
}
```

`TradeInfo` is persisted as a JSON blob (`trades.data`), so **no DDL change** is needed
for `bond`; existing rows deserialise with `bond: None` (`#[serde(default)]`).

```rust
pub enum BondClaimPhase { Pending, Submitted, Acknowledged, Completed, Expired }

pub struct BondClaim {
    pub order_id: String,
    pub node_pubkey: String,       // daemon that issued the claim; submission target
    pub amount_sats: u64,          // counterparty share
    pub slashed_at: i64,
    pub deadline_at: i64,          // slashed_at + window_days * 86_400, frozen at first receipt
    pub phase: BondClaimPhase,
    pub submitted_invoice: Option<String>,
    pub fiat_code: String,         // from the SmallOrder, for display only
    pub fiat_amount: Option<f64>,
    pub payment_method: String,
    pub updated_at: i64,
}

pub struct BondClaimUpdate { pub order_id: String, pub phase: BondClaimPhase }
```

`MostroNodeStats` (`rust/src/api/node_stats.rs`) grows the full policy so Rust can
compute estimates and deadlines without asking Dart:

```rust
pub bond_policy: BondPolicy,               // Unsupported | Disabled | Enabled
pub bond_apply_to: Option<BondApplyTo>,    // Take | Make | Both
pub bond_amount_pct: Option<f64>,          // fraction
pub bond_base_amount_sats: Option<u64>,
pub bond_slash_on_waiting_timeout: Option<bool>,
pub bond_slash_node_share_pct: Option<f64>,
pub bond_payout_claim_window_days: Option<u32>,
```

The existing `bond_required` / `bond_pct` fields are kept as derived accessors for the
node card until the selector PR (§10, PR-1c) drops them.

### 7.2 Rust — `DaemonReply` (`rust/src/mostro/pending.rs`)

```rust
pub enum DaemonReply {
    // … existing …
    /// `pay-bond-invoice` on a Take record: the take was accepted pending the bond.
    TakeAccepted { …, bond: Option<BondRequest> },      // extend the existing variant
    /// `pay-bond-invoice` on a Create record: the order exists but is unpublished.
    BondRequested { daemon_id: String, bond: BondRequest },
}
pub struct BondRequest { pub amount_sats: u64, pub invoice: String }
```

### 7.3 Persistence — `rust/src/db/`

- `trades.data` JSON: gains `bond` (no migration).
- New table / store **`bond_claims`** keyed by `node_pubkey:order_id`, one JSON `data`
  column plus `node_pubkey`, `phase` and `deadline_at` columns for listing/sorting:

  ```sql
  CREATE TABLE IF NOT EXISTS bond_claims (
    id          TEXT PRIMARY KEY NOT NULL,   -- "<node_pubkey>:<order_id>"
    node_pubkey TEXT NOT NULL,
    data        TEXT NOT NULL,               -- BondClaim JSON
    phase       TEXT NOT NULL,
    deadline_at INTEGER NOT NULL,
    updated_at  INTEGER NOT NULL
  );
  CREATE INDEX IF NOT EXISTS idx_bond_claims_node ON bond_claims(node_pubkey, phase);
  ```

  Added to `SQLITE_INIT_SQL` (`rust/src/db/schema.rs`, idempotent `IF NOT EXISTS`) and
  to `indexeddb.rs` (`ALL_STORES`, `DB_VERSION` 3 → 4). `Storage` trait gains
  `save_bond_claim`, `get_bond_claim`, `list_bond_claims`, `delete_bond_claim`.
- `SCHEMA_VERSION` bumped for documentation consistency.

### 7.4 Bridge surface — `rust/src/api/`

| Function | Module | Purpose |
|---|---|---|
| `take_order` / `create_order` (existing) | `orders.rs` | return a `TradeInfo` / `OrderInfo` carrying the bond state |
| `request_bond_invoice_again(order_id)` | `bond.rs` | idempotent retake to recover a lost bolt11 (taker only) |
| `abandon_bonded_order(order_id)` | `bond.rs` | local wipe for a maker bond the user will not pay |
| `estimate_bond_sats(order_amount_sats) -> Option<u64>` | `bond.rs` | `max(pct × amount, base)` from the active node's stats; `None` when policy not enabled |
| `submit_bond_payout_invoice(order_id, invoice)` | `bond.rs` | build + publish the `add-bond-invoice` reply **to `claim.node_pubkey`** (not the active node), set phase `Submitted` |
| `list_bond_claims()` / `get_bond_claim(order_id)` | `bond.rs` | for My Trades and the claim screen |
| `on_bond_claim_updated() -> BondClaimStream` | `bond.rs` | broadcast of `BondClaimUpdate`, same pattern as `BondSlashedStream` |
| `on_bond_slashed()` (existing) | `bond.rs` | unchanged |

Every change under `rust/src/api/` requires `./scripts/frb-generate.sh`.

### 7.5 Dart

- `lib/features/trades/models/trade_status.dart`: `TradeStatus.waitingBond` (machine
  name `waiting-bond`) for both bond statuses; `docs/automation-contract.md` updated.
- `lib/features/order/models/bond_claim_view.dart` (presentation only: formatted
  amount, deadline, phase copy).
- Providers: `bondClaimsProvider` (list, invalidated by the claim stream),
  `bondClaimProvider(orderId)`, `bondPolicyProvider` (from node stats).
- l10n keys in all five `.arb` files, `flutter gen-l10n`.

---

## 8. UI surfaces

Design references: `docs/design/145-bond-payout-banner.png`,
`docs/design/145-trades-payout-pending.png`, `docs/design/145-bond-slashed.png`. The
pay-bond screen has no mock; it reuses the pay-invoice screen's layout.

### 8.1 Before committing — policy warnings

- **Node card / selector** (`lib/features/settings/widgets/node_card.dart`): the trust
  row keeps "Bond X %"; the blocker `NodeBlocker.bondUnsupported` is **removed**. A
  legacy daemon (`unsupported`) shows "No bond".
- **Take screen**: when the node policy applies to takers, an info block above the CTA:
  "This node asks takers to lock an anti-abuse bond of ≈ N sats (min. M). It is
  returned when the trade ends honestly." For market-price orders the estimate uses the
  live rate the screen already has; if unavailable, show the percentage and floor.
- **Create-order screen**: same block when the policy applies to makers, plus "your
  order will not be visible until the bond is locked".

### 8.2 Pay-bond screen — `/pay_bond/:orderId`

Same skeleton as `pay_lightning_invoice_screen.dart` (QR, amount, copy, share,
"Pay with Lightning wallet" via NWC, waiting state). Differences:

- Title "Lock anti-abuse bond"; explanatory line: "N sats are held, not spent; they are
  released when the trade ends. They can be slashed if a solver rules against you in a
  dispute" — always shown — plus "or if you let a waiting step time out" **only when
  `bond_slash_on_waiting_timeout = true`** (the dispute risk exists on every
  bond-enabled node; the timeout risk is the node-policy switch).
- Countdown to the bolt11 expiry when `expires_at` is known; nothing otherwise.
- Taker: **Cancel** (daemon cancel). Maker: **Abandon** (local wipe, copy explains).
- Restored without an invoice: "Request the invoice again" (taker) / countdown only
  (maker).
- On `TradeUpdate` leaving the waiting-bond status: taker-buyer → Trade Detail;
  taker-seller → `/pay_invoice/:orderId` with a one-line "Bond locked. Now lock the
  trade amount." banner; maker → `/my_order/:orderId`.
- On `TradeUpdate` to `canceled` / `expired`: snackbar chosen by `reason` (§6.1:
  lost race / maker cancelled / expired / neutral) and back to the order book.

### 8.3 My Trades and Trade Detail

- Status chip **WAITING BOND** for `waitingBond`; subtitle "Lock N sats to continue".
- **PAYOUT PENDING** badge (orange, per mock) on any trade with a claim in `Pending`;
  **PAYOUT IN PROGRESS** for `Submitted` / `Acknowledged`. A claim whose trade row was
  wiped renders its own row ("Cancelled · bond claim available") built from the claim
  store.
- Trade Detail **bond banner** (mock 145-bond-payout-banner): "Your N-sat bond is
  ready to come back. Paste any Lightning invoice for N sats to claim it." + **ADD
  PAYOUT INVOICE**; phases change the copy (in progress / paid on <date>); `Expired`
  shows a muted line.
- Trade Detail durable notice for a dispute-cause slash: "The node slashed your N-sat
  bond in this dispute."

### 8.4 Claim screen — `/bond_payout/:orderId`

Reuses `add_lightning_invoice_screen.dart` building blocks: bolt11 field with paste,
"Create with wallet" (NWC `make_invoice` for the exact amount), amount and deadline
("Claim before <date>, N days left"), submit. After submit: "Invoice sent — waiting for
the node"; on `Acknowledged`/`Completed` the form is replaced by a status card and a
single Close button. Errors via `localizedDaemonError` with new markers.

### 8.5 Notifications

- `bond-slashed`: existing card; tap opens the dialog from mock 145-bond-slashed with
  "View policy" → About.
- `add-bond-invoice` (new claim): "You can claim N sats from a slashed bond" → claim
  screen.
- `bond-payout-completed`: "Bond payout of N sats received".
- Push notifications: routed through the existing push pipeline only if the trade
  update path already produces pushes; otherwise deferred (tracked as an open item,
  §13).

---

## 9. Session, restore and restart resilience

v2 differs structurally from v1 here, and most of v1's §8 (60-second deferred session
deletion, `#197`) **does not port**:

- **Trade keys are never dropped from decryption coverage.** Every derived trade key
  joins the process-wide kind-14 filter (`ensure_global_dm_coverage`,
  `rust/src/api/orders.rs:5276`) for the life of the process, independently of the
  trade row. A trailing `bond-slashed` after a `canceled` wipe is still received and
  decrypted; the `BondSlashed` arm is already exempt from the row gates.
- What must be **verified and tested** (task T4.2): after a **restart**, keys of wiped
  trades are re-added to the global filter (the `trade_keys` table keeps
  `(order_id, key_index)` and the wipe records `wiped_index`). If they are not, a
  `bond-slashed` or `add-bond-invoice` arriving during the restart gap is lost until the
  daemon's next retry (claims) or forever (slash notice). The fix, if needed, is to seed
  the global filter from `trade_keys` at startup, bounded to keys used in the last
  `bond_payout_claim_window_days` + margin.
- **Claims survive everything** because they live in their own store and the daemon
  re-sends the request on a cadence until the deadline.
- **Restore session** rebuilds bond statuses (§6.5). The pending-request registry is
  in-memory; a maker-bond confirmation arriving after a restart is matched by
  `(trade pubkey, order id)` against the persisted `WaitingMakerBond` row (§6.2).
- **Retake identity contract.** Two different things are both called "retake"; they
  must not be conflated:
  - **Re-request on the same take** (§6.5 taker restore, `request_bond_invoice_again`,
    T1.3): the trade row still exists at `WaitingTakerBond`. The client re-emits
    `take-buy` / `take-sell` with the **same trade key and trade index** stored on the
    row and a **fresh `request_id`**; the daemon answers with the same bolt11
    (idempotent per upstream §6.5.1). The reply updates the existing row's `invoice` /
    `expires_at`; no new row, no new key.
  - **New take after the previous one ended** (cancel, expiry, lost race): the old row
    was wiped; `take_order` derives a **fresh trade key and index** and creates a new
    row, as today. The daemon sees a different pubkey and creates a new bond.
  - v1's "clear the stale timer on retake" guard has no counterpart: there is no
    deferred-deletion timer in v2.

---

## 10. Implementation plan — phases, tasks, PRs

Conventions:

- One PR per line in the "PR" column; several low-complexity tasks may share a PR
  **only when they touch the same layer and the PR description argues why** (atomic
  PRs, small enough for a human or an AI to review in one sitting; grouping allowed with
  a written justification).
- Branch names `feat/bond-<phase>-<short>`; commits `feat(bond): …` / `fix(bond): …`;
  every PR links this document and the sub-issue it closes.
- Order of landing is the order below unless stated "orthogonal".
- After every phase the app must be fully functional against a bond-less node.
- The Rust half of a phase is always mergeable before its Dart half: it exposes new
  data that nothing renders yet.

### Phase 0 — Foundation (no behaviour change)

Additive types and parsing; the `BondRequired` refusal stays in place.

| Task | Scope | Files |
|---|---|---|
| T0.1 | `OrderStatus::{WaitingTakerBond, WaitingMakerBond}`; `map_core_status` maps them; `is_hard_terminal` / `cancellation_wipes_history` / `status_for_action` updated (both statuses are never-active ⇒ wiped on cancel); Dart `TradeStatus.waitingBond` + `tradeStatusFromOrderStatus` + automation contract | `rust/src/api/types.rs`, `rust/src/mostro/status.rs`, `lib/features/trades/models/trade_status.dart`, `docs/automation-contract.md` |
| T0.2 | `BondRole`, `BondState`, `BondInfo`, `TradeInfo.bond` (`serde(default)`), JSON round-trip tests on `trade_json.rs` | `rust/src/api/types.rs`, `rust/src/db/trade_json.rs` |
| T0.3 | Full bond policy on `MostroNodeStats` (7 tags, three-state, range-validated exactly like the Dart model) + `estimate_bond_sats`; keep `bond_required`/`bond_pct` as derived | `rust/src/api/node_stats.rs`, `rust/src/api/bond.rs` |

**PR-0** — T0.1 + T0.2 + T0.3, one PR. Justification: all three are additive Rust
types with unit tests, no runtime path changes, ~300 lines; splitting them would produce
PRs whose only reviewable content is an enum. Requires `frb-generate.sh`.

Acceptance: `cargo test`, `flutter analyze` green; a `WaitingTakerBond` in a `SmallOrder`
now round-trips to Dart; the app behaves identically.

### Phase 1 — Taker bond (closes #208)

| Task | Scope | Files |
|---|---|---|
| T1.1 | `classify_take_reply`: `PayBondInvoice` ⇒ `TakeAccepted { status: WaitingTakerBond, bond: Some(..) }` (retire the `BondRequired` short-circuit); bolt11 `expiry` decoding in Rust (add a pure-Rust bolt11 decoder crate, native + wasm) into `BondInfo.expires_at`, `None` on decode failure; `take_order` persists the trade with `bond = Requested` and no `timeout_at`; `PayBondInvoice` dispatch arm for the *late / replayed* case (after the 10 s window, or the same-take re-request of §9): update the existing row's `invoice` / `expires_at`, no duplicate trade; `TradeUpdate.reason` field (`None` from every existing emitter) | `rust/Cargo.toml`, `rust/src/mostro/pending.rs`, `rust/src/api/orders.rs`, `rust/src/api/types.rs` |
| T1.2 | Lock inference: every trade-progress arm (`AddInvoice`, `WaitingBuyerInvoice`, `PayInvoice`, `WaitingSellerToPay`, `BuyerTookOrder`, `HoldInvoicePaymentAccepted`) sets `bond.state = Locked` when the row is at `WaitingTakerBond`; `Canceled` at `WaitingTakerBond` classifies the cause (`UserCanceled` / `MakerCanceled` / `BondLostRace` / none, §6.1) from the pending cancel registry and the order's last wire status, wipes the row, emits the update with `reason`, and keeps the order in the local book only while the wire says `pending`; `Released`/`Success`/admin outcomes set `Released` unless a slash notice arrived; local bond expiry sweep: `Expired` + `TradeUpdate { reason: BondExpired }` **then** wipe, only when `expires_at` is known (extends the #148 timeout job) | `rust/src/api/orders.rs`, `rust/src/mostro/status.rs` |
| T1.3 | `request_bond_invoice_again(order_id)` (idempotent retake with the stored trade index) | `rust/src/api/bond.rs`, `rust/src/mostro/actions.rs` |
| T1.4 | Pay-bond screen + route + navigation on `TradeUpdate`; take screen: navigate on `WaitingTakerBond`, race-loss snackbar; seller-as-taker hand-off banner | `lib/features/order/screens/pay_bond_invoice_screen.dart`, `lib/core/app_routes.dart`, `take_order_screen.dart`, `pay_lightning_invoice_screen.dart`, l10n |
| T1.5 | Take-screen policy block with the estimate; WAITING BOND chip + subtitle in My Trades / Trade Detail; `localizedDaemonError` markers | `take_order_screen.dart`, `lib/features/trades/…`, `lib/core/daemon_errors.dart`, l10n |
| T1.6 | Gate flip: remove `NodeBlocker.bondUnsupported`, `nodeNotSelectableBond`, `nodeBondUnsupported`, `bondRequired`; node card reads the new policy fields; update selector tests and goldens | `node_selector_rules.dart`, `node_card.dart`, tests, l10n (5 locales) |

- **PR-1a** — T1.1 + T1.2 + T1.3 (Rust). Justification: T1.2 is meaningless without
  T1.1 (a row can enter the status but never leave it) and T1.3 is a 40-line builder
  the screen needs; all three are exercised by the same dispatch tests.
- **PR-1b** — T1.4 (Dart, the screen and navigation). One task, one PR: it is the
  largest UI piece of the feature.
- **PR-1c** — T1.5 + T1.6 (Dart). Justification: both are copy and gating; T1.6 is the
  user-visible switch and lands last so a half-implemented flow is never reachable from
  the selector.

Acceptance: against a regtest node with `apply_to = "take"`, taking a sell order and a
buy order each locks the bond and continues to the normal flow; abandoning the bond and
losing the race both leave no trade row and a clear message; a bond-less node behaves as
before.

### Phase 2 — Maker bond (closes #191)

| Task | Scope | Files |
|---|---|---|
| T2.1 | Create-record correlation: `PayBondInvoice` on a `Create` record ⇒ `DaemonReply::BondRequested`; the record stays pending with `bond_requested = true`; `NewOrder` on such a record flips `WaitingMakerBond → Pending`, `bond → Locked`; fallback match by `(trade pubkey, order id)` when the registry is empty (restart); `create_order` returns `OrderInfo{status = WaitingMakerBond}` and persists the maker row with the bond | `rust/src/mostro/pending.rs`, `rust/src/api/orders.rs` |
| T2.2 | `abandon_bonded_order(order_id)`; local expiry for `WaitingMakerBond` = min(bolt11 expiry, order `expires_at`) with the same update-then-wipe sequence as T1.2; `cancel_order` returns a `BondCancelNotAllowed` marker when called at `WaitingMakerBond` instead of hitting the daemon | `rust/src/api/bond.rs`, `rust/src/api/orders.rs` |
| T2.3 | Create flow: navigate to the pay-bond screen (maker variant: Abandon, "not published yet" copy); My Order status block for `WaitingMakerBond`; create-form policy block | `add_order_screen.dart`, `pay_bond_invoice_screen.dart`, `my_order_status_block.dart`, l10n |

- **PR-2a** — T2.1 + T2.2 (Rust). Justification: T2.2 is the exit path of the state
  T2.1 introduces; shipping T2.1 alone would leave an unpaid maker order stuck locally.
- **PR-2b** — T2.3 (Dart).

Acceptance: with `apply_to = "make"`, creating an order shows the bond screen first,
the order appears in the book only after payment, and My Order reflects both states;
abandoning leaves nothing behind; `apply_to = "both"` exercises Phases 1 and 2 on one
trade.

### Phase 3 — Payout claim (closes #192, #193, #195 banner/badge)

Orthogonal to Phase 2; depends on Phase 0 only. Can land in parallel with Phase 1/2.

| Task | Scope | Files |
|---|---|---|
| T3.1 | `BondClaim` model (with `node_pubkey`) + `bond_claims` storage on SQLite **and** IndexedDB (`DB_VERSION` bump) + `Storage` trait methods + tests | `rust/src/api/types.rs`, `rust/src/db/{schema,sqlite,indexeddb,mod}.rs` |
| T3.2 | Dispatch arms: `AddBondInvoice` with `BondPayoutRequest` (phase-aware upsert per the §6.4 table, frozen `deadline_at`, `Expired` on arrival past deadline; ignore the `PaymentRequest` shape — that is our own reply echoed back); `BondInvoiceAccepted` / `BondPayoutCompleted` ⇒ phase; `CantDo` correlated to a pending claim submission ⇒ local resolution (§6.4); `BondClaimStream`; the kind-14 daemon filter includes the `node_pubkey` of every non-terminal claim in addition to the active node | `rust/src/api/orders.rs`, `rust/src/api/bond.rs` |
| T3.3 | `submit_bond_payout_invoice` (validate non-empty, publish `add-bond-invoice` with `PaymentRequest(None, bolt11, None)` addressed to `claim.node_pubkey`, phase `Submitted`, `NoDaemonResponse` handling as `send_invoice` does), `list_bond_claims`, `get_bond_claim` | `rust/src/mostro/actions.rs`, `rust/src/api/bond.rs` |
| T3.4 | Claim screen + route; NWC "Create with wallet" | `lib/features/order/screens/bond_payout_invoice_screen.dart`, `app_routes.dart`, l10n |
| T3.5 | Trade Detail banner, My Trades badge and claim-only rows, providers, notification for new claim / completed | `lib/features/trades/…`, `lib/features/notifications/…`, `app_bootstrap.dart`, l10n |

- **PR-3a** — T3.1 (storage). One task: it is the only PR touching the DB layer on
  both platforms and deserves a focused review.
- **PR-3b** — T3.2 + T3.3 (Rust protocol). Justification: the acks are trivial arms
  once the claim store exists; the submit call is the other half of the same
  conversation and its tests share fixtures with the dispatch tests.
- **PR-3c** — T3.4 (Dart, claim screen).
- **PR-3d** — T3.5 (Dart, list/detail/notifications).

Acceptance: a dispute resolved with `slash_buyer = true` on regtest makes the seller's
app show PAYOUT PENDING, accept an invoice, move through acknowledged/completed, and
refuse nothing silently; a claim past its window renders as expired; killing the app
between `add-bond-invoice` and the submission loses nothing.

### Phase 4 — Slash notice polish and resilience (closes #195 dialog, #197)

| Task | Scope | Files |
|---|---|---|
| T4.1 | Bond-slashed dialog (mock), "View policy" link, Trade Detail durable notice for the dispute cause; `bond.state = Slashed` on the trade row when it still exists | `lib/features/notifications/…`, `trade_detail_screen.dart`, `rust/src/api/orders.rs` (one line), l10n |
| T4.2 | Verify/fix restart coverage of wiped trade keys (§9) with a test that wipes a trade, restarts the core, and delivers a `bond-slashed` for it | `rust/src/api/orders.rs`, `rust/src/api/nostr.rs` |
| T4.3 | Restore session: bond statuses from `RestoreData`, "request again" path end-to-end | `rust/src/api/orders.rs`, `pay_bond_invoice_screen.dart` |

- **PR-4a** — T4.1 (Dart + one Rust line). Justification for the mixed PR: the Rust
  change is a single state write that the Dart notice depends on.
- **PR-4b** — T4.2 + T4.3 (Rust resilience). Justification: both are "what happens
  after a restart" and share the restart test harness.

### Phase 5 — Hardening and docs

| Task | Scope |
|---|---|
| T5.1 | Web smoke: the claim store and bond statuses exercised in `test/web/smoke` fixtures |
| T5.2 | Push notification routing for `add-bond-invoice` / `bond-payout-completed` if the push pipeline supports data-only messages; otherwise document the gap |
| T5.3 | Update `CLAUDE.md` (domain gotchas: bond statuses never on the wire book; claims independent of trades), `specs/004` data-model/contracts, this document's status line; remove dead l10n |

**PR-5** — T5.1 + T5.2 + T5.3 grouped: docs and test plumbing, no protocol change.

### Issue mapping

| Issue | Phase / PRs |
|---|---|
| #208 taker flow | Phase 1 (PR-1a…1c) |
| #191 maker flow | Phase 2 (PR-2a, 2b) |
| #192 `add-bond-invoice` | Phase 3 (PR-3a, 3b) |
| #193 payout phases + acks | Phase 3 (PR-3b, 3c) |
| #195 banner, badge, dialog | Phase 3 (PR-3d) + Phase 4 (PR-4a) |
| #197 session lifecycle | Phase 4 (PR-4b) — resolved as "verify coverage", not as a deferral timer |
| #145 epic | closed by PR-5 |

---

## 11. Testing strategy

Rust tests live inline (`#[cfg(test)]`), Dart tests mirror `lib/` under `test/`. Every
PR adds the tests for its own tasks; coverage target 80 % on new code.

**Rust unit (per PR):**

- `classify_take_reply`: `PayBondInvoice` ⇒ `TakeAccepted` with bond, status
  `WaitingTakerBond`, amount from the `SmallOrder`; negative/zero amount rejected.
- Dispatch: bond arm on a missing row, on an existing `WaitingTakerBond` row (idempotent
  re-send), on a row past `WaitingTakerBond` (ignored); lock inference for each
  progress action; `Canceled` at `WaitingTakerBond` wipes + `BondLostRace`; a
  `bond-slashed` never changes `order.amount_sats` or `order.status` (regression of
  #194, extended to the new `bond` field).
- Create correlation: `PayBondInvoice` then `NewOrder` on one `request_id`; `NewOrder`
  with an empty registry matched by pubkey + id; `NewOrder` for a wiped
  `WaitingMakerBond` row ignored.
- Claims: the §6.4 phase-aware upsert table (cadence retry is a no-op, re-prompt after
  `Acknowledged` re-arms), `slashed_at` anchor, deadline arithmetic (window from stats
  at first receipt, default 15, frozen afterwards), arrival past deadline ⇒ `Expired`,
  ack transitions, `CantDo` local resolution matrix, a claim from node A survives a
  switch to node B and submits to A, storage round-trip on SQLite (native) and the
  IndexedDB stub contract (wasm target compiled by `build-web.sh`).
- Cancel-cause classification at `WaitingTakerBond`: own cancel, wire `canceled`, wire
  `in-progress`, wire `pending`, no wire status — each yields the expected `reason` and
  local-book outcome; bolt11 expiry decoding (valid, no `expiry` field ⇒ bolt11 default
  3600 s, garbage ⇒ `None` and no sweep).
- Node stats: seven tags, three-state policy, malformed values fall back to
  `Unsupported`, `estimate_bond_sats` floor/percentage cases.
- Restart: wiped trade key still decrypts a `bond-slashed` after re-init (T4.2).

**Dart:**

- Pure rules (`node_selector_rules_test.dart`: bond no longer blocks;
  `trade_status` mapping; claim view formatting).
- Widget tests: pay-bond screen (taker vs maker variants, restored-without-invoice,
  navigation on `TradeUpdate`), claim screen phases, Trade Detail banner per phase, My
  Trades badge and claim-only row, bond-slashed dialog.
- Goldens for the node card trust row and the WAITING BOND chip (see
  `docs/golden-tests.md`).
- l10n: `untranslated_messages.txt` stays empty (CI-checked).

**Manual regtest checklist per PR (mirrors upstream §14.4):** lock a taker bond; lose a
lock race; cancel during the bond window; lock a maker bond and see the order publish;
abandon a maker bond; dispute slash with each `(slash_seller, slash_buyer)` combination
the phase reaches; timeout slash; claim, ack, completion; late claim refused.

---

## 12. Comparison with the v1 client

Checked item by item against `MostroP2P/mobile` `docs/architecture/ANTI_ABUSE_BOND.md`
after drafting the above.

| v1 concern | Covered here | How v2 differs |
|---|---|---|
| Three-state `BondPolicy`, seven tags, range validation | §3.4, §7.1 T0.3 | Same model; Dart copy already exists, Rust copy added so logic stays in Rust |
| Five wire actions in the enum | §3.1 | Provided by `mostro-core`; nothing to add |
| `waiting-taker-bond` status mapping | §7.1 T0.1 | Also maps `waiting-maker-bond` (v1 deliberately did not) |
| Pay-bond screen, route, restore maps back to it | §8.2, §6.5 | Same; plus explicit "request again" because v2 restores from `RestoreData`, not from a local message log |
| Seller-as-taker two sequential invoices | §6.1 | Same, with an explicit hand-off banner |
| Maker bond via the create notifier, same `requestId`, ephemeral session until published | §6.2, T2.1 | Same correlation idea; v2 persists the row immediately (status carries the "unpublished" meaning) instead of keeping it in memory |
| Maker cannot cancel, abandons locally | §6.2 | Same |
| `BondPayoutPhase` reduced from message history | §6.4, §7.1 | v2 stores an explicit claim phase instead of reducing a message log (v2 has no per-order message log to reduce) |
| Deadline anchored on `slashed_at`, default 15 days | §6.4 | Same |
| Expired request dropped without navigating | §6.4 | Persisted as `Expired` instead of dropped, so the user can see why nothing is claimable |
| PAYOUT PENDING / IN PROGRESS badges, CLAIM button, claim screen with single Close | §8.3, §8.4 | Same (same mocks) |
| Submission publishes then persists, errors keep the form | T3.3 | Same |
| `bond-slashed` payload identical for both causes; cause inferred from history | §6.3 | Same inference, already implemented in Rust |
| Order-state guard: acks must not overwrite the tracked order | §5 principle 3, tests | Same, enforced in the Rust dispatch |
| 60 s deferred session deletion, reconcile on restart, retake guard | §9, T4.2 | **Not ported**: keys stay in the global filter; replaced by a restart-coverage verification |
| Notifications wiring; push not wired | §8.5, T5.2 | Push explicitly scoped as a Phase 5 check |
| Pure-helper tests without mocks | §11 | Rust unit tests play that role |
| Known limitation: no live countdown | §8.2 | Countdown included on the pay-bond screen; deadline on the claim screen is static (acceptable) |
| Known limitation: dedup keyed on timestamp treats retries as new | §5 principle 5 | Fixed by design: keyed on `order_id` + `slashed_at` |

Items v1 did not have that this spec adds: local expiry of an unpaid bond (both roles),
the lock-race loss message, the `CantDo` local resolution matrix, claim rows for wiped
trades, the pre-take/pre-create estimate, and web parity of the claim store.

---

## 13. Open questions and assumptions to verify

1. **Restart coverage of wiped trade keys** (§9, T4.2) — assumed to need work; verify
   before PR-4b.
2. **Does `RestoreData` include `waiting-taker-bond` / `waiting-maker-bond` orders?**
   Assumed yes (they are open orders on the daemon side). If the daemon filters them,
   the local rows are the only record and the "request again" path is the recovery.
3. **bolt11 decoder crate.** `lightning-invoice` (rust-lightning) is the candidate:
   pure Rust, `no_std`-capable, builds for `wasm32-unknown-unknown`. Confirm it does
   not drag a conflicting `secp256k1` / `bitcoin` version into the tree next to
   `bip32` / `k256` before PR-1a; if it does, a minimal bech32 + tagged-field reader
   for the `x` (expiry) and `c`/timestamp fields is acceptable (no signature check is
   needed — the daemon is the trusted source of the invoice).
7. **Upstream follow-ups to propose** (not blockers): ship `claim_window_days` or
   `deadline_at` inside `BondPayoutRequest` so the deadline is immutable end to end;
   an idempotent re-request for a maker bond bolt11 (or the bolt11 in `RestoreData`)
   so a fresh-device restore does not strand a `WaitingMakerBond` order; a cause field
   on `bond-slashed`.
4. **Amount seeding for a seller-as-taker.** The existing `PayInvoice` arm seeds
   `order.amount_sats` from the payload; confirm the `PayBondInvoice` payload's
   `amount` (the bond) is never used for that seeding (T1.1 test).
5. **Push pipeline capability** for data-only bond events (T5.2).
6. **Concurrent-bond visibility**: after a lost race the local book must show the order
   as available again only if the wire still says `pending`; the existing
   `settle_after_lost_take` path is expected to cover this — confirm in T1.2 tests.

---

## 14. References

- Upstream spec: <https://github.com/MostroP2P/mostro/blob/main/docs/ANTI_ABUSE_BOND.md>
- Upstream code consulted: `src/app/bond/flow.rs` (`request_taker_bond`,
  `request_maker_bond`, `on_bond_invoice_accepted`), `src/app/cancel.rs` (status guard
  `Pending | WaitingTakerBond`), `src/util.rs` (`publish_order`,
  `resume_publish_after_maker_bond`), `src/scheduler.rs` (silent `WaitingMakerBond`
  expiry), `src/nip33.rs` (`bond_policy_tags`, `WaitingTakerBond → pending`).
- Protocol docs: <https://mostro.network/protocol/>
- v1 client doc: <https://github.com/MostroP2P/mobile/blob/main/docs/architecture/ANTI_ABUSE_BOND.md>
- Epic and sub-issues: #145, #191, #192, #193, #195, #197, #208 (this repo)
- Design mocks: `docs/design/145-bond-payout-banner.png`,
  `docs/design/145-trades-payout-pending.png`, `docs/design/145-bond-slashed.png`
- Precedent for a phased client spec in this repo: `docs/cashu/README.md`
