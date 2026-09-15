# Contract: Anti-Abuse Bond

**Module**: `rust/src/api/bond.rs`

The bridge surface for Mostro's anti-abuse bond: the active node's policy, the
maker's way out of an unpaid bond window, and the payout claims a user holds
when a counterparty's bond was slashed. The design, the wire contract and the
phase plan live in `docs/ANTI_ABUSE_BOND.md`; this file only pins the API.

Bond **statuses** are not here: a take or a create that needs a bond returns
its trade or order at `WaitingTakerBond` / `WaitingMakerBond` (see
`contracts/orders.md`), and neither status is ever on the public book.

Rust returns stable markers, never prose; Dart maps them to localized text.

## Node policy

### get_bond_policy() → BondPolicyInfo?
The active node's advertised policy, parsed from its kind 38385 info event.
`None` means not known yet (startup, a node switch, an unreachable node);
`Some(policy = Unsupported)` means known, and the daemon predates bonds.

### estimate_bond_sats(order_amount_sats: u64) → u64?
The bond the active node would ask for, for the pre-commit warning. `None`
when the policy is unknown, not `Enabled`, or has no percentage. Never used to
charge anything: the daemon sends the exact bolt11.

## Bond windows

### abandon_bonded_order(order_id: String) → ()
Walk away from an order parked at `WaitingMakerBond` without paying. The daemon
refuses a cancel in this window and reaps the unpaid order itself, so this only
wipes the local row and emits `Canceled` with `UserCanceled`. Decided under the
order's guard: a bond that locked meanwhile is a published order and is refused.
**Errors**: `TradeNotFound`, `NotWaitingBond`.

### close_expired_bond_window(order_id: String) → bool
Close a bond-window row now if its deadline passed unpaid, which the periodic
sweep would otherwise do on its next pass. Returns whether the row was closed;
a paid, published or still-live window is left alone. **Errors**:
`StorageUnavailable`.

## Payout claims

A claim is created by the daemon's `add-bond-invoice` and is **independent of
any trade**. The winner's trade may be completed, canceled or wiped by then.
Claims are stored in `bond_claims`, keyed `<node_pubkey>:<order_id>`, so two
nodes can hold one for the same order. The submission always goes to the node
that issued the claim, whichever node is active.

Phases: `Pending` (invoice asked for, or re-asked) → `Submitted` (our bolt11
published) → `Acknowledged` (`bond-invoice-accepted`) → `Completed`
(`bond-payout-completed`), or `Expired` when the claim window closes first.
`Completed` and `Expired` are terminal. The deadline is `slashed_at` plus the
node's `payout_claim_window_days` (15 by default), frozen on first receipt.

**Delivery coverage.** The global kind-14 filter's authors are the active node,
every node with a non-terminal claim, and every node the user switched away
from, kept for its claim window plus a 15-day margin. The retained set is
persisted in the `bond_claim_retained_nodes` setting. Without it, a slash that
lands after a switch would be asked for on a node nothing listens to.

### list_bond_claims() → Vec<BondClaim>
Every claim, most recently changed first. **Errors**: `StorageUnavailable`.

### get_bond_claim(order_id: String) → BondClaim?
The claim for one order: the open one when several nodes issued one, otherwise
the most recently changed. **Errors**: `StorageUnavailable`.

### get_bond_claim_from(node_pubkey: String, order_id: String) → BondClaim?
The exact claim a `BondClaimUpdate` names. **Errors**: `StorageUnavailable`.

### submit_bond_payout_invoice(order_id: String, invoice: String) → ()
Publish the `add-bond-invoice` reply to the issuing node, from the trade key
the request was addressed to. Marks the claim `Submitted` so a cadence retry
does not re-arm the form, then waits for the daemon's verdict. **Errors**:
`ClaimNotFound`, `ClaimNotClaimable` (acknowledged, paid or expired),
`InvalidInvoice`, `InvoiceAmountMismatch` (a decodable bolt11 for other than
the share), `TradeKeyMissing`, `BondClaimRejected` (a `CantDo` the claim cannot
explain; it stays `Pending`), `BondClaimExpired`, `NoDaemonResponse` (the claim
stays `Submitted`; the acknowledgement arrives on the global feed).

## Streams

### on_bond_claim_updated() → Stream<BondClaimUpdate>
Every claim phase change: a new claim, a submission, an acknowledgement, a
payout, an expiry. A lagging consumer skips ahead rather than ending.

### on_bond_slashed() → Stream<BondSlashedEvent>
Every `bond-slashed` notice for the user's own bond. `event_id` is the source
event's id; the daemon replays history on reconnect, so consumers key their
notification on it.

## Notifications

Bond notices are in-app only. The push pipeline sends content-free wake-ups for
kind 14 p-tagged to a registered trade pubkey and cannot name a bond action, so
there is no push routing for them (`docs/ANTI_ABUSE_BOND.md` §8.5).
