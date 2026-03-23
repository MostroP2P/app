# Tasks: Mostro Mobile v2 — P2P Exchange Client

**Input**: Design documents from `/specs/001-mostro-p2p-client/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/

**Organization**: Tasks grouped by user story to enable independent implementation and testing. US1+US2 share a phase because buy/sell flows share the same state machine, stepper, and order model.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story (US1–US13)
- Exact file paths from plan.md project structure

---

## Phase 1: Setup

**Purpose**: Project initialization and basic structure

- [ ] T001 Create Flutter project structure with `lib/main.dart`, `lib/src/` directories per plan.md
- [ ] T002 Create Rust workspace in `rust/` with `Cargo.toml` — dependencies: nostr-sdk 0.44+, mostro-core, sqlx (sqlite), serde, thiserror, tracing, tokio, chacha20poly1305, bip32
- [ ] T003 Configure `flutter_rust_bridge.yaml` and `rust_builder/` (Cargokit integration)
- [ ] T004 [P] Add Flutter dependencies to `pubspec.yaml`: flutter_rust_bridge, riverpod, go_router, flutter_secure_storage, local_auth, flutter_local_notifications, qr_code_scanner
- [ ] T005 [P] Configure `rust/src/lib.rs` with module declarations for api/, core/, db/, platform/
- [ ] T006 [P] Set up `wasm32-unknown-unknown` target support in `rust/Cargo.toml` with feature-gated deps (tokio native, wasm-bindgen-futures web)
- [ ] T007 Run `flutter_rust_bridge_codegen generate` and verify Dart bindings compile
- [ ] T008 [P] Set up linting: `clippy.toml` for Rust, `analysis_options.yaml` for Flutter
- [ ] T009 [P] Create `lib/src/l10n/` with initial English ARB file and l10n configuration

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T010 Implement shared types in `rust/src/api/types.rs` — all enums (OrderKind, OrderStatus, TradeRole, BuyerStep, SellerStep, TradeStep, etc.) and structs (OrderInfo, TradeInfo, ChatMessage, RelayInfo, etc.) per contracts/types.md
- [ ] T011 Implement storage trait in `rust/src/db/storage.rs` — async CRUD interface for all entities (Identity, Order, Trade, Message, Relay, Dispute, Settings, MessageQueue, NwcWallet, FileAttachment, Rating)
- [ ] T012 [P] Implement SQLite storage backend in `rust/src/db/sqlite.rs` — implements storage trait using sqlx, all table creation and migrations in `rust/src/db/migrations/`
- [ ] T013 [P] Implement IndexedDB storage backend in `rust/src/db/indexeddb.rs` — WASM-only implementation of storage trait using indexed_db_futures
- [ ] T014 Implement platform runtime in `rust/src/platform/native.rs` (tokio) and `rust/src/platform/web.rs` (wasm-bindgen-futures) with feature-gated async spawning
- [ ] T015 Implement NIP-59 Gift Wrap module in `rust/src/core/gift_wrap.rs` — create rumor, seal (Kind 13), wrap (Kind 1059), unwrap and decrypt
- [ ] T016 Implement BIP-32 key derivation in `rust/src/core/key_derivation.rs` — path `m/44'/1237'/38383'/0/N`, derive master key (N=0) and trade keys (N≥1), ECDH shared key computation
- [ ] T017 Implement Mostro protocol handler in `rust/src/core/protocol.rs` — message construction/parsing using mostro-core types, action enum mapping, message format `{"order": {"version": 1, ...}}`
- [ ] T018 [P] Implement trade state machine in `rust/src/core/trade_state.rs` — order status transitions (Pending→WaitingBuyerInvoice→...→Success), timeout tracking, buyer/seller step mapping
- [ ] T019 [P] Implement offline message queue in `rust/src/core/message_queue.rs` — queue events when offline, flush on reconnect, retry logic with max attempts
- [ ] T020 Implement Nostr client API in `rust/src/api/nostr.rs` — initialize with relays, connect/disconnect, subscribe to Kind 38383 orders and Kind 1059 gift wraps, publish events, connection state stream
- [ ] T021 Implement `rust/src/db/mod.rs` — feature-gated module that exports SQLite on native and IndexedDB on web
- [ ] T022 [P] Create responsive scaffold widget in `lib/src/widgets/responsive_scaffold.dart` — breakpoints (<600px mobile, 600-1200px tablet, >1200px desktop), BottomNavigationBar vs NavigationRail
- [ ] T023 [P] Create layout variants in `lib/src/layouts/mobile_layout.dart`, `lib/src/layouts/tablet_layout.dart`, `lib/src/layouts/desktop_layout.dart`
- [ ] T024 Set up go_router navigation in `lib/src/routing/app_router.dart` — all 9 screens with routes, deep link support for `mostro://order/<id>`
- [ ] T025 [P] Create connection provider in `lib/src/providers/connection_provider.dart` — wraps Rust on_connection_state_changed stream, exposes ConnectionState to UI
- [ ] T026 [P] Create layout provider in `lib/src/providers/layout_provider.dart` — current breakpoint/layout mode from MediaQuery

