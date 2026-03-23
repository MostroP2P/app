# Contract: Reputation API

**Module**: `rust/src/api/reputation.rs`

Rating system and privacy mode management.

## Functions

### submit_rating(trade_id: String, score: u8) → ()
Submit a rating for the counterparty after a successful trade.

**Preconditions**: Trade MUST be completed with `Success` outcome.
Identity MUST NOT be in privacy mode.

**Side effects**: Sends `rate` action to Mostro daemon via NIP-59.

**Errors**: `TradeNotComplete`, `PrivacyModeEnabled`, `AlreadyRated`,
`ProtocolError`.

---

### get_privacy_mode() → bool
Check whether privacy mode is enabled.

---

### set_privacy_mode(enabled: bool) → ()
Enable or disable privacy mode.

**Side effects**: When enabled, no reputation data is sent/received
in future trades. Session recovery becomes unavailable.

**Errors**: `NoIdentity`.

---

### get_rating_for_trade(trade_id: String) → RatingInfo?
Get the rating submitted/received for a specific trade.
Returns null if no rating exists.

## Streams

### on_rating_received() → Stream<RatingReceivedEvent>
Emits when a counterparty submits a rating for the current user.

## Types

### RatingInfo
```text
trade_id: String
score: u8
is_mine: bool       # Did I submit this rating?
created_at: i64
```

### RatingReceivedEvent
```text
trade_id: String
score: u8
from_pubkey: String
```
