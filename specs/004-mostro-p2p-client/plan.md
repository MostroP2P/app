# Implementation Plan: Mostro Mobile v2 — P2P Bitcoin Lightning Exchange

**Branch**: `004-mostro-p2p-client` | **Date**: 2026-03-29 | **Spec**: [spec.md](spec.md)
**Input**: Flutter/Dart with Riverpod, GoRouter, and Sembast for the Flutter shell. Rust core via flutter_rust_bridge using nostr-sdk for all Nostr protocol handling, NIP-59 gift wrap encryption, and cryptographic operations. No crypto in Dart. NWC support for auto-paying Lightning invoices. Platform targets: iOS, Android, web (PWA), and desktop.

## Summary

Build Mostro Mobile v2, a P2P Bitcoin Lightning exchange application that replicates the complete v1 user experience across 23 interaction flows (walkthrough → order book → create/take order → trade execution → chat → disputes → rating). The app uses a **Rust core / Flutter shell** architecture: all Nostr protocol handling, NIP-59 Gift Wrap encryption, BIP-32 key derivation, NWC wallet integration, and relay communication live exclusively in Rust via `nostr-sdk`. Flutter handles UI, routing (GoRouter), state management (Riverpod), and local persistence (Sembast on all platforms). All 23 V1 flow sections from `V1_FLOW_GUIDE.md` are the binding UX specification; `DESIGN_SYSTEM.md` governs visual appearance.

## Technical Context

**Language/Version**: Rust stable 1.94+ (core); Dart 3.x / Flutter 3.x (UI shell)
**Primary Dependencies**:
- Rust: `nostr-sdk 0.44+`, `mostro-core 0.8+`, `flutter_rust_bridge 2.x`, `sqlx` (native), `indexed_db_futures` (web), `bip32`, `bip39`, `chacha20poly1305`, `tokio` (native), `wasm-bindgen-futures` (web)
- Dart/Flutter: `flutter_rust_bridge 2.x`, `riverpod` (state), `go_router` (navigation), `sembast` (local DB all platforms), `flutter_secure_storage` (key storage bridge)

**Storage**: Sembast (Dart, all platforms) for UI-layer state; SQLite via `sqlx` (Rust, native) / IndexedDB via `indexed_db_futures` (Rust, web) for protocol-layer persistence. Feature-gated via `#[cfg(target_arch = "wasm32")]`.

**Testing**: `cargo test` + `cargo clippy -- -D warnings` (Rust); `flutter test` + `flutter analyze` (Dart)

**Target Platform**: iOS 15+, Android 6+, Web (PWA, Chrome/Firefox/Safari), macOS 12+, Windows 10+, Linux (GTK)

**Project Type**: Mobile + Desktop + Web application (Flutter multi-platform)

**Performance Goals**: Cold start < 2 seconds; order book load < 3 seconds; chat message delivery < 5 seconds; UI at 60 fps on mid-range mobile hardware

**Constraints**: Offline-first (queue outbound messages when offline); zero crypto in Dart; no analytics/telemetry; responsive layouts for mobile, tablet, and desktop; all relay I/O originates in Rust

**Scale/Scope**: ~23 distinct screens (per V1_FLOW_GUIDE.md); 15 Mostro order states; ~50 functional requirements; 5 languages (EN, ES, IT, FR, DE)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| **I. Rust Core, Flutter Shell** | ✅ PASS | All Nostr logic, NIP-59, BIP-32, NWC, relay I/O in Rust/nostr-sdk. Zero crypto in Dart. `flutter_rust_bridge` is the sole bridge. |
| **II. Privacy by Design** | ✅ PASS | NIP-59 Gift Wrap on all Mostro messages. No analytics. Keys never stored unencrypted. Ephemeral trade keys per order. No non-relay HTTP calls from core. |
| **III. Protocol Compliance** | ✅ PASS | Uses `mostro-core` crate directly for type-safe message construction. Compatible with any conforming Mostro daemon. Protocol version mismatches surfaced as user-visible errors. |
| **IV. Offline-First Architecture** | ✅ PASS | Sembast (Dart) + SQLite/IndexedDB (Rust) are local source of truth. `MessageQueue` entity handles offline outbox. Relay sync on reconnect. |
| **V. Multi-Platform from Day One** | ✅ PASS | iOS, Android, web (PWA), macOS, Windows, Linux all targeted. WASM build via wasm-pack. Responsive layouts. Platform features degrade gracefully (QR, notifications, camera). |
| **VI. Simplicity Over Features** | ✅ PASS | One screen, one purpose per V1_FLOW_GUIDE.md. Progressive disclosure. Trade progress indicator on all active trade screens. |
| **VII. V1 UX is Non-Negotiable** | ✅ PASS | V1_FLOW_GUIDE.md is the binding spec for all 23 flow sections. DESIGN_SYSTEM.md governs visuals. No improvisation. |