**Checkpoint**: Foundation ready — user story implementation can begin

---

## Phase 3: User Story 3 — Onboarding & Identity Setup (P1)

**Goal**: New user creates/imports identity, sets up security, connects to relays, reaches home screen.

**Independent Test**: Install app → complete onboarding → arrive at home screen with working identity.

### Implementation for User Story 3

- [ ] T027 [US3] Implement identity API in `rust/src/api/identity.rs` — create_identity (BIP-39 mnemonic + BIP-32 derivation), import_from_mnemonic (with optional recovery flag), import_from_nsec, get_identity, delete_identity, derive_trade_key, get_trade_key per contracts/identity.md
- [ ] T028 [US3] Implement set_pin, enable_biometric, unlock functions in `rust/src/api/identity.rs` — PIN validation (4-8 digits), biometric availability check, unlock with max attempts
- [ ] T029 [US3] Implement export_encrypted_backup in `rust/src/api/identity.rs` — encrypt identity with passphrase, NIP-49 compatible format
- [ ] T030 [US3] Create identity provider in `lib/src/providers/identity_provider.dart` — wraps Rust identity API, exposes IdentityInfo stream, manages onboarding state
- [ ] T031 [US3] Create onboarding screen in `lib/src/screens/onboarding_screen.dart` — welcome page, "Create New" vs "Import Existing" choice, mnemonic display/confirmation, mnemonic input (import), optional PIN/biometric setup
- [ ] T032 [US3] Create splash screen in `lib/src/screens/splash_screen.dart` — app loading, check for existing identity, PIN/biometric unlock if set, route to onboarding or home
- [ ] T033 [US3] Wire relay initialization into onboarding flow — on identity creation/import, call initialize() with default relay list, verify connection before proceeding to home

**Checkpoint**: User Story 3 complete — new users can onboard and reach the home screen

---

## Phase 4: User Stories 1 + 2 + 4 — Buy/Sell Trades & Order Browsing (P1+P2)

**Goal**: Users can browse orders, create orders, take orders, and complete buy/sell trade flows end-to-end with visual progress stepper.

**Independent Test**: Browse orders → take/create order → complete full buy or sell flow → trade appears in history.

### Implementation for User Stories 1, 2, 4

- [ ] T034 [US4] Implement orders API in `rust/src/api/orders.rs` — get_orders (with filters), get_order, create_order, take_order, cancel_order, on_orders_updated stream, on_order_status_changed stream per contracts/orders.md
- [ ] T035 [US1] Implement buyer trade actions in `rust/src/api/orders.rs` — submit_buyer_invoice (AddInvoice action), mark_fiat_sent (FiatSent action), on_trade_step_changed stream
- [ ] T036 [US2] Implement seller trade actions in `rust/src/api/orders.rs` — confirm_fiat_received (Release action), on_trade_step_changed stream
- [ ] T037 [US1] [US2] Implement trade timeout tracking in `rust/src/api/orders.rs` — on_trade_timeout_tick stream, countdown per state using Mostro expirationSeconds
- [ ] T038 [P] [US4] Create orders provider in `lib/src/providers/orders_provider.dart` — wraps Rust orders API, exposes filtered order list, manages loading/error states
- [ ] T039 [P] [US1] [US2] Create active trade provider in `lib/src/providers/active_trade_provider.dart` — wraps trade step stream, manages current trade state, countdown timer state
- [ ] T040 [US4] Create order card widget in `lib/src/widgets/order_card.dart` — displays order summary (type, amount, price, currency, payment method, creator reputation)
- [ ] T041 [US4] Create home screen in `lib/src/screens/home_screen.dart` — order list with pull-to-refresh, filter bar (buy/sell, currency, payment method), offline indicator, FAB for create order
- [ ] T042 [US4] Create order detail screen in `lib/src/screens/order_detail_screen.dart` — full order details, "Take Order" button (for takers), "Cancel Order" button (for creators)
- [ ] T043 [US2] Create order creation screen in `lib/src/screens/create_order_screen.dart` — buy/sell selector, amount input (sats/fiat), price type (market/fixed), payment method, premium, review + publish
- [ ] T044 [US1] [US2] Create trade stepper widget in `lib/src/widgets/trade_stepper.dart` — horizontal (desktop) / vertical (mobile), buyer steps vs seller steps, current step highlight, completed checkmarks, tappable for details/timestamps, animated transitions, dispute red indicator
- [ ] T045 [US1] [US2] Create countdown timer widget in `lib/src/widgets/countdown_timer.dart` — displays seconds remaining for current trade state, visual urgency at low time
- [ ] T046 [US1] [US2] Create active trade screen in `lib/src/screens/active_trade_screen.dart` — trade stepper, countdown timer, action buttons (pay invoice / fiat sent / confirm received / cancel), invoice display (QR + copy), chat panel placeholder
- [ ] T047 [US1] Create QR scanner widget in `lib/src/widgets/qr_scanner.dart` — native camera on mobile, paste-from-clipboard + file upload fallback on web/desktop
- [ ] T048 [US1] [US2] Integrate NWC auto-pay into active trade screen — when hold invoice presented and NWC connected, auto-pay via `rust/src/api/nwc.rs` pay_invoice, fallback to manual QR/copy if NWC fails

