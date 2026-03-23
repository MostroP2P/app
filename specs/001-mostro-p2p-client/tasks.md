# Tasks: Mostro Mobile v2 — P2P Exchange Client

**Input**: Design documents from `/specs/001-mostro-p2p-client/`
**Prerequisites**: plan.md, spec.md, data-model.md, contracts/, research.md, quickstart.md

**Tests**: Not explicitly requested — test tasks omitted. Add via `/speckit.checklist` if needed.

**Organization**: Tasks grouped by user story. US1+US2 (Buy+Sell) combined as they share the same trade lifecycle.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Project initialization, Rust crate creation, Flutter scaffolding

- [ ] T001 Initialize Flutter project at repo root with all 6 platform targets (iOS, Android, Web, macOS, Windows, Linux — directories: ios/, android/, web/, macos/, windows/, linux/) per plan.md
- [ ] T002 Create Rust crate at rust/ with Cargo.toml including dependencies: nostr-sdk 0.44+, mostro-core, bip32, bip39, chacha20poly1305, sqlx, serde, tokio
- [ ] T003 [P] Configure flutter_rust_bridge v2 with rust_builder/ cargokit integration per quickstart.md
- [ ] T004 [P] Configure linting: cargo clippy -D warnings, flutter analyze, rustfmt, dart format per constitution quality standards
- [ ] T005 [P] Create lib/ directory structure: app.dart, providers/, screens/, widgets/, theme/, l10n/, router.dart per plan.md project structure
- [ ] T006 [P] Create rust/src/ directory structure: api/, protocol/, storage/, crypto/, network/ per plan.md project structure
- [ ] T007 Add Flutter dependencies to pubspec.yaml: flutter_riverpod, go_router, flutter_secure_storage, share_plus, mobile_scanner per plan.md

**Checkpoint**: Project compiles on all platforms, bridge generates Dart bindings from empty Rust API

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core infrastructure that MUST be complete before ANY user story

**CRITICAL**: No user story work can begin until this phase is complete

- [ ] T008 Implement storage trait in rust/src/storage/mod.rs with async CRUD operations for all entities from data-model.md
- [ ] T009 [P] Implement SQLite storage backend in rust/src/storage/sqlite.rs with sqlx, all table schemas from data-model.md (Identity, Order, Trade, Message, Relay, Dispute, Settings, MessageQueue, NwcWallet, FileAttachment, Rating)
- [ ] T010 [P] Implement IndexedDB storage backend in rust/src/storage/indexeddb.rs with indexed_db_futures for web platform, same trait interface
- [ ] T011 Create database migrations in rust/src/storage/migrations/ for all 11 entities from data-model.md
- [ ] T012 Implement BIP-32/39 key derivation in rust/src/crypto/keys.rs: mnemonic generation (12-word), seed derivation, hierarchical key path m/44'/1237'/38383'/0/N per contracts/identity.md
- [ ] T013 [P] Implement platform secure storage bridge in rust/src/crypto/secure_store.rs for encrypted mnemonic/key persistence
- [ ] T014 Implement NIP-59 Gift Wrap in rust/src/protocol/gift_wrap.rs: three-layer encryption (Rumor kind 38383 → Seal kind 13 → Gift Wrap kind 1059) with NIP-44 per protocol reference
- [ ] T015 [P] Implement Nostr relay pool in rust/src/network/relay_pool.rs: connect, subscribe (kind 38383, 1059, 10002), publish, reconnect with backoff per contracts/nostr.md
- [ ] T016 [P] Implement offline message queue in rust/src/network/message_queue.rs: queue outgoing NIP-59 events when offline, send on reconnect per data-model.md MessageQueue entity
- [ ] T017 Implement order state machine in rust/src/protocol/state_machine.rs: all 15 states (Pending, WaitingBuyerInvoice, WaitingPayment, Active, FiatSent, SettledHoldInvoice, Success, PaymentFailed, Canceled, Expired, CooperativelyCanceled, CanceledByAdmin, SettledByAdmin, CompletedByAdmin, Dispute), valid transitions, and action-to-state mapping per protocol reference
- [ ] T018 [P] Implement protocol action builders in rust/src/protocol/actions.rs: new-order, take-sell, take-buy, pay-invoice, add-invoice, fiat-sent, release, cancel, dispute, rate, restore per protocol actions table
- [ ] T019 Create Riverpod providers skeleton in lib/providers/: identity_provider.dart, orders_provider.dart, trade_provider.dart, messages_provider.dart, relay_provider.dart, wallet_provider.dart, settings_provider.dart per plan.md
- [ ] T020 [P] Implement responsive layout scaffold in lib/widgets/responsive_layout.dart: three breakpoints (<600px mobile + BottomNav, 600-1200px tablet, >1200px desktop + NavigationRail) per contracts/types.md and spec US9
- [ ] T021 [P] Implement dark/light theme definitions in lib/theme/: AppTheme with semantic color tokens for both themes, ThemeMode (System/Dark/Light), WCAG AA contrast per spec FR-019a-f and DESIGN_SYSTEM.md
- [ ] T022 Configure go_router in lib/router.dart with routes for all screens: onboarding, home, order_detail, create_order, trade, dispute, history, settings per plan.md

