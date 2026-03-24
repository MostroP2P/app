# Tasks: Mostro Mobile v2 — P2P Exchange Client

**Input**: Design documents from `/specs/001-mostro-p2p-client/`
**Prerequisites**: plan.md ✓, spec.md ✓ (13 user stories, 58 FRs), research.md ✓, data-model.md ✓ (11 entities), contracts/ ✓ (9 contracts)

## Format: `[ID] [P?] [Story?] Description with file path`

- **[P]**: Can run in parallel (different files, no dependencies on incomplete tasks)
- **[Story]**: User story this task belongs to ([US1]–[US13])
- Setup and Foundational phases have no story label

---

## Phase 1: Setup

**Purpose**: Project initialization and scaffolding on all 6 target platforms

- [ ] T001 Initialize Flutter project at repo root: pubspec.yaml (sdk: ">=3.0.0"), placeholder lib/main.dart calling runApp, flutter create --platforms=ios,android,macos,windows,linux,web
- [ ] T002 Initialize Rust crate in rust/: Cargo.toml with crate-type = ["cdylib", "staticlib"], rust/src/lib.rs with flutter_rust_bridge macro scaffolding, rust_builder/Cargo.toml for Cargokit integration per plan.md
- [ ] T003 [P] Add Flutter dependencies to pubspec.yaml: flutter_rust_bridge ^2.0, flutter_riverpod ^2.0, go_router ^13.0, flutter_secure_storage ^9.0, file_picker, permission_handler, qr_flutter, mobile_scanner, flutter_localizations
- [ ] T004 [P] Add Rust dependencies to rust/Cargo.toml: nostr-sdk 0.44+, mostro-core, sqlx (features: sqlite, runtime-tokio, macros), bip32, bip39, chacha20poly1305, reqwest (features: rustls-tls), tokio (features: rt-multi-thread), serde/serde_json, anyhow
- [ ] T005 Configure flutter_rust_bridge v2 codegen: create flutter_rust_bridge.yaml at repo root (rust_input, dart_output paths), add rust/build.rs and rust_builder/build.rs per research R2
- [ ] T006 [P] Add WASM support: rustup target add wasm32-unknown-unknown in CI; feature-gate async runtime in rust/src/lib.rs (#[cfg(target_arch="wasm32")] uses wasm-bindgen-futures; else uses tokio) per research R1/R2
- [ ] T007 [P] Configure iOS platform in ios/: add Keychain entitlements in ios/Runner/Runner.entitlements, update Podfile to use static frameworks for flutter_rust_bridge
- [ ] T008 [P] Configure Android platform in android/: add internet + camera permissions to android/app/src/main/AndroidManifest.xml, verify Gradle NDK config for JNI flutter_rust_bridge build

**Checkpoint**: `flutter pub get` succeeds; `cargo build --manifest-path rust/Cargo.toml` succeeds on native; project opens on iOS Simulator and Android Emulator

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core Rust infrastructure that MUST be complete before any user story begins

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

- [ ] T009 Define Storage trait in rust/src/storage/mod.rs: async CRUD methods for all 11 entities (Identity, Order, Trade, Message, Relay, Settings, MessageQueue, NwcWallet, FileAttachment, Rating, Dispute), feature-gated with #[cfg_attr(target_arch="wasm32", ...)] per research R4
- [ ] T010 Create all SQLite schema migrations in rust/src/storage/migrations/001_initial.sql: tables for all 11 entities with FK constraints, indices on trade_id, order_id, status, cached_at per data-model.md
- [ ] T011 [P] Implement SQLite storage backend in rust/src/storage/sqlite.rs: all Storage trait methods using sqlx + tokio for native platforms
- [ ] T012 [P] Implement IndexedDB storage backend in rust/src/storage/indexeddb.rs: all Storage trait methods using indexed_db_futures for wasm32 target per research R4
- [ ] T013 Implement NIP-59 Gift Wrap in rust/src/protocol/gift_wrap.rs: wrap(rumor, sender_key, recipient_pubkey) → Kind 1059 event, unwrap(gift_wrap, recipient_key) → rumor, using nostr-sdk per spec Protocol Reference and research R3
- [ ] T014 [P] Implement BIP-32/39 key derivation in rust/src/crypto/keys.rs: derive_identity_key(mnemonic) at m/44'/1237'/38383'/0/0, derive_trade_key(mnemonic, index) at m/44'/1237'/38383'/0/N using bip32 + bip39 per research R8
- [ ] T015 [P] Implement platform secure storage bridge in rust/src/crypto/secure_store.rs: store(key, bytes) and load(key) using platform keychain (iOS/macOS Keychain, Android Keystore, Windows DPAPI, Linux libsecret, Web SubtleCrypto) per research R5
- [ ] T016 [P] Implement ChaCha20-Poly1305 file encryption in rust/src/crypto/file_encrypt.rs: encrypt(plaintext, key) → [nonce:12][ciphertext][tag:16] blob, decrypt(blob, key) → plaintext using chacha20poly1305 per research R7
- [ ] T017 Implement relay pool in rust/src/network/relay_pool.rs: connect/disconnect relays, subscribe(filter) → event stream, publish(event), auto-reconnect with exponential backoff, expose ConnectionState per research R1
- [ ] T018 [P] Implement offline message queue in rust/src/network/message_queue.rs: enqueue(event_json, target_relays), flush_queue() on reconnect, retry with max 10 attempts, prune Sent items after 24h per data-model.md MessageQueue entity
- [ ] T019 [P] Implement Blossom HTTP client in rust/src/network/blossom.rs: upload_blob(encrypted_bytes) with server fallback (blossom.primal.net, blossom.band, nostr.media, blossom.sector01.com, 24242.io, nosto.re), download_blob(url) per research R7
- [ ] T020 Implement order state machine in rust/src/protocol/state_machine.rs: all 15 mostro-core states, valid transition map per data-model.md, handle Action::PaymentFailed (order stays SettledHoldInvoice), set CooperativelyCanceled client-side on cooperative cancel acceptance
- [ ] T021 [P] Implement protocol action builders in rust/src/protocol/actions.rs: build_new_order(), take_sell(), take_buy(), fiat_sent(), release(), cancel(), add_invoice(), dispute(), rate(), restore() as Gift Wrap–wrapped Nostr events per research R3
- [ ] T022 Define all shared API types in rust/src/api/types.rs: all enums (OrderStatus 15 variants, TradeRole, BuyerStep, SellerStep, MessageType, DisputeStatus, RelayStatus, ConnectionState, ThemeMode, LogLevel, etc.) and structs (OrderInfo, TradeInfo, ChatMessage, NymIdentity {pseudonym: String, icon_index: u8, color_hue: u16}, AppState, etc.) per contracts/types.md
- [ ] T023 Run flutter_rust_bridge codegen: flutter_rust_bridge_codegen generate to emit lib/src/rust/ Dart bindings from all rust/src/api/*.rs files; verify generated files compile
- [ ] T024 [P] Implement app theme in lib/theme/app_theme.dart: dark and light ThemeData with WCAG-AA contrast ratios, brand color palette consistent in both modes, smooth AnimatedTheme transition with no flash per FR-019b–f
- [ ] T025 [P] Set up go_router in lib/router.dart: all named routes (/onboarding, /onboarding/create, /onboarding/import, /onboarding/pin, /onboarding/recovery, /home, /order/:id, /trade, /dispute, /history, /history/:id, /settings/*, /about, /shared/:orderid) with redirect guard (no identity → /onboarding)
- [ ] T026 [P] Set up Riverpod providers scaffold in lib/providers/: empty AsyncNotifierProvider stubs for identity_provider.dart, orders_provider.dart, trade_provider.dart, messages_provider.dart, relay_provider.dart, wallet_provider.dart, settings_provider.dart
- [ ] T027 [P] Set up l10n in lib/l10n/: add flutter_localizations + intl to pubspec.yaml, create app_en.arb with all UI string keys as placeholders, configure MaterialApp localizations delegates
- [ ] T028 Implement app entry and responsive scaffold: lib/app.dart (MaterialApp.router with theme, Riverpod ProviderScope, localizations), lib/widgets/responsive_layout.dart (LayoutBuilder at 3 breakpoints: <600 phone, 600–1200 tablet, >1200 desktop with appropriate navigation chrome) per FR-021 and US9

**Checkpoint**: `cargo test && cargo clippy -- -D warnings` pass; `flutter analyze` zero issues; app launches to blank screen on iOS + Android + Chrome

---

## Phase 3: User Story 3 — Onboarding & Identity Setup (Priority: P1) 🎯 First Deliverable

**Goal**: New user creates or imports identity and arrives at home screen with relays connected

**Independent Test**: Fresh install → complete onboarding → home screen visible with relay connected indicator — no trades needed

- [ ] T029 [US3] Implement identity API in rust/src/api/identity.rs: create_identity(), import_from_mnemonic(words, recover), import_from_nsec(nsec), get_identity(), export_encrypted_backup(passphrase), delete_identity(), set_pin(pin), enable_biometric(), unlock(pin), derive_trade_key(), get_trade_key(index), get_nym_identity(pubkey) per contracts/identity.md
- [ ] T030 [P] [US3] Implement nym identity generation in rust/src/crypto/nym.rs: deterministic_nym(pubkey) → (pseudonym: String adjective-noun, icon_index: u8 0–36, color_hue: u16 0–359); same pubkey always yields same output; called by get_nym_identity() per FR-052/FR-053
- [ ] T031 [US3] Implement identity provider in lib/providers/identity_provider.dart: wrap identity Rust API, expose IdentityInfo? stream via on_identity_changed(), handle create/import/delete actions
- [ ] T032 [P] [US3] Implement welcome screen in lib/screens/onboarding/welcome_screen.dart: app logo, "Create New Identity" and "Import Existing" buttons per US3 scenario 1
- [ ] T033 [P] [US3] Implement create identity screen in lib/screens/onboarding/create_identity_screen.dart: call create_identity(), display 12-word mnemonic grid, backup-confirmation checkbox, "I've saved my phrase" CTA per US3 scenario 2
- [ ] T034 [P] [US3] Implement import identity screen in lib/screens/onboarding/import_identity_screen.dart: 12/24-word mnemonic word-grid input and nsec bech32 field, real-time BIP-39 validation, import CTA per US3 scenario 3
- [ ] T035 [P] [US3] Implement PIN setup screen in lib/screens/onboarding/pin_setup_screen.dart: 4–8 digit entry with confirm field, optional biometric enable toggle, skip button per US3 scenario 4
- [ ] T036 [US3] Implement nostr init in rust/src/api/nostr.rs (bootstrap subset): initialize(relays: None) connecting to preconfigured default relays; relay provider in lib/providers/relay_provider.dart exposes ConnectionState stream
- [ ] T037 [US3] Wire onboarding navigation in lib/router.dart: redirect guard sends users without identity to /onboarding; after successful identity creation/import navigate to /home per US3 scenario 5
- [ ] T038 [US3] Implement home screen shell in lib/screens/home/home_screen.dart: scaffold with AppBar (hamburger menu), empty order list placeholder, relay status chip in AppBar — functional shell before order loading is implemented

**Checkpoint**: Fresh install → create or import identity → PIN setup (or skip) → home screen shell visible with relay connected chip

---

## Phase 4: User Story 4 — Browse & Filter Orders (Priority: P2)

**Goal**: User sees live order list; can filter by type, currency, payment method; offline cached orders visible

**Independent Test**: With identity, open app → order list loads → apply Buy filter → only buy orders visible; go offline → cached orders shown with indicator

- [ ] T039 [US4] Implement orders browse API in rust/src/api/orders.rs: get_orders(filters: OrderFilters?) fetching Kind 38383 events, caching in local DB (cached_at), returning cached results when offline; on_orders_updated() stream emitting on relay events per contracts/orders.md
- [ ] T040 [US4] Implement orders provider in lib/providers/orders_provider.dart: subscribe to on_orders_updated() stream, hold filter state (OrderFilters), expose filtered Vec<OrderInfo>, handle offline cached-only mode
- [ ] T041 [P] [US4] Implement order card widget in lib/widgets/order_card.dart: display OrderKind badge, fiat amount (fixed: "100 USD" / range: "50–200 USD"), payment method, premium chip, creator reputation score chip (when available) per US4 scenario 1
- [ ] T042 [P] [US4] Implement home screen order list in lib/screens/home/home_screen.dart: live-updating order list using orders provider, filter bar (Buy/Sell/All toggle, fiat currency dropdown, payment method search field), offline banner per US4 scenarios 1–4 and FR-003/FR-004
- [ ] T043 [US4] Implement order detail screen in lib/screens/order_detail/order_detail_screen.dart: full OrderInfo display (amount, price, payment method, creator reputation), "Take Order" CTA (disabled if active trade exists), deep-link landing routing per US4 scenario 5 and FR-006

**Checkpoint**: Home screen shows live orders from relays; filters narrow results correctly; offline shows cached orders + banner; order detail opens from list

---

## Phase 5: User Story 1 — Complete a Buy Trade (Priority: P1) 🎯 MVP

**Goal**: Buyer takes a sell order, pays hold invoice (auto via NWC or manual QR), marks fiat sent, completes trade

**Independent Test**: Take sell order → pay invoice → mark fiat sent → see "Complete" in trade history

- [ ] T044 [US1] Extend orders API in rust/src/api/orders.rs: take_order(order_id) → TradeInfo, mark_fiat_sent(trade_id), submit_buyer_invoice(trade_id, bolt11), get_active_trade(), on_trade_step_changed() stream, on_trade_timeout_tick() stream per contracts/orders.md
- [ ] T045 [US1] Implement NWC API in rust/src/api/nwc.rs: connect_wallet(nwc_uri), disconnect_wallet(), get_wallet(), get_balance(), pay_invoice(bolt11) → PaymentResult, on_wallet_status_changed() stream per contracts/nwc.md
- [ ] T046 [US1] Implement trade provider in lib/providers/trade_provider.dart: subscribe to on_trade_step_changed() and on_trade_timeout_tick() streams, expose current TradeInfo and countdown seconds, dispatch trade actions
- [ ] T047 [US1] Implement wallet provider in lib/providers/wallet_provider.dart: wrap NWC Rust API, expose NwcWalletInfo? and WalletStatus stream, provide pay_invoice action
- [ ] T048 [P] [US1] Implement trade progress widget in lib/widgets/trade_progress.dart: stepper component displaying BuyerStep (OrderTaken → PayInvoice → PaymentLocked → FiatSent → AwaitingRelease → Complete) or SellerStep variant; highlight current step; Disputed overlay; per contracts/types.md and FR-009/FR-010
- [ ] T049 [P] [US1] Implement countdown timer widget in lib/widgets/countdown_timer.dart: display mm:ss countdown driven by on_trade_timeout_tick() stream; color changes at low time per FR-040
- [ ] T050 [P] [US1] Implement QR scanner widget in lib/widgets/qr_scanner.dart: mobile_scanner on native; clipboard paste + image upload fallback on web (no camera API) per US9 scenario 3 and FR-022
- [ ] T051 [US1] Implement active trade screen in lib/screens/trade/trade_screen.dart: trade_progress widget at top, step-specific action area (invoice QR display for PayInvoice, "Fiat Sent" button for FiatSent), countdown timer, NWC auto-pay status indicator per US1 scenarios 2–6 and FR-007/FR-009
- [ ] T052 [US1] Implement NWC auto-pay flow in trade logic: on PayInvoice step entry with wallet connected → call pay_invoice() automatically; on WalletTimeout or failure → surface invoice QR + copy-paste fallback + notification per US1 scenario 3 and edge case (NWC wallet disconnects)
- [ ] T053 [US1] Implement PaymentFailed action handling: when on_trade_step_changed() carries paymentFailed action → show distinct alert dialog; keep trade in SettledHoldInvoice; present "Resubmit Invoice" input for buyer per FR-048 and edge case

**Checkpoint**: Full buy flow works end-to-end: take order → NWC auto-pay OR manual QR → fiat sent → trade complete; PaymentFailed alert shown correctly

---

## Phase 6: User Story 2 — Complete a Sell Trade (Priority: P1)

**Goal**: Seller creates a sell order, receives taker, confirms fiat, releases Bitcoin

**Independent Test**: Create sell order → order appears on home screen → cancel before taken works; with taker → confirm fiat → trade completes; seller progress indicator shows seller steps

- [ ] T054 [US2] Extend orders API in rust/src/api/orders.rs: create_order(NewOrderParams) with fixed/range fiat validation, cancel_order(order_id), confirm_fiat_received(trade_id) per contracts/orders.md and FR-005 range validation
- [ ] T055 [P] [US2] Implement create order screen in lib/screens/create_order/create_order_screen.dart: Buy/Sell kind toggle, fixed-vs-range fiat amount switch (fiat_amount XOR fiat_amount_min+fiat_amount_max), fiat code picker, payment method field, premium slider, "Publish Order" CTA with validation per US2 scenario 1 and data-model.md validation rules
- [ ] T056 [US2] Extend active trade screen for seller role in lib/screens/trade/trade_screen.dart: seller action area (wait for taker → "Cancel Order", taker found → wait, payment locked → wait, await fiat → "Confirm Fiat Received"), SellerStep progress indicator per US2 scenarios 2–5
- [ ] T057 [US2] Implement background notifications: Android foreground service in android/app/src/.../TradeNotificationService.kt (active only during trades); nostr.rs register_push_token() for FCM token registration (silent push, zero content) per FR-041 and research R9
- [ ] T058 [US2] Wire trade event notifications: on_trade_step_changed() events → local notification when taker found, payment locked, fiat sent; use flutter_local_notifications per US2 scenario 2 and FR-041

**Checkpoint**: Seller creates order, order visible on home; cancel before taker works; full sell journey with confirm fiat completes trade; seller progress indicator shows correct steps

---

## Phase 7: User Story 5 — Encrypted P2P Chat During Trade (Priority: P2)

**Goal**: Both trade parties can exchange encrypted messages and file attachments; nym pseudonyms identify each party

**Independent Test**: Active trade → send message → counterparty receives within seconds; send image → inline preview; restart app → chat history persists from local DB

- [ ] T059 [US5] Implement messages API in rust/src/api/messages.rs: send_message(trade_id, content), get_messages(trade_id), mark_as_read(trade_id), get_unread_count(), send_file(trade_id, bytes, name, mime), download_attachment(message_id), get_attachment_status(message_id), on_new_message(trade_id) stream, on_attachment_progress(message_id) stream per contracts/messages.md
- [ ] T060 [US5] Implement messages provider in lib/providers/messages_provider.dart: subscribe to on_new_message() per active trade, manage chat message list, handle send_file upload state and on_attachment_progress() updates
- [ ] T061 [P] [US5] Implement nym avatar widget in lib/widgets/nym_avatar.dart: call get_nym_identity(pubkey), render pseudonym text label, select icon by icon_index (u8 0–36 maps to icon set), fill avatar circle background with HSV color from color_hue (u16 0–359) per FR-052/FR-053 and contracts/types.md NymIdentity
- [ ] T062 [P] [US5] Implement chat bubble widget in lib/widgets/chat_bubble.dart: mine (right-aligned)/theirs (left-aligned) layout, NymAvatar for sender, message text, timestamp, read dot indicator, attachment preview slot
- [ ] T063 [P] [US5] Implement attachment preview widget in lib/widgets/attachment_preview.dart: images auto-load inline with on_attachment_progress() bar; documents/videos show download button + file info; upload progress overlay for outgoing files per US5 scenarios 5–6
- [ ] T064 [US5] Integrate chat panel into trade screen in lib/screens/trade/trade_screen.dart: tabbed or split layout (Progress | Chat); display NymAvatar for both parties at top of chat; mark messages read on view per US5 scenarios 3, 8–9
- [ ] T065 [US5] Persist chat locally encrypted: messages stored encrypted at rest in DB (FR-045); get_messages() loads from local DB on screen open without relay re-fetch; survive app restart per US5 scenario 7

**Checkpoint**: Real-time chat during active trade; image attachment shows inline preview; documents show download button; nym pseudonyms and avatars displayed; chat history loaded from local DB after restart

---

## Phase 8: User Story 13 — Cooperative Cancel (Priority: P2)

**Goal**: Either party requests cancel; counterparty accepts; trade ends with CooperativelyCanceled outcome

**Independent Test**: Party A requests cancel → Party B sees request → B accepts → trade in history as CooperativelyCanceled

- [ ] T066 [US13] Extend orders API in rust/src/api/orders.rs: request_cooperative_cancel(trade_id), accept_cooperative_cancel(trade_id), on_cooperative_cancel_requested() stream per contracts/orders.md
- [ ] T067 [US13] Implement cooperative cancel UI in trade screen lib/screens/trade/trade_screen.dart: "Request Cancel" button in action area; incoming cancel request banner ("Counterparty requests cancel — Accept / Ignore"); strong warning banner when cancel requested after FiatSent step per US13 scenarios 1–3 and edge case
- [ ] T068 [US13] Set CooperativelyCanceled client-side: on accept_cooperative_cancel() response, update local trade status to CooperativelyCanceled (per state_machine.rs note: client-side only), route to trade complete screen with CooperativeCancel outcome per US13 scenario 4

**Checkpoint**: Initiate cancel → counterparty sees banner → accept → trade shows CooperativelyCanceled; warning appears if fiat already sent

---

## Phase 9: User Story 6 — Dispute Resolution (Priority: P2)

**Goal**: User opens dispute, submits evidence, receives admin messages, sees admin resolution (3 distinct outcomes)

**Independent Test**: Active trade in correct state → open dispute → submit evidence text → dispute state in progress indicator → admin resolution transitions to final state

- [ ] T069 [US6] Implement disputes API in rust/src/api/disputes.rs: open_dispute(trade_id, reason), submit_evidence(trade_id, text), get_dispute(trade_id), on_dispute_updated(trade_id) stream per contracts/disputes.md
- [ ] T070 [US6] Implement dispute provider in lib/providers/dispute_provider.dart: wrap dispute Rust API, expose Dispute? stream via on_dispute_updated(), dispatch open/evidence actions
- [ ] T071 [P] [US6] Implement dispute screen in lib/screens/dispute/dispute_screen.dart: optional reason text input, evidence text submission field with "Submit" button, admin messages chat thread (MessageType.Admin), dispute status banner (Open/InReview/Resolved) per US6 scenarios 1–4
- [ ] T072 [US6] Integrate dispute into trade flow: "Open Dispute" button visible in trade screen when current_step is between PaymentLocked and AwaitingRelease/AwaitingFiat; trade_progress widget shows Disputed overlay; on_dispute_updated() transitions to InProgress → CanceledByAdmin / SettledByAdmin / CompletedByAdmin as distinct final states per US6 scenario 5 and edge case

**Checkpoint**: Dispute opens from active trade; evidence submitted; admin messages visible; all three admin resolution outcomes shown as distinct final states in trade history

---

## Phase 10: User Story 11 — Reputation & Rating (Priority: P2)

**Goal**: Post-trade rating prompt after successful trades; privacy mode suppresses rating; counterparty reputation shown on orders

**Independent Test**: Complete trade → rating prompt → submit → confirmed; privacy mode trade → no prompt; order detail shows reputation score

- [ ] T073 [US11] Implement reputation API in rust/src/api/reputation.rs: submit_rating(trade_id, score), get_privacy_mode(), set_privacy_mode(enabled), get_rating_for_trade(trade_id), on_rating_received() stream per contracts/reputation.md
- [ ] T074 [US11] Implement trade completion screen in lib/screens/trade/trade_complete_screen.dart: success animation/icon, rating prompt (star selector 1–5), skip button; rating prompt suppressed when identity.privacy_mode = true; show notification dot on on_rating_received() events per US11 scenarios 1–4
- [ ] T075 [US11] Show reputation on order card and detail: extend order_card.dart and order_detail_screen.dart to display creator reputation score chip (hidden when privacy mode enabled or score unavailable) per US11 scenario 5

**Checkpoint**: Rating prompt on successful trade complete; submit_rating() sends to daemon; privacy mode hides prompt; reputation visible on order cards

---

## Phase 11: User Story 10 — Session Recovery (Priority: P2)

**Goal**: User imports mnemonic with recover=true, daemon returns active trades, local state reconstructed, trade key index synced

**Independent Test**: Known mnemonic with daemon-side active orders → import with recovery → trades appear in trade list + history; key index synced; privacy mode blocks recovery with explanation

- [ ] T076 [US10] Implement session recovery in rust/src/api/identity.rs (import_from_mnemonic recover=true path): send Action::restore to daemon, receive order/dispute IDs, request details for each, reconstruct local DB, sync trade_key_index per research R10 and US10 scenarios 1–3, 5
- [ ] T077 [US10] Implement recovery progress stream in rust/src/api/identity.rs: on_recovery_progress() emitting RecoveryProgress {phase, current, total} during each recovery sub-step
- [ ] T078 [US10] Implement recovery progress screen in lib/screens/onboarding/recovery_progress_screen.dart: animated progress bar, phase label ("Connecting…", "Fetching orders…", "Syncing…"), current/total counter, dismiss on completion per US10 scenarios 2–3, 5
- [ ] T079 [US10] Handle privacy mode recovery block: if identity.privacy_mode = true when import recover=true is requested, return PrivacyModeRecoveryUnavailable error; import screen shows explanatory message per US10 scenario 4 and edge case

**Checkpoint**: Recovery reconstructs active trades + history from daemon; progress screen shown; trade key index correctly synced; privacy mode block shown

---

## Phase 12: User Story 9 — Multi-Platform Responsive Experience (Priority: P2)

**Goal**: Same codebase renders correctly on phone, tablet, and desktop; platform features degrade gracefully

**Independent Test**: Resize browser window across breakpoints → layout transitions smoothly; QR fallback works on web; no layout flash on theme change

- [ ] T080 [US9] Implement phone layout in lib/widgets/responsive_layout.dart: single-column content area, BottomNavigationBar with Home / Active Trade / History tabs at <600px per US9 scenario 1
- [ ] T081 [US9] Implement desktop layout in lib/widgets/responsive_layout.dart: two-panel with NavigationRail (permanent) + main content area at >1200px; master-detail order list + detail pane per US9 scenario 2
- [ ] T082 [US9] Implement platform capability detection in lib/widgets/qr_scanner.dart: detect camera availability; show clipboard-paste and image-upload alternatives on web or no-camera platforms per US9 scenario 3
- [ ] T083 [US9] Implement push notification graceful degradation: on platforms without silent push support (web, desktop), poll relay on app focus for missed trade events; show badge on tab bar per US9 scenario 4
- [ ] T084 [US9] Implement smooth layout and theme transitions: use LayoutBuilder in responsive_layout.dart with AnimatedSwitcher for breakpoint changes; ensure theme switch during open modal does not close modal or lose form state per US9 scenario 5 and edge case (theme switch during modal)

**Checkpoint**: Phone/tablet/desktop layouts render correctly; QR fallback available on web; resize transitions without flash; theme change keeps open modals intact

---

## Phase 13: User Story 7 — Settings & Relay Management (Priority: P3)

**Goal**: User manages relays, account, preferences, wallet, and About via drawer navigation

**Independent Test**: Open drawer → Account/Settings/About accessible → add relay → change theme instantly → view About with live node data → enable diagnostic logging → node selector warns on switch

- [ ] T085 [US7] Implement settings API in rust/src/api/settings.rs: get_settings(), set_theme(ThemeMode), set_language(locale), set_default_fiat_code(code?), set_default_lightning_address(address?), set_logging_enabled(bool), set_privacy_mode(bool), on_settings_changed() stream per contracts/settings.md
- [ ] T086 [US7] Implement settings provider in lib/providers/settings_provider.dart: wrap settings Rust API, expose AppSettings stream, propagate ThemeMode changes to MaterialApp.themeMode in lib/app.dart
- [ ] T087 [P] [US7] Implement drawer navigation in lib/app.dart: NavigationDrawer with Account, Settings, About items triggered by hamburger icon; accessible from all main screens per US7 scenario 1
- [ ] T088 [P] [US7] Implement relay settings screen in lib/screens/settings/relay_settings_screen.dart: relay list with status dot indicators (Connected/Disconnected/Error), add relay URL field with wss:// validation, remove relay button, blacklist toggle, auto-sync status per US7 scenarios 2–3, 12
- [ ] T089 [P] [US7] Implement account screen in lib/screens/settings/account_screen.dart: mnemonic display (first 2 + last 2 words visible, middle 8 masked as "• • • •", "Show" button reveals all), "Generate New User" button with confirmation dialog + data-clear warning, "Import Mostro User" button leading to import screen per US7 scenarios 4–6
- [ ] T090 [P] [US7] Implement preferences screen in lib/screens/settings/preferences_screen.dart: privacy mode toggle (Reputation Mode / Full Privacy), theme selector (System/Dark/Light chips), language picker (10 supported locales), default fiat currency dropdown, Lightning Address text field per US7 scenarios 7–10 and FR-044/FR-054/FR-055
- [ ] T091 [P] [US7] Implement NWC wallet settings screen in lib/screens/settings/nwc_settings_screen.dart: paste NWC URI field, connect/disconnect button, wallet status chip, optional balance display per US7 scenario 11
- [ ] T092 [US7] Wire theme switching end-to-end: settings_provider streams ThemeMode → MaterialApp.themeMode updates instantly; OS theme changes auto-apply when ThemeMode.System; transition during open modal must not close modal or lose input per US7 scenarios 8–9 and edge case
- [ ] T093 [US7] Implement relay auto-sync in rust/src/api/nostr.rs: enable_relay_auto_sync(mostro_pubkey) subscribes to daemon's kind 10002 events, adds discovered relays (additive only, no disconnects), emits on_relay_auto_synced() per US7 scenario 12 and contracts/nostr.md
- [ ] T094 [P] [US7] Implement diagnostic logging: in-memory log ring buffer in Rust (LogEntry per types.md), settable via set_logging_enabled(); lib/screens/settings/logs_screen.dart displays log list filterable by LogLevel, export-as-text button; no sensitive data (keys, tokens, mnemonics) in any log; logging resets to false on process start per US7 scenario 13 and FR-050/FR-051
- [ ] T095 [P] [US7] Implement About screen in lib/screens/settings/about_screen.dart: app version, commit hash, GitHub link (tappable), MIT license (tappable modal), Mostro node card (pubkey, version, fee%, min/max order sats, supported currencies, LN node ID + alias) with info-icon tooltips per US7 scenarios 14–15 and FR-057/FR-058
- [ ] T096 [US7] Implement Mostro node selector: get_known_mostro_nodes() and set_active_mostro(pubkey) in rust/src/api/nostr.rs; node picker in preferences screen with confirmation dialog warning about non-default relay reset on switch per FR-056 and edge case
- [ ] T097 [US7] Auto-fill Lightning Address: set_default_lightning_address() persists to settings; when user is buyer in sell order, pre-fill invoice submission field with stored Lightning Address (if set) per FR-055

**Checkpoint**: All settings reachable via drawer; relay add/remove works; mnemonic mask and show toggle work; theme switches instantly including during open modal; About shows live node data; node switch shows warning dialog

---

## Phase 14: User Story 8 — Trade History (Priority: P3)

**Goal**: User views chronological completed trade list with detail; empty state for new users

**Independent Test**: With completed trades in DB, navigate to history → list shown newest-first; tap → detail; with no trades → empty state guidance

- [ ] T098 [US8] Extend orders API in rust/src/api/orders.rs: get_trade_history() → Vec<TradeHistoryEntry> from local DB, ordered by completed_at descending per contracts/orders.md
- [ ] T099 [P] [US8] Implement history screen in lib/screens/history/history_screen.dart: ListView of TradeHistoryEntry with NymAvatar for counterparty, kind badge, fiat amount, fiat code, outcome chip (Success/Canceled/Expired/DisputeWon/DisputeLost/CooperativelyCanceled), empty-state widget with trade CTA per US8 scenarios 1, 3
- [ ] T100 [P] [US8] Implement history detail screen in lib/screens/history/history_detail_screen.dart: full trade details (date, amounts, payment method, counterparty nym, final status, rating submitted/received if any) per US8 scenario 2

**Checkpoint**: History list populated from local DB; empty state shown for new users; detail view has all trade fields including rating info

---

## Phase 15: User Story 12 — Deep Links & Order Sharing (Priority: P3)

**Goal**: Orders shareable as deep links and QR; tapping link opens app to order detail

**Independent Test**: Share order → link generated + QR shown; tap mostro://order/<id> → app opens to order detail; unknown ID → error state

- [ ] T101 [US12] Extend orders API in rust/src/api/orders.rs: share_order(order_id) → OrderShareInfo {deep_link, qr_data, order}, resolve_deep_link(uri) → String? order ID per contracts/orders.md
- [ ] T102 [P] [US12] Implement share order UI in lib/screens/order_detail/order_detail_screen.dart: "Share" icon button → bottom sheet with QR code (qr_flutter widget using qr_data), "Copy Link" button (deep_link), "Share via OS" button per US12 scenario 1
- [ ] T103 [US12] Configure deep link handling on all platforms: iOS (ios/Runner/Info.plist CFBundleURLSchemes mostro), Android (AndroidManifest.xml intent-filter for mostro://), Web (redirect from web URL), macOS (Info.plist) per US12 scenario 2
- [ ] T104 [US12] Implement deep link routing in lib/screens/shared/deep_link_screen.dart: call resolve_deep_link() on incoming URI, navigate to /order/:id if valid; show "Order not found" if unknown ID; on web without app show app download redirect per US12 scenarios 2–3

**Checkpoint**: Share generates valid deep link + QR; tapping link opens order detail; unknown order shows error; web fallback to app store

---

## Phase 16: Polish & Cross-Cutting Concerns

**Purpose**: Offline resilience, error surfaces, WASM validation, and final quality gate

- [ ] T105 Implement offline indicator banner in lib/widgets/offline_banner.dart: persistent top banner when ConnectionState is Offline or Reconnecting; dismiss on reconnection; shown on home, trade, and chat screens per edge case (connectivity loss mid-trade)
- [ ] T106 [P] Implement force-close trade recovery in app startup: on launch with active trade in local DB (completed_at null), route to /trade and emit on_trade_step_changed() sync from relays to catch up on missed events per edge case
- [ ] T107 [P] Surface edge-case error states: invalid mnemonic on import (immediate inline error), order already taken race condition (OrderAlreadyTaken error → toast + redirect to home), file upload retry UI (unsent attachment state + retry button) per edge cases
- [ ] T108 [P] Validate WASM web build: flutter build web with wasm-pack integration; smoke-test IndexedDB storage, WebSocket relay connections, and NIP-59 decryption in Chrome; verify wasm-opt binary size within reason per research R1/R2
- [ ] T109 [P] Run quickstart.md validation scenarios: follow setup steps in specs/001-mostro-p2p-client/quickstart.md end-to-end on iOS Simulator, Android Emulator, and Chrome web; document any deviations
- [ ] T110 Final quality gate: `cargo test && cargo clippy -- -D warnings` (Rust zero warnings), `flutter test && flutter analyze` (Dart zero issues); verify all 15 order states render with distinct indicators per plan.md Quality Standards

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundational)**: Depends on Phase 1 — **BLOCKS all user stories**
- **Phase 3 (US3)**: Depends on Phase 2 — first deliverable
- **Phase 4 (US4)**: Depends on Phase 3 (needs identity to fetch orders)
- **Phase 5 (US1)**: Depends on Phase 3 + Phase 4 (needs browse to find orders to take)
- **Phase 6 (US2)**: Depends on Phase 3 + Phase 4 (shares trade screen from Phase 5)
- **Phase 7 (US5)**: Depends on Phase 5 or 6 (needs active trade for chat)
- **Phase 8 (US13)**: Depends on Phase 5 (active trade for cancel)
- **Phase 9 (US6)**: Depends on Phase 5 (active trade for dispute)
- **Phase 10 (US11)**: Depends on Phase 5 or 6 (post-trade rating)
- **Phase 11 (US10)**: Depends on Phase 3 (extends import flow)
- **Phase 12 (US9)**: Depends on Phase 2 (layout wraps all stories — can develop in parallel)
- **Phase 13 (US7)**: Depends on Phase 3 (identity + relay for account/relay screens)
- **Phase 14 (US8)**: Depends on Phase 5 or 6 (needs completed trades in DB)
- **Phase 15 (US12)**: Depends on Phase 4 (needs order detail screen)
- **Phase 16 (Polish)**: Depends on all stories

### Parallel Opportunities Per Phase

**Phase 2**: T011/T012 (storage backends), T014/T015/T016 (crypto), T017/T018/T019 (network), T024/T025/T026/T027 (Flutter foundations) — all parallel groups

**Phase 3**: T032/T033/T034/T035 (onboarding screens) — all parallel

**Phase 5**: T048/T049/T050 (widgets) — parallel; T044/T045 (Rust APIs) — parallel

**Phase 7**: T061/T062/T063 (chat widgets) — parallel

**Phase 13**: T088/T089/T090/T091/T094/T095 (settings screens) — parallel

---

## Parallel Example: Phase 2 (Foundational)

```bash
# Storage backends — run together:
Task T011: Implement SQLite backend in rust/src/storage/sqlite.rs
Task T012: Implement IndexedDB backend in rust/src/storage/indexeddb.rs

# Crypto — run together:
Task T014: Implement BIP-32/39 key derivation in rust/src/crypto/keys.rs
Task T015: Implement platform secure storage in rust/src/crypto/secure_store.rs
Task T016: Implement ChaCha20-Poly1305 file encryption in rust/src/crypto/file_encrypt.rs

# Flutter foundations — run together (after T023 codegen):
Task T024: Implement app theme in lib/theme/app_theme.dart
Task T025: Set up go_router in lib/router.dart
Task T026: Set up Riverpod providers scaffold in lib/providers/
Task T027: Set up l10n in lib/l10n/
```

---

## Implementation Strategy

### MVP First (US3 + US4 + US1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (**critical — blocks everything**)
3. Complete Phase 3: US3 Onboarding
4. Complete Phase 4: US4 Browse Orders
5. Complete Phase 5: US1 Buy Trade
6. **STOP AND VALIDATE**: Complete buy trade end-to-end
7. Deploy to TestFlight / Play internal track

### Incremental Delivery

1. Phase 1 + Phase 2 → project compiles on all 6 targets
2. + US3 → onboard, create identity, reach home screen
3. + US4 → browse live orders from relay
4. + US1 → complete buy trade (**MVP!**)
5. + US2 → complete sell trade
6. + US5 → encrypted chat during trades
7. + US13 + US6 → cooperative cancel and disputes
8. + US11 + US10 → reputation and session recovery
9. + US9 → polished multi-platform responsive layouts
10. + US7 + US8 + US12 → settings, history, deep links
11. + Polish → production ready

### Parallel Team Strategy (Post-Foundational)

With 2 developers once Phase 2 completes:
- **Developer A**: US3 (Onboarding) → US1 (Buy)
- **Developer B**: US4 (Browse) → US2 (Sell)

After US1 + US2 done:
- **Developer A**: US5 (Chat) → US13 (Cooperative Cancel)
- **Developer B**: US6 (Dispute) → US11 (Reputation)

---

## Notes

- `[P]` tasks touch different files — safe to run in parallel without conflicts
- `[Story]` label maps every task to the spec user story it delivers
- **Rust/Dart boundary**: all Nostr, crypto, and network code in Rust; Dart is UI only
- **NymIdentity types**: `pseudonym: String`, `icon_index: u8 (0–36)`, `color_hue: u16 (0–359)` — never use f64 for hue
- **CooperativelyCanceled**: set client-side only via action notifications; daemon does NOT send a status update
- **PaymentFailed**: is an Action notification — order stays `SettledHoldInvoice`; buyer may resubmit invoice
- **Range orders**: `fiat_amount` XOR (`fiat_amount_min` + `fiat_amount_max`) — mutually exclusive per data-model.md
- **privacy_mode**: `Identity.privacy_mode` is authoritative; Settings mirrors it via `set_privacy_mode()` only
- **logging_enabled**: runtime-only — process startup unconditionally sets false regardless of stored value
- Commit after each checkpoint; stop at any checkpoint to validate the story independently before proceeding
