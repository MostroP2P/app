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

## Phase 19: Bridge Stabilization & Protocol Compliance

**Context**: Phase 18 wired the real order book bridge but integration testing revealed several blocking bugs: (1) no relay pool existed at app startup because `nostr_api.initialize()` was never called; (2) `orderBookProvider` never emitted an initial value so the shimmer never resolved; (3) the Kind 38383 author filter was missing `author = mostro_pubkey`; (4) all status values were wrong (PascalCase vs kebab-case); (5) FRB generated broken stubs for non-serializable Rust types; (6) missing Android logging made diagnosis impossible.

**Objectives**:
1. Unblock live order display — resolve all protocol and initialization bugs.
2. Establish correct Mostro protocol understanding in code and docs.
3. Improve relay pool reliability and observability.
4. Fix UI accessibility and error handling gaps found in CodeRabbit review.

**Key Protocol Corrections**:

- **Kind 38383 authorship**: The Mostro **daemon node** (not makers) creates and signs Kind 38383 events. Makers send a `new-order` NIP-59 Gift Wrap to the node; the node publishes the order. Clients must filter with `author = mostro_pubkey` to scope to the trusted instance.
- **Status serde convention**: `mostro-core` uses `#[serde(rename_all = "kebab-case")]` on all enums. All 15 status values on the wire are kebab-case: `"pending"`, `"in-progress"`, `"waiting-buyer-invoice"`, `"waiting-payment"`, `"fiat-sent"`, `"settled-hold-invoice"`, `"canceled-by-admin"`, `"settled-by-admin"`, `"completed-by-admin"`, `"cooperatively-canceled"`, `"active"`, `"canceled"`, `"expired"`, `"success"`, `"dispute"`. The filter `s` tag value is `"pending"` (not `"Pending"`).

**Key Files Changed**:
- `rust/src/api/orders.rs` — `ResetGuard` panic safety, logging, `pub(crate)` visibility fix
- `rust/src/api/identity.rs` — `pub(crate)` for `get_active_keys()` / `get_active_trade_keys()`
- `rust/src/api/nostr.rs` — connection state logging
- `rust/src/nostr/order_events.rs` — kebab-case `parse_status()`, `author` in filter, lenient `z` tag
- `rust/src/nostr/relay_pool.rs` — 500ms connect delay, 2s poll interval, pass pubkey to filter
- `rust/src/lib.rs` — `init_app()` with `android_logger` for `#[frb(init)]`
- `rust/Cargo.toml` — add `log`, `android_logger`
- `lib/main.dart` — `nostr_api.initialize()` call, `_watchConnectionState()` diagnostics
- `lib/features/home/providers/home_order_providers.dart` — initial cache yield in `orderBookProvider`
- `lib/features/home/screens/home_screen.dart` — retry error state
- `lib/features/settings/widgets/relay_management_card.dart` — accessibility labels
- `lib/features/about/screens/about_screen.dart` — `hideCurrentSnackBar()` before copy snackbar
- `lib/features/settings/widgets/currency_selector_dialog.dart` — remove `c` alias
- `lib/l10n/app_*.arb` (all 5 locales) — new keys: `errorLoadingOrders`, `retry`, `disableRelayLabel`, `enableRelayLabel`, `removeRelayTooltip`

**Dependencies**: Phase 18 complete.

---

## Phase 20: First-Launch Identity Setup & Backup Confirmation (US1 / US2)

**Spec coverage**: FR-001 through FR-013 (spec.md §User Scenarios & Testing, User Story 1 and User Story 2)
**V1 references**: `WALKTHROUGH_SCREEN.md`, `NOTIFICATIONS_SYSTEM.md`, `ACCOUNT_SCREEN.md`, `AUTHENTICATION.md`

**Context**: spec.md was updated to expand US1 and US2 with precise behavioral requirements for: (a) silent background identity generation on first launch, (b) a non-dismissible pinned backup reminder notification, (c) a red-dot indicator on the notification bell with a shake animation, and (d) an explicit backup confirmation checkbox that appears alongside the revealed mnemonic on the Account screen. This phase closes the gap between the existing walkthrough/identity scaffolding and the full first-launch + backup-confirmation loop.

