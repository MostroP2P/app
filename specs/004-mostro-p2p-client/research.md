# Research: Mostro Mobile v2 — P2P Exchange Client

**Branch**: `001-mostro-p2p-client` | **Date**: 2026-03-22

## R1: nostr-sdk WASM Compatibility

**Decision**: Use nostr-sdk with feature-gated WASM support for web target.

**Rationale**: nostr-sdk (rust-nostr project) supports `wasm32-unknown-unknown`
as a first-class target. The project provides official JavaScript/TypeScript
bindings (`@rust-nostr/nostr-sdk` npm package) built via wasm-pack. The crate
uses `#[cfg(target_arch = "wasm32")]` conditional compilation extensively
to swap platform-specific implementations.

**Key constraints for WASM builds**:
- Storage backends like SQLite, nostrdb (ndb), rocksdb, and lmdb do NOT
  compile to WASM. Use IndexedDB-based storage on web.
- Networking uses WebSockets via `ws_stream_wasm` instead of native TCP/TLS.
- Async runtime is `wasm-bindgen-futures` — tokio's multi-threaded runtime
  is unavailable on WASM.
- Timer/sleep functions require WASM-compatible alternatives.
- Binary size requires monitoring; use `wasm-opt` and careful feature
  selection.

**Alternatives considered**:
- `dart_nostr` (pure Dart): Would violate Constitution Principle I (Rust Core).
  Rejected.
- JS/TS bindings only for web: Viable but adds a separate integration path.
  Using flutter_rust_bridge's own WASM compilation keeps a single codebase.

## R2: flutter_rust_bridge v2 Web/WASM Support

**Decision**: Use flutter_rust_bridge v2 with wasm-pack for web builds,
with feature-gated async runtime in Rust.

**Rationale**: flutter_rust_bridge v2 officially supports Flutter web. It
uses `wasm-pack` internally to compile Rust to WASM and generates appropriate
Dart shims that use JS interop (`dart:js_interop`) on web instead of
`dart:ffi` on native.

**Setup requirements**:
- Install `wasm-pack` (`cargo install wasm-pack`)
- Add Rust target: `rustup target add wasm32-unknown-unknown`
- Run codegen: `flutter_rust_bridge_codegen generate`
- Build step invokes `wasm-pack build` before/during `flutter build web`

**Key constraints**:
- All Rust calls from Dart are async on web (browser single-threaded model).
  Synchronous calls available on native become async on web.
- No Dart `Isolate` support on web — cannot transparently bridge to Web
  Workers.
- Crate dependencies must be WASM-compatible — no `std::fs`, `std::net`,
  native TLS, or OS-specific syscalls.
- Binary size needs monitoring with `wasm-opt`.

**Async runtime strategy**:
- **Native (iOS, Android, macOS, Windows, Linux)**: Use `tokio` with
  `rt-multi-thread` feature.
- **Web (WASM)**: Use `wasm-bindgen-futures::spawn_local` for async execution.
- Feature-gate with `#[cfg(target_arch = "wasm32")]` /
  `#[cfg(not(target_arch = "wasm32"))]`.

**Alternatives considered**:
- Pure Dart for web: Violates Constitution Principle I. Rejected.
- Separate web codebase: Violates Constitution Principle V (Multi-Platform
  from Day One). Rejected.

## R3: Mostro Protocol Details

**Decision**: Implement against the Mostro protocol as defined in
`mostro-core` crate, using Kind 38383 for public orders and Kind 1059
(NIP-59 Gift Wrap) for all private communication.

**Rationale**: The Mostro protocol is well-documented with a reference
daemon, core types library, and CLI client. Using `mostro-core` as a
dependency ensures type-level compatibility with any conforming daemon.

**Protocol message format**:
```json
{
  "order": {
    "version": 1,
    "id": "<order-uuid>",
    "action": "<Action enum>",
    "content": { ... }
  }
}
```

**Action enum values**: `NewOrder`, `TakeSell`, `TakeBuy`, `FiatSent`,
`Release`, `Cancel`, `Dispute`, `AdminCancel`, `AdminSettle`, `PayInvoice`,
`AddInvoice`, `RateUser`, and others.

**Nostr event kinds**:
- **Kind 38383**: Parameterized replaceable event for public order listings.
  Uses `d` tags for order ID, filterable tags for amount/currency/method.
- **Kind 1059**: NIP-59 Gift Wrap — outer encrypted envelope using
  ephemeral keypair. Used for ALL private Mostro communication.