**Checkpoint**: Foundation ready — Rust core compiles, bridge generates bindings, storage works, NIP-59 encrypts/decrypts, relay connects, theme renders

---

## Phase 3: User Story 3 — Onboarding & Identity Setup (Priority: P1) MVP

**Goal**: New user creates identity or imports mnemonic, sets optional PIN/biometric, reaches home screen

**Independent Test**: Install app → complete onboarding → arrive at home screen with connected relays

### Implementation for User Story 3

- [ ] T023 [US3] Implement identity creation API in rust/src/api/identity.rs: create_identity() generates mnemonic, derives master key, stores encrypted per contracts/identity.md
- [ ] T024 [US3] Implement identity import API in rust/src/api/identity.rs: import_from_mnemonic(), import_from_private_key() per contracts/identity.md
- [ ] T025 [P] [US3] Implement identity export API in rust/src/api/identity.rs: export_backup() returns encrypted backup per contracts/identity.md
- [ ] T026 [P] [US3] Implement PIN/biometric unlock in rust/src/api/identity.rs: setup_pin(), enable_biometric(), verify_unlock() per contracts/identity.md
- [ ] T027 [US3] Implement Nostr init API in rust/src/api/nostr.rs: initialize() connects to default relays, starts subscriptions per contracts/nostr.md
- [ ] T028 [US3] Create welcome screen in lib/screens/onboarding/welcome_screen.dart: "Create New Identity" and "Import Existing" buttons per spec US3 scenario 1
- [ ] T029 [US3] Create mnemonic display screen in lib/screens/onboarding/mnemonic_screen.dart: show 12-word phrase, confirm backup prompt per spec US3 scenario 2
- [ ] T030 [US3] Create import screen in lib/screens/onboarding/import_screen.dart: mnemonic word input with validation, private key paste per spec US3 scenario 3
- [ ] T031 [US3] Create PIN setup screen in lib/screens/onboarding/pin_screen.dart: optional PIN entry, biometric toggle, skip option per spec US3 scenario 4
- [ ] T032 [US3] Wire onboarding flow in lib/providers/identity_provider.dart: manage onboarding state, call Rust APIs, navigate to home on completion per spec US3 scenario 5

**Checkpoint**: User can create/import identity, optionally set PIN, reach home screen with relays connected

---

## Phase 4: User Stories 1+2 — Buy & Sell Trade Lifecycle (Priority: P1) MVP

**Goal**: Complete buy and sell flows end-to-end with progress indicator

**Independent Test**: Two users complete a full trade from order creation/take to settlement

### Implementation for User Stories 1+2

