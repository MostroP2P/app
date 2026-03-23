# Contract: Disputes API

**Module**: `rust/src/api/disputes.rs`

Dispute initiation, evidence submission, and resolution tracking.

## Functions

### open_dispute(trade_id: String, reason: String?) → Dispute
Initiate a dispute on an active trade.

**Preconditions**: Trade MUST be in a state between `PaymentLocked` and
completion (i.e., funds are in escrow). No existing open dispute on
this trade.

**Side effects**: Sends Dispute action to Mostro daemon via NIP-59.
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

## Streams

### on_dispute_updated(trade_id: String) → Stream<Dispute>
Emits when dispute status changes (opened, admin message received,
resolved).
