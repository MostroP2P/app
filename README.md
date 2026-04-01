# Mostro Mobile

> Non-custodial, peer-to-peer Bitcoin ↔ fiat exchange on Lightning Network — powered by the Mostro protocol over Nostr.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-blue?logo=flutter)](https://flutter.dev)
[![Rust](https://img.shields.io/badge/Rust-1.94+-orange?logo=rust)](https://www.rust-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platforms](https://img.shields.io/badge/platforms-Android%20%7C%20iOS%20%7C%20Web%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux-lightgrey)](#supported-platforms)

---

## Table of Contents

1. [What is Mostro Mobile?](#what-is-mostro-mobile)
2. [What is Mostro?](#what-is-mostro)
3. [The Mostro Protocol](#the-mostro-protocol)
4. [Architecture & Fundamentals](#architecture--fundamentals)
5. [Supported Platforms](#supported-platforms)
6. [Getting Started (Users)](#getting-started-users)
7. [Getting Started (Developers)](#getting-started-developers)
8. [Project Structure](#project-structure)
9. [Contributing](#contributing)
10. [Internationalization](#internationalization)
11. [Security](#security)
12. [License](#license)

---

## What is Mostro Mobile?

Mostro Mobile is the official cross-platform client for the [Mostro](https://mostro.network) peer-to-peer exchange network. It lets anyone buy or sell Bitcoin for local fiat currency using the Lightning Network — without accounts, without KYC, and without trusting a third party.

**Key features:**

- **Non-custodial** — Your keys stay on your device. No exchange holds your funds.
- **Privacy-first** — Encrypted messaging (NIP-59 Gift Wrap over Nostr) between trading parties. Optional privacy mode hides reputation data.
- **Lightning-native** — All BTC settlements happen via Lightning invoices (BOLT 11). Supports [Nostr Wallet Connect (NWC)](https://nwc.dev) for automated invoice generation.
- **Censorship-resistant** — Built on the Nostr network; no central server or domain to block.
- **Multi-platform** — Single codebase targets Android, iOS, Web (PWA), macOS, Windows, and Linux.
- **Open source** — MIT licensed. Fully auditable, no proprietary components.

---

## What is Mostro?

Mostro is a decentralized peer-to-peer Bitcoin exchange system. It acts as a **non-custodial escrow daemon** that facilitates trades between parties who want to exchange Bitcoin (via Lightning) for fiat currency.

Unlike centralized exchanges (e.g., Binance, Coinbase), Mostro:

- Does not hold user funds or require registration
- Does not have access to trade secrets or personal data
- Cannot censor or block orders
- Relies on cryptographic proofs, not corporate trust
- Is run by independent operators — anyone can run a Mostro node

The Mostro daemon (server component) is an open-source project written in Rust: [MostroP2P/mostro](https://github.com/MostroP2P/mostro). This repository is the **mobile/desktop/web client** that talks to any Mostro daemon.

---

## The Mostro Protocol

The Mostro protocol is a message-passing specification built on top of [Nostr](https://nostr.com). All communication between clients and the Mostro daemon travels as encrypted Nostr events.

### Core Concepts

| Concept | Description |
|---------|-------------|
| **Order Book** | Mostro daemons publish pending orders as Nostr events of [Kind 38383](https://mostro.network/protocol/list_orders.html) — parameterized replaceable events. |
| **Trade Messages** | All trade actions (take order, add invoice, confirm fiat sent, release funds) are sent as [NIP-59 Gift Wrap](https://github.com/nostr-protocol/nips/blob/master/59.md) encrypted messages directed to the Mostro node pubkey. |
| **P2P Chat** | Direct messages between buyer and seller use NIP-59 Kind 14 encrypted DMs directed to the peer's pubkey. |
| **Hold Invoices** | The seller pays a Lightning hold invoice when taking a buy order. Funds are locked until the buyer confirms fiat receipt, then the daemon releases the HTLC. |
| **Reputation** | Each trade can result in a mutual star rating, published as a Nostr event by the daemon. |
| **Disputes** | Either party can open a dispute, escalating to a human Mostro operator for resolution. |

### Trade Flow

```
Maker creates order  →  Mostro daemon publishes Kind 38383 to relays
Taker sees order     →  sends NIP-59 "take-order" to daemon
Daemon responds      →  notifies both parties via NIP-59 DM

Seller pays Lightning hold invoice (funds locked in HTLC)
Buyer submits Lightning invoice to receive sats

Fiat transfer happens off-chain (bank transfer, cash, etc.)

Buyer confirms "fiat-sent" via NIP-59 message
Seller confirms receipt  →  daemon settles hold invoice
Sats released to buyer   →  trade complete
Both parties rate each other (optional)
```

### Event Kinds Used

| Kind | Description |
|------|-------------|
| `38383` | Public order book (published by Mostro daemon) |
| `1059` | NIP-59 Gift Wrap — encrypted trade messages to/from daemon |
| `14` | NIP-59 encrypted DM — P2P chat between peers |

### Protocol Reference

- Full spec: [mostro.network/protocol](https://mostro.network/protocol)
- NIP-59 Gift Wrap: [github.com/nostr-protocol/nips/blob/master/59.md](https://github.com/nostr-protocol/nips/blob/master/59.md)
- Order Kind 38383: [mostro.network/protocol/list_orders.html](https://mostro.network/protocol/list_orders.html)

---

## Architecture & Fundamentals

Mostro Mobile uses a **split-architecture** model: all cryptography, protocol logic, and network I/O live in a Rust core; the UI shell is written in Flutter/Dart.

```
┌─────────────────────────────────────────────┐
│               Flutter / Dart UI             │
│  Riverpod state · GoRouter · Material 3     │
│  Sembast (UI-layer persistence, all plats.) │
└──────────────────┬──────────────────────────┘
                   │  flutter_rust_bridge 2.x (FFI / WASM)
┌──────────────────▼──────────────────────────┐
│                  Rust Core                  │
│                                             │
│  nostr-sdk 0.44   →  relay pool, NIP-59     │
│  mostro-core 0.8  →  protocol FSM, types    │
│  bip32 / bip39    →  HD key derivation      │
│  k256             →  secp256k1 ECDH         │
│  chacha20poly1305 →  file encryption        │
│                                             │
│  SQLite (native)  ·  IndexedDB (WASM/web)   │
└─────────────────────────────────────────────┘
```

### Design Principles

- **Offline-first** — Orders and trade state persist locally; outbound messages are queued and retried when relay connectivity is restored.
- **Identity via BIP-32/39** — The master identity key is derived from a BIP-39 mnemonic. Per-trade ephemeral keys are derived via BIP-32 path `m/44'/1237'/38383'/0/N` to prevent cross-trade correlation.
- **Zero server dependency** — The app can function with any compliant Mostro node. The default node pubkey is configurable in settings.
- **Type-safe bridge** — The Rust API surface is defined through `flutter_rust_bridge` annotations; all Dart–Rust interactions are generated, never hand-written.
- **Platform parity** — Web builds use `wasm-pack` to compile the Rust core to WASM; storage and async runtime are feature-gated per target.

### Tech Stack

| Layer | Technology | Version |
|-------|-----------|---------|
| UI Framework | Flutter | 3.x |
| UI Language | Dart | 3.x |
| Core Language | Rust | 1.94+ stable |
| Rust–Dart Bridge | flutter_rust_bridge | 2.11.1 |
| State Management | Riverpod | 2.6.1 |
| Routing | GoRouter | 14.8.1 |
| Nostr Protocol | nostr-sdk | 0.44 |
| Mostro Types / FSM | mostro-core | 0.8.0 |
| UI-layer Persistence | Sembast | 3.8.2 |
| Protocol Persistence (native) | SQLite via sqlx | 0.8 |
| Protocol Persistence (web) | IndexedDB | 0.4 |
| HD Key Derivation | bip32 / bip39 | 0.5 / 2 |
| ECDH (P2P chat keys) | k256 | 0.13 |
| File Encryption | chacha20poly1305 | 0.10 |
| Async Runtime (native) | tokio | 1 |
| Async Runtime (web) | wasm-bindgen-futures | 0.4 |
| Wallet Integration | Nostr Wallet Connect | NWC spec |

---

## Supported Platforms

| Platform | Status |
|----------|--------|
| Android 6.0+ | Supported |
| iOS 15+ | Supported |
| Web (PWA) | Supported (WASM) |
| macOS 12+ | Supported |
| Windows 10+ | Supported |
| Linux (GTK) | Supported |

---

## Getting Started (Users)

### Install the App

**Android**

Download the latest APK from the [Releases](../../releases) page and install it, or build from source (see the Developer section below).

**iOS**

Available via TestFlight (link in Releases) or build from source with Xcode.

**Web (PWA)**

Open the hosted web app in a modern browser and install it as a Progressive Web App using the browser's "Add to Home Screen" / "Install" option.

**Desktop (macOS / Windows / Linux)**

Download the binary for your platform from the [Releases](../../releases) page.

### First Run

1. On first launch, the app generates a BIP-39 mnemonic seed phrase.
2. **Back up your seed phrase immediately** — it is the only way to recover your identity and trade history.
3. Configure your preferred Mostro node pubkey and Nostr relays in **Settings → Relays**.
4. (Optional) Connect a Lightning wallet via **Settings → Connect Wallet** (Nostr Wallet Connect) for automated invoice handling.

---

## Getting Started (Developers)

### Prerequisites

Make sure the following tools are installed on your system:

| Tool | Version | Install |
|------|---------|---------|
| Flutter SDK | 3.x stable | [flutter.dev/docs/get-started](https://flutter.dev/docs/get-started/install) |
| Rust toolchain | 1.94+ stable | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| WASM target | — | `rustup target add wasm32-unknown-unknown` |
| wasm-pack | latest | `cargo install wasm-pack` |
| flutter_rust_bridge CLI | 2.x | `dart pub global activate flutter_rust_bridge` |
| Xcode (macOS / iOS only) | 15+ | Mac App Store |
| Android Studio / NDK (Android only) | latest | [developer.android.com](https://developer.android.com/studio) |

### Clone & Setup

```bash
git clone https://github.com/MostroP2P/mobilev2.git
cd mobilev2

# Install Dart/Flutter dependencies
flutter pub get

# Verify the Rust core compiles
cd rust && cargo build && cd ..

# Regenerate flutter_rust_bridge bindings (needed after any Rust API change)
flutter_rust_bridge_codegen generate
```

### Run

```bash
# Auto-detect connected device
flutter run

# Target a specific platform
flutter run -d android
flutter run -d ios
flutter run -d chrome        # Web (WASM)
flutter run -d macos
flutter run -d windows
flutter run -d linux
```

### Build for Production

```bash
# Android APK
flutter build apk --release

# Android App Bundle (Play Store)
flutter build appbundle --release

# iOS
flutter build ios --release

# Web (PWA)
flutter build web --pwa-strategy=offline-first --release

# macOS
flutter build macos --release

# Windows
flutter build windows --release

# Linux
flutter build linux --release
```

### Testing

```bash
# Rust unit tests
cargo test

# Rust linter (must pass with zero warnings)
cargo clippy -- -D warnings

# Flutter static analysis
flutter analyze

# Flutter tests
flutter test
```

All CI checks must pass before merging. Run both suites locally before opening a PR.

### Regenerating the Bridge

If you modify any `#[frb]`-annotated Rust function in `rust/src/api/`:

```bash
flutter_rust_bridge_codegen generate
```

> **Do not hand-edit** files under `lib/src/rust/` — they are auto-generated and will be overwritten on the next codegen run. Always commit generated files alongside the Rust changes that triggered them.

---

## Project Structure

```
mostro-mobile/
├── lib/                        # Flutter/Dart UI shell
│   ├── core/                   #   App root, routing (GoRouter), theme, design tokens
│   ├── features/               #   Feature modules (one per user flow)
│   │   ├── walkthrough/        #     Onboarding flow
│   │   ├── home/               #     Order book + filters
│   │   ├── order/              #     Create / take order, invoices
│   │   ├── trades/             #     Active trades, trade detail
│   │   ├── chat/               #     P2P encrypted chat
│   │   ├── disputes/           #     Dispute management
│   │   ├── rate/               #     Post-trade rating
│   │   ├── notifications/      #     Notification center
│   │   ├── account/            #     Identity, key backup
│   │   └── settings/           #     Relays, wallet, preferences
│   ├── shared/                 #   Cross-feature providers, widgets, utils
│   ├── l10n/                   #   Localization strings (EN, ES, IT, FR, DE)
│   └── src/rust/               #   Auto-generated Rust bridge (DO NOT EDIT)
│
├── rust/                       # Rust core
│   └── src/
│       ├── api/                #   Public bridge API surface (9 modules)
│       ├── crypto/             #   BIP-32/39 derivation, ECDH, file encryption
│       ├── db/                 #   SQLite (native) / IndexedDB (WASM)
│       ├── mostro/             #   Protocol FSM & state machine
│       ├── nostr/              #   Relay pool, gift wrap, event parsers
│       ├── nwc/                #   Nostr Wallet Connect client
│       └── queue/              #   Offline outbound message queue
│
├── rust_builder/               # iOS/macOS Cargokit build integration
├── test/                       # Flutter widget tests
├── specs/                      # Design specs, planning docs, API contracts
├── assets/                     # Walkthrough images, fiat currency data
├── pubspec.yaml                # Dart/Flutter manifest
└── rust/Cargo.toml             # Rust manifest
```

---

## Contributing

Contributions are welcome. Please read this section before opening an issue or pull request.

### Reporting Bugs

1. Search [existing issues](../../issues) first to avoid duplicates.
2. Open a new issue using the **Bug Report** template.
3. Include: platform, Flutter/Rust versions, reproduction steps, and relevant logs (`flutter run --verbose` or `adb logcat`).

### Requesting Features

1. Open a [Feature Request](../../issues/new) issue.
2. Describe the use case — what problem does it solve and who benefits?
3. Features that align with the Mostro protocol roadmap are prioritized.

### Submitting a Pull Request

1. **Fork** the repository and create a branch from `main`:
   ```bash
   git checkout -b feat/your-feature-name
   ```

2. **Follow the code style:**
   - Dart: standard Flutter conventions, enforced by `analysis_options.yaml`
   - Rust: `cargo fmt` + `cargo clippy -- -D warnings` (zero warnings required)
   - Commits: use [Conventional Commits](https://www.conventionalcommits.org/) — `feat:`, `fix:`, `refactor:`, `docs:`, `test:`

3. **Write tests** for any new Rust API functions. Flutter widget tests are encouraged for new screens.

4. **Keep PRs focused** — one concern per PR. Large refactors should be discussed in an issue first.

5. **Ensure all checks pass locally** before pushing:
   ```bash
   cargo test && cargo clippy -- -D warnings
   flutter analyze && flutter test
   ```

6. Open the PR against `main`, fill in the PR template, and link the related issue.

7. Maintainers will review within a few days. Address feedback with new commits — do not force-push a branch under review.

### Branch Policy

| Branch pattern | Purpose |
|----------------|---------|
| `main` | Protected — requires passing CI and one approving review |
| `feat/<name>` | New features |
| `fix/<name>` | Bug fixes |
| `docs/<name>` | Documentation only |
| `refactor/<name>` | Code restructuring without behavior change |

### Development Notes

- **Bridge changes:** Any modification to `rust/src/api/` requires re-running `flutter_rust_bridge_codegen generate`. Commit the generated files together with the Rust changes.
- **Serde conventions:** `mostro-core` uses `#[serde(rename_all = "kebab-case")]` — all protocol status strings on the wire are kebab-case (e.g., `"waiting-buyer-invoice"`, `"fiat-sent"`, `"in-progress"`).
- **`pub` vs `pub(crate)`:** Only types that must be exposed to the Dart bridge should be `pub`. Internal helpers and types wrapping `nostr-sdk` structs should be `pub(crate)` to prevent broken FRB stub generation.
- **Key derivation:** Per-trade keys follow BIP-32 path `m/44'/1237'/38383'/0/N`. Never reuse the master identity key for trade-level messages.
- **Offline-first:** New trade actions must go through the outbound message queue (`rust/src/queue/`) so they are retried on reconnect. Do not call the relay client directly from action handlers.

### Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/version/2/1/code_of_conduct/). Be respectful, constructive, and inclusive. Violations can be reported to the maintainers via the contact listed in the GitHub organization profile.

---

## Internationalization

The app is localized in:

| Language | Code | File |
|----------|------|------|
| English | `en` | `lib/l10n/app_en.arb` |
| Spanish | `es` | `lib/l10n/app_es.arb` |
| Italian | `it` | `lib/l10n/app_it.arb` |
| French | `fr` | `lib/l10n/app_fr.arb` |
| German | `de` | `lib/l10n/app_de.arb` |

To add a new language:

1. Copy `lib/l10n/app_en.arb` to `lib/l10n/app_<code>.arb`
2. Translate all string values (keep the `"@@locale"` key correct)
3. Add the locale to `l10n.yaml` supported locales list
4. Run `flutter gen-l10n` to regenerate the Dart localizations
5. Open a PR — translation contributions are always welcome

---

## Security

### Responsible Disclosure

If you discover a security vulnerability, **please do not open a public issue.** Instead:

- Open a [GitHub Security Advisory](../../security/advisories/new) (preferred), or
- Email the maintainers directly via the contact in the GitHub organization profile.

We aim to acknowledge reports within 72 hours and provide a fix within 30 days for critical issues.

### Security Model

- **Keys never leave the device** — the BIP-39 seed is stored in platform secure storage (`flutter_secure_storage`, backed by Android Keystore / iOS Keychain / Linux SecretService).
- **End-to-end encrypted trade messages** — all communication between the app and the Mostro daemon uses NIP-59 Gift Wrap (secp256k1 ECDH + ChaCha20-Poly1305).
- **Per-trade ephemeral keys** — a new BIP-32 child key is derived for each trade, preventing cross-trade correlation even if a single trade key is compromised.
- **The Mostro daemon never sees plaintext** — all messages are encrypted to the daemon's public key; only the holder of the corresponding private key can decrypt them.
- **No telemetry** — the app does not collect analytics, crash reports, or any usage data.

---

## License

MIT License

See [LICENSE](LICENSE) for the full text.

---

*Mostro Mobile is an independent open-source project. It is not affiliated with any centralized exchange or financial institution.*
