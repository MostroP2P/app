# Anti-Abuse Bond

How the Mostro Mobile app (v1) participates in the **anti-abuse bond** feature. This document is
the **behavioural reference**: it describes what the client must do, derived from the v1 mobile
implementation, so v2 can replicate it.

> **Pending in v2 — not yet implemented.** v2 has no bond support of any kind today. This
> document describes the v1 (mobile) behaviour as the parity target; it is descriptive, not a
> v2 design.

> **Scope.** The bond is a **daemon** feature. The economics, the slash decisions, the
> hold-invoice custody, the payout scheduler and the dispute mechanics all live in `mostrod`.
> The client never *decides* anything about a bond — it renders what the daemon instructs and
> submits what the user provides. This doc covers only the **client** side: discovering a
> node's policy, the wire messages it reacts to, the screens it shows, and the
> session/restore handling it must get right.

## Where mobile implements this

| Concern | Mobile source |
|---------|---------------|
| Wire actions (5) | `lib/data/models/enums/action.dart` |
| `waiting-taker-bond` status | `lib/data/models/enums/status.dart` |
| Node policy model + parsing | `lib/features/mostro/mostro_instance.dart` |
| Payout request payload | `lib/data/models/bond_payout_request.dart` |
| Payout-phase helpers (pure) | `lib/shared/utils/bond_payout_helpers.dart` |
| Cancel-lifecycle helpers (pure) | `lib/shared/utils/bond_cancel_helpers.dart` |
| Slash-cause helpers (pure) | `lib/shared/utils/bond_slash_helpers.dart` |
| Message handling / session logic | `lib/features/order/notifiers/abstract_mostro_notifier.dart` |
| Maker-bond create flow | `lib/features/order/notifiers/add_order_notifier.dart` |
| Order-state guard | `lib/features/order/models/order_state.dart` |
| Pay-bond / payout-claim screens | `lib/features/order/screens/pay_bond_invoice_screen.dart`, `bond_payout_invoice_screen.dart` |
| Routes | `lib/core/app_routes.dart` |

---

## 1. Overview

An anti-abuse bond is a **second Lightning hold invoice** — separate from the trade escrow —
that a node may require a user to lock when entering a trade. It deters griefing: a user who
abandons or sabotages a trade can have the bond **slashed**; an honest user always gets it
**released**.

The feature is **opt-in and off-by-default at the node level**. A node that does not enable it
produces zero behaviour change in the app. Because policy varies per node, the client must:

1. **Discover** whether the connected node enforces bonds, and on which side (§2).
2. **React** to the bond wire messages when they arrive (§3–§7).
3. **Manage sessions and restore** so a trailing slash notice is never lost (§8).

---

## 2. Discovering the node's bond policy

A node advertises its bond policy in its **kind-38385** info event. The client parses those
tags into its `MostroInstance` model.

### Three-state policy

The policy is deliberately **three states**, not a boolean, so the app can tell "feature off"
apart from "old daemon":

```dart
enum BondPolicy { unsupported, disabled, enabled }
enum BondApplyTo { take, make, both }
```

| State | Meaning |
|-------|---------|
| `unsupported` | `bond_enabled` tag absent → legacy daemon |
| `disabled` | `bond_enabled="false"` → operator left it off |
| `enabled` | `bond_enabled="true"` → bond active, other tags present |

An empty or whitespace-only `bond_enabled=""` is treated as **missing** (`unsupported`), not
`disabled`. Malformed values fall back to `unsupported` defensively, so a corrupt payload can
never masquerade as an intentional policy:

```dart
BondPolicy get bondPolicy {
  final raw = _getOptionalTagValue('bond_enabled')?.toLowerCase();
  switch (raw) {
    case 'true':
      return BondPolicy.enabled;
    case 'false':
      return BondPolicy.disabled;
    default:
      return BondPolicy.unsupported; // absent, empty, or malformed
  }
}
```

### The seven tags