**Checkpoint**: US1+US2+US4 complete — users can browse, create, take orders and complete full trade flows

---

## Phase 5: User Story 5 — Encrypted P2P Chat (P2)

**Goal**: Trade parties exchange encrypted messages and file attachments during active trades.

**Independent Test**: Two parties in a trade send/receive text messages and file attachments in real time.

### Implementation for User Story 5

- [ ] T049 [US5] Implement messages API in `rust/src/api/messages.rs` — send_message (sharedKey ECDH encryption), get_messages, mark_as_read, get_unread_count, on_new_message stream per contracts/messages.md
- [ ] T050 [US5] Implement file crypto in `rust/src/core/file_crypto.rs` — ChaCha20-Poly1305 encrypt/decrypt, blob structure [nonce:12][encrypted_data][auth_tag:16]
- [ ] T051 [US5] Implement Blossom client in `rust/src/core/blossom.rs` — upload encrypted blob (HTTP PUT), download blob, server list (blossom.primal.net, blossom.band, nostr.media, etc.), retry logic
- [ ] T052 [US5] Implement file attachment functions in `rust/src/api/messages.rs` — send_file (encrypt + upload + send URL), download_attachment (download + decrypt), get_attachment_status, on_attachment_progress stream per contracts/messages.md
- [ ] T053 [P] [US5] Create messages provider in `lib/src/providers/messages_provider.dart` — wraps Rust messages API, exposes message list stream, unread count, attachment progress
- [ ] T054 [US5] Create chat panel widget in `lib/src/widgets/chat_panel.dart` — message list, text input, send button, attachment button (file picker), inline image previews, download buttons for docs/videos
- [ ] T055 [P] [US5] Create file attachment widget in `lib/src/widgets/file_attachment.dart` — image preview (auto-download), document/video download button, progress indicator, file type icon
- [ ] T056 [US5] Integrate chat panel into active trade screen `lib/src/screens/active_trade_screen.dart` — alongside trade stepper, collapsible on mobile, side panel on desktop

**Checkpoint**: US5 complete — trade parties can chat with text and encrypted file attachments

---

## Phase 6: User Story 6 — Dispute Resolution (P2)

**Goal**: Either party initiates dispute, submits evidence, receives admin messages, sees resolution.

**Independent Test**: Open dispute → submit evidence → receive admin message → see resolution.

### Implementation for User Story 6

- [ ] T057 [US6] Implement disputes API in `rust/src/api/disputes.rs` — open_dispute, submit_evidence, get_dispute, on_dispute_updated stream per contracts/disputes.md. Dispute chat uses tradeKey (not sharedKey)
- [ ] T058 [US6] Create dispute screen in `lib/src/screens/dispute_screen.dart` — dispute status indicator, evidence submission (text), admin chat (separate from P2P chat), resolution display
- [ ] T059 [US6] Update trade stepper to show dispute state — red indicator, paused stepper, "Disputed" overlay on current step in `lib/src/widgets/trade_stepper.dart`
- [ ] T060 [US6] Add "Open Dispute" button to active trade screen `lib/src/screens/active_trade_screen.dart` — confirmation dialog, navigate to dispute screen on initiation