- [ ] T033 [US1] Implement order creation API in rust/src/api/orders.rs: create_order() with NewOrderParams (fixed + range amounts), publish via NIP-59 per contracts/orders.md
- [ ] T034 [US1] Implement order fetching API in rust/src/api/orders.rs: get_orders(), get_order(), stream on_orders_updated() from kind 38383 events per contracts/orders.md
- [ ] T035 [US1] Implement take order API in rust/src/api/orders.rs: take_order() sends TakeBuy/TakeSell action, creates local Trade record per contracts/orders.md
- [ ] T036 [US1] Implement trade action APIs in rust/src/api/orders.rs: submit_buyer_invoice(), mark_fiat_sent(), confirm_fiat_received() per contracts/orders.md
- [ ] T037 [US1] Implement trade state streams in rust/src/api/orders.rs: on_trade_step_changed(), on_order_status_changed(), on_trade_timeout_tick() per contracts/orders.md
- [ ] T038 [P] [US1] Implement cancel order API in rust/src/api/orders.rs: cancel_order() for own untaken orders per contracts/orders.md
- [ ] T039 [US1] Create order list screen in lib/screens/home/home_screen.dart: display orders with OrderCard widgets, filter controls (buy/sell, currency, payment method) per spec US4 scenarios 1-3
- [ ] T040 [P] [US1] Create order card widget in lib/widgets/order_card.dart: show type, amount/range, price, payment method, premium, creator reputation per spec US1 scenario 1
- [ ] T041 [US1] Create order detail screen in lib/screens/order_detail/order_detail_screen.dart: full order info + "Take Order" button per spec US1 scenario 1
- [ ] T042 [US2] Create order creation screen in lib/screens/create_order/create_order_screen.dart: form for type, amount (fixed/range), currency, payment method, premium per spec US2 scenario 1
- [ ] T043 [US1] Create trade screen in lib/screens/trade/trade_screen.dart: active trade view with progress indicator, action buttons, countdown timer per spec US1 scenarios 2-6
- [ ] T044 [P] [US1] Create trade progress indicator widget in lib/widgets/trade_progress.dart: visual stepper showing BuyerStep/SellerStep with current/completed/remaining, responsive (vertical mobile, horizontal desktop) per spec US1 scenario 6
- [ ] T045 [P] [US1] Create QR scanner widget in lib/widgets/qr_scanner.dart: camera scan on mobile, paste/upload fallback on web per spec FR-022
- [ ] T046 [US1] Wire trade providers in lib/providers/trade_provider.dart: manage active trade state, listen to Rust streams, update UI per spec US1+US2 all scenarios
- [ ] T047 [US1] Wire orders provider in lib/providers/orders_provider.dart: fetch/cache orders, apply filters, listen to Rust streams per spec US4 all scenarios

**Checkpoint**: Full buy and sell trade flow works end-to-end with progress indicator. Orders can be created (fixed + range), browsed, filtered, and taken.

---

## Phase 5: User Story 4 — Browse & Filter Orders (Priority: P2)

**Goal**: Users see order book with filtering, offline cache, detail view

**Independent Test**: User opens app, sees orders, applies filters, views order detail

### Implementation for User Story 4

- [ ] T048 [US4] Implement offline order cache in rust/src/api/orders.rs: return cached orders when offline with `cached_at` staleness indicator per spec US4 scenario 4
- [ ] T049 [US4] Add offline indicator to home screen in lib/screens/home/home_screen.dart: show "offline" badge when ConnectionState is Offline, display cached orders per spec US4 scenario 4
- [ ] T050 [US4] Add currency and payment method filter chips to lib/screens/home/home_screen.dart per spec US4 scenarios 2-3

**Checkpoint**: Order book works online and offline with filtering

---

## Phase 6: User Story 5 — Encrypted P2P Chat (Priority: P2)

**Goal**: Trade counterparties exchange encrypted messages and file attachments