| Tag | Notes |
|-----|-------|
| `bond_enabled` | always emitted on modern daemons |
| `bond_apply_to` | `take` \| `make` \| `both` |
| `bond_slash_on_waiting_timeout` | node policy: can a timeout slash? |
| `bond_amount_pct` | validated to `[0.0, 1.0]` |
| `bond_base_amount_sats` | floor in sats, `>= 0` |
| `bond_slash_node_share_pct` | node's share of a slash, `[0.0, 1.0]` |
| `bond_payout_claim_window_days` | days to claim before forfeit, `> 0` |

The six parameter fields are non-null **only** when the policy is `enabled`; each getter
validates its range and yields `null` on out-of-range or unparseable input.

`bond_payout_claim_window_days` is the most load-bearing for the client: it is how the app
computes the forfeit deadline locally (§6). When a node does not advertise it, the app
defaults to **15 days** at every call site.

The bond amount itself (`max(amount_pct * order, base_amount_sats)`) is **never computed by
the client for charging** — the daemon always sends the exact bolt11. The pct/base tags exist
only so the UI can warn the user up front what a trade on this node will cost.

---

## 3. The wire contract

Five `Action` values carry the entire client-visible bond protocol:

```dart
payBondInvoice('pay-bond-invoice'),
addBondInvoice('add-bond-invoice'),
bondInvoiceAccepted('bond-invoice-accepted'),
bondPayoutCompleted('bond-payout-completed'),
bondSlashed('bond-slashed'),
```

| Action | Direction | Payload | App reaction |
|--------|-----------|---------|--------------|
| `pay-bond-invoice` | Mostro → user | `PaymentRequest` (bolt11) | Show pay-bond screen (§4, §5) |
| `add-bond-invoice` | Mostro → winner | `BondPayoutRequest` | Show payout-claim screen (§6) |
| `bond-invoice-accepted` | Mostro → winner | `Order` (null status) | Mark payout "in progress" (§6) |
| `bond-payout-completed` | Mostro → winner | `Order` (null status) | Mark payout done (§6) |
| `bond-slashed` | Mostro → slashed user | `Order` (bond amount, null status) | Forfeiture dialog (§7) |

Two directions are deliberately distinct: `pay-bond-invoice` (Mostro asks the user to **pay** a
bolt11) versus `add-bond-invoice` (Mostro asks the winner to **provide** a payout bolt11). They
never share a code path.

**On the dispute slash (Phase 2).** The solver-directed dispute slash is a **daemon-internal**
decision. The client never sees it directly: the loser receives a normal `admin-canceled` /
`admin-settled` with `payload: null`, and the slash surfaces indirectly later — either as an
`add-bond-invoice` to the winner or a `bond-slashed` notice to the loser. There is no
slash-specific wire signal on the trade resolution itself.

---

## 4. Flow 1 — Taker pays a bond

When `apply_to ∈ {take, both}` and a taker takes an order, the daemon parks the order at
`waiting-taker-bond` and sends the taker a `pay-bond-invoice`.

```text
take-buy / take-sell
        │
        ▼
Mostro:  order → waiting-taker-bond,  pay-bond-invoice (bond bolt11)
        │
        ▼
App:  status → waiting-taker-bond
      navigate → /pay_bond/:orderId
        │
   user pays bond HTLC
        │
        ▼
Mostro:  bond Locked → trade flow continues (pay-invoice / add-invoice)
```

- **Status mapping.** `pay-bond-invoice` resolves the tracked order to `waiting-taker-bond`.
  The order's *public* NIP-69 bucket stays `pending` on the daemon side, so the order is still
  visible and takeable to others — the app does not hide it.
- **Navigation.** The handler routes to `/pay_bond/:orderId`. The screen renders the QR/bolt11
  and lets the user cancel out of the bond window.
- **Restore.** On restart, an order rebuilt as `waiting-taker-bond` maps back to the
  `pay-bond-invoice` action, so the user lands on the pay-bond screen again.
- **Seller-as-taker.** When the taker is the *seller* (a buy-order taken), the daemon sends two
  sequential messages on the same order: `pay-bond-invoice` first, then the trade hold invoice
  as `pay-invoice` once the bond locks. The client dispatches on **action type** — no bolt11
  memo parsing is needed.

---

