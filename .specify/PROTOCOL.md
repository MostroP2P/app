# Mostro Protocol Reference

> ⚠️ **CRITICAL**: This is the foundational document for all Mostro client development.
> The protocol specification defines ALL communication between clients and the Mostro daemon.

## Protocol Repository

**Source**: https://github.com/MostroP2P/protocol

This repository contains the complete specification for:
- Message formats and actions
- Order lifecycle and state machine
- Message transport encryption (NIP-44 direct + NIP-59 gift wrap)
- Event kinds and tags
- Error handling

## Why This Matters for v2

The protocol is **the contract** between the client and mostrod. Every feature in the app
must comply with this specification. When implementing features:

1. **Read the protocol first** before coding any Mostro interaction
2. **Actions and messages** must match exactly what the protocol defines
3. **State transitions** must follow the protocol's order state machine
4. **Error codes** and handling must match protocol expectations

## Key Protocol Documents

| Document | Description | Link |
|----------|-------------|------|
| **README.md** | Protocol overview | [View](https://github.com/MostroP2P/protocol/blob/main/README.md) |
| **ACTIONS.md** | All message actions (new-order, take-sell, release, etc.) | [View](https://github.com/MostroP2P/protocol/blob/main/ACTIONS.md) |
| **MESSAGES.md** | Message format and payloads | [View](https://github.com/MostroP2P/protocol/blob/main/MESSAGES.md) |
| **ORDER.md** | Order structure and fields | [View](https://github.com/MostroP2P/protocol/blob/main/ORDER.md) |

## Protocol Actions Reference

### Order Creation
- `new-order` - Create a new buy/sell order
- `take-sell` - Take a sell order (buyer action)
- `take-buy` - Take a buy order (seller action)

### Trade Flow
- `pay-invoice` - Prompt to pay hold invoice
- `add-invoice` - Buyer submits Lightning invoice
- `fiat-sent` - Buyer marks fiat as sent
- `release` - Seller releases funds

### Cancellation
- `cancel` - Cancel order
- `cooperative-cancel-initiated-by-you` - Request cooperative cancel
- `cooperative-cancel-initiated-by-peer` - Peer requested cancel
- `cooperative-cancel-accepted` - Cancel accepted

### Disputes
- `dispute` - Initiate dispute
- `admin-take-dispute` - Admin claims dispute
- `admin-settle` - Admin settles to one party
- `admin-cancel` - Admin cancels trade

### Rating
- `rate` - Submit counterparty rating
- `rate-received` - Rating received notification

### Session Management
- `restore` - Restore sessions from mnemonic
- `orders` - Request order history
- `last-trade-index` - Sync trade key index

## Order Status Flow

```text
┌─────────┐
│ pending │ ──────────────────────────────────────────┐
└────┬────┘                                           │
     │ take-sell/take-buy                             │
     ▼                                                │
┌─────────────────────┐                               │
│ waiting-buyer-invoice│ (for sell orders)            │
└──────────┬──────────┘                               │
           │ add-invoice                              │
           ▼                                          │
┌─────────────────┐                                   │
│ waiting-payment │                                   │
└────────┬────────┘                                   │
         │ hold-invoice-payment-accepted              │
         ▼                                            │
┌────────┐                                            │
│ active │                                            │
└───┬────┘                                            │
    │ fiat-sent                                       │
    ▼                                                 │
┌───────────┐                                         │
│ fiat-sent │                                         │
└─────┬─────┘                                         │
      │ release                                       │
      ▼                                               │
┌─────────┐                                           │
│ success │ ◄─────────────────────────────────────────┘
└─────────┘           (or canceled/expired/dispute)
```

## Message transport

> **Changed in transport v2**: messages to the Mostro daemon previously used
> NIP-59 gift wrap (kind 1059); they now use NIP-44 direct (signed kind 14).
> Peer/dispute chat still uses NIP-59 gift wrap (kind 1059).

Daemon messages (transport v2 — NIP-44 direct):

```text
┌──────────────────────────────────────────────────┐
│ Kind 14 event (authored & signed by trade key)   │
│ - NIP-44 encrypted content                        │
│ - JSON payload with action + order                │
│ - Optional identity proof; signature is verified  │
└──────────────────────────────────────────────────┘
```

Peer/dispute chat (NIP-59 gift wrap):

```text
┌──────────────────────────────────────────────────┐
│ Gift Wrap (kind 1059)                            │
│ ┌──────────────────────────────────────────────┐ │
│ │ Seal (kind 13)                               │ │
│ │ ┌──────────────────────────────────────────┐ │ │
│ │ │ Rumor — chat message payload             │ │ │
│ │ └──────────────────────────────────────────┘ │ │
│ └──────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────┘
```

## Implementation Notes for v2

### Rust Core
All protocol handling should be in the Rust core:
- Message serialization/deserialization
- NIP-44 (daemon) / NIP-59 gift wrap (peer chat) wrapping/unwrapping (via nostr-sdk)
- Action validation
- State machine enforcement

### Flutter UI
Flutter should only:
- Display order state
- Collect user input
- Trigger actions via Rust API

## Versioning

The protocol may evolve. Always check:
- Protocol version in mostrod announcements
- Backward compatibility notes
- Deprecation warnings

---

**Always refer to the protocol repository for the authoritative specification.**