**Independent Test**: Two parties in an active trade send/receive text and image messages

### Implementation for User Story 5

- [ ] T051 [US5] Implement messaging API in rust/src/api/messages.rs: send_message(), get_messages(), stream on_message_received() with NIP-59 encryption via shared ECDH key per contracts/messages.md
- [ ] T052 [US5] Implement encrypted chat storage in rust/src/api/messages.rs: store messages encrypted at rest, decrypt only in memory per spec FR-045
- [ ] T053 [US5] Implement file encryption in rust/src/crypto/file_encrypt.rs: ChaCha20-Poly1305 encrypt/decrypt for attachments per contracts/messages.md
- [ ] T054 [P] [US5] Implement Blossom upload/download in rust/src/network/blossom.rs: upload encrypted blob, download by hash, fallback across multiple servers per contracts/messages.md and spec FR-047
- [ ] T055 [US5] Implement file attachment API in rust/src/api/messages.rs: send_file(), download_file() with encrypt/upload and download/decrypt per contracts/messages.md
- [ ] T056 [US5] Create chat interface in lib/screens/trade/chat_panel.dart: message list, text input, file attach button, integrated with trade screen per spec US5 scenarios 1-3
- [ ] T057 [P] [US5] Create chat bubble widget in lib/widgets/chat_bubble.dart: sender/receiver styling, timestamp, read status per spec US5
- [ ] T058 [P] [US5] Create attachment preview widget in lib/widgets/attachment_preview.dart: inline image preview for images, download button for documents/videos per spec US5 scenarios 5-6
- [ ] T059 [US5] Wire messages provider in lib/providers/messages_provider.dart: listen to Rust stream, manage chat state, handle file uploads per spec US5 scenarios 1-7

**Checkpoint**: Encrypted text and file messaging works during trades, persists across app restarts

---

## Phase 7: User Story 13 — Cooperative Cancel (Priority: P2)

**Goal**: Either party can request cancellation, counterparty accepts or ignores

**Independent Test**: One party requests cancel, other accepts, trade is canceled with funds returned

### Implementation for User Story 13

- [ ] T060 [US13] Implement cooperative cancel APIs in rust/src/api/orders.rs: request_cooperative_cancel(), accept_cooperative_cancel(), stream on_cooperative_cancel_requested() per contracts/orders.md
- [ ] T061 [US13] Add cancel request UI to trade screen in lib/screens/trade/trade_screen.dart: "Request Cancel" button, incoming cancel request dialog, accept/ignore actions per spec US13 scenarios 1-4
- [ ] T062 [US13] Add "Cooperatively Canceled" state display to trade progress indicator in lib/widgets/trade_progress.dart per spec US13 scenario 4

**Checkpoint**: Cooperative cancellation flow works end-to-end

---

## Phase 8: User Story 6 — Dispute Resolution (Priority: P2)

**Goal**: Users can initiate disputes, submit evidence, receive admin messages, see resolution

**Independent Test**: User initiates dispute on active trade, sees admin messages and resolution

### Implementation for User Story 6

- [ ] T063 [US6] Implement dispute API in rust/src/api/disputes.rs: initiate_dispute(), submit_evidence(), get_dispute(), stream on_dispute_updated() per contracts/disputes.md
- [ ] T064 [US6] Implement dispute chat in rust/src/api/disputes.rs: send_dispute_message(), get_dispute_messages() using trade key (not shared key) per contracts/disputes.md
- [ ] T065 [US6] Create dispute screen in lib/screens/dispute/dispute_screen.dart: dispute status, evidence submission, admin chat, resolution display per spec US6 scenarios 1-5
- [ ] T066 [US6] Add dispute state to trade progress indicator in lib/widgets/trade_progress.dart: distinct dispute visual (settledByAdmin, completedByAdmin, canceledByAdmin) per spec US6 scenario 5

**Checkpoint**: Dispute flow works — initiate, submit evidence, receive admin messages, see resolution

---

