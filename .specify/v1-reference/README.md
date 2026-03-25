# V1 Reference Documentation

> 🔴 **CRITICAL: Read the Protocol First!**
> 
> Before diving into these docs, understand the **Mostro Protocol**:
> - **Protocol Repository**: https://github.com/MostroP2P/protocol
> - **Local Reference**: [../PROTOCOL.md](../PROTOCOL.md)
> 
> The protocol defines ALL communication between clients and mostrod. It is the source of truth.

---

> ⚠️ **IMPORTANT: These documents are from Mostro Mobile v1 (Dart/Flutter implementation)**
>
> Use these as **REFERENCE ONLY** for understanding the business logic, protocols, and flows.
> The v2 implementation uses **Rust core + flutter_rust_bridge**, so code examples in these
> docs are in Dart and must be **adapted to Rust** for the core logic layer.

## What to extract from these docs

| From V1 Docs | Use in V2 |
|--------------|-----------|
| Business logic & flows | Implement in Rust (`rust/src/api/`) |
| Protocol details (Nostr, NIP-59) | Implement in Rust using `nostr-sdk` |
| State machines (order status) | Implement in Rust, expose to Flutter |
| Crypto (keys, encryption) | Implement in Rust, **NOT in Dart** |
| UI/UX patterns | Keep in Flutter |
| Platform specifics (FCM, notifications) | Keep in Flutter |

## Document Index

### Screens & Navigation

| Document | Description | V2 Relevance |
|----------|-------------|--------------|
| [HOME_SCREEN.md](./HOME_SCREEN.md) | Home screen, order book, filters, FAB | Keep in Flutter (UI) |
| [NAVIGATION_ROUTES.md](./NAVIGATION_ROUTES.md) | GoRouter routes, deep links, redirects | Adapt navigation for Rust core |
| [ORDER_BOOK.md](./ORDER_BOOK.md) | Public order book vs My Trades, filters | Keep in Flutter |
| [ORDER_CREATION.md](./ORDER_CREATION.md) | AddOrderScreen, form and order creation flow | Keep in Flutter (UI + client flow) |
| [TAKE_ORDER.md](./TAKE_ORDER.md) | TakeOrderScreen, rutas `/take_sell` y `/take_buy`, acciones `take-sell`/`take-buy` | Keep in Flutter (UI + flujo cliente) |
| [TRADE_EXECUTION.md](./TRADE_EXECUTION.md) | PayLightningInvoice, AddLightningInvoice, TradeDetail, protocol actions `pay-invoice`/`fiat-sent`/`release`, execution FSM | UI in Flutter, state machine in Rust |
| [MY_TRADES.md](./MY_TRADES.md) | `/order_book` (TradesScreen), status filter, data providers, list items, pull-to-refresh, navigation | Keep in Flutter (UI + client flow) |
| [DRAWER_MENU.md](./DRAWER_MENU.md) | Side drawer, bottom nav bar | Keep in Flutter |

### Core Architecture

| Document | Description | V2 Relevance |
|----------|-------------|--------------|
| [ARCHITECTURE.md](./ARCHITECTURE.md) | Overall app architecture, layers | Adapt layers for Rust core |
| [SESSION_AND_KEY_MANAGEMENT.md](./SESSION_AND_KEY_MANAGEMENT.md) | BIP-32/39, trade keys, mnemonic, restore | **CRITICAL** - Move to Rust |
| [NOSTR.md](./NOSTR.md) | Nostr protocol, NIP-59 Gift Wrap, events | **CRITICAL** - Use nostr-sdk in Rust |

### Features

