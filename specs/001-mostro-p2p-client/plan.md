# Implementation Plan: Mostro Mobile v2 — P2P Exchange Client

**Branch**: `001-mostro-p2p-client` | **Date**: 2026-03-22 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-mostro-p2p-client/spec.md`

## Summary

Build a multi-platform (iOS, Android, Web, macOS, Windows, Linux) P2P Bitcoin/Lightning exchange client for the Mostro protocol. Rust core handles all cryptography, Nostr protocol, and business logic via `nostr-sdk` and `mostro-core`. Flutter renders UI with responsive layouts across screen sizes. Communication uses NIP-59 Gift Wrap encryption. Local-first architecture with SQLite (native) / IndexedDB (web) storage, offline message queuing, and session recovery from mnemonic.

## Technical Context

**Language/Version**: Rust stable (latest, currently 1.94+) (core logic); Dart 3.x / Flutter 3.x (UI)
**Primary Dependencies**: nostr-sdk 0.44+, mostro-core, flutter_rust_bridge 2.x, Riverpod (state management), go_router (navigation), sqlx (SQLite), indexed_db_futures (web), bip32/bip39 (key derivation), chacha20poly1305 (file encryption)
**Storage**: SQLite via sqlx (native platforms), IndexedDB (web)
**Testing**: `cargo test` + `cargo clippy -- -D warnings` (Rust); `flutter test` + `flutter analyze` (Dart)
**Target Platform**: iOS, Android, Web (WASM), macOS, Windows, Linux
**Project Type**: Multi-platform mobile/desktop/web app
**Performance Goals**: App launch + order list < 2s; message delivery < 1s; 60 fps UI; queued messages sent < 5s after reconnection
**Constraints**: Offline-capable, zero plaintext key storage, no analytics/telemetry, no network calls from Dart, all crypto in Rust only
**Scale/Scope**: ~15 screens, one active trade at a time, single user identity per installation, 15 protocol-defined order states

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Evidence |
|-----------|--------|----------|
| I. Rust Core, Flutter Shell | **PASS** | All Nostr logic, crypto, protocol, and network calls in Rust via nostr-sdk. Flutter handles only UI. flutter_rust_bridge is the sole bridge. Zero crypto in Dart. See [ARCHITECTURE.md](../../.specify/ARCHITECTURE.md) for boundary rules, forbidden patterns, and platform feature matrix. |
| II. Privacy by Design | **PASS** | NIP-59 Gift Wrap for all Mostro communication. No analytics/telemetry. Keys encrypted at rest via platform secure storage. Ephemeral trade data cleared post-completion. No phone-home to non-relay servers (push server sends zero content). |
| III. Protocol Compliance | **PASS** | Uses mostro-core crate for type-safe protocol messages. Kind 38383 for public orders, Kind 1059 for private communication. Works with any conforming Mostro daemon. |
| IV. Offline-First Architecture | **PASS** | SQLite/IndexedDB as source of truth. MessageQueue entity for offline outbox. Sync on reconnection. Trade state persisted locally across force-close. |
| V. Multi-Platform from Day One | **PASS** | Flutter targets all 6 platforms. Rust compiles to native + WASM. Responsive layouts at 3 breakpoints. Platform features degrade with fallbacks (QR → paste, push → in-app). |
| VI. Simplicity Over Features | **PASS** | One screen per purpose. Progressive disclosure. Trade progress indicator always visible. Sensible defaults (preconfigured relays, skip-able security setup). One active trade at a time. |

**Gate result**: All principles satisfied. No violations to track.

### Post-Phase 1 Re-check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Rust Core, Flutter Shell | **PASS** | All contracts define Rust-side APIs exposed via flutter_rust_bridge. No Dart crypto or network calls in any contract. |
| II. Privacy by Design | **PASS** | File attachments use ChaCha20-Poly1305 in Rust. Push notifications carry zero content. NWC credentials encrypted at rest. |
| III. Protocol Compliance | **PASS** | Order state machine matches Mostro protocol exactly (15 states per mostro-core: Pending, WaitingBuyerInvoice, WaitingPayment, Active, FiatSent, SettledHoldInvoice, Success, Canceled, CooperativelyCanceled, Dispute, SettledByAdmin, CanceledByAdmin, CompletedByAdmin, Expired, InProgress). Note: PaymentFailed is an Action, not a Status. |
| IV. Offline-First Architecture | **PASS** | MessageQueue contract handles offline outbox. Orders cached locally with `cached_at` timestamp. |
| V. Multi-Platform from Day One | **PASS** | Storage trait with SQLite/IndexedDB backends. Async runtime feature-gated for WASM vs native. |
| VI. Simplicity Over Features | **PASS** | Contracts expose focused APIs per domain. No multipurpose interfaces. |

## Project Structure

### Documentation (this feature)

```text
specs/001-mostro-p2p-client/
├── plan.md              # This file
├── research.md          # Phase 0: technology research and decisions
├── data-model.md        # Phase 1: entity definitions and relationships
├── quickstart.md        # Phase 1: setup and development guide
├── contracts/           # Phase 1: Rust-to-Flutter API contracts
│   ├── identity.md      # Identity creation, import, key derivation
│   ├── orders.md        # Order CRUD, trade lifecycle, deep links
│   ├── messages.md      # P2P messaging, file attachments
│   ├── nostr.md         # Relay management, connection state
│   ├── nwc.md           # Nostr Wallet Connect integration
│   ├── disputes.md      # Dispute lifecycle
│   ├── reputation.md    # Rating system, privacy mode
│   └── types.md         # Shared enums and structs
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
lib/                          # Flutter UI layer
├── app.dart                  # App entry, MaterialApp, go_router setup
├── providers/                # Riverpod providers (state management)
│   ├── identity_provider.dart
│   ├── orders_provider.dart
│   ├── trade_provider.dart
│   ├── messages_provider.dart
│   ├── relay_provider.dart
│   ├── wallet_provider.dart
│   └── settings_provider.dart
├── screens/                  # One screen per purpose
│   ├── onboarding/           # Welcome, create/import identity, PIN setup
│   ├── home/                 # Order list with filters
│   ├── order_detail/         # Single order view + take action
│   ├── create_order/         # New buy/sell order form
│   ├── trade/                # Active trade with progress indicator + chat
│   ├── dispute/              # Dispute view with evidence submission
│   ├── history/              # Past trades list + detail
│   ├── settings/             # Relay, identity, wallet, preferences
│   └── shared/               # Deep link landing
├── widgets/                  # Reusable UI components
│   ├── trade_progress.dart   # Visual step indicator
│   ├── order_card.dart       # Order list item
│   ├── chat_bubble.dart      # Message display
│   ├── qr_scanner.dart       # QR with platform fallback
│   └── responsive_layout.dart # Breakpoint-aware scaffold
├── theme/                    # Dark/light theme definitions
├── l10n/                     # Internationalization strings
└── router.dart               # go_router route definitions

