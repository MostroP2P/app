# Mostro Mobile v1 — Current Features Reference

This document captures features from the existing v1 implementation that must be preserved in v2.

## NWC (Nostr Wallet Connect)

### Connection
- Parse NWC URIs: `nostr+walletconnect://<pubkey>?relay=<url>&secret=<hex>`
- Store credentials in Flutter Secure Storage
- Support multiple relay URLs per connection

### Operations
- Pay invoices programmatically during trade
- Get wallet info (optional balance display)
- Connection status feedback

### Supported Wallets
- Alby
- Coinos
- Any NWC-compatible wallet

## Encrypted File Messaging

### Supported Types
- Images: JPG, PNG, GIF, WEBP (auto-preview)
- Documents: PDF, DOC, TXT, RTF
- Videos: MP4, MOV, AVI, WEBM
- Size limit: 25MB per file

### Implementation
- ChaCha20-Poly1305 AEAD encryption
- Blossom servers for decentralized storage
- Blob structure: `[nonce:12][encrypted_data][auth_tag:16]`
- Download-on-demand for non-images

### Blossom Servers

blossom.primal.net (http://blossom.primal.net/)
blossom.band
nostr.media
blossom.sector01.com (http://blossom.sector01.com/)
24242.io (http://24242.io/)
nosto.re (http://nosto.re/)


## Session Recovery

### Restore Flow
1. User enters 12-word BIP-39 mnemonic
2. App sends `Action.restore` to Mostro
3. Mostro returns order IDs + disputes
4. App requests order details
5. App syncs trade key index
6. Sessions reconstructed locally

### Limitations
- Only works in reputation mode
- Privacy mode cannot restore (by design)

## Background Notifications

### Android
- Smart foreground service (only during active trades)
- FCM for app-killed scenarios
- Hybrid approach: background when idle, foreground when trading

### Notification Types
- Trade status changes
- P2P chat messages (generic "New message")
- Admin/dispute messages
- Timeout warnings

### Push Server
- Monitors relays for tradeKey.public in p-tag
- Sends silent FCM to wake app
- No message content transmitted

## Dispute System

### Actions
- `dispute`: Initiate dispute
- `adminTakeDispute`: Admin claims dispute
- `adminSettle`: Admin settles to one party
- `adminCancel`: Admin cancels trade
- `sendDm`: Admin/user messages

### Dispute Chat
- Separate from P2P chat
- Uses tradeKey (not sharedKey)
- Full NIP-59 encryption

## Reputation System

### Actions
- `rate`: Submit rating for counterparty
- `rateReceived`: Receive rating notification

### Rating Flow
1. Trade completes successfully
2. Prompt appears to rate counterparty
3. Rating sent to Mostro
4. Stored on Mostro side

### Privacy Mode
- No reputation tracking
- Anonymous trades
- Cannot restore session history

## Relay Management

### Auto-Sync
- Subscribe to Mostro's kind 10002 events
- Update local relay list from Mostro instance
- Additive only (no disconnect during sync)

### Manual Management
- Add custom relays
- Remove/blacklist relays
- View connection status

## Deep Links

### URI Scheme
- `mostro://order/<order_id>`
- QR code scanning
- Share order links

## Key Derivation

### BIP-32 Path
`m/44'/1237'/38383'/0/N`
- N=0: Master identity key
- N≥1: Trade keys (one per order)

### Storage
- Mnemonic: Flutter Secure Storage
- Master key: Flutter Secure Storage
- Trade index: SharedPreferences

## Order States

### Status Flow

pending → waitingBuyerInvoice → waitingPayment → active → fiatSent → success
↓
dispute → (admin resolution)


### Timeout Handling
- Countdown timers per state
- Auto-revert to pending on taker timeout
- Session cleanup on maker timeout

## Chat Architecture

### P2P Chat
- Uses sharedKey (ECDH derived)
- Simplified NIP-59 wrapping
- Plain text content

### Admin Chat
- Uses tradeKey
- Full NIP-59 Gift Wrap
- JSON format: `{"dm": {"action": "send-dm", "payload": {...}}}`

## Mostro Instance Configuration

### Kind 38383 Tags
- `k`: order kind (buy/sell)
- `s`: status
- `f`: fiat code

- `pm`: payment method
- `expiration`: order expiration timestamp

### Mostro Settings (from events)
- `expirationHours`: pending order lifetime (default 24h)
- `expirationSeconds`: waiting state timeout (default 900s)
- `mostroPublicKey`: daemon identity

## Cooperative Cancel

### Flow
1. Either party initiates cancel request
2. Counterparty receives notification
3. Counterparty accepts or ignores
4. If accepted, trade canceled, funds returned

### Actions
- `cooperativeCancelInitiatedByYou`
- `cooperativeCancelInitiatedByPeer`
- `cooperativeCancelAccepted`

## Invoice Handling

### Hold Invoices
- Mostro creates hold invoice
- Buyer pays, funds locked
- Seller confirms fiat, funds released

### Buyer Invoice
- For sell orders, buyer provides invoice
- Validated by Mostro
- Payment sent on completion

### Actions
- `addInvoice`: Buyer submits invoice
- `buyerInvoiceAccepted`: Mostro validates
- `payInvoice`: Prompt to pay hold invoice
- `holdInvoicePaymentAccepted`: Payment confirmed
- `holdInvoicePaymentSettled`: Funds released
