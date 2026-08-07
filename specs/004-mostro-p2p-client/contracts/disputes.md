# Contract: Disputes API

**Module**: `rust/src/api/disputes.rs`

Dispute initiation, evidence submission, and resolution tracking.

## Functions

### open_dispute(trade_id: String, reason: String?) → Dispute
Initiate a dispute on an active trade.

**Preconditions**: Trade MUST be in a state between `PaymentLocked` and
completion (i.e., funds are in escrow). No existing open dispute on
this trade.

The daemon accepts a dispute only on an `Active` or `FiatSent` order and
answers anything earlier with `CantDo`, so the status already held locally is
checked before publishing. `InProgress` passes: it is the public bucket, i.e. a
trade whose real state is unknown, and that call belongs to the daemon.

The open is **single-flight per trade**: a second call while one is still
awaiting the daemon is refused. Both would derive the same trade key, so the
second registration would replace the first one's pending record and strand its
caller on a timeout the daemon never caused.

**Side effects**: Sends the Dispute action to the Mostro daemon via NIP-44
(Kind 14), carrying a random u64 `request_id` nonce, and waits up to 10 s for
the reply the daemon echoes it in — `DisputeInitiatedByYou` on acceptance,
`CantDo` on rejection. Only the correlated acceptance creates the local
Dispute record; that reply also carries the daemon's dispute UUID, which is
the id the solver and the daemon's Kind 38386 dispute event refer to, so the
record is stored under it. The reply doubles as the status update that moves
the trade to `Disputed` and is processed normally. On rejection or timeout
**the call persists nothing** — a publish is not an acceptance, and the caller
surfaces the error instead of showing a dispute that does not exist.

An acceptance **without** that dispute id is malformed and fails closed: it
persists nothing and reports `ProtocolError`. `Dispute.id` is contractually the
daemon's, and a locally minted id would be indistinguishable from a real one
while being wrong. A conforming daemon always sends it, so this is a
protocol-violation guard rather than a routine path.

An acceptance that arrives **after** the caller timed out is still reconciled:
the daemon did open the dispute, and its reply moves the trade to `Disputed`
either way, so the record is created then (unread, and without the reason,
which went with the timed-out call). Suppressing it would leave a disputed
trade with no dispute to open and no solver to reach. The same missing-id guard
applies.

A solver can be assigned inside that same window, in which case the record
already exists as the peer-style placeholder `admin-took-dispute` writes
(`InReview`, not ours, no reason, solver known, locally minted id). The
reconciliation **claims** it — daemon id and initiator flag replace the local
ones, solver and `InReview` survive — because the correlated acceptance proves
the dispute is ours. Any other existing record (a retry that succeeded, a
resolved dispute) is left untouched.

The local status check and the reply correlation are two layers of the same
concern: the check keeps most rejections off the wire, and the correlation
reconciles the ones that still come back (issues #203 and #202).

The nonce gate is the dispatcher's, shared with the order requests — see
[orders.md](orders.md) "Daemon confirmation & request correlation".

Note: the daemon replies `CantDo` only for `MostroCantDo` causes. A duplicate
dispute or a daemon-side DB failure is an internal error it merely logs, so
those surface as `NoDaemonResponse` rather than a precise reason.

**Errors**: `TradeNotDisputable`, `DisputeAlreadyOpen`, `ProtocolError`,
`NoDaemonResponse`, plus daemon `CantDo` reasons passed through as errors.

---

### submit_evidence(trade_id: String, text: String) → ChatMessage
Submit text evidence for an open dispute. Delivered as an admin-type
message.

**Validation**: `text` MUST not be empty. Dispute MUST be open.

**Errors**: `NoOpenDispute`, `EvidenceEmpty`.

---

### get_dispute(trade_id: String) → Dispute?
Get dispute details for a trade. Returns null if no dispute exists.

## Streams

### on_dispute_updated(trade_id: String) → Stream<Dispute>
Emits when dispute status changes (opened, admin message received,
resolved).