rust/                         # Rust core logic
├── Cargo.toml
├── src/
│   ├── api/                  # flutter_rust_bridge exposed functions
│   │   ├── identity.rs       # Identity management API
│   │   ├── orders.rs         # Order + trade lifecycle API
│   │   ├── messages.rs       # Messaging API
│   │   ├── nostr.rs          # Relay management API
│   │   ├── nwc.rs            # NWC wallet API
│   │   ├── disputes.rs       # Dispute API
│   │   └── reputation.rs     # Rating API
│   ├── protocol/             # Mostro protocol handling
│   │   ├── actions.rs        # Protocol action builders
│   │   ├── gift_wrap.rs      # NIP-59 encryption/decryption
│   │   └── state_machine.rs  # Order state transitions
│   ├── storage/              # Persistence layer
│   │   ├── mod.rs            # Storage trait definition
│   │   ├── sqlite.rs         # SQLite implementation (native)
│   │   ├── indexeddb.rs      # IndexedDB implementation (web)
│   │   └── migrations/       # Schema migrations
│   ├── crypto/               # Cryptographic operations
│   │   ├── keys.rs           # BIP-32/39 key derivation
│   │   ├── secure_store.rs   # Platform secure storage bridge
│   │   └── file_encrypt.rs   # ChaCha20-Poly1305 for attachments
│   ├── network/              # Network layer
│   │   ├── relay_pool.rs     # Relay connection management
│   │   ├── message_queue.rs  # Offline outbox
│   │   └── blossom.rs        # Blossom file upload/download
│   └── lib.rs                # Crate root
└── tests/                    # Rust tests
    ├── protocol_tests.rs
    ├── storage_tests.rs
    └── crypto_tests.rs

rust_builder/                 # Cargokit build integration (flutter_rust_bridge)

test/                         # Flutter widget and integration tests

ios/                          # iOS platform project
android/                      # Android platform project
macos/                        # macOS platform project
windows/                      # Windows platform project
linux/                        # Linux platform project
web/                          # Web platform project
```

**Structure Decision**: Flutter + Rust hybrid. Flutter project at repo root (`lib/`) with Rust crate at `rust/`. This follows flutter_rust_bridge v2 conventions. The `rust_builder/` directory contains Cargokit integration for native builds. Platform directories (`ios/`, `android/`, etc.) are standard Flutter platform projects. All 6 platforms share the same `lib/` and `rust/` source code.

## Complexity Tracking

> No constitution violations detected. No complexity justifications needed.

## Generated Artifacts

| Artifact | Path | Status |
|----------|------|--------|
| Research | `specs/001-mostro-p2p-client/research.md` | Complete (12 decisions) |
| Data Model | `specs/001-mostro-p2p-client/data-model.md` | Complete (11 entities) |
| Contracts | `specs/001-mostro-p2p-client/contracts/` | Complete (8 contracts) |
| Quickstart | `specs/001-mostro-p2p-client/quickstart.md` | Complete |
| Tasks | `specs/001-mostro-p2p-client/tasks.md` | Exists (generated separately via /speckit.tasks) |