## 5. Flow 2 — Maker pays a bond on order creation

When `apply_to ∈ {make, both}`, the daemon requests a bond from the **maker** *before* the order
is published to Nostr. This flow is driven by the maker-create notifier, because the order does
not exist publicly yet.

Crucially, the client does **not** use a dedicated `waiting-maker-bond` status. The maker side
reuses `pay-bond-invoice` and tracks the limbo with an **ephemeral session flag**.

```text
submit new-order
        │
        ▼
Mostro:  order parked (WaitingMakerBond, daemon-side),
         pay-bond-invoice (PaymentRequest) on the create requestId
        │
        ▼
App:  session.bondPending = true   ← in-memory only, NOT persisted
      navigate → /pay_bond/:orderId
        │
   maker pays bond HTLC
        │
        ▼
Mostro:  bond Locked → order published → new-order ack on same requestId
        │
        ▼
App:  session.bondPending = false  ← now persisted for real
      navigate → order confirmed
```

- **`session.bondPending`** marks a maker order stuck in bond limbo. While `true`, the session
  is **in memory only**, so an abandoned, never-paid order never survives a restart. The shared
  `pay-bond-invoice` handler skips persistence in this state.
- **Same `requestId`.** Both the bond bolt11 and the publication ack return on the create
  `requestId`, so the maker-create notifier stays alive until the bond locks.
- **Abandoning a maker bond.** The daemon rejects an explicit `cancel` while the order sits at
  `WaitingMakerBond`. So the client abandons **locally**: if `bondPending == true`, cancel drops
  the in-memory session and lets the server-side hold invoice expire.

---

## 6. Flow 3 — Claiming a slashed bond's share

When a bond is slashed (by solver directive or timeout), the daemon settles the HTLC immediately
and then asks the **winning counterparty** for a payout bolt11 so it can forward their share.
This is the only bond flow with a multi-step state machine on the client, modelled as
`BondPayoutPhase`.

```text
add-bond-invoice (BondPayoutRequest { order, slashed_at })
        │
        ▼
App:  expiry check against claim window
      if not expired → navigate /bond_payout/:orderId
        │
   user submits payout bolt11
        ▼
Mostro:  bond-invoice-accepted  → phase: acknowledged
        ▼
Mostro:  bond-payout-completed  → phase: completed
```

### Phase model

```dart
enum BondPayoutPhase { none, pending, acknowledged, completed }
```

| Phase | Latest bond message | UI |
|-------|---------------------|----|
| `none` | no bond-payout messages | — |
| `pending` | inbound `add-bond-invoice` (`BondPayoutRequest`) | claim form + deadline |
| `acknowledged` | `bond-invoice-accepted` | "in progress", form hidden |
| `completed` | `bond-payout-completed` | done, single CLOSE button |