## Phase 9: User Story 10 — Session Recovery (Priority: P2)

**Goal**: Users restore trades and history from mnemonic on a new device

**Independent Test**: User enters mnemonic on fresh install, sees all prior trades and active disputes

### Implementation for User Story 10

- [ ] T067 [US10] Implement session recovery API in rust/src/api/identity.rs: restore_from_mnemonic() sends restore action to daemon, processes order IDs and disputes, syncs trade key index per contracts/identity.md
- [ ] T068 [US10] Add recovery flow to import screen in lib/screens/onboarding/import_screen.dart: progress indicator during restore, error handling for privacy mode per spec US10 scenarios 1-5

**Checkpoint**: Account restoration from mnemonic works with trade key index sync

---

## Phase 10: User Story 11 — Reputation & Rating (Priority: P2)

**Goal**: Post-trade rating with privacy mode toggle

**Independent Test**: Complete trade → rate counterparty → verify rating sent; toggle privacy mode → verify no rating prompt

### Implementation for User Story 11

- [ ] T069 [US11] Implement reputation API in rust/src/api/reputation.rs: submit_rating(), get_privacy_mode(), set_privacy_mode(), stream on_rating_received() per contracts/reputation.md
- [ ] T070 [US11] Create rating prompt in lib/screens/trade/trade_screen.dart: post-completion rating dialog with score input per spec US11 scenarios 1-2
- [ ] T071 [US11] Add reputation display to order card in lib/widgets/order_card.dart: show creator's reputation score (hidden in privacy mode) per spec US11 scenario 5
- [ ] T072 [US11] Add privacy mode toggle to settings screen in lib/screens/settings/settings_screen.dart: global toggle, warning about recovery unavailability per spec FR-044

**Checkpoint**: Rating system works, privacy mode disables reputation and recovery

---

## Phase 11: User Story 9 — Multi-Platform Responsive (Priority: P2)

**Goal**: App adapts layout across phone, tablet, desktop; platform features degrade gracefully

**Independent Test**: App renders correctly at each breakpoint; QR fallback works on web

### Implementation for User Story 9

- [ ] T073 [US9] Implement tablet master-detail layout in lib/widgets/responsive_layout.dart: order list + detail side panel for 600-1200px per spec US9 scenario 2
- [ ] T074 [US9] Implement desktop multi-panel layout in lib/widgets/responsive_layout.dart: NavigationRail + order list + trade panel for >1200px per spec US9 scenario 2
- [ ] T075 [P] [US9] Add keyboard navigation support for desktop in lib/widgets/responsive_layout.dart per spec FR-044 (DESIGN_SYSTEM.md section 9.2)
- [ ] T076 [P] [US9] Add platform-specific interactions: haptic feedback on mobile, hover states on web per spec FR-044 (DESIGN_SYSTEM.md section 9)

**Checkpoint**: All three breakpoints render correctly, platform features degrade gracefully

---

## Phase 12: User Story 7 — Settings & Relay Management (Priority: P3)

**Goal**: Users manage relays, identity, wallet, preferences, diagnostics

**Independent Test**: User adds relay, changes theme, connects NWC wallet, enables logging

### Implementation for User Story 7

- [ ] T077 [US7] Implement relay management API in rust/src/api/nostr.rs: add_relay(), remove_relay(), blacklist_relay(), get_relays(), auto-sync from kind 10002 per contracts/nostr.md
- [ ] T078 [US7] Implement NWC wallet API in rust/src/api/nwc.rs: connect_wallet(), disconnect_wallet(), get_wallet_info(), pay_invoice(), stream on_wallet_status_changed() per contracts/nwc.md
- [ ] T079 [US7] Create settings screen in lib/screens/settings/settings_screen.dart: relay list with health status, identity export, theme selector (System/Dark/Light), language selector, wallet connection, diagnostics toggle per spec US7 scenarios 1-9
- [ ] T080 [P] [US7] Implement NWC auto-pay integration in rust/src/api/nwc.rs: auto-reconnect with backoff, automatic hold invoice payment during trades, fallback to manual per spec FR-046 and contracts/nwc.md
- [ ] T081 [P] [US7] Implement diagnostic logging in rust/src/api/diagnostics.rs: opt-in in-memory buffer (max 1000 FIFO), strip sensitive data, export to file, reset on restart per spec FR-050/FR-051
- [ ] T082 [US7] Create log viewer screen in lib/screens/settings/log_viewer_screen.dart: filter by level, search, export/share per spec FR-051