**Checkpoint**: US6 complete — dispute flow works end-to-end

---

## Phase 7: User Story 13 — Cooperative Cancel (P2)

**Goal**: Either party requests cancel, counterparty accepts/ignores, trade canceled with funds returned.

**Independent Test**: Request cancel → counterparty accepts → trade shows as "Cooperatively Canceled".

### Implementation for User Story 13

- [ ] T061 [US13] Implement cooperative cancel in `rust/src/api/orders.rs` — request_cooperative_cancel, accept_cooperative_cancel, on_cooperative_cancel_requested stream per contracts/orders.md
- [ ] T062 [US13] Add cooperative cancel UI to active trade screen `lib/src/screens/active_trade_screen.dart` — "Request Cancel" button, incoming cancel request notification with "Accept" / "Ignore", warning dialog if fiat already sent
- [ ] T063 [US13] Update trade stepper and history to show CooperativelyCanceled state in `lib/src/widgets/trade_stepper.dart`

**Checkpoint**: US13 complete — cooperative cancellation works

---

## Phase 8: User Story 9 — Multi-Platform Responsive Experience (P2)

**Goal**: App adapts layout to phone/tablet/desktop with graceful platform feature fallbacks.

**Independent Test**: Same app renders correctly at all three breakpoints; QR fallback works on web.

### Implementation for User Story 9

- [ ] T064 [US9] Implement mobile layout in `lib/src/layouts/mobile_layout.dart` — single column, BottomNavigationBar, full-screen navigation
- [ ] T065 [P] [US9] Implement tablet layout in `lib/src/layouts/tablet_layout.dart` — optional master-detail, adaptive navigation
- [ ] T066 [P] [US9] Implement desktop layout in `lib/src/layouts/desktop_layout.dart` — multi-panel (NavRail + order list + trade panel), persistent navigation rail
- [ ] T067 [US9] Update all screens to use responsive scaffold — wrap each screen with responsive_scaffold.dart, ensure content adapts to breakpoint
- [ ] T068 [US9] Implement platform-aware QR scanner fallbacks in `lib/src/widgets/qr_scanner.dart` — WebRTC camera on web (if available), paste-from-clipboard fallback, image upload fallback
- [ ] T069 [US9] Implement platform-aware notification handling in `rust/src/platform/notifications.rs` — FCM on Android, APNs on iOS, Service Worker on web, background process on desktop

**Checkpoint**: US9 complete — app works on all platforms with correct layouts

---

## Phase 9: User Story 10 — Session Recovery (P2)

**Goal**: User recovers active trades/disputes by importing mnemonic.

**Independent Test**: Import mnemonic → daemon returns active trades → local state reconstructed.

### Implementation for User Story 10

- [ ] T070 [US10] Implement session recovery in `rust/src/api/identity.rs` — when import_from_mnemonic called with `recover: true`, send Action.restore to Mostro daemon, process response (order IDs + disputes), sync trade key index, reconstruct local DB
- [ ] T071 [US10] Add on_recovery_progress stream in `rust/src/api/identity.rs` — emit phases (connecting, fetching_orders, syncing) with current/total counts
- [ ] T072 [US10] Add recovery option to onboarding import flow in `lib/src/screens/onboarding_screen.dart` — checkbox "Recover active trades", progress indicator during recovery, privacy mode warning
- [ ] T073 [US10] Update identity provider in `lib/src/providers/identity_provider.dart` — handle recovery progress stream, show recovery status to user

**Checkpoint**: US10 complete — session recovery works in reputation mode

---

## Phase 10: User Story 11 — Reputation & Rating (P2)

**Goal**: Rate counterparty after trade; privacy mode hides reputation.

**Independent Test**: Complete trade → rate counterparty → rating acknowledged. Toggle privacy mode.

### Implementation for User Story 11

- [ ] T074 [US11] Implement reputation API in `rust/src/api/reputation.rs` — submit_rating (rate action), get_privacy_mode, set_privacy_mode, get_rating_for_trade, on_rating_received stream per contracts/reputation.md
- [ ] T075 [P] [US11] Create reputation provider in `lib/src/providers/reputation_provider.dart` — wraps Rust reputation API, privacy mode state, rating prompt logic
- [ ] T076 [US11] Create rating dialog widget in `lib/src/widgets/rating_dialog.dart` — score selector, submit button, shown after trade success (only in reputation mode)
- [ ] T077 [US11] Integrate rating prompt into trade completion flow — after trade completes with Success in active_trade_screen, show rating dialog if not in privacy mode
- [ ] T078 [US11] Display reputation on order cards — show creator reputation score in `lib/src/widgets/order_card.dart` and `lib/src/screens/order_detail_screen.dart` (if available)

