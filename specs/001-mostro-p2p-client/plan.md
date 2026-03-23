# Implementation Plan: Mostro Mobile v2 — P2P Exchange Client

**Branch**: `001-mostro-p2p-client` | **Date**: 2026-03-22 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-mostro-p2p-client/spec.md`
**V1 Reference**: `.specify/CURRENT_FEATURES.md`

## Summary

Build a multi-platform (iOS, Android, Web, macOS, Windows, Linux) client
for the Mostro P2P Bitcoin/Lightning exchange. All Nostr protocol logic,
cryptography, and data persistence live in Rust (via nostr-sdk and
mostro-core). Flutter provides the UI shell with responsive layouts. NIP-59
Gift Wrap ensures all Mostro communication is private. The app is
offline-first with local SQLite storage (IndexedDB on web) and message
queuing.

Key v1 features preserved: NWC wallet integration for automatic invoice
payment, encrypted file messaging via Blossom servers, session recovery
from mnemonic, reputation system with privacy mode, deep links
(`mostro://order/<id>`), cooperative cancel flow, BIP-32 key derivation
with trade-specific keys, relay auto-sync from Mostro kind 10002 events,
background push notifications via FCM, and separate P2P/admin chat
encryption channels.

## Technical Context

**Language/Version**: Rust (stable, 1.75+) for core; Dart 3.x / Flutter 3.x for UI
**Primary Dependencies**: nostr-sdk 0.44+, mostro-core, flutter_rust_bridge 2.x, Riverpod, go_router
**Storage**: SQLite via sqlx (native), IndexedDB (web)
**Testing**: `cargo test` + `cargo clippy` (Rust), `flutter test` + `flutter analyze` (Dart)
**Target Platform**: iOS, Android, Web (PWA), macOS, Windows, Linux
**Project Type**: Multi-platform mobile/desktop/web app
**Performance Goals**: <2s app launch, <1s order list load, <500ms message delivery
**Constraints**: Offline-capable, zero crypto in Dart, NIP-59 for all Mostro comms, one active trade at a time
**Scale/Scope**: 9 screens, 8 Rust API modules, ~42 functional requirements

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Gate | Status |
|---|-----------|------|--------|
| I | Rust Core, Flutter Shell | All Nostr, crypto, protocol, NWC, file encryption, and network logic in Rust. Flutter renders UI only. flutter_rust_bridge as sole bridge. | PASS |
| II | Privacy by Design | NIP-59 Gift Wrap for all Mostro comms. ChaCha20-Poly1305 for file attachments. No analytics/telemetry. Keys encrypted at rest. Privacy mode available. Ephemeral data cleared post-trade. No phone-home. Push server transmits no message content. | PASS |
| III | Protocol Compliance | Uses mostro-core types directly. Supports all v1 protocol actions (restore, cooperativeCancel, rate, addInvoice, etc.). Compatible with any Mostro daemon. BIP-32 key derivation at `m/44'/1237'/38383'/0/N`. | PASS |
| IV | Offline-First | SQLite (native) / IndexedDB (web) as source of truth. Relay sync when connected. Message queue when offline. File uploads retry. No data loss. | PASS |
| V | Multi-Platform Day One | All 6 targets from start. Responsive layouts (mobile/tablet/desktop). Platform features degrade gracefully. NWC works on all platforms. Deep links on mobile. | PASS |
| VI | Simplicity Over Features | One screen, one purpose. Trade stepper always visible with countdown timers. Sensible defaults. Fast startup. One active trade (v2.0 scope). NWC auto-pay reduces manual steps. | PASS |

**Quality gates**:
- `cargo clippy -- -D warnings` zero warnings
- `cargo test` all green
- `flutter analyze` zero issues
- `flutter test` all green
- All public Rust API documented
- UI tested at mobile, tablet, desktop breakpoints

**All gates pass. Proceeding.**

## Project Structure

### Documentation (this feature)

```text
specs/001-mostro-p2p-client/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── identity.md
│   ├── orders.md
│   ├── messages.md
│   ├── disputes.md
│   ├── nostr.md
│   ├── nwc.md
│   ├── reputation.md
│   └── types.md
└── tasks.md             # Phase 2 output (/speckit.tasks)
```

### Source Code (repository root)