**Deviation from V1 reference**:
- V1 (`ACCOUNT_SCREEN.md`): tapping "Show" reveals all 12 words; revealing them alone marks backup as confirmed.
- Updated spec (FR-010, FR-011): tapping "Show" reveals all 12 words **and** simultaneously displays a confirmation checkbox. Backup is only confirmed when the user explicitly ticks the checkbox. Viewing the words without ticking does **not** confirm backup.
- V1 (`ACCOUNT_SCREEN.md`): masked mnemonic shows first 2 + last 2 words, middle 8 as `•••`.
- Updated spec (FR-009): mnemonic is fully masked by default (all 12 words hidden as `•••`).
- These are intentional deviations; spec.md supersedes V1 reference for these two behaviors.

---

### Objectives

1. Ensure identity generation happens silently in Rust on first launch, persisted to secure storage before any UI renders.
2. *(Implemented in Dart)* Track `backup_confirmed` state in `BackupReminderNotifier` (SharedPreferences keys `backupReminderActive` / `backupReminderDismissed`). Migrating this flag to the Rust storage layer (SQLite native / IndexedDB web) is **planned future work**.
3. *(Planned future work)* Add `get_backup_confirmed()` / `set_backup_confirmed()` / `reset_backup_confirmation()` to the Rust `identity.rs` API surface once the Rust persistence layer is in place.
4. *(Implemented in Dart)* `backupReminderProvider` (`BackupReminderNotifier`) drives the bell icon, notification list, and Account screen. It is pre-seeded synchronously in `main()` via `ProviderScope.overrides` to eliminate the startup loading race.
5. Implement the pinned backup reminder notification: always first in the list, not removable via swipe, "Mark all as read", or "Clear all".
6. Implement the `AnimatedBellIcon` widget: red dot (no number) while backup pending; numbered badge after; shake animation on any indicator change.
7. Update the Secret Words card in the Account screen: fully masked by default → "Show" reveals words + checkbox; checkbox tap calls `confirmBackupComplete()`.
8. Reset `backup_confirmed` to `false` on "Generate New User" (FR-013).

---

### Key Files

> **Current implementation note**: backup confirmation state is managed entirely in Dart via `BackupReminderNotifier` and SharedPreferences (`backupReminderActive` / `backupReminderDismissed`). The Rust-side API and schema additions below are **planned future work** for when the Rust persistence layer is extended.

**Rust core (planned future work):**

| File | Change |
|------|--------|
| `rust/src/api/identity.rs` | Add `get_backup_confirmed() -> bool`, `set_backup_confirmed()`, `reset_backup_confirmation()`. Call `reset_backup_confirmation()` at the end of `generate_new_user()`. Store flag in the `identity` table (`backup_confirmed INTEGER NOT NULL DEFAULT 0`). |
| `rust/src/db/schema.rs` | Add `backup_confirmed INTEGER NOT NULL DEFAULT 0` column to the identity table. Migration-safe. |

**Dart/Flutter (current implementation):**

| File | Change |
|------|--------|
| `lib/features/account/providers/backup_reminder_provider.dart` | `BackupReminderNotifier`: `StateNotifierProvider<bool>` backed by SharedPreferences keys `backupReminderActive` / `backupReminderDismissed`. Pre-seeded synchronously in `main()` via `ProviderScope.overrides` to avoid startup loading race. |
| `lib/core/services/identity_service.dart` | `IdentityService`: manages identity lifecycle (create on first launch, reload on subsequent). `regenerate()` atomically replaces stored identity. |
| `lib/shared/widgets/animated_bell_icon.dart` | **New.** Stateful widget wrapping the bell icon. Watches `backupReminderProvider` and `unreadCountProvider`. Shows red dot when backup pending; numbered gold badge otherwise. Fires a shake animation (2 oscillations, 300 ms, ease-in-out) on indicator state change. |
| `lib/core/app.dart` or `lib/core/app_bar_builder.dart` | Replace static bell icon with `AnimatedBellIcon`. |
| `lib/features/notifications/notifiers/notifications_notifier.dart` | Pin the backup reminder as the first list item when `backupReminderProvider == true`. Override `markAllAsRead()` and `deleteAll()` to skip the backup reminder item. |
| `lib/features/notifications/screens/notifications_screen.dart` | Render the backup reminder card above all other items when backup is pending; not swipeable. |
| `lib/features/account/screens/account_screen.dart` | `SecretWordsCard`: fully masked by default; "Show" reveals words + animates in confirmation checkbox; checkbox calls `confirmBackupComplete()`. |
| `lib/l10n/app_en.arb` + all 4 locale files | Add keys: `backupReminderTitle`, `backupReminderMessage`, `backupConfirmCheckbox`, `secretWordsShowButton`, `secretWordsHideButton`. |