**Checkpoint**: US11 complete — reputation system works, privacy mode hides it

---

## Phase 11: User Story 7 — Settings & Relay Management (P3)

**Goal**: Manage relays, identity, wallet, preferences (theme, language, security).

**Independent Test**: Add/remove relay, connect NWC wallet, change theme, export backup.

### Implementation for User Story 7

- [ ] T079 [US7] Implement NWC client in `rust/src/core/nwc_client.rs` — parse NWC URI, connect to wallet relay, pay_invoice (NIP-47), get_info, connection status monitoring
- [ ] T080 [US7] Implement NWC API in `rust/src/api/nwc.rs` — connect_wallet, disconnect_wallet, get_wallet, get_balance, pay_invoice, on_wallet_status_changed stream per contracts/nwc.md
- [ ] T081 [US7] Implement relay auto-sync in `rust/src/api/nostr.rs` — enable_relay_auto_sync (subscribe to Mostro Kind 10002), get_mostro_settings, on_relay_auto_synced stream per contracts/nostr.md
- [ ] T082 [US7] Implement push token registration in `rust/src/api/nostr.rs` — register_push_token, push server integration per contracts/nostr.md
- [ ] T083 [P] [US7] Create NWC provider in `lib/src/providers/nwc_provider.dart` — wraps Rust NWC API, wallet status, balance display
- [ ] T084 [US7] Create settings screen in `lib/src/screens/settings_screen.dart` — sections: Identity (view pubkey, export backup, delete), Wallet (NWC connect/disconnect, balance), Relays (list with status, add/remove, auto-sync toggle), Preferences (theme, language, privacy mode), Security (PIN, biometric)
- [ ] T085 [US7] Implement theme switching — dark/light/system theme in settings, persist to Settings entity, apply via Flutter ThemeData

**Checkpoint**: US7 complete — settings fully functional

---

## Phase 12: User Story 8 — Trade History (P3)

**Goal**: View chronological list of past trades with details.

**Independent Test**: Complete a trade → see it in history with correct details.

### Implementation for User Story 8

- [ ] T086 [US8] Implement get_trade_history in `rust/src/api/orders.rs` — query completed trades from DB, return Vec<TradeHistoryEntry> sorted by completion time
- [ ] T087 [US8] Create history screen in `lib/src/screens/history_screen.dart` — chronological trade list, tap for details (date, amounts, payment method, outcome, counterparty), empty state with guidance
- [ ] T088 [US8] Add history tab to navigation — add route in `lib/src/routing/app_router.dart`, add to BottomNavigationBar/NavigationRail

**Checkpoint**: US8 complete — trade history viewable

---

## Phase 13: User Story 12 — Deep Links & Order Sharing (P3)

**Goal**: Share orders via deep links/QR; clicking link opens order detail.

**Independent Test**: Share order link → click on another device → app opens to that order.

### Implementation for User Story 12

- [ ] T089 [US12] Implement deep link parsing in `rust/src/core/deep_links.rs` — parse `mostro://order/<id>` URIs, validate format
- [ ] T090 [US12] Implement share_order and resolve_deep_link in `rust/src/api/orders.rs` — generate deep link + QR data, parse incoming URIs per contracts/orders.md
- [ ] T091 [US12] Add share button to order detail screen `lib/src/screens/order_detail_screen.dart` — generate deep link, show QR code, system share sheet
- [ ] T092 [US12] Wire deep link handling into `lib/src/routing/app_router.dart` — handle `mostro://` scheme on app launch and while running, navigate to order detail

**Checkpoint**: US12 complete — order sharing and deep links work

---