- **Kind 13**: NIP-59 Seal — inner encrypted layer (NIP-44 encryption)
  inside the Gift Wrap.

**NIP-59 Gift Wrap flow**:
1. Create unsigned "rumor" event with the actual message content.
2. Encrypt rumor using NIP-44 into a Seal (Kind 13), signed by sender.
3. Wrap Seal into a Gift Wrap (Kind 1059), signed by ephemeral one-time key.
4. The `p` tag on Gift Wrap points to recipient; sender identity is hidden.
5. Relays only see ephemeral keys, not real participants.

**Order state machine** (15 mostro-core states):
```text
Pending
  → WaitingBuyerInvoice (sell orders: buyer must provide invoice; buy orders skip this)
  → WaitingPayment (hold invoice issued, awaiting buyer payment)
    → Active (funds locked in escrow)
      → FiatSent (buyer marked fiat sent)
        → SettledHoldInvoice (seller confirmed, funds released)
          → Success (trade complete)
          (if LN payment fails: Action::PaymentFailed sent, then Action::AddInvoice)
      → Dispute (either party disputes)
        → InProgress (admin took dispute)
        → CanceledByAdmin | SettledByAdmin | CompletedByAdmin
    → Expired (buyer never paid, timeout)
  → Canceled (creator canceled or timeout)
  → CooperativelyCanceled (UI-only state — protocol sends action notifications, does not change status)
```

> PaymentFailed is an Action, not a Status. CooperativelyCanceled is client-side UI only.

**Reference implementations**:
- Daemon: `github.com/MostroP2P/mostro` (Rust)
- Core types: `crates.io/crates/mostro-core` v0.8.0 (Rust crate)
- CLI client: `github.com/MostroP2P/mostro-cli` (Rust)
- Mobile client v1: `github.com/MostroP2P/mostro-mobile` (Flutter)
- Docs: `mostro.network`

**Alternatives considered**:
- Custom protocol implementation: Fragile, risks incompatibility. Rejected.
- Use mostro-core directly as Cargo dependency: Preferred. Gives type-safe
  message construction and state validation.

## R4: Storage Strategy (Cross-Platform)

**Decision**: SQLite on native platforms, IndexedDB on web.

**Rationale**: Constitution mandates SQLite or equivalent for local
persistence. SQLite compiles natively on all mobile/desktop targets. On web,
SQLite is not available — IndexedDB is the browser-native storage option.

**Implementation approach**:
- Define a storage trait in Rust with async methods for CRUD operations.
- Native implementation: `sqlx` with SQLite driver.
- Web implementation: `indexed_db_futures` crate (or similar
  WASM-compatible IndexedDB wrapper).
- Feature-gate implementations with `#[cfg(target_arch = "wasm32")]`.
- Shared migration logic; schema definitions portable between backends.

**Alternatives considered**:
- sql.js (SQLite compiled to WASM): Possible but adds complexity and
  bundle size. IndexedDB is simpler for web.
- Hive/Isar from Dart: Violates Constitution Principle I. Rejected.

## R5: Secure Key Storage (Cross-Platform)

**Decision**: Platform-specific secure storage accessed via Rust, with
encrypted-file fallback.

**Rationale**: Keys must never leave the device unencrypted (Constitution
Principle II). Each platform has a secure enclave or keychain.

**Per-platform approach**:
- **iOS**: Keychain Services
- **Android**: Android Keystore + EncryptedSharedPreferences
- **macOS**: Keychain Services
- **Windows**: Windows Credential Manager (DPAPI)
- **Linux**: libsecret (GNOME Keyring / KWallet)
- **Web**: SubtleCrypto API for key derivation + encrypted localStorage
  or IndexedDB. NOTE: Web storage is inherently less secure than native
  secure enclaves.

**Flutter-side integration**: `flutter_secure_storage` package handles
platform-specific secure storage from Dart. However, since Constitution
mandates all crypto in Rust, the Rust core should manage key encryption
and only use platform secure storage for the master key/PIN-derived key.

**Alternatives considered**:
- Store keys only in Dart via flutter_secure_storage: Violates Constitution
  Principle I (zero crypto in Dart). Rejected for key material.
- Rely on Rust-only secure storage crates: Limited cross-platform support.
  Hybrid approach preferred — Rust encrypts, platform stores.

## R6: Nostr Wallet Connect (NWC) Integration

**Decision**: Implement NWC client in Rust for automatic invoice payment
during trades.

