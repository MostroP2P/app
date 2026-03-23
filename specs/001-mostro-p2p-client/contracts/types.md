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
| CooperativelyCanceled | CanceledByAdmin | SettledByAdmin | Dispute
```

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

## Structs (Dart-visible)

### OrderInfo
```text
id: String
kind: OrderKind
status: OrderStatus
amount_sats: u64?
fiat_amount: f64
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
file_name: String
mime_type: String
file_size: u64
file_type: FileType
download_status: DownloadStatus
local_path: String?
```

### RelayInfo
```text
url: String
is_active: bool
is_default: bool
status: RelayStatus
last_connected_at: i64?
last_error: String?
```

### TradeHistoryEntry
```text
id: String
order_kind: OrderKind
fiat_amount: f64
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

### AppState
```text
connection: ConnectionState
has_identity: bool
has_active_trade: bool
has_nwc_wallet: bool
unread_messages: u32
pending_queue_count: u32
```
