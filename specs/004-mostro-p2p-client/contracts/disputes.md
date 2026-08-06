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

**Side effects**: Sends Dispute action to Mostro daemon via NIP-44 (Kind 14).
Creates local Dispute record. Updates trade step to `Disputed`.

**Errors**: `TradeNotDisputable`, `DisputeAlreadyOpen`, `ProtocolError`.

---

### submit_evidence(trade_id: String, text: String) → ChatMessage
Submit text evidence for an open dispute. Delivered as an admin-type
message.

**Validation**: `text` MUST not be empty. Dispute MUST be open.

**Errors**: `NoOpenDispute`, `EvidenceEmpty`.

---

### get_dispute(trade_id: String) → Dispute?
Get dispute details for a trade. Returns null if no dispute exists.

## Persistence and restart

The Dispute record is **in-memory by design** — its status and resolution come
back from daemon events. One field is the exception: the **solver pubkey**
arrives exactly once, in `admin-took-dispute`, and cannot be re-derived. It is
persisted to the settings KV under `dispute_admin:<order_id>`.

**Rehydration**: on relay (re)connect, dispute records are rebuilt for persisted
trades that have a stored solver, before dispute-chat listeners are re-armed.
Restored records are `InReview` (a stored solver means one took the dispute),
`initiated_by_me: false`, and **unread** — the pre-restart read state is not
recoverable and an active dispute must surface. Records already in memory win.
This is what makes `get_dispute` non-null and `submit_evidence` work again after
a restart.

**Terminal states**: the solver key is deleted when a resolution reaches the
dispute store, and rehydration additionally skips — and clears — any trade whose
order status is finished (`SettledByAdmin`, `CanceledByAdmin`,
`CompletedByAdmin`, `Success`, `Canceled`, `CooperativelyCanceled`, `Expired`).
The trade status, not the dispute record, is the durable signal: the daemon's
`admin-settled` / `admin-canceled` are persisted by the order status-sync path
without being routed into the dispute store. Without this, a resolved dispute
would be resurrected as `InReview` on every restart.

**Platform limitation (web)**: persistence is native-only today. The Flutter
shell does not call `init_db` on web, and the IndexedDB store's `list_trades`
is still a stub (#233), so a browser reload loses the solver pubkey and the
dispute chat with it. No change is needed in this module once #233 lands trade
persistence on web.

## Streams

### on_dispute_updated(trade_id: String) → Stream<Dispute>
Emits when dispute status changes (opened, admin message received,
resolved).