**Rationale**: v1 already supports NWC, and it dramatically simplifies the
buyer experience by eliminating manual invoice copy-paste. NWC is a Nostr
native protocol — fits naturally into the Rust core alongside nostr-sdk.

**NWC URI format**: `nostr+walletconnect://<pubkey>?relay=<url>&secret=<hex>`

**Operations needed**:
- `pay_invoice`: Pay a Lightning invoice via connected wallet.
- `get_info`: Query wallet info (optional balance display).
- Connection status monitoring.

**Key design decisions**:
- NWC credentials stored in platform secure storage (same as identity keys).
- Multiple relay URLs supported per wallet connection.
- Fallback to manual QR/paste if NWC fails or disconnects mid-trade.
- NWC communication also uses Nostr events — all handled in Rust.

**Alternatives considered**:
- LNURLPay: Not Nostr-native, requires HTTP calls. Rejected.
- WebLN (web only): Platform-specific. NWC works everywhere. Rejected.

## R7: Encrypted File Messaging via Blossom

**Decision**: Use ChaCha20-Poly1305 AEAD encryption with Blossom servers
for decentralized file storage.

**Rationale**: v1 uses this exact approach. ChaCha20-Poly1305 is fast,
well-supported in Rust, and provides authenticated encryption. Blossom
is a decentralized media hosting protocol for Nostr.

**Blob structure**: `[nonce:12][encrypted_data][auth_tag:16]`

**Supported file types**:
- Images: JPG, PNG, GIF, WEBP (auto-preview in chat)
- Documents: PDF, DOC, TXT, RTF (download button)
- Videos: MP4, MOV, AVI, WEBM (download button)
- Size limit: 25MB per file

**Blossom server list** (from v1):
- blossom.primal.net, blossom.band, nostr.media
- blossom.sector01.com, 24242.io, nosto.re

**Upload flow**:
1. User selects file in Flutter UI.
2. File bytes passed to Rust via bridge.
3. Rust encrypts with ChaCha20-Poly1305 using a random nonce.
4. Encrypted blob uploaded to Blossom server via HTTP PUT.
5. Blossom URL sent as message content via NIP-59 Gift Wrap.
6. Recipient downloads blob, decrypts in Rust, displays in Flutter.

**Download behavior**: Images download and preview automatically. All
other types show a download button (download-on-demand).

**WASM consideration**: HTTP uploads on web use `reqwest` with
WASM-compatible backend (fetch API). File size limits apply equally.

**Alternatives considered**:
- Inline file content in Nostr events: Size-limited, inefficient. Rejected.
- External file servers (S3, etc.): Centralized, violates privacy. Rejected.

## R8: BIP-32 Key Derivation

**Decision**: Use BIP-32 derivation path `m/44'/1237'/38383'/0/N` as
established in v1.

**Rationale**: This is the existing v1 standard. Changing it would break
session recovery for users migrating from v1.

**Key indices**:
- `N=0`: Master identity key (Nostr keypair)
- `N≥1`: Trade keys (one per order, auto-incremented)

**Implementation**: Use `bip32` Rust crate for derivation. The trade key
index is persisted locally and synced during session recovery.