**Post-Phase 1 re-check**: All gates still pass. The data model, contracts, and project structure confirm no violations. The `MessageQueue` entity directly addresses Principle IV; the WASM-gated storage trait addresses Principle V; `mostro-core` dependency addresses Principle III.

## Project Structure

### Documentation (this feature)

```text
specs/004-mostro-p2p-client/
├── plan.md              # This file
├── spec.md              # Feature specification
├── research.md          # Phase 0 — architecture research (12 decisions)
├── data-model.md        # Phase 1 — entity definitions
├── quickstart.md        # Phase 1 — developer getting-started guide
├── contracts/           # Phase 1 — Rust API contracts (9 modules)
│   ├── types.md
│   ├── orders.md
│   ├── messages.md
│   ├── identity.md
│   ├── nostr.md
│   ├── nwc.md
│   ├── disputes.md
│   ├── reputation.md
│   └── settings.md
└── tasks.md             # Phase 2 output (/speckit.tasks — NOT generated here)
```

### Source Code (repository root)

```text
lib/                          # Flutter/Dart UI shell
├── core/
│   ├── app_routes.dart       # GoRouter route definitions (23 routes)
│   ├── app_theme.dart        # Design system tokens (colors, typography)
│   └── app.dart              # App bootstrap, Riverpod ProviderScope
├── features/
│   ├── walkthrough/          # Section 1: onboarding walkthrough
│   ├── home/                 # Sections 3–5: order book + FAB
│   ├── order/                # Sections 7–10: create/take order, invoice screens
│   ├── trades/               # Sections 11–12, 16–18: trade detail + my trades
│   ├── chat/                 # Sections 19–20: P2P chat list + room
│   ├── disputes/             # Sections 21–23: dispute list + admin chat
│   ├── rate/                 # Section 13: post-trade rating
│   ├── notifications/        # Section 15: notification center
│   ├── account/              # Section 2 + 15: backup + identity
│   ├── settings/             # Section 14: settings screen
│   ├── drawer/               # Section 6: drawer menu
│   └── about/                # About screen
├── shared/
│   ├── providers/            # Cross-feature Riverpod providers
│   ├── widgets/              # Reusable UI components
│   └── utils/
└── generated/                # flutter_rust_bridge generated bindings (DO NOT EDIT)

rust/                         # Rust core
├── src/
│   ├── api/                  # flutter_rust_bridge public API surface
│   │   ├── mod.rs
│   │   ├── orders.rs         # Order CRUD + subscription
│   │   ├── trades.rs         # Trade lifecycle actions
│   │   ├── messages.rs       # P2P + admin chat
│   │   ├── identity.rs       # Key management + backup
│   │   ├── nostr.rs          # Relay management + event stream
│   │   ├── nwc.rs            # NWC wallet connect
│   │   ├── disputes.rs       # Dispute open/chat
│   │   ├── reputation.rs     # Rating submit/read
│   │   └── settings.rs       # Preferences
│   ├── db/                   # Storage trait + backends
│   │   ├── mod.rs
│   │   ├── schema.rs         # Shared table/index definitions
│   │   ├── sqlite.rs         # Native SQLite backend (sqlx)
│   │   └── indexeddb.rs      # Web IndexedDB backend (wasm only)
│   ├── nostr/                # Nostr event construction + parsing
│   │   ├── gift_wrap.rs      # NIP-59 Gift Wrap encode/decode
│   │   ├── order_events.rs   # Kind 38383 event parsing
│   │   └── relay_pool.rs     # Multi-relay connection manager
│   ├── crypto/               # Key derivation + encryption
│   │   ├── keys.rs           # BIP-39 mnemonic, BIP-32 derivation
│   │   ├── ecdh.rs           # ECDH shared key computation
│   │   └── file_enc.rs       # ChaCha20-Poly1305 file encryption
│   ├── nwc/                  # Nostr Wallet Connect client
│   │   └── client.rs
│   ├── mostro/               # Mostro protocol FSM + message handling
│   │   ├── fsm.rs            # Order state machine (15 states)
│   │   ├── actions.rs        # Action dispatch (take, fiat-sent, release, etc.)
│   │   └── session.rs        # Per-trade session state
│   └── queue/                # Offline message queue
│       └── outbox.rs
├── Cargo.toml
└── build.rs                  # flutter_rust_bridge codegen invocation

rust_builder/                 # Build tooling for flutter_rust_bridge + wasm-pack
test/
├── widget/                   # Flutter widget tests
├── integration/              # Flutter integration tests
└── rust/                     # Cargo unit tests (also in rust/src/**/*.rs)
specs/                        # Planning artifacts (this directory)
assets/
├── images/                   # Walkthrough images (wt-1.png … wt-6.png), logos
├── data/
│   └── fiat.json             # Fiat currency + country flag data
└── l10n/                     # ARB localization files (EN, ES, IT, FR, DE)
```

