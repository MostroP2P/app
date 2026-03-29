# Quickstart: Mostro Mobile v2

**Branch**: `004-mostro-p2p-client` | **Date**: 2026-03-29

Get the project building and running for the first time on all supported platforms.

---

## Prerequisites

| Tool | Version | Install |
|------|---------|---------|
| Flutter | 3.x stable | `flutter.dev/docs/get-started` |
| Rust | stable 1.94+ | `rustup.rs` |
| wasm-pack | latest | `cargo install wasm-pack` |
| WASM target | — | `rustup target add wasm32-unknown-unknown` |
| flutter_rust_bridge codegen | 2.x | `cargo install flutter_rust_bridge_codegen` |

Platform-specific tools: Xcode (iOS/macOS), Android SDK (Android), standard C toolchain (Linux/Windows).

---

## Initial Setup

```bash
# 1. Clone and switch to feature branch
git clone https://github.com/MostroP2P/mobilev2.git
cd mobilev2
git checkout 004-mostro-p2p-client

# 2. Install Flutter dependencies
flutter pub get

# 3. Generate flutter_rust_bridge bindings
flutter_rust_bridge_codegen generate

# 4. Verify Rust builds (native)
cd rust && cargo build && cargo test && cargo clippy -- -D warnings
cd ..

# 5. Verify Flutter analysis
flutter analyze
```

---

## Run on Each Platform

```bash
# Mobile (connect device or start emulator/simulator first)
flutter run                          # auto-detects connected device
flutter run -d android               # Android emulator/device
flutter run -d ios                   # iOS simulator/device

# Web (PWA)
flutter run -d chrome                # local dev server
flutter build web --pwa-strategy=offline-first   # production PWA build

# Desktop
flutter run -d macos
flutter run -d windows
flutter run -d linux
```

---

## Key Directories

| Path | Purpose |
|------|---------|
| `lib/` | Flutter/Dart UI shell |
| `lib/features/` | One subdirectory per V1_FLOW_GUIDE.md feature group |
| `lib/generated/` | Auto-generated bridge bindings — **do not edit** |
| `rust/src/api/` | Public Rust API surface (what Flutter calls) |
| `rust/src/mostro/` | Mostro protocol FSM and message actions |
| `rust/src/crypto/` | BIP-39/BIP-32 key derivation, ECDH, file encryption |
| `rust/src/nostr/` | Gift Wrap (NIP-59), relay pool, Kind 38383 events |
| `assets/data/fiat.json` | Fiat currency and country flag data |
| `assets/l10n/` | ARB localization files (EN, ES, IT, FR, DE) |

---

## Architecture at a Glance

```
Flutter UI (Dart)
    │  Riverpod providers  GoRouter routes  Sembast local state
    │
    ▼  flutter_rust_bridge (FFI on native, WASM on web)
    │
Rust Core
    ├── nostr-sdk       — relay connections, NIP-59 gift wrap, event parsing
    ├── mostro-core     — Mostro protocol types, FSM, message construction
    ├── sqlx (SQLite)   — native storage (iOS, Android, macOS, Windows, Linux)
    ├── indexed_db_futures — web storage (WASM only, feature-gated)
    ├── bip32/bip39     — HD key derivation (m/44'/1237'/38383'/0/N)
    ├── chacha20poly1305 — file attachment encryption
    └── NWC client      — Nostr Wallet Connect auto-pay
```

**Rule**: Network calls to relays and all cryptographic operations originate exclusively in Rust. Flutter never touches keys or makes relay connections.

---

## Re-generating the Bridge

Run this whenever you add or change public functions in `rust/src/api/`:

```bash
flutter_rust_bridge_codegen generate
```

The generated files in `lib/generated/` are committed to the repo for reproducibility.

---

## Running Tests

```bash
# Rust unit tests
cd rust && cargo test

# Rust linting (zero warnings required)
cargo clippy -- -D warnings

# Flutter widget + unit tests
flutter test

# Flutter static analysis (zero issues required)
flutter analyze
```

---

## Localization

Add new strings to `assets/l10n/app_en.arb` first, then run:

```bash
flutter gen-l10n
```

All 5 locales (EN, ES, IT, FR, DE) must be updated before merging.

---

## V1 Reference

Before implementing any screen, read:

1. `.specify/v1-reference/V1_FLOW_GUIDE.md` — screen-by-screen interaction spec (authoritative)
2. The linked `.specify/v1-reference/<SCREEN>.md` — full per-screen detail
3. `DESIGN_SYSTEM.md` — colors, typography, spacing, component patterns

The flow guide and design system take precedence over any other source.