**Checkpoint**: Settings fully functional — relay management, NWC wallet, theme, diagnostics

---

## Phase 13: User Story 8 — Trade History (Priority: P3)

**Goal**: Users view past trades with details

**Independent Test**: User with completed trades sees chronological history with trade details

### Implementation for User Story 8

- [ ] T083 [US8] Implement trade history API in rust/src/api/orders.rs: get_trade_history() returns completed trades sorted by date per contracts/orders.md
- [ ] T084 [US8] Create history screen in lib/screens/history/history_screen.dart: chronological trade list, detail view on tap, empty state guidance per spec US8 scenarios 1-3

**Checkpoint**: Trade history displays all past trades with correct details

---

## Phase 14: User Story 12 — Deep Links & Order Sharing (Priority: P3)

**Goal**: Users share orders via deep links and QR codes

**Independent Test**: Share order link → open on another device → navigates to order detail

### Implementation for User Story 12

- [ ] T085 [US12] Implement deep link APIs in rust/src/api/orders.rs: share_order() generates mostro://order/<id> link + QR data, resolve_deep_link() parses URI per contracts/orders.md
- [ ] T086 [US12] Configure deep link handling in lib/router.dart: register mostro:// URI scheme, route to order detail on launch per spec FR-036
- [ ] T087 [P] [US12] Create share dialog in lib/screens/order_detail/order_detail_screen.dart: deep link + QR code display per spec US12 scenarios 1-3

**Checkpoint**: Order sharing works across platforms

---

## Phase 15: Polish & Cross-Cutting Concerns

**Purpose**: Improvements that affect multiple user stories

- [ ] T088 [P] Implement background notifications in lib/: FCM integration for Android/iOS, silent push with zero content per spec FR-041/FR-049
- [ ] T089 [P] Implement internationalization in lib/l10n/: string extraction, locale switching, at minimum English and Spanish per spec FR-020
- [ ] T090 Implement Mostro instance switching in lib/screens/settings/settings_screen.dart: warn user, reset non-default relays per edge case "Mostro instance change"
- [ ] T091 [P] Add accessibility labels to all interactive elements: semantic labels, logical focus order, minimum 44x44px touch targets per DESIGN_SYSTEM.md section 8
- [ ] T092 Run quickstart.md validation: verify all setup steps, build commands, and test commands work across platforms
- [ ] T093 Code cleanup: remove unused imports, ensure cargo clippy -D warnings passes, flutter analyze zero issues per constitution quality standards

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Setup completion — BLOCKS all user stories
- **US3 Onboarding (Phase 3)**: Depends on Phase 2 — BLOCKS trades (identity required)
- **US1+US2 Trade (Phase 4)**: Depends on Phase 3 (needs identity)
- **US4 Browse (Phase 5)**: Can start after Phase 2, but most value after Phase 4
- **US5 Chat (Phase 6)**: Depends on Phase 4 (needs active trade)
- **US13 Cancel (Phase 7)**: Depends on Phase 4 (needs active trade)
- **US6 Disputes (Phase 8)**: Depends on Phase 4 (needs active trade)
- **US10 Recovery (Phase 9)**: Depends on Phase 3 (needs identity/mnemonic)
- **US11 Reputation (Phase 10)**: Depends on Phase 4 (needs completed trade)
- **US9 Responsive (Phase 11)**: Can start after Phase 2 (cross-cutting layout)
- **US7 Settings (Phase 12)**: Can start after Phase 2 (relay/wallet infrastructure)
- **US8 History (Phase 13)**: Depends on Phase 4 (needs trade data)
- **US12 Deep Links (Phase 14)**: Depends on Phase 4 (needs order detail screen)
- **Polish (Phase 15)**: Depends on all desired user stories being complete

