# Contract: Shared Types

**Module**: `rust/src/api/types.rs`

Shared types exposed to Flutter via flutter_rust_bridge. These are the
data structures that cross the Rust/Dart boundary.

## Enums

### OrderKind
```text
Buy | Sell
```

### OrderStatus
```text
Pending | WaitingBuyerInvoice | WaitingPayment | Active | FiatSent
| SettledHoldInvoice | Success | Canceled | Expired
| CooperativelyCanceled | CanceledByAdmin | SettledByAdmin
| CompletedByAdmin | Dispute | InProgress
| WaitingTakerBond | WaitingMakerBond
```
> Note: `WaitingTakerBond` / `WaitingMakerBond` are never on the wire book: the
> first publishes as `pending`, the second publishes nothing. They exist only on
> the local trade row, learned from `pay-bond-invoice` (`contracts/bond.md`).
> Note: `PaymentFailed` is NOT a status - it's an Action notification sent when
> Lightning payment to buyer fails. Order remains in `SettledHoldInvoice` status.

> Note: `PaymentFailed` is NOT a status — it's an Action notification sent when
> the LN payment fails. The order remains in `SettledHoldInvoice`.
> `CooperativelyCanceled` is a **client-side UI state only** — the protocol
> does not change order status for cooperative cancellation.

> Note: `InProgress` reaches this client as NIP-69's public bucket for "the
> order left the book", not as the mostro-core FSM state that follows an admin
> taking a dispute. It carries no claim about the escrow, so it MUST NOT be
> mapped onto `Active` in the UI. See "Public status vs. trade status" in
> `contracts/orders.md`.

### TradeRole
```text
Buyer | Seller
```

### BuyerStep
```text
OrderTaken | PayInvoice | PaymentLocked | FiatSent
| AwaitingRelease | Complete
```

### SellerStep
```text
OrderPublished | TakerFound | InvoiceCreated | PaymentLocked
| AwaitingFiat | Complete
```

### TradeStep
```text
Buyer(BuyerStep) | Seller(SellerStep) | Disputed
```

### TradeOutcome
```text
Success | Canceled | Expired | DisputeWon | DisputeLost
```
> Note: `PaymentFailed` removed - LN payment failures are transient and retried,
> not a final trade outcome.

> Note: `PaymentFailed` removed — LN payment failures are transient and retried,
> not a terminal trade outcome. The order stays in `SettledHoldInvoice`.

### MessageType
```text
Peer | Admin | System
```

### DisputeStatus
```text
Open | InReview | Resolved
```

### DisputeResolution
```text
FundsToMe | FundsToCounterparty | CooperativeCancel
```

### RelayStatus
```text
Connected | Disconnected | Connecting | Error
```

### ConnectionState
```text
Online | Offline | Reconnecting
```

### QueuedMessageStatus
```text
Pending | Sent | Failed
```

### CooperativeCancelState
```text
RequestedByMe | RequestedByPeer | Accepted
```

### FileType
```text
Image | Document | Video
```

### DownloadStatus
```text
Pending | Downloading | Downloaded | Failed
```

### WalletStatus
```text
Connected | Disconnected | Connecting | Error
```

### ThemeMode
```text
System | Dark | Light
```

### LogLevel
```text
Debug | Info | Warning | Error
```

## Structs (Dart-visible)

### OrderInfo
```text
id: String
kind: OrderKind
status: OrderStatus
amount_sats: u64?
fiat_amount: f64?
fiat_amount_min: f64?
fiat_amount_max: f64?
fiat_code: String
payment_method: String
premium: f64
creator_pubkey: String
created_at: i64 (unix timestamp)
expires_at: i64?
is_mine: bool
```

### TradeInfo
```text
id: String
order: OrderInfo
role: TradeRole
counterparty_pubkey: String
current_step: TradeStep
hold_invoice: String?
buyer_invoice: String?
trade_key_index: u32
cooperative_cancel_state: CooperativeCancelState?
timeout_at: i64?
started_at: i64
completed_at: i64?
outcome: TradeOutcome?
peer_rating: f64?
peer_reviews: u32?
peer_days: u32?
rated_at: i64?
bond: BondInfo?
```

`bond` is set when the node required an anti-abuse bond for this trade, and
`None` otherwise (and on rows written before the field existed).