```text
lib/                          # Flutter UI
├── main.dart
└── src/
    ├── rust/                 # Generated flutter_rust_bridge bindings
    ├── screens/              # UI screens (9 screens)
    │   ├── splash_screen.dart
    │   ├── onboarding_screen.dart
    │   ├── home_screen.dart
    │   ├── order_detail_screen.dart
    │   ├── create_order_screen.dart
    │   ├── active_trade_screen.dart
    │   ├── dispute_screen.dart
    │   ├── settings_screen.dart
    │   └── history_screen.dart
    ├── widgets/              # Reusable widgets
    │   ├── trade_stepper.dart
    │   ├── order_card.dart
    │   ├── chat_panel.dart
    │   ├── file_attachment.dart
    │   ├── qr_scanner.dart
    │   ├── rating_dialog.dart
    │   ├── countdown_timer.dart
    │   └── responsive_scaffold.dart
    ├── providers/            # Riverpod state management
    │   ├── identity_provider.dart
    │   ├── orders_provider.dart
    │   ├── active_trade_provider.dart
    │   ├── messages_provider.dart
    │   ├── connection_provider.dart
    │   ├── nwc_provider.dart
    │   ├── reputation_provider.dart
    │   └── layout_provider.dart
    ├── layouts/              # Responsive layout system
    │   ├── mobile_layout.dart
    │   ├── tablet_layout.dart
    │   └── desktop_layout.dart
    ├── routing/              # Deep links + navigation
    │   └── app_router.dart
    └── l10n/                 # Translations

rust/                         # Rust core
├── Cargo.toml
└── src/
    ├── lib.rs
    ├── api/                  # Flutter-exposed API (contracts)
    │   ├── mod.rs
    │   ├── identity.rs       # Key management + BIP-32 derivation
    │   ├── orders.rs         # Order lifecycle
    │   ├── messages.rs       # P2P chat + file attachments
    │   ├── disputes.rs       # Dispute handling
    │   ├── nostr.rs          # Relay management + auto-sync
    │   ├── nwc.rs            # Nostr Wallet Connect
    │   ├── reputation.rs     # Ratings + privacy mode
    │   └── types.rs          # Shared types
    ├── core/                 # Internal business logic
    │   ├── mod.rs
    │   ├── trade_state.rs    # Order state machine + timers
    │   ├── gift_wrap.rs      # NIP-59 wrapping
    │   ├── key_derivation.rs # BIP-32 m/44'/1237'/38383'/0/N
    │   ├── file_crypto.rs    # ChaCha20-Poly1305 file encryption
    │   ├── message_queue.rs  # Offline message queue
    │   ├── blossom.rs        # Blossom server file upload/download
    │   ├── nwc_client.rs     # NWC protocol implementation
    │   ├── deep_links.rs     # URI scheme parsing
    │   └── protocol.rs       # Mostro protocol handling
    ├── db/                   # Storage layer
    │   ├── mod.rs
    │   ├── storage.rs        # Storage trait
    │   ├── sqlite.rs         # Native SQLite impl
    │   ├── indexeddb.rs      # Web IndexedDB impl
    │   └── migrations/       # Schema migrations
    └── platform/             # Platform-specific code
        ├── mod.rs
        ├── native.rs         # tokio runtime, native secure storage
        ├── web.rs            # wasm-bindgen-futures, web storage
        └── notifications.rs  # FCM + foreground service bridge

rust_builder/                 # Cargokit build integration
flutter_rust_bridge.yaml      # Bridge configuration

test/                         # Flutter tests
├── widget/
├── integration/
└── providers/

rust/tests/                   # Rust tests
├── unit/
└── integration/
```

**Structure Decision**: Hybrid Flutter + Rust project. Flutter at repo root
(`lib/`), Rust core in `rust/` subdirectory. Standard flutter_rust_bridge
v2 layout. Expanded from initial plan with NWC, Blossom, reputation, deep
links, and notification modules.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| Dual storage backend (SQLite + IndexedDB) | Web platform cannot use SQLite natively | Single backend impossible across all 6 targets |
| Feature-gated async runtime (tokio + wasm-bindgen-futures) | tokio unavailable on WASM | Single runtime doesn't exist for native + web |
| Dual chat encryption (sharedKey P2P + tradeKey admin) | Mostro protocol requires different keys for peer vs admin chat | Single key approach would break protocol compliance |
| External push server dependency | Background notifications when app killed (FCM) | No alternative for reliable mobile push; server transmits no content (privacy OK) |