---

### Implementation Notes

**Bell animation sequencing**: The shake must fire exactly once per *state change* (not continuously). Use `AnimationController` with a `addStatusListener` that resets to `forward()` only when the indicator value changes. Listening to `ref.listen(backupConfirmedProvider, ...)` and `ref.listen(unreadCountProvider, ...)` inside the widget's `ConsumerState` covers both triggers.

**Pinned notification item identity**: The backup reminder is a synthetic item, not stored in `NotificationsHistoryRepository`. It is injected at position 0 by `NotificationsNotifier.build()` when `backupConfirmed == false`. This avoids polluting the trade-event notification history and makes dismissal purely a state-flag change (no DB delete needed).

**Fully masked mnemonic**: Replace the V1 `_maskSeedPhrase()` helper (which showed first 2 + last 2 words) with a new implementation that returns `List.filled(12, '•••').join(' ')` when `_isHidden == true`. The "Show" button toggles `_isHidden` to `false` and also sets `_showCheckbox = true` in the same `setState` call.

**Checkbox animation**: Use `AnimatedOpacity` + `AnimatedSize` wrapping the checkbox row, animating from `height: 0 / opacity: 0` to fully visible over 200 ms when `_showCheckbox` transitions from false to true.

**Backup reset on new identity**: `IdentityService.regenerate()` atomically writes the new mnemonic before clearing old metadata. After `regenerate()` returns, the Dart layer calls `backupReminderProvider.notifier.showBackupReminder()` to re-activate the badge.

**Constitution compliance**:
- ⚠️ **I (Rust Core)**: `backup_confirmed` is currently tracked in Dart (SharedPreferences). Migration to Rust storage is planned future work once the persistence layer supports it.
- ✅ **II (Privacy)**: No analytics. Confirmed state is local-only; never transmitted.
- ✅ **IV (Offline-First)**: Flag is in SharedPreferences; readable with no connectivity.
- ✅ **V (Multi-Platform)**: SharedPreferences works on all Flutter platforms without separate code paths.
- ✅ **VI (Simplicity)**: Single `BackupReminderNotifier`, two SharedPreferences keys, pre-seeded at startup. No new architectural layers.

---

### Acceptance Test Checklist

- [ ] Fresh install: identity is generated before walkthrough renders; `backupReminderProvider` is `false`.
- [ ] Bell shows red dot immediately after walkthrough is dismissed; no number badge.
- [ ] Bell plays shake animation once when red dot first appears.
- [ ] Notifications screen: backup reminder is pinned at position 0; swipe-to-dismiss is disabled; "Mark all as read" and "Clear all" do not remove it.
- [ ] Tapping backup reminder navigates to `/key_management` (Account screen).
- [ ] Account screen: Secret Words card shows all 12 words as `•••` by default.
- [ ] Tapping "Show": all 12 words appear; checkbox appears (animated in); backup reminder notification is still present; bell still shows red dot.
- [ ] Tapping checkbox: `confirmBackupComplete()` called; backup reminder removed; red dot gone; bell switches to numbered badge mode (or static if no unread notifications).
- [ ] State survives app restart: confirmed flag persists across sessions (SharedPreferences).
- [ ] "Generate New User": `IdentityService.regenerate()` + `showBackupReminder()` called; backup reminder re-appears; red dot re-appears.

---

## Complexity Tracking

No constitution violations identified. Architecture matches exactly what the constitution prescribes: Rust core + Flutter shell + single bridge. The storage trait with two backends (SQLite native / IndexedDB web) is required by Constitution Principle V (multi-platform from day one) — no alternative satisfies both native and web without violating Principle I.