### User Story Dependencies

```text
Phase 2 (Foundational)
  └─→ US3 (Identity) ─→ US1+US2 (Trade) ─→ US5 (Chat)
                     │                    ├─→ US13 (Cancel)
                     │                    ├─→ US6 (Disputes)
                     │                    ├─→ US11 (Reputation)
                     │                    ├─→ US8 (History)
                     │                    └─→ US12 (Deep Links)
                     └─→ US10 (Recovery)
  └─→ US4 (Browse) — can start after Phase 2
  └─→ US9 (Responsive) — can start after Phase 2
  └─→ US7 (Settings) — can start after Phase 2
```

### Within Each User Story

- Rust API implementation before Flutter UI
- Models/storage before services
- Core implementation before integration
- Story complete before moving to next priority

### Parallel Opportunities

- All [P] tasks within a phase can run concurrently
- After Phase 4 completes, Phases 6-8 (Chat, Cancel, Disputes) can run in parallel
- Phase 11 (Responsive), Phase 12 (Settings) can start alongside any Phase 3+ work
- Phase 9 (Recovery) can run in parallel with Phase 4+ (only needs identity)

---

## Parallel Example: Phase 2 (Foundational)

```bash
# Sequential first (storage trait needed by backends):
Task T008: Storage trait

# Then parallel:
Task T009: SQLite backend
Task T010: IndexedDB backend
Task T012: BIP-32/39 keys
Task T013: Secure storage
Task T015: Relay pool
Task T016: Message queue

# Then sequential (needs storage + crypto):
Task T014: NIP-59 Gift Wrap
Task T017: State machine
Task T018: Protocol actions
```

## Parallel Example: Phase 4 (Trade Lifecycle)

```bash
# Parallel Rust APIs:
Task T033: create_order
Task T034: get_orders
Task T038: cancel_order

# Sequential (depends on above):
Task T035: take_order
Task T036: trade actions
Task T037: trade streams

# Parallel Flutter UI:
Task T040: order card widget
Task T044: trade progress widget
Task T045: QR scanner widget

# Sequential (depends on APIs + widgets):
Task T039: home screen
Task T041: order detail screen
Task T043: trade screen
```

---

## Implementation Strategy

### MVP First (Phases 1-4)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: US3 Onboarding
4. Complete Phase 4: US1+US2 Trade Lifecycle
5. **STOP and VALIDATE**: Full buy and sell flow works end-to-end
6. Deploy/demo with core trading

### Incremental Delivery

1. Setup + Foundational → Foundation ready
2. Add US3 (Onboarding) → Identity works → Deploy (minimal)
3. Add US1+US2 (Trade) → Full trading → Deploy (MVP!)
4. Add US5 (Chat) + US13 (Cancel) + US6 (Disputes) → Complete trade experience
5. Add US10 (Recovery) + US11 (Reputation) → Trust features
6. Add US7 (Settings) + US8 (History) + US12 (Deep Links) → Full feature set
7. Polish → Production ready

### Parallel Team Strategy

With multiple developers after Phase 2:

- **Developer A**: US3 (Identity) → US1+US2 (Trade) → US5 (Chat)
- **Developer B**: US9 (Responsive layouts) → US7 (Settings) → US12 (Deep Links)
- **Developer C**: US10 (Recovery) → US6 (Disputes) → US11 (Reputation)

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently completable and testable after its dependencies
- US1+US2 combined because buy/sell are two sides of the same trade lifecycle
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- All protocol logic in Rust, all UI in Flutter — zero exceptions per constitution
