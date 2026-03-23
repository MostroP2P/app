# Data Model: Mostro Mobile v2

**Branch**: `001-mostro-p2p-client` | **Date**: 2026-03-22

## Entities

### Identity

Represents the user's cryptographic identity. One per app installation.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| public_key | String | Nostr public key (hex) |
| encrypted_private_key | Bytes | Private key encrypted with user's PIN/passphrase |
| mnemonic_hash | String | Hash of mnemonic for verification (never store plaintext) |
| display_name | String? | Optional user-chosen display name |
| created_at | Timestamp | When identity was created |
| last_used_at | Timestamp | Last activity timestamp |
| trade_key_index | u32 | Current BIP-32 trade key index (N in m/44'/1237'/38383'/0/N) |
| privacy_mode | bool | Whether user is in privacy mode (no reputation). **Authoritative source.** The Settings `privacy_mode` key is a convenience alias: writes MUST go through `set_privacy_mode()` on the Identity API, which updates Identity first and then propagates to Settings. On read, Identity.privacy_mode wins any conflict. Settings MUST NOT be written directly for this key. |
| derivation_path | String | BIP-32 base path: `m/44'/1237'/38383'/0` |

**Validation rules**:
- `public_key` MUST be a valid 64-char hex string (32 bytes).
- `encrypted_private_key` MUST never be stored as plaintext.
- Mnemonic MUST be BIP-39 compliant (12 or 24 words).
- `trade_key_index` starts at 0 (master) and auto-increments per trade.

---

### Order

A buy or sell offer on the Mostro network.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Mostro order ID |
| kind | Enum | `Buy` or `Sell` |
| status | Enum | See state machine below |
| amount_sats | u64? | Amount in satoshis (null if fiat-defined) |
| fiat_amount | f64? | Fixed amount in fiat (null if range order) |
| fiat_amount_min | f64? | Min fiat amount for range orders (null if fixed) |
| fiat_amount_max | f64? | Max fiat amount for range orders (null if fixed) |
| fiat_code | String | ISO 4217 currency code (e.g., "USD", "EUR") |
| payment_method | String | Fiat payment method description |
| premium | f64 | Price premium/discount percentage |
| creator_pubkey | String | Public key of order creator |
| created_at | Timestamp | When order was created |
| expires_at | Timestamp? | Expiration time (null if no expiry) |
| nostr_event_id | String? | Kind 38383 event ID on relay |
| is_mine | bool | Whether current user created this order |
| cached_at | Timestamp | When this order was last fetched/updated locally |

**Validation rules**:
- `fiat_code` MUST be a valid ISO 4217 code.
- Either `fiat_amount` OR both `fiat_amount_min` and `fiat_amount_max` MUST be provided, but NOT both. If `fiat_amount` is present, `fiat_amount_min` and `fiat_amount_max` MUST be absent; if `fiat_amount_min`/`fiat_amount_max` are present, `fiat_amount` MUST be absent.
- If range: `fiat_amount_min` MUST be > 0 and < `fiat_amount_max`.
- `premium` is a signed float (negative = discount).

**State machine** (15 mostro-core states):
```text
Pending
├─→ WaitingBuyerInvoice (sell orders: buyer must provide invoice)
│     └─→ WaitingPayment (buy orders skip WaitingBuyerInvoice, go here directly)
│           ├─→ Active
│           │     ├─→ FiatSent
│           │     │     └─→ SettledHoldInvoice → Success
│           │     │           (if LN payment fails: Action::PaymentFailed notification,
│           │     │            order stays SettledHoldInvoice, buyer resubmits invoice)
│           │     └─→ Dispute
│           │           ├─→ InProgress (admin took dispute)
│           │           ├─→ CanceledByAdmin
│           │           ├─→ SettledByAdmin
│           │           ├─→ CompletedByAdmin
│           │           └─→ (direct admin resolution without InProgress)
│           └─→ Expired (protocol-enforced inactivity timeout)
├─→ Canceled (explicit user action: creator cancels own untaken order)
└─→ CooperativelyCanceled (client-side UI state only — protocol sends action notifications, does not change order status)
```

**15 mostro-core statuses**: Pending, WaitingBuyerInvoice, WaitingPayment, Active, FiatSent,
SettledHoldInvoice, Success, Canceled, CooperativelyCanceled, Dispute, InProgress,
SettledByAdmin, CanceledByAdmin, CompletedByAdmin, Expired.

---

### Trade

An active transaction linking buyer, seller, and order. Only one active
trade at a time (v2.0 scope constraint).

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Trade identifier |
| order_id | UUID | FK → Order |
| role | Enum | `Buyer` or `Seller` |
| counterparty_pubkey | String | Other party's public key |
| current_step | Enum | Current progress step (see below) |
| hold_invoice | String? | Lightning hold invoice (if issued) |
| buyer_invoice | String? | Buyer-provided invoice for sell orders |
| trade_key_index | u32 | BIP-32 key index for this trade |
| shared_key | String? | ECDH-derived key for P2P chat (hex) |
| cooperative_cancel_state | Enum? | `RequestedByMe`, `RequestedByPeer`, `Accepted`, null |
| timeout_at | Timestamp? | When current state times out |
| started_at | Timestamp | When trade began |
| completed_at | Timestamp? | When trade finished (null if active) |
| outcome | Enum? | `Success`, `Canceled`, `Expired`, `DisputeWon`, `DisputeLost` |

**Buyer progress steps**: `OrderTaken`, `PayInvoice`, `PaymentLocked`,
`FiatSent`, `AwaitingRelease`, `Complete`

**Seller progress steps**: `OrderPublished`, `TakerFound`, `InvoiceCreated`,
`PaymentLocked`, `AwaitingFiat`, `Complete`

**Special step**: `Disputed` (overlays any step, pauses normal flow)

**Validation rules**:
- `counterparty_pubkey` MUST differ from current user's public key.
- Only one trade with `completed_at = null` allowed at any time.

---

### Message

An encrypted communication between trade parties or with admin during
disputes. Persisted locally after decryption.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| trade_id | UUID | FK → Trade |
| sender_pubkey | String | Sender's public key |
| recipient_pubkey | String | Recipient's public key |
| content | String | Decrypted message text |
| message_type | Enum | `Peer`, `Admin`, `System` |
| is_mine | bool | Whether current user sent this |
| is_read | bool | Whether user has seen this message |
| created_at | Timestamp | When message was sent |
| received_at | Timestamp | When message was received locally |
| nostr_event_id | String? | Gift Wrap event ID (for dedup) |

**Validation rules**:
- `content` MUST not be empty.
- `nostr_event_id` used to deduplicate messages received from multiple relays.

---

### Relay

A Nostr relay the app connects to.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| url | String | WebSocket URL (wss://...) |
| is_active | bool | Whether app should connect to this relay |
| is_default | bool | Whether this is a preconfigured default |
| source | Enum | `Default`, `MostroDiscovered`, `UserAdded` |
| is_blacklisted | bool | If true, relay will not be auto-added even if daemon announces it |
| status | Enum | `Connected`, `Disconnected`, `Connecting`, `Error` |
| last_connected_at | Timestamp? | Last successful connection |
| last_error | String? | Most recent error message |
| added_at | Timestamp | When relay was added |

**Validation rules**:
- `url` MUST be a valid WebSocket URL (wss:// or ws://).
- At least one relay MUST be active at all times.

---

### Dispute

An exception flow on an active trade.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| trade_id | UUID | FK → Trade |
| initiated_by | Enum | `Me` or `Counterparty` |
| reason | String? | Optional reason text |
| status | Enum | `Open`, `InReview`, `Resolved` |
| resolution | Enum? | `FundsToMe`, `FundsToCounterparty`, `CooperativeCancel` |
| opened_at | Timestamp | When dispute was opened |
| resolved_at | Timestamp? | When dispute was resolved |

**Validation rules**:
- A dispute can only be opened on a trade with `current_step` between
  `PaymentLocked` and `AwaitingRelease`/`AwaitingFiat`.
- Only one open dispute per trade.

---

### Settings

User preferences stored locally.

| Field | Type | Description |
|-------|------|-------------|
| key | String | Setting identifier (PK) |
| value | String | JSON-encoded setting value |
| updated_at | Timestamp | Last modification |

**Known keys**: `theme` (dark/light/system), `locale` (language code),
`pin_enabled` (bool), `biometric_enabled` (bool),
`default_fiat_currency` (ISO code), `notification_enabled` (bool),
`privacy_mode` (bool — global toggle, applies to future trades),
`logging_enabled` (bool — diagnostic logging, runtime-only: not persisted to storage; startup code unconditionally sets this to `false` on process start regardless of any prior value).

---

### MessageQueue (offline outbox)

Outgoing messages queued when offline.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| event_json | String | Serialized Nostr event (Gift Wrapped) |
| target_relays | String | JSON array of relay URLs to publish to |
| created_at | Timestamp | When queued |
| retry_count | u32 | Number of send attempts |
| last_retry_at | Timestamp? | Last attempt timestamp |
| status | Enum | `Pending`, `Sent`, `Failed` |

**Validation rules**:
- `retry_count` MUST not exceed configurable max (default: 10).
- `Sent` items SHOULD be pruned after 24 hours.

### NwcWallet

A Nostr Wallet Connect wallet connection for automatic invoice payment.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| wallet_pubkey | String | Wallet service public key (hex) |
| encrypted_secret | Bytes | NWC secret encrypted at rest |
| relay_urls | String | JSON array of relay URLs for this wallet |
| status | Enum | `Connected`, `Disconnected`, `Connecting`, `Error` |
| wallet_name | String? | Human-readable wallet name (e.g., "Alby") |
| balance_sats | u64? | Optional cached balance |
| last_connected_at | Timestamp? | Last successful connection |
| created_at | Timestamp | When wallet was added |

**Validation rules**:
- `wallet_pubkey` MUST be a valid 64-char hex string.
- `relay_urls` MUST contain at least one valid wss:// URL.
- Only one active NWC wallet at a time.

---

### FileAttachment

An encrypted file sent or received in trade chat.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| message_id | UUID | FK → Message |
| file_type | Enum | `Image`, `Document`, `Video` |
| mime_type | String | MIME type (e.g., "image/jpeg") |
| file_name | String | Original file name |
| file_size | u64 | Size in bytes (max 25MB) |
| blossom_url | String | URL on Blossom server |
| encryption_nonce | Bytes | 12-byte nonce for ChaCha20-Poly1305 |
| encryption_key_encrypted | Bytes | Symmetric key encrypted at rest (wrapped by the device master key; plaintext key is ephemeral and held only in memory during encrypt/decrypt) |
| key_wrapping_id | String | Identifier of the wrapping key used to encrypt `encryption_key_encrypted` |
| download_status | Enum | `Pending`, `Downloading`, `Downloaded`, `Failed` |
| local_path | String? | Path to decrypted file on device (null if not downloaded) |
| created_at | Timestamp | When attachment was created |

**Validation rules**:
- `file_size` MUST not exceed 26,214,400 bytes (25MB).
- `file_type` determined from `mime_type`.
- Images auto-download; documents and videos are download-on-demand.

---

### Rating

A counterparty rating after a successful trade.

| Field | Type | Description |
|-------|------|-------------|
| id | UUID | Primary key |
| trade_id | UUID | FK → Trade |
| rated_pubkey | String | Public key of the rated party |
| score | u8 | Rating score |
| submitted | bool | Whether rating was sent to daemon |
| created_at | Timestamp | When rating was created |

**Validation rules**:
- Only available when `identity.privacy_mode` is false.
- One rating per trade per direction (I rate them, they rate me).

---

## Relationships

```
Identity (1) ──── (*) Trade
                      │
Order (1) ────────── (1) Trade
                      │
Trade (1) ────────── (*) Message
                      │
Trade (1) ────────── (0..1) Dispute
                      │
Dispute (1) ─────── (*) Message (where message_type = Admin)

Message (1) ─────── (0..1) FileAttachment

Trade (1) ────────── (0..1) Rating (my rating of counterparty)

NwcWallet (0..1) ── independent (one active wallet)
Relay (*) ── independent, no FK relationships
Settings (*) ── independent key-value store
MessageQueue (*) ── independent outbox
```