The phase is reduced from the message history — **latest relevant message by timestamp wins**.
An **outbound** `add-bond-invoice` (the user's own `PaymentRequest` reply) does not define a
phase: the reducer skips it and keeps looking, so retries and acknowledgements interleave
correctly:

```dart
BondPayoutPhase bondPayoutPhase(List<MostroMessage> messages) {
  final relevant = messages.where((m) =>
      m.action == Action.addBondInvoice ||
      m.action == Action.bondInvoiceAccepted ||
      m.action == Action.bondPayoutCompleted);
  if (relevant.isEmpty) return BondPayoutPhase.none;

  final sorted = [...relevant]..sort(
      (a, b) => (b.timestamp ?? 0).compareTo(a.timestamp ?? 0));

  for (final msg in sorted) {
    switch (msg.action) {
      case Action.bondPayoutCompleted:
        return BondPayoutPhase.completed;
      case Action.bondInvoiceAccepted:
        return BondPayoutPhase.acknowledged;
      case Action.addBondInvoice:
        if (msg.payload is BondPayoutRequest) return BondPayoutPhase.pending;
        continue; // outbound PaymentRequest reply: keep looking
      default:
        continue;
    }
  }
  return BondPayoutPhase.none;
}
```

### Deadline anchored on `slashed_at`

`BondPayoutRequest` carries `slashed_at`, the fixed slash timestamp. The client computes the
forfeit deadline **from that anchor**, never from message receipt time — so a recipient who was
offline for days still sees the true deadline:

```dart
DateTime bondClaimDeadline(int slashedAt, int claimWindowDays) =>
    DateTime.fromMillisecondsSinceEpoch(
      (slashedAt + claimWindowDays * 86400) * 1000, isUtc: true,
    ).toLocal();
```

The claim window comes from the node's `bond_payout_claim_window_days`, defaulting to **15**
when absent. An already-expired request is dropped without navigating.

### Where it surfaces

- **My Trades badge:** "PAYOUT PENDING" while a claim is pending, "PAYOUT IN PROGRESS" while
  acknowledged.
- **Trade Details CLAIM button:** shown only while a claim is pending; pushes
  `/bond_payout/:orderId`.
- **Claim screen:** on `acknowledged` / `completed` it hides the form and shows an info message
  plus a single CLOSE button.
- **Submission:** the claim publishes **then** persists, and lets persistence errors propagate
  so the screen keeps the user on the form rather than silently losing the submission.

---

## 7. Forfeiture notice (`bond-slashed`)

`bond-slashed` is a **best-effort** notice the daemon sends to the slashed party when their bond
is forfeited. It complements the resolution message the user already gets for the order, and is
sent for **both** slash causes:

- **Timeout slash** — the user missed a waiting-state deadline. The daemon sends `canceled`
  first, then `bond-slashed` ~150 ms later. (Not sent on a voluntary cancel — that returns the
  bond.) This `canceled`-then-`bond-slashed` ordering is why the client must defer session
  deletion (§8).
- **Dispute-resolution slash** — a solver directed the slash while resolving a dispute. The
  daemon sends `admin-settled` / `admin-canceled` first, then `bond-slashed`.

**Payload (identical for both causes).** An `Order` (`SmallOrder`) whose `amount` is the
**slashed bond amount**, not the trade amount, and whose `status` is `null`. There is **no
`reason` field** — the wire message does not say which cause triggered it.

### Inferring the cause

Because the payload is identical, the client infers the cause from the order's message history.
The two causes are mutually exclusive: a timeout slash only happens in a waiting state, before
any dispute; once disputed, the only slash path is the admin resolution. So a single
dispute/admin action in the history unambiguously marks a dispute slash:

```dart
enum BondSlashCause { timeout, dispute }

const _disputeActions = {
  Action.disputeInitiatedByYou,
  Action.disputeInitiatedByPeer,
  Action.adminSettled,
  Action.adminCanceled,
};

BondSlashCause bondSlashCause(List<MostroMessage> messages) {
  final disputed = messages.any((m) => _disputeActions.contains(m.action));
  return disputed ? BondSlashCause.dispute : BondSlashCause.timeout;
}
```

The cause is computed **once, at notification creation**, and persisted into the notification's
`slash_cause` so the notification stays self-contained. When storage is unavailable (background)
the inference defaults to `timeout`.

### Rendering

- The notification maps to the **cancellation** type. The title is the same for both causes; the
  **message** is chosen by cause (a timeout variant vs a dispute variant).
- Tapping opens a detail dialog whose copy is picked from the persisted `slash_cause`.
- **Order-details notice (dispute only):** a durable line in the order detail is shown **only**
  when the order's bond was slashed **and** the cause is `dispute`. A timeout slash shows nothing
  there (the notification already covers it).

### Why it was being dropped before

Two bugs, both fixed: (1) the action was not in the enum, so message parsing threw and discarded
the notice; (2) the `canceled` handler deleted the session immediately, dropping the trade key
from the subscription filter and the decryption key, so the trailing notice could never be
received or decrypted. The session-lifecycle rules in §8 are the fix for the second.

---

## 8. Session lifecycle & restart resilience

This is the subtlest part of the client. Because `bond-slashed` arrives *after* `canceled`,
deleting the session on `canceled` would drop the keys needed to receive (and decrypt) the
trailing notice. But deferring deletion for *every* cancel would strand sessions for ordinary
voluntary cancels. The rule:

> **Defer deletion only for a bonded order the user did NOT cancel itself.** A voluntary cancel
> returns the bond (no slash, no notice); a non-bonded order is never slashed.

```dart
bool shouldDeferBondCancelDeletion({
  required bool userInitiated,
  required bool hadBond,
}) =>
    !userInitiated && hadBond;
```

### Live `canceled` handling

- `userInitiated || !hadBond` → delete the session **immediately** (original behaviour).
- bonded **and** not user-initiated (the real timeout-slash case) → start a **60 s** deferral
  timer.

The `bond-slashed` handler cancels that timer and deletes the session once the notice lands. It
is out-of-order safe: if `bond-slashed` arrives first, the later `canceled` finds no session and
no-ops. The "user initiated this cancel" marker is set after a successful cancel send and is
**deliberately not persisted** (persisting an outbound marker would corrupt rebuilt state on a
rejected or cooperative cancel); the restart case is handled by reconciliation instead.

### Restart reconciliation

The 60 s timer is in-memory and lost if the app closes inside the window. On restart, the sync
pass reconciles any order rebuilt as `canceled` into one of three actions:

```dart
enum BondCancelReconcileAction { none, deleteNow, rearm }

BondCancelReconcileAction reconcileBondCancelAction({
  required bool sessionExists,
  required bool hadBond,
  required bool bondSlashedReceived,
  required int latestCanceledTimestamp,
  required int nowMs,
  required int graceWindowMs,
}) {
  if (!sessionExists || !hadBond) return BondCancelReconcileAction.none;

  final elapsed = nowMs - latestCanceledTimestamp;
  if (bondSlashedReceived ||
      latestCanceledTimestamp == 0 ||
      elapsed >= graceWindowMs) {
    return BondCancelReconcileAction.deleteNow;
  }
  return BondCancelReconcileAction.rearm;
}
```

| Outcome | When |
|---------|------|
| `none` | no session, no bond, or a live timer already owns it |
| `deleteNow` | `bond-slashed` already received, no cancel timestamp, or window elapsed |
| `rearm` | window not yet elapsed — re-arm the timer for the remainder |

### Retake guard

If the user retakes the same `orderId` within the 60 s window, a stale grace timer (live or
reconcile-rearmed) must not delete the fresh session. Retaking clears the pending deletion timer
and the user-cancel flag right after the new session is created.

---

## 9. Guarding the tracked order

The bond payout acks and the slash notice all carry a `SmallOrder` with a **null status** and a
**bond-sized amount**. If that were allowed to overwrite the tracked trade order, My Trades would
show the bond amount and lose the real trade status. The guard never lets the three acks replace
the tracked order, and leaves the order status unchanged:

```dart
// Bond acks and the slash notice: their SmallOrder has a null status and a
// bond-sized amount; don't let it overwrite the tracked trade order.
final bool isBondPayoutAck =
    message.action == Action.bondInvoiceAccepted ||
    message.action == Action.bondPayoutCompleted ||
    message.action == Action.bondSlashed;

order: (message.payload is Order && !isBondPayoutAck)
    ? message.getPayload<Order>()
    : /* keep current order */ ...
```

Correspondingly, the status resolver returns the **current** status unchanged for
`add-bond-invoice` and for the three acks, so an ack never moves the order out of its real trade
state. Only `pay-bond-invoice` actually sets a status (`waiting-taker-bond`).

---

## 10. Known limitations / open items

- **Push notifications** for bond actions are not wired — only in-app surfaces work.
- **Anti-spam dedup** of daemon retries uses keys that include the message timestamp, so each
  `add-bond-invoice` retry is treated as new.
- **Real-time deadline countdown:** the forfeit deadline is computed at screen open, not
  refreshed live.
- **Offline correctness** of the 60 s deferral depends on relay retention of the trailing
  `bond-slashed` gift wrap.
- **Slash-cause inference is a heuristic.** The daemon ships no `reason` on `bond-slashed`, so
  the client infers timeout vs dispute from order history and defaults to `timeout` when the
  history is unavailable. A daemon-side `reason` field would make this unambiguous.