## Phase 14: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T093 [P] Run `cargo clippy -- -D warnings` and fix all warnings in `rust/`
- [ ] T094 [P] Run `flutter analyze` and fix all issues in `lib/`
- [ ] T095 [P] Add doc comments to all public Rust API functions in `rust/src/api/*.rs`
- [ ] T096 [P] Verify ephemeral trade data cleanup — after trade completion, clear sensitive data per Constitution Principle II in `rust/src/core/trade_state.rs`
- [ ] T097 [P] Add accessibility labels (semantics) to all interactive widgets in `lib/src/widgets/` and `lib/src/screens/`
- [ ] T098 Test responsive layout at all three breakpoints (mobile <600px, tablet 600-1200px, desktop >1200px)
- [ ] T099 Verify NIP-59 encryption — no plaintext message content observable on network, test with relay inspection
- [ ] T100 Test offline mode — disconnect network, verify cached orders display, messages queue, reconnect and flush
- [ ] T101 Test with at least two different Mostro daemon instances to confirm no single-daemon dependency
- [ ] T102 Run `cargo test` and `flutter test` — all tests pass
- [ ] T103 Run quickstart.md validation — follow developer setup guide end-to-end on a clean environment

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **US3 Onboarding (Phase 3)**: Depends on Phase 2 — BLOCKS US1/US2/US4 (need identity)
- **US1+US2+US4 Trading (Phase 4)**: Depends on Phase 3 (identity required)
- **US5 Chat (Phase 5)**: Depends on Phase 4 (need active trade)
- **US6 Disputes (Phase 6)**: Depends on Phase 4 (need active trade)
- **US13 Cooperative Cancel (Phase 7)**: Depends on Phase 4 (need active trade)
- **US9 Responsive (Phase 8)**: Depends on Phase 2 (can start after foundation, but best after Phase 4 for testing)
- **US10 Recovery (Phase 9)**: Depends on Phase 3 (identity module) + Phase 4 (trade model)
- **US11 Reputation (Phase 10)**: Depends on Phase 4 (need completed trades)
- **US7 Settings (Phase 11)**: Depends on Phase 2 (can start early, but NWC needs Phase 4 for testing)
- **US8 History (Phase 12)**: Depends on Phase 4 (need completed trades)
- **US12 Deep Links (Phase 13)**: Depends on Phase 4 (need order detail screen)
- **Polish (Phase 14)**: Depends on all previous phases

### User Story Dependencies

- **US3 (P1)**: Standalone — gateway for all other stories
- **US1+US2 (P1)**: Depend on US3 for identity
- **US4 (P2)**: Integrated with US1+US2 in Phase 4
- **US5 (P2)**: Depends on US1+US2 (active trade context)
- **US6 (P2)**: Depends on US1+US2 (active trade context)
- **US9 (P2)**: Independent of stories, depends on foundation
- **US10 (P2)**: Depends on US3 + US1/US2
- **US11 (P2)**: Depends on US1+US2 (completed trade)
- **US13 (P2)**: Depends on US1+US2 (active trade context)
- **US7 (P3)**: Mostly independent, NWC testing needs US1
- **US8 (P3)**: Depends on US1+US2 (completed trades to display)
- **US12 (P3)**: Depends on US4 (order detail screen)

### Within Each User Story

- Models/types before services/API
- Rust API before Flutter providers
- Providers before UI screens/widgets
- Core implementation before integration

### Parallel Opportunities

- All Setup tasks marked [P] can run in parallel
- All Foundational tasks marked [P] can run in parallel
- After Phase 4 completes: US5, US6, US7, US8, US9, US10, US11, US12, US13 can largely proceed in parallel
- Within each story: [P] tasks can run simultaneously

---

## Parallel Example: Phase 4 (Trading)

```bash
# Step 1: Rust API (sequential within, parallel across modules)
T034: Orders API (get, create, take, cancel)
T035: Buyer trade actions (parallel with T036)
T036: Seller trade actions (parallel with T035)
T037: Timeout tracking (after T034)

# Step 2: Flutter providers (parallel)
T038: Orders provider
T039: Active trade provider

# Step 3: UI widgets and screens (some parallel)
T040+T044+T045+T047: Widgets (parallel — different files)
T041+T042+T043+T046: Screens (sequential — share navigation)
T048: NWC integration (after T046)
```

---

## Implementation Strategy

### MVP First (Phase 1–4)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks everything)
3. Complete Phase 3: US3 Onboarding
4. Complete Phase 4: US1+US2+US4 Trading
5. **STOP and VALIDATE**: End-to-end buy and sell trades work
6. Deploy/demo as MVP

### Incremental Delivery

1. Setup + Foundational + US3 → Identity works
2. + US1+US2+US4 → Full trading (MVP!)
3. + US5 → Chat during trades
4. + US6 + US13 → Disputes + cooperative cancel
5. + US9 → Responsive layouts polished
6. + US10 + US11 → Recovery + reputation
7. + US7 → Full settings
8. + US8 + US12 → History + deep links
9. + Polish → Release candidate

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps to user story for traceability
- Test tasks T098–T103 defined for validation and quality gates
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- Constitution compliance verified at each phase boundary