| Document | Description | V2 Relevance |
|----------|-------------|--------------|
| [ORDER_STATUS_HANDLING.md](./ORDER_STATUS_HANDLING.md) | Order state machine, transitions | Move state machine to Rust |
| [P2P_CHAT_SYSTEM.md](./P2P_CHAT_SYSTEM.md) | Encrypted chat, sharedKey, `/chat_list` & `/chat_room` flows | **CRITICAL** - Move to Rust |
| [DISPUTE_SYSTEM.md](./DISPUTE_SYSTEM.md) | Dispute list, admin chat, creation/resolution pipeline | **CRITICAL** - Move dispute logic to Rust |
| [RATING_SYSTEM.md](./RATING_SYSTEM.md) | Post-trade rating UX, `RatingUser` payload, reputation display | Crypto in Rust; UI in Flutter |
| [NWC_ARCHITECTURE.md](./NWC_ARCHITECTURE.md) | Nostr Wallet Connect integration | Move to Rust |
| [ENCRYPTED_IMAGE_MESSAGING_IMPLEMENTATION.md](./ENCRYPTED_IMAGE_MESSAGING_IMPLEMENTATION.md) | ChaCha20-Poly1305, Blossom | Crypto in Rust, upload in Flutter |
| [AUTHENTICATION.md](./AUTHENTICATION.md) | Auth flow, biometric unlock | Adapt for Rust key management |
| [ACCOUNT_SCREEN.md](./ACCOUNT_SCREEN.md) | Account screen, mnemonic backup | Reference from navigation |
| [SETTINGS_SCREEN.md](./SETTINGS_SCREEN.md) | Settings hub (language, fiat, relays, wallet, lightning address) | Keep in Flutter |
| [NOTIFICATION_SETTINGS.md](./NOTIFICATION_SETTINGS.md) | Push notification toggles, sound/vibration prefs | Keep in Flutter |
| [NOTIFICATIONS_SYSTEM.md](./NOTIFICATIONS_SYSTEM.md) | Complete notification architecture (in-app + push + FCM) | Core logic in Rust, UI in Flutter |
| [ORDER_STATES.md](./ORDER_STATES.md) | Order status enum and values | Move to Rust |

### Platform & Infrastructure

| Document | Description | V2 Relevance |
|----------|-------------|--------------|
| [FCM_IMPLEMENTATION.md](./FCM_IMPLEMENTATION.md) | Push notifications, background service | Keep in Flutter (platform-specific) |
| [RELAY_SYNC_IMPLEMENTATION.md](./RELAY_SYNC_IMPLEMENTATION.md) | Relay management, kind 10002 | Move relay logic to Rust |
| [LOGGING_SYSTEM.md](./LOGGING_SYSTEM.md) | Logging, export, privacy | Adapt for Rust + Flutter logging |

## Key Differences: V1 vs V2

### V1 (Current)
```
┌─────────────────────────────────────┐
│           Flutter/Dart              │
│  ┌─────────────────────────────┐    │
│  │   UI + Business Logic +     │    │
│  │   Crypto + Nostr (dart_nostr)│   │
│  └─────────────────────────────┘    │
└─────────────────────────────────────┘
```

### V2 (Target)
```
┌─────────────────────────────────────┐
│           Flutter/Dart              │
│        (UI + Platform only)         │
├─────────────────────────────────────┤
│       flutter_rust_bridge           │
├─────────────────────────────────────┤
│              Rust Core              │
│  ┌─────────┐ ┌─────────┐ ┌───────┐  │
│  │ Orders  │ │  Chat   │ │ Keys  │  │
│  │ Nostr   │ │  NWC    │ │Crypto │  │
│  └─────────┘ └─────────┘ └───────┘  │
│            nostr-sdk                │
└─────────────────────────────────────┘
```

## How to Use These Docs

1. **Read the doc** to understand the feature/flow
2. **Extract the business logic** (ignore Dart implementation details)
3. **Design the Rust API** that exposes needed functionality to Flutter
4. **Implement in Rust** using appropriate crates (nostr-sdk, etc.)
5. **Expose via flutter_rust_bridge** with appropriate types

## Migration Priority

Based on complexity and dependencies:

1. **Phase 1**: Identity & Keys (SESSION_AND_KEY_MANAGEMENT.md)
2. **Phase 2**: Nostr Core (NOSTR.md, RELAY_SYNC_IMPLEMENTATION.md)
3. **Phase 3**: Orders (ORDER_STATUS_HANDLING.md)
4. **Phase 4**: Chat (P2P_CHAT_SYSTEM.md, ENCRYPTED_IMAGE_MESSAGING_IMPLEMENTATION.md)
5. **Phase 5**: NWC (NWC_ARCHITECTURE.md)
6. **Phase 6**: Notifications (FCM_IMPLEMENTATION.md) - stays in Flutter

---

**Source**: https://github.com/MostroP2P/mobile/tree/main/docs/architecture
**Copied**: March 2026