**Structure Decision**: Flutter multi-platform monorepo with a `lib/` Dart shell and `rust/` Rust core. Features are organized as self-contained directories under `lib/features/`, each mirroring a V1_FLOW_GUIDE.md section group. The Rust `api/` layer exposes only what the Flutter shell needs; all protocol internals stay inside `rust/src/`. The `generated/` directory is owned by `flutter_rust_bridge_codegen` and must never be edited manually.

## Phase 18: Real Order Book Bridge + Shimmer Loading

**Context**: Phases 1–17 implemented the complete UI with mock order data and left bridge wiring for the order book explicitly deferred. Phase 18 closes the gap between the Rust `OrderBook` infrastructure (already implemented in `orders.rs`) and the Flutter `orderBookProvider` (currently `Provider<List<OrderItem>>` with hardcoded mock data).

**Objectives**:
1. Subscribe to Kind 38383 events from the trusted Mostro relay — the public order book as specified in `PROTOCOL.md §Order Publication`.
2. Stream live orders into the Flutter UI via `on_orders_updated()` FRB stream → `StreamProvider`.
3. Show DESIGN_SYSTEM.md §9.1 shimmer skeletons during initial load (`shimmer: ^3.0.0`).

**Key Files**:
- `rust/src/api/orders.rs` — add `subscribe_orders()` and `on_orders_updated()` / `OrdersStream`
- `rust/src/api/nostr.rs` — call `subscribe_orders()` on `ConnectionState::Online`
- `lib/features/home/providers/home_order_providers.dart` — replace mock `Provider` with `StreamProvider.autoDispose`
- `lib/shared/widgets/order_list_skeleton.dart` — new shimmer widget
- `lib/features/home/screens/home_screen.dart` — wire `provider.when(loading/error/data)`
- `pubspec.yaml` — add `shimmer: ^3.0.0`

**Dependencies**: Phase 5 (US3 order book UI), Phase 2 (relay pool), flutter_rust_bridge codegen.

---

## Complexity Tracking

No constitution violations identified. Architecture matches exactly what the constitution prescribes: Rust core + Flutter shell + single bridge. The storage trait with two backends (SQLite native / IndexedDB web) is required by Constitution Principle V (multi-platform from day one) — no alternative satisfies both native and web without violating Principle I.