`counterparty_pubkey` is the **peer's trade pubkey**, never the Mostro
node's (`order.creator_pubkey` on a book order is the node — the 38383
event author). It starts **empty** for both roles and is populated when a
daemon message names both trade pubkeys (the peer-reveal capture, #334 —
see `orders.md`). On backends with a trades store the trade row is the
**durable** peer record and the in-memory session only a cache of it; web
has no trades store yet (#233), so there the write is a stub, the session
is the only holder, and a restart recovers the peer only through a
replayed reveal. Once set it never changes for a trade, and it is what
the chat UI gates the room on.

### Anti-abuse bond types

See `contracts/bond.md` for how these are produced.

```text
BondRole       = Maker | Taker
BondState      = Requested | Locked | Released | Slashed
BondPolicy     = Unsupported | Disabled | Enabled
BondApplyTo    = Take | Make | Both
SlashCause     = Timeout | Dispute
BondClaimPhase = Pending | Submitted | Acknowledged | Completed | Expired
```

```text
BondInfo {
  role: BondRole
  amount_sats: u64            // as sent by the daemon, never computed
  invoice: String?            // None only after a fresh-device restore
  state: BondState
  requested_at: i64
  expires_at: i64?            // decoded from the bolt11; None disables local expiry
  locked_at: i64?
}

BondPolicyInfo {              // every field but policy is None unless Enabled
  policy: BondPolicy
  apply_to: BondApplyTo?
  amount_pct: f64?            // wire fraction, 0.01 = 1 %
  base_amount_sats: u64?
  slash_on_waiting_timeout: bool?
  slash_node_share_pct: f64?
  payout_claim_window_days: u32?
}

BondClaim {                   // stored under "<node_pubkey>:<order_id>"
  order_id: String
  node_pubkey: String         // the issuing node, the submission target
  trade_index: u32?           // the slashed attempt's key; None on old rows
  amount_sats: u64            // the share; the invoice must match exactly
  slashed_at: i64
  deadline_at: i64            // frozen on first receipt
  phase: BondClaimPhase
  submitted_invoice: String?
  fiat_code: String
  fiat_amount: f64?
  payment_method: String
  updated_at: i64
}

BondClaimUpdate { order_id: String, node_pubkey: String, phase: BondClaimPhase }

BondSlashedEvent {
  event_id: String
  order_id: String
  amount_sats: u64            // the slashed bond, not the order
  fiat_code: String
  fiat_amount: i64
  payment_method: String
  cause: SlashCause           // inferred from the trade row's status
}
```

### ChatMessage
```text
id: String
trade_id: String
sender_pubkey: String
content: String
message_type: MessageType
is_mine: bool
is_read: bool
has_attachment: bool
attachment: AttachmentInfo?
created_at: i64
```

### AttachmentInfo
```text
file_name: String        # sanitized
mime_type: String        # declared by the sender
file_size: u64           # before encryption
file_type: FileType
download_status: DownloadStatus
blossom_url: String      # https://…/<sha256>
sha256: String           # of the encrypted blob
encrypted_size: u64
width: u32?              # images
height: u32?
counterpart_pubkey: String?  # our own sends only: who it was encrypted to
                             # (peer or solver); never from the wire (#596)
```

### RelaySource
```text
Default | MostroDiscovered | UserAdded
```

### RelayInfo
```text
url: String
is_active: bool
is_default: bool
source: RelaySource
is_blacklisted: bool
status: RelayStatus
last_connected_at: i64?
last_error: String?
```

### TradeHistoryEntry
```text
id: String
order_kind: OrderKind
fiat_amount: f64?
fiat_amount_min: f64?
fiat_amount_max: f64?
fiat_code: String
amount_sats: u64?
payment_method: String
counterparty_pubkey: String
outcome: TradeOutcome
completed_at: i64
```

### IdentityInfo
```text
public_key: String
display_name: String?
privacy_mode: bool
trade_key_index: u32
created_at: i64
```

### NymIdentity
```text
pseudonym: String         # Deterministic pseudonym (adjective-noun format)
icon_index: u8            # Icon selector (0–36)
color_hue: u16            # HSV hue (0–359) for avatar background
```

> All fields derived deterministically from the public key. The same key
> always produces the same name, icon, and color across sessions and devices.
>
> **Rendering contract (Flutter)**: The icon MUST always be rendered in white
> (`Colors.white`) over the HSV-colored background circle. The v1 implementation
> had a bug where the icon color matched the background, making it invisible.
> v2 MUST always use white icon color regardless of `color_hue` (FR-011c).

### LogEntry
```text
id: u32
level: LogLevel
tag: String
message: String
timestamp: i64
```

### AppState
```text
connection: ConnectionState
has_identity: bool
has_active_trade: bool
has_nwc_wallet: bool
unread_messages: u32
pending_queue_count: u32
theme: ThemeMode
privacy_mode: bool
logging_enabled: bool
```