**P2P chat uses sharedKey** (ECDH-derived from both parties' trade keys).
**Admin chat uses tradeKey** (the trade-specific derived key directly).
This is protocol-mandated — both key types must be supported.

## R9: Background Push Notifications

**Decision**: Hybrid notification approach — foreground service during
active trades + FCM for app-killed scenarios on mobile.

**Rationale**: v1 uses this approach successfully. Users must be notified
of trade events even when the app is closed, but the push server must
transmit zero message content (Constitution Principle II — Privacy).

**Architecture**:
- **Push server**: External service monitoring relays for tradeKey.public
  in p-tag. Sends silent FCM push to wake the app. No content transmitted.
- **Android**: Smart foreground service (active only during trades) + FCM
  fallback when app killed.
- **iOS**: Silent push notifications via APNs (triggered by push server).
- **Web**: Service Worker with Web Push API (where supported).
- **Desktop**: No push server needed — background process maintains relay
  connection.

**Privacy compliance**: Push server sees only that "an event exists for
pubkey X" — never the message content. This is acceptable under
Constitution Principle II since no analytics/tracking occurs and no
content is transmitted.

**Alternatives considered**:
- Pure polling: Drains battery, unreliable when app killed. Rejected.
- WebSocket keep-alive: Not possible when app killed on mobile. Rejected.

## R10: Session Recovery Protocol

**Decision**: Implement Mostro's `Action.restore` protocol for session
recovery from mnemonic.

**Rationale**: v1 supports this. Essential for users who lose/replace
devices.

**Recovery flow**:
1. User enters 12-word BIP-39 mnemonic.
2. App derives master key (N=0) and sends `Action.restore` to Mostro.
3. Mostro returns list of order IDs + dispute IDs associated with the key.
4. App requests details for each order/dispute.
5. App syncs trade key index (to continue deriving trade-specific keys).
6. Local DB is reconstructed from daemon responses.

**Limitation**: Recovery only works in reputation mode. Privacy mode
trades are not tracked by the daemon (by design — the whole point of
privacy mode is that the daemon doesn't associate trades with identity).

**Alternatives considered**:
- Local-only backup/restore (encrypted file): Complementary, not
  alternative. Should support both daemon recovery and local backup.

## R11: Cooperative Cancel Protocol

**Decision**: Implement the two-phase cooperative cancel flow from v1.

**Rationale**: Protocol-mandated feature. Required for interoperability
with any Mostro daemon.

**Protocol actions**:
- `cooperativeCancelInitiatedByYou`: Sent when requesting cancel.
- `cooperativeCancelInitiatedByPeer`: Received when counterparty requests.
- `cooperativeCancelAccepted`: Sent/received on acceptance.

**UX consideration**: If cancel is requested after "Fiat Sent", display
a strong warning that fiat may already be in transit.

## R12: Reputation System

**Decision**: Implement rating + privacy mode as in v1.

**Rationale**: v1 feature. Reputation builds trust; privacy mode is
essential for anonymity-focused users.

**Protocol actions**:
- `rate`: Submit rating after trade success.
- `rateReceived`: Notification of received rating.

**Privacy mode**: When enabled, no reputation data is sent/received,
trades are anonymous, and session recovery is unavailable. Toggle in
settings.

## R13: Kind 38383 Authorship (Protocol Correction)

**Decision**: Filter Kind 38383 events by `author = mostro_pubkey`, not by maker pubkey.

**Rationale**: The Mostro **daemon node** (not makers) creates and publishes Kind 38383 parameterized replaceable events. The flow is:
1. Maker sends a `new-order` NIP-59 Gift Wrap (Kind 1059) to the Mostro node.
2. The Mostro node validates the order and publishes a Kind 38383 event **signed with the node's own keypair**.
3. Clients subscribe to Kind 38383 events where `author = mostro_pubkey` to see the orders belonging to that specific trusted instance.

Filtering by the Mostro node's pubkey also serves as a trust scope — it ensures clients only receive orders from the configured, trusted daemon, not from arbitrary publishers.

**References**: `https://mostro.network/protocol/list_orders.html`, `https://mostro.network/protocol/new_sell_order.html`

**Implementation**: `pending_orders_filter()` in `rust/src/nostr/order_events.rs` must include `.author(mostro_pubkey)`. The pubkey comes from `crate::config::DEFAULT_MOSTRO_PUBKEY`.

## R14: mostro-core Serde Conventions

**Decision**: All Mostro protocol enum values on the wire use `kebab-case` (not PascalCase, snake_case, or camelCase).

**Rationale**: `mostro-core` decorates its enums with `#[serde(rename_all = "kebab-case")]`. This affects the `s` tag (status) in Kind 38383 events and any JSON content inside Gift Wrap messages. A client that matches `"Pending"` will see zero orders; the actual wire value is `"pending"`.

**Complete status mapping** (wire value → `OrderStatus` variant):

| Wire value (kebab-case) | Rust variant |
|------------------------|--------------|
| `pending` | `Pending` |
| `waiting-buyer-invoice` | `WaitingBuyerInvoice` |
| `waiting-payment` | `WaitingPayment` |
| `active` | `Active` |
| `fiat-sent` | `FiatSent` |
| `settled-hold-invoice` | `SettledHoldInvoice` |
| `success` | `Success` |
| `canceled` | `Canceled` |
| `cooperatively-canceled` | `Canceled` (maps to same) |
| `expired` | `Expired` |
| `canceled-by-admin` | `CanceledByAdmin` |
| `settled-by-admin` | `SettledByAdmin` |
| `completed-by-admin` | `CompletedByAdmin` |
| `dispute` | `Dispute` |
| `in-progress` | `InProgress` |

**Implementation**: `parse_status()` in `rust/src/nostr/order_events.rs`. The Nostr filter tag value must also be `"pending"` (lowercase).

**Note on order kind**: The `k` tag values are `"buy"` and `"sell"` (already lowercase). Only the `s` (status) tag required correction.
