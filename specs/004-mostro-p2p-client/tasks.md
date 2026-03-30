# Tasks: Mostro Mobile v2 — P2P Bitcoin Lightning Exchange

**Input**: Design documents from `specs/004-mostro-p2p-client/`
**Prerequisites**: plan.md ✅, spec.md ✅, research.md ✅, data-model.md ✅, contracts/ (9 files) ✅, quickstart.md ✅

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks grouped by user story (15 stories + foundation) to enable independent implementation and testing of each story. V1_FLOW_GUIDE.md section references are noted per story for implementation guidance.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no cross-story dependencies)
- **[Story]**: User story (US1–US15) from spec.md
- All paths are relative to repository root

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Bootstrap the monorepo, configure all toolchains, install dependencies.

- [x] T001 Create full directory structure per plan.md: `lib/features/`, `lib/core/`, `lib/shared/`, `rust/src/api/`, `rust/src/db/`, `rust/src/nostr/`, `rust/src/crypto/`, `rust/src/mostro/`, `rust/src/nwc/`, `rust/src/queue/`, `assets/data/`, `assets/images/`, `assets/l10n/`
- [x] T002 Configure `rust/Cargo.toml` with all dependencies: `nostr-sdk 0.44+`, `mostro-core 0.8+`, `flutter_rust_bridge 2.x`, `sqlx` (features: sqlite, runtime-tokio), `indexed_db_futures`, `bip32`, `bip39`, `chacha20poly1305`, `tokio` (rt-multi-thread, native only), `wasm-bindgen-futures` (wasm only)
- [x] T003 [P] Configure `pubspec.yaml` with Flutter dependencies: `flutter_rust_bridge 2.x`, `riverpod`/`flutter_riverpod`, `go_router`, `sembast`, `flutter_secure_storage`, `introduction_screen`, `qr_flutter`, `mobile_scanner`, `intl`, `shared_preferences`
- [x] T004 Configure `rust/build.rs` to invoke `flutter_rust_bridge_codegen generate` and set up `rust_builder/` scaffolding for wasm-pack web builds
- [x] T005 [P] Add Rust WASM target and document in `quickstart.md`: `rustup target add wasm32-unknown-unknown`; add `wasm-pack` and `flutter_rust_bridge_codegen` to prerequisites
- [x] T006 [P] Configure linting: `.clippy.toml` (Rust, deny warnings), `analysis_options.yaml` (Flutter, strict), pre-commit hooks running `cargo clippy -- -D warnings` and `flutter analyze`
- [x] T007 [P] Populate `assets/data/fiat.json` with full fiat currency list (ISO 4217 code, name, country flag emoji); create placeholder walkthrough images `assets/images/wt-1.png` through `wt-6.png`; create skeleton ARB files `assets/l10n/app_en.arb`, `app_es.arb`, `app_it.arb`, `app_fr.arb`, `app_de.arb`

**Checkpoint**: `flutter pub get`, `cd rust && cargo build`, `flutter analyze` all pass.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Cross-cutting infrastructure that EVERY user story depends on. No story work can begin until this phase is complete.

**⚠️ CRITICAL**: All phases 3–17 are blocked until this phase is complete.

- [x] T008 Implement all shared types in `rust/src/api/types.rs`: all enums (`OrderKind`, `OrderStatus` with 15 states, `TradeRole`, `BuyerStep`, `SellerStep`, `TradeStep`, `TradeOutcome`, `MessageType`, `DisputeStatus`, `RelayStatus`, `ConnectionState`, `WalletStatus`, `ThemeMode`, `FileType`, `DownloadStatus`, `QueuedMessageStatus`, `CooperativeCancelState`) and all structs (`OrderInfo`, `TradeInfo`, `ChatMessage`, `AttachmentInfo`, `RelayInfo`, `IdentityInfo`, `NymIdentity`, `AppState`, `LogEntry`) per `contracts/types.md`. Mark `flutter_rust_bridge` annotations. Note: `PaymentFailed` is NOT a status — it is an Action notification only.
- [x] T009 Implement storage trait in `rust/src/db/mod.rs` defining async CRUD interface for all entities (Identity, Order, Trade, Message, Relay, Dispute, Settings, MessageQueue, NwcWallet, FileAttachment, Rating). Implement SQLite backend in `rust/src/db/sqlite.rs` using `sqlx` with full schema migrations for all 11 entities per `data-model.md`.
- [x] T010 [P] Implement IndexedDB storage backend in `rust/src/db/indexeddb.rs` using `indexed_db_futures`, feature-gated with `#[cfg(target_arch = "wasm32")]`. Must implement the same trait as `sqlite.rs` and support all 11 entities.
- [x] T011 [P] Implement NIP-59 Gift Wrap encode/decode in `rust/src/nostr/gift_wrap.rs` using `nostr-sdk`: create unsigned rumor event, encrypt into Seal (Kind 13, NIP-44), wrap into Gift Wrap (Kind 1059, ephemeral key). Export `wrap_message(content, recipient_pubkey, sender_key)` and `unwrap_message(gift_wrap_event, recipient_key)`.
- [x] T012 [P] Implement relay pool with Kind 1059 + Kind 38383 subscriptions in `rust/src/nostr/relay_pool.rs` using `nostr-sdk`. Multi-relay connection manager: connect, disconnect, add/remove relays, subscribe to order events (Kind 38383) and gift-wrap DMs (Kind 1059 targeting user's trade keys), emit events via channels.
- [x] T013 [P] Implement offline message queue in `rust/src/queue/outbox.rs`: persist queued Nostr events to DB (entity: `MessageQueue`), retry on reconnection up to 10 attempts, prune `Sent` items after 24 hours, expose `queue_message(event_json, target_relays)` and `flush_queue()`.
- [x] T014 Implement app design system tokens in `lib/core/app_theme.dart`: colors (`mostroGreen #8CC63F`, `purpleButton #7856AF`, `sellRed #FF8A8A`, `errorRed #EF6A6A`, dark background, card background, text primary/secondary, input background), typography scale, spacing constants, component styles for buttons (filled/outline), cards, chips/badges. Dark and light theme variants. Matches `DESIGN_SYSTEM.md` exactly.
- [x] T015 [P] Implement GoRouter route definitions scaffold in `lib/core/app_routes.dart` with all 23 routes: `/walkthrough`, `/`, `/add_order`, `/take_sell/:orderId`, `/take_buy/:orderId`, `/pay_invoice/:orderId`, `/add_invoice/:orderId`, `/trade_detail/:orderId`, `/order_book`, `/chat_list`, `/chat_room/:orderId`, `/key_management`, `/settings`, `/about`, `/notifications`, `/relays`, `/wallet_settings`, `/connect_wallet`, `/rate_user/:orderId`, `/dispute_details/:disputeId`, `/notification_settings`, `/logs`, `/dispute_chat/:disputeId`. All routes are stubs returning placeholder `Scaffold` at this stage; redirect logic added in US1 phase.
- [x] T016 Implement app bootstrap in `lib/core/app.dart`: `ProviderScope` wrapping `MaterialApp.router` with GoRouter, `AppTheme` themes (dark default), locale resolution, `flutter_rust_bridge` Rust library initialization on startup. Initialize Nostr relay pool on startup.

**Checkpoint**: App launches to a blank scaffold on all 5 platforms. `cargo test` passes. `flutter analyze` clean.

---

## Phase 3: User Story 1 — First Launch & Identity Setup (Priority: P1) 🎯 MVP Start

**V1 ref**: Section 1 (`WALKTHROUGH_SCREEN.md`, `SESSION_AND_KEY_MANAGEMENT.md`, `AUTHENTICATION.md`)

**Goal**: New user sees walkthrough once, app silently creates identity, subsequent launches skip to home.

**Independent Test**: Fresh install → 6-slide walkthrough appears → Done/Skip → order book (blank). Reinstall same device → walkthrough skipped, goes direct to home.

- [x] T017 Implement BIP-39/BIP-32 key derivation in `rust/src/crypto/keys.rs`: `generate_mnemonic()` → 12-word BIP-39, `derive_master_key(mnemonic)` → identity key at path `m/44'/1237'/38383'/0/0`, `derive_trade_key(mnemonic, index)` → trade key at `m/44'/1237'/38383'/0/N`. Use `bip32` + `bip39` crates.
- [x] T018 [P] Implement ECDH shared key derivation in `rust/src/crypto/ecdh.rs`: `derive_shared_key(my_privkey, peer_pubkey)` → 32-byte shared secret. Used for P2P chat encryption (trade key + peer trade key).
- [x] T019 [P] Implement deterministic nym identity in `rust/src/crypto/nym.rs`: `get_nym_identity(pubkey)` → `NymIdentity { pseudonym, icon_index, color_hue }`. Pseudonym = adjective-noun format derived deterministically from pubkey bytes. Icon index 0–36, color hue 0–359. Same pubkey → same result always. See `contracts/identity.md` → `get_nym_identity`.
- [x] T020 Implement identity API in `rust/src/api/identity.rs` per `contracts/identity.md`: `create_identity()`, `get_identity()`, `import_from_mnemonic()`, `derive_trade_key()`, `get_trade_key()`, `get_nym_identity()`, `delete_identity()`, `export_encrypted_backup()`. `create_identity()` stores encrypted private key via `flutter_secure_storage` bridge (key never leaves device unencrypted). Emit `on_identity_changed()` stream.
- [x] T021 Implement walkthrough screen (6 slides) in `lib/features/walkthrough/screens/walkthrough_screen.dart` using `introduction_screen` package. Slides per `WALKTHROUGH_SCREEN.md`: Page 1 Welcome, Page 2 Privacy by Default, Page 3 Security, Page 4 Encrypted Chat, Page 5 Take an Offer, Page 6 Create Your Own Offer. Navigation: Skip (top-left), ← / → arrows, Done (last slide). Dots indicator (active = pill 16x8, inactive = circle 8x8).
- [x] T022 [P] Implement highlight config in `lib/features/walkthrough/utils/highlight_config.dart`: regex patterns to highlight key terms in green (`AppTheme.mostroGreen`, semibold w600) per slide. Terms: "Nostr"/"no KYC"/"censorship-resistant" (S1), "Reputation mode"/"Full privacy mode" (S2), "Hold Invoices" (S3), "end-to-end encrypted" (S4), "order book" (S5), "create your own offer" (S6). All 5 languages supported.
- [x] T023 Implement first-run provider in `lib/features/walkthrough/providers/first_run_provider.dart` using `shared_preferences`: `firstRunComplete` bool key. `markFirstRunComplete()` sets it to `true`. Activates `backupReminderProvider.showBackupReminder()` on completion.
- [x] T024 Wire GoRouter redirect in `lib/core/app_routes.dart`: if `firstRunComplete == false` → redirect all routes to `/walkthrough`; after walkthrough Done/Skip → set `firstRunComplete = true` → navigate to `/`. On first launch, `create_identity()` is called before the walkthrough is shown (invisible to user).

**Checkpoint**: Fresh launch shows walkthrough, Done/Skip lands on blank home, subsequent launches skip walkthrough. Identity created silently.

---

## Phase 4: User Story 2 — Secret Words Backup (Priority: P1)

**V1 ref**: Section 2 (`NOTIFICATIONS_SYSTEM.md`, `ACCOUNT_SCREEN.md`)

**Goal**: Backup reminder pinned in notifications, bell shows red dot, viewing secret words clears it permanently.

**Independent Test**: After walkthrough → bell has red dot + shake animation. Open Notifications → pinned backup card. Tap → Account screen → "Show" → 12 words appear → return to home → red dot gone permanently.

- [x] T025 Implement notification bell widget in `lib/shared/widgets/notification_bell.dart`: two states — (1) red dot (no number, before backup complete), (2) dark-gold pill badge with white number (after backup, count of unreads). Bell plays left-right shake animation (`AnimationController`) whenever any indicator is active. Integrates with `backupReminderProvider` and `unreadNotificationCountProvider`.
- [x] T026 [P] Implement backup reminder provider in `lib/features/account/providers/backup_reminder_provider.dart`: persists `backupReminderDismissed` bool in `SharedPreferences`. `showBackupReminder()` activates the red dot. `confirmBackupComplete()` sets dismissed = true, removes red dot permanently.
- [x] T027 Implement account screen in `lib/features/account/screens/account_screen.dart` with first card: "Secret Words" — shows masked mnemonic (first 2 + last 2 words visible, middle dots `•••`). "Show" button calls `get_identity()` on Rust side to retrieve the 12 words via `export_encrypted_backup()`. On show: reveals all 12 words, calls `backupReminderProvider.confirmBackupComplete()` which dismisses the red dot permanently. Route: `/key_management`.
- [x] T028 Implement notifications screen in `lib/features/notifications/screens/notifications_screen.dart`: scrollable card list, overflow menu with "Mark all as read" and "Clear all". Pinned backup reminder card always first (gavel/key icon, title "You must back up your account"). Tap on backup card → `/key_management`. Route: `/notifications`. Bell in AppBar taps to this screen.

**Checkpoint**: Backup reminder flow works end-to-end: red dot → view words → dot clears permanently. Notification bell states correct.

---

## Phase 5: User Story 3 — Browse the Order Book (Priority: P1)

**V1 ref**: Sections 3–5 (`HOME_SCREEN.md`, `ORDER_BOOK.md`)

**Goal**: Public order book with BUY/SELL tabs, order cards, and filter dialog. Tapping a card navigates to Take Order.

**Independent Test**: App shows two tabs with mock order list. Filter by "ARS" → only ARS orders shown. Tap order card → Take Order screen (stub). Empty state appears when no orders match.

- [x] T029 Implement Nostr relay API in `rust/src/api/nostr.rs` per `contracts/nostr.md`: `initialize(relays)`, `add_relay(url)`, `remove_relay(url)`, `get_relays()`, `get_connection_state()`, `flush_message_queue()`. Streams: `on_connection_state_changed()`, `on_relay_status_changed()`. Wire into relay pool from T012.
- [x] T030 [P] Implement Kind 38383 order event parsing in `rust/src/nostr/order_events.rs`: parse Nostr event tags to `OrderInfo` struct (kind, status, fiat_amount, fiat_code, premium, payment_method, creator_pubkey, created_at, expires_at). Use `mostro-core` types for deserialization. Only surface `status == Pending` orders.
- [x] T031 [P] Implement orders API read path in `rust/src/api/orders.rs` per `contracts/orders.md`: `get_orders(filters)` subscribes to Kind 38383 events from relay pool, caches locally, applies `OrderFilters` (kind, fiat_code, payment_method). Returns `Vec<OrderInfo>` sorted by ascending expiration. Stream: `on_orders_updated()` emits on any order list change.
- [x] T032 Implement home screen in `lib/features/home/screens/home_screen.dart`: AppBar (hamburger ☰ left, Mostro logo center — green skull, tappable 500ms happy face, notification bell right), BUY BTC / SELL BTC tabs (swipeable), filter pill below tabs (funnel icon + "FILTER" + offer count), scrollable order list, green FAB bottom-right, bottom nav bar (3 tabs). Tab logic: "BUY BTC" tab → shows **sell** orders (taker buys); "SELL BTC" tab → shows **buy** orders (taker sells). Labels are from the taker's perspective per V1_FLOW_GUIDE.md §3.
- [x] T033 [P] Implement order list item card widget in `lib/features/home/widgets/order_list_item.dart` with 5 rows: (1) status pill "SELLING"/"BUYING" + relative timestamp, (2) fiat amount/range in large bold + currency code + flag emoji, (3) price type label "Market Price (+5.0%)" with premium in green/red, (4) nested dark card with payment icon + comma-separated methods (truncated with "..."), (5) nested dark card with star rating (fractional fill) + trade count + days active. Skeleton shimmer for loading state. Empty state: centered icon + "No orders available".
- [x] T034 [P] Implement order book stream providers in `lib/features/home/providers/home_order_providers.dart`: `orderBookProvider` (StreamProvider from Rust), `homeOrderTypeProvider` (StateProvider: buy/sell tab), `currencyFilterProvider`, `paymentMethodFilterProvider`, `ratingFilterProvider`, `premiumRangeFilterProvider` (all StateProviders). `filteredOrdersProvider` (Provider) applies all filters to pending orders.
- [x] T035 [P] Implement order filter dialog in `lib/shared/widgets/order_filter.dart`: multi-select currency chips, multi-select payment method chips, rating range slider (0–5.0), premium range slider (-10%–+10%), Reset button. Reads/writes the individual filter providers. Shown via `showDialog` from HomeScreen.
- [x] T036 [P] Implement bottom navigation bar in `lib/shared/widgets/bottom_nav_bar.dart`: 3 tabs (Order Book / list-icon, My Trades / lightning-bolt, Chat / speech-bubble). My Trades tab has red dot badge when `orderBookNotificationCountProvider > 0`. Chat tab has red dot badge when `chatCountProvider > 0`. Active tab icon + label in green `#8CC63F`. GoRouter integration.
- [x] T037 [P] Implement drawer menu in `lib/features/drawer/screens/drawer_menu.dart`: slides from left, ~70% screen width, 30% black overlay behind. Header: Mostro mascot icon + "Beta" label + "MOSTRO" title. 3 menu items (Account `/key_management`, Settings `/settings`, About `/about`) with white outline icons + white labels. Generous vertical spacing.

**Checkpoint**: Order book renders with live or mocked order cards. Both tabs work. Filter reduces list. Tap card → stub Take Order screen opens.

---

## Phase 6: User Story 4 — Create an Order (Priority: P1)

**V1 ref**: Section 7 (`ORDER_CREATION.md`)

**Goal**: FAB expands into Buy/Sell buttons; Create Order form validates and submits; order appears in My Trades as Pending.

**Independent Test**: Tap FAB → two sub-buttons appear. Tap Sell → form opens pre-set to Sell. Fill all fields → Submit enabled → Submit → trade appears in My Trades as Pending.

- [ ] T038 Implement Mostro protocol FSM in `rust/src/mostro/fsm.rs`: 15 `OrderStatus` states, allowed action-per-role table (buyer/seller × status → allowed actions), `next_status(current, action, role)` function. Reference: `data-model.md` state machine and `contracts/types.md`.
- [ ] T039 [P] Implement Mostro action dispatch in `rust/src/mostro/actions.rs`: `new_order(params)`, `take_buy(order_id, amount)`, `take_sell(order_id, amount)`. Each builds a `MostroMessage` using `mostro-core` types, wraps via NIP-59 Gift Wrap, publishes to relays. On success returns updated `OrderInfo`.
- [ ] T040 Implement orders API write path in `rust/src/api/orders.rs`: add `create_order(params: NewOrderParams)` per `contracts/orders.md`. Validates params (fiat_amount XOR range; fiat_code valid; payment_method non-empty), builds `MostroMessage(action: NewOrder)`, wraps NIP-59, publishes. Queues if offline.
- [ ] T041 Implement AddOrderButton FAB widget in `lib/shared/widgets/add_order_button.dart`: collapsed state = circular 56dp green `#8CC63F` "+" button. On tap: main FAB → gray "×", dark overlay (~30% black), two stacked rectangular buttons: Buy (green `#8CC63F`, down-lightning-bolt, navigates to `/add_order?type=buy`) and Sell (salmon `#FF8A8A`, up-lightning-bolt, navigates to `/add_order?type=sell`). Tap overlay or "×" collapses back.
- [ ] T042 Implement create order screen in `lib/features/order/screens/add_order_screen.dart`: AppBar "CREATING NEW ORDER". 4 cards: (1) "You want to sell/buy Bitcoin" + fiat amount input + currency selector, (2) payment methods multi-select + custom text input, (3) Market/Fixed price toggle with info icon, (4) Premium slider -10%–+10% (visible only in market mode). Bottom bar: Cancel (gray outline) + Submit (green filled, disabled until valid). Reads `orderType` from route extra. Pre-fills `defaultFiatCode` and `defaultLightningAddress` from settings.
- [ ] T043 [P] Implement currency section widget (tappable, opens currency dialog) in `lib/features/order/widgets/currency_section.dart`: reads from `selectedFiatCodeProvider`. Shows selected code + flag.
- [ ] T044 [P] Implement payment method section (multi-select dropdown + custom text field) in `lib/features/order/widgets/payment_method_section.dart`: opens multi-select list, shows selected methods as chips, custom text input field below.
- [ ] T045 [P] Implement price type + premium section in `lib/features/order/widgets/price_section.dart`: Market/Fixed toggle (switch). Market mode: slider -10%–+10% with editable numeric field on purple background + pencil icon. Fixed mode: sats input field.
- [ ] T046 Wire create order form submission in `add_order_screen.dart`: on Submit → call `create_order()` via Rust bridge → on success navigate to `/order_book` (My Trades tab); validate fiat amount against Mostro instance min/max limits from `MostroInstance`.

**Checkpoint**: Full create order flow works. Submitted order appears in My Trades as Pending. FAB expands/collapses correctly.

---

## Phase 7: User Story 5 — Take an Existing Order (Priority: P1)

**V1 ref**: Section 8 (`TAKE_ORDER.md`), Section 10 (Range Amount Modal)

**Goal**: Tapping an order card opens detail view; tapping Buy/Sell (with range modal if needed) takes the order and navigates to invoice/trade screens.

**Independent Test**: Tap a sell order card → Take Order screen with all 5 info cards + countdown + Close/Buy buttons. Tap Buy on a range order → modal appears, enter amount → submit → navigates to Add Invoice screen.

- [ ] T047 Implement take order screen in `lib/features/order/screens/take_order_screen.dart`: AppBar "SELL ORDER DETAILS"/"BUY ORDER DETAILS". 5 info cards: (1) description + fiat/currency/flag/price/premium, (2) payment method, (3) creation date, (4) order ID with copy icon (📋), (5) creator reputation (rating ⭐, reviews 👤, days 📅). Countdown timer (circular progress + "Time remaining: HH:MM:SS"). Bottom: Close (green outline) + Buy/Sell (green filled). For range orders: amount input appears above buttons before showing take-action modal. Routes: `/take_sell/:orderId` and `/take_buy/:orderId`.
- [ ] T048 [P] Implement range amount modal in `lib/features/order/widgets/range_amount_modal.dart`: centered dialog with title, numeric input (green cursor), helper text "Min: X – Max: Y [currency]", Cancel + Submit buttons. Submit disabled until amount in range. Error message if out of range.
- [ ] T049 Implement take order actions in `rust/src/api/orders.rs`: add `take_order(order_id, role, fiat_amount)` — sends `take-sell` or `take-buy` `MostroMessage` via NIP-59. Returns `TradeInfo` with initial state. Errors: `OrderAlreadyTaken`, `OutOfRange`, `ProtocolError`, `Timeout`.
- [ ] T050 Wire take order navigation in `lib/features/order/screens/take_order_screen.dart`: on confirm → call `take_order()` → for buyer: navigate to `/add_invoice/:orderId`; for seller: navigate to `/pay_invoice/:orderId`. On `OrderAlreadyTaken` → show error snackbar + return to order book. On timeout (10s no response) → return to order book with timeout notification.

**Checkpoint**: Full take order flow: card tap → detail screen → Buy/Sell → range modal (if applicable) → next appropriate screen.

---

## Phase 8: User Story 6 — Trade Execution: Buyer Flow (Priority: P1)

**V1 ref**: Sections 9, 11 (`TRADE_EXECUTION.md`, `ORDER_STATES.md`)

**Goal**: Buyer adds Lightning invoice (manual or NWC), trade goes active, buyer taps Fiat Sent, seller releases, buyer receives payment.

**Independent Test**: Take a sell order without NWC → Add Invoice screen appears with sats + fiat amounts → enter invoice → trade goes active → Trade Detail shows Fiat Sent button → tap Fiat Sent → status updates to "Fiat sent".

- [ ] T051 Implement trade session management in `rust/src/mostro/session.rs`: per-trade state (`Session` struct: order_id, role, trade_key_index, shared_key, admin_shared_key, peer). `create_session()`, `update_session()`, `get_session()`, session timeout cleanup (10s for take actions). ECDH shared key computed when peer pubkey received from Mostro (`hold-invoice-payment-accepted` action).
- [ ] T052 Implement add lightning invoice screen in `lib/features/order/screens/add_lightning_invoice_screen.dart`: AppBar with order context. Single rounded card: info text "Enter a Lightning Invoice of [sats] Sats equivalent to [fiat] [currency]..." + multi-line invoice text input (dark bg, rounded, floating label "Lightning Invoice"). If default Lightning address in settings → pre-fill. Cancel (text button gray) + Submit (green filled). Route: `/add_invoice/:orderId`. Shown when NWC is NOT configured for buyer taking sell order.
- [ ] T053 [P] Implement NWC invoice widget in `lib/shared/widgets/nwc_invoice_widget.dart`: auto-generates Lightning invoice via NWC when wallet connected. Shows loading state. On invoice ready → `onInvoiceConfirmed(invoice)` callback. On failure → `onFallbackToManual()` callback.
- [ ] T054 [P] Implement LN address confirmation widget in `lib/shared/widgets/ln_address_confirmation_widget.dart`: shows "Confirm: send sats to [address]" with Confirm + Change buttons. Used when user has default Lightning address and NWC is not configured.
- [ ] T055 Implement invoice submission action in `rust/src/api/orders.rs`: add `send_invoice(order_id, invoice_or_address, amount_sats)` — sends `AddInvoice` `MostroMessage` to Mostro. On failure: `on_payment_failed` stream event.
- [ ] T056 Implement trade detail screen in `lib/features/trades/screens/trade_detail_screen.dart`: AppBar "ORDER DETAILS". 5 cards: (1) trade summary "You are buying [sats] sats for [fiat] [currency] [flag]", (2) payment method, (3) creation date, (4) order ID + copy, (5) instructions + status label. Countdown widget (color-coded as time elapses). Action button rows derived from `OrderState.getActions(role)`. Watches `orderNotifierProvider(orderId)` for live state.
- [ ] T057 [P] Implement trade info cards widget in `lib/features/trades/widgets/trade_info_cards.dart`: reusable components for the 5 info cards used in trade detail. `OrderIdCard` with copy-to-clipboard. `InstructionsCard` with green lightning bolt icon + instructional text based on role + status.
- [ ] T058 [P] Implement Mostro reactive button in `lib/shared/widgets/mostro_reactive_button.dart`: button that shows spinner while waiting for Mostro response, success check on completion, error state on failure. Listens to `mostroMessageStreamProvider` for its specific action.
- [ ] T059 Implement fiat-sent action in `rust/src/api/orders.rs`: add `send_fiat_sent(order_id)` — sends `FiatSent` `MostroMessage`. Updates local `Trade.current_step` to `FiatSent`. Streams: `on_trade_updated(order_id)` emits new `TradeInfo`.
- [ ] T060 Wire buyer trade detail buttons per FSM: active state → show FIAT SENT (green) + CANCEL (red) + DISPUTE (red) + CONTACT (green). Fiat Sent tap → `send_fiat_sent()` → reactive button flow. CONTACT → `/chat_room/:orderId`.

**Checkpoint**: Full buyer flow: add invoice → active trade detail → Fiat Sent → status changes to "Fiat sent". Cancel and dispute buttons visible.

---

## Phase 9: User Story 7 — Trade Execution: Seller Flow (Priority: P1)

**V1 ref**: Sections 12, 17, 18 (`TRADE_EXECUTION.md`, `NWC_ARCHITECTURE.md`)

**Goal**: Seller pays hold invoice (QR or NWC auto-pay), trade active, buyer sends fiat, seller sees Release button, confirms → sats released.

**Independent Test**: Take a buy order without NWC → Pay Invoice screen with QR code appears → "pay" manually → trade goes active → seller sees "Active order" instructions → buyer marks fiat sent → seller sees RELEASE → confirmation modal → Yes → success screen.

- [ ] T061 Implement pay lightning invoice screen in `lib/features/order/screens/pay_lightning_invoice_screen.dart`: AppBar "Pay Lightning Invoice". White card with info text "Pay this invoice of [sats] Sats..." + QR code (centered, scannable) + Copy button (green) + Share button (green) + Cancel button (red). Route: `/pay_invoice/:orderId`. Shown to seller when NWC is NOT configured. Seller pays externally → Mostro detects payment → trade transitions to active.
- [ ] T062 [P] Implement NWC payment widget in `lib/shared/widgets/nwc_payment_widget.dart`: single "Pay with Wallet" button (large green, wallet icon). Calls `nwc_api.pay_invoice(bolt11)` via Rust. Shows loading spinner during payment. `onPaymentSuccess` and `onFallbackToManual` callbacks. Used on `pay_lightning_invoice_screen.dart` when NWC is connected.
- [ ] T063 [P] Implement pay invoice widget (manual QR mode) in `lib/shared/widgets/pay_lightning_invoice_widget.dart`: QR code display using `qr_flutter`, copy button, share button (system share sheet). `onSubmit` (user confirms manual payment), `onCancel` callbacks.
- [ ] T064 Extend trade detail screen in `lib/features/trades/screens/trade_detail_screen.dart` for seller fiat-sent view: Card 5 instruction text becomes "The buyer [handle] has confirmed they sent you [fiat] [currency] using [method]. Once you verify, release the sats." Status label: "Fiat sent". Action buttons: CLOSE (green outline) + RELEASE (green filled) + CANCEL (red) + DISPUTE (red) in one row, CONTACT (green full-width) below.
- [ ] T065 Implement release confirmation dialog in `lib/features/trades/widgets/release_confirmation_dialog.dart`: centered modal on dark overlay. Large gray info icon. Title "Release Bitcoin". Body "Are you sure you want to release the Satoshis to the buyer?" No (gray) + Yes (green) buttons.
- [ ] T066 Implement release order action in `rust/src/api/orders.rs`: add `release_order(order_id)` — sends `Release` `MostroMessage`. Updates trade status to `SettledHoldInvoice` → `Success`. Streams `on_trade_updated(order_id)`.
- [ ] T067 Wire seller active view in trade detail: active status + seller role → show CLOSE + CANCEL + DISPUTE + CONTACT (no RELEASE, no FIAT SENT). Seller card 5 instruction: "Contact the buyer [handle] with payment instructions." Status: "Active order".
- [ ] T068 Wire seller release flow: RELEASE tap → confirmation dialog → Yes → `release_order()` → reactive button → on Success → navigate to rate screen `/rate_user/:orderId`.

**Checkpoint**: Full seller flow: pay hold invoice (both QR and NWC paths) → active → fiat sent by buyer → Release confirmation → trade completes and navigates to rating.

---

## Phase 10: User Story 8 — Encrypted P2P Chat (Priority: P1)

**V1 ref**: Sections 19–20 (`P2P_CHAT_SYSTEM.md`)

**Goal**: Per-trade encrypted chat with text + encrypted file attachments. Unread badges on Chat tab. Trade info + user info panels with copyable shared key.

**Independent Test**: Open CONTACT on active trade → chat room with peer handle + avatar. Send text → appears immediately (optimistic). Attach image → uploads encrypted → appears as image preview. Chat tab badge increments on new message, clears on open.

- [ ] T069 Implement file encryption in `rust/src/crypto/file_enc.rs`: `encrypt_file(bytes, key)` → `[nonce:12][ciphertext][tag:16]` using `chacha20poly1305`. `decrypt_file(encrypted_bytes, key)` → plaintext bytes. Key derived from ECDH shared key + file-specific nonce.
- [ ] T070 Implement Blossom HTTP client in `rust/src/nostr/blossom.rs`: `upload_blob(encrypted_bytes, mime_type, server_url)` → Blossom URL. `download_blob(url)` → encrypted bytes. Server list: blossom.primal.net, blossom.band, nostr.media, blossom.sector01.com, 24242.io, nosto.re. Try each in order on failure. Max 25MB.
- [ ] T071 Implement messages API in `rust/src/api/messages.rs` per `contracts/messages.md`: `send_message(trade_id, content)`, `get_messages(trade_id)`, `mark_as_read(trade_id)`, `get_unread_count()`, `send_file(trade_id, file_bytes, file_name, mime_type)`, `download_attachment(message_id)`. All outbound messages wrapped NIP-59 using ECDH shared key. Streams: `on_new_message(trade_id)`, `on_unread_count_changed()`, `on_attachment_progress(message_id)`. Persist decrypted messages locally.
- [ ] T072 Implement nym avatar widget in `lib/shared/widgets/nym_avatar.dart`: colored circle background (HSV hue from `NymIdentity.color_hue`), white icon from `NymIdentity.icon_index` (0–36 icon set, ALWAYS white regardless of hue — v1 bug fix per `contracts/types.md` NymIdentity rendering contract). Deterministic: same pubkey → same appearance always.
- [ ] T073 Implement chat list screen in `lib/features/chat/screens/chat_rooms_screen.dart`: AppBar + "Chat" title + two sub-tabs (Messages / Disputes, swipeable). Messages tab: empty state "No messages available" OR `ListView` of `ChatListItem`. Disputes tab: `DisputesList` component (Phase 12). Tab description text below tabs. Route: `/chat_list`.
- [ ] T074 [P] Implement chat list item widget in `lib/features/chat/widgets/chat_list_item.dart`: `NymAvatar` + peer handle (bold white) + context line "You are selling/buying sats to/from [handle]" + last message preview (own: "You: ...") + timestamp chip + red unread dot. Sorted by most recent session start. Tap → mark as read + navigate to `/chat_room/:orderId`.
- [ ] T075 [P] Implement chat rooms providers in `lib/features/chat/providers/chat_providers.dart`: `chatRoomsNotifierProvider` (StateNotifier from sessions), `sortedChatRoomsProvider`, `chatCountProvider` (unread count for badge), `chatReadStatusService` (SharedPreferences last-read timestamps). `ChatRoomsNotifier` only includes sessions with peer + at least one message.
- [ ] T076 Implement chat room screen in `lib/features/chat/screens/chat_room_screen.dart`: AppBar (← + `NymAvatar` + peer handle + "You are chatting with [handle]" subtitle). Two info buttons: "Exchange Information" + "User Information" (toggle panels). Message list (`ChatMessagesList`). `MessageInput` at bottom. If session or peer missing → show error screen. Route: `/chat_room/:orderId`.
- [ ] T077 [P] Implement message bubble widget in `lib/features/chat/widgets/message_bubble.dart`: own messages (right-aligned, purple `#7856AF` background, white text, tail pointing right), peer messages (left-aligned, darker shade of peer's avatar `color_hue`, white text, tail pointing left). Timestamp below bubble. Long-press → copy to clipboard. Optimistic send: append before relay confirm.
- [ ] T078 [P] Implement message input widget in `lib/features/chat/widgets/message_input.dart`: paperclip icon (📎 opens file picker), text input "Write a message..." pill, green send button (paper plane ✈️). Attachment in progress → spinner replaces paperclip. Submit via `send_message()` or `send_file()`. Keyboard show/hide adjusts scroll position.
- [ ] T079 [P] Implement trade info panel in `lib/features/chat/widgets/info_panels.dart`: `TradeInformationTab` (order ID, fiat/sats amounts, status chip, payment method, creation date — all from `orderNotifierProvider`). `UserInformationTab` (peer avatar + handle + "Peer's Public Key" in blue monospace copyable, "Your name" + "Your shared key" in blue monospace copyable — ECDH key). Shared key is critical for dispute resolution; display with tap-to-copy.
- [ ] T080 Implement encrypted image message widget in `lib/features/chat/widgets/encrypted_image_message.dart`: auto-download and display image preview for `MessageType` image_encrypted. Uses `download_attachment()` + `decrypt_file()`. Loading spinner, error fallback. Tap → full-screen viewer.
- [ ] T081 [P] Implement encrypted file message widget in `lib/features/chat/widgets/encrypted_file_message.dart`: download button with file name, size, type chip. Download triggers `download_attachment()`. Progress bar via `on_attachment_progress`. Opens file after download.

**Checkpoint**: Full P2P chat: text messages sent/received, optimistic display, unread badge works, file/image attachments upload encrypted and display, shared key visible in User Info panel.

---

## Phase 11: User Story 12 — My Trades List (Priority: P1)

**V1 ref**: Section 16 (`MY_TRADES.md`, `ORDER_STATES.md`)

**Goal**: My Trades tab shows all user trades with status/role badges; status filter; tap → Trade Detail; badge on tab for unseen updates.

**Independent Test**: Create a trade → My Trades tab shows card with correct status badge + role badge + fiat amount. Filter by "Active" → only active trades shown. Tab has red dot when trade updates occur.

- [ ] T082 Implement trades screen in `lib/features/trades/screens/trades_screen.dart`: AppBar (☰ + Mostro logo + bell). Sub-header: "My Trades" title (bold white) + "▼ Status | All" filter dropdown. Scrollable list of `TradesListItem`. Empty state "No trades" with icon. Route: `/order_book` (bottom nav tab 2). Sorted newest first.
- [ ] T083 [P] Implement trade list item widget in `lib/features/trades/widgets/trades_list_item.dart`: card with chevron (→). Top: "Selling Bitcoin"/"Buying Bitcoin" (bold white). Below: colored status badge chip (Pending=yellow, Active=blue, FiatSent=blue, Success=green, Canceled=gray, Dispute=red) + role badge ("Created by you"/"Taken by you", blue chip). Amount: bank icon + "966 ARS" + time ago (gray small). Payment method (gray small). Tap → `/trade_detail/:orderId`.
- [ ] T084 [P] Implement trades providers in `lib/features/trades/providers/trades_providers.dart`: `filteredTradesWithOrderStateProvider` (watches all sessions, reads `orderNotifierProvider(orderId)` for each, applies status filter). `selectedStatusFilterProvider` (StateProvider for dropdown). `orderBookNotificationCountProvider` (unseen trade update count for My Trades tab badge).

**Checkpoint**: My Trades tab populated with correct cards, filter dropdown works, badge increments on trade update.

---

## Phase 12: User Story 9 — Dispute System with Admin Chat (Priority: P2)

**V1 ref**: Sections 21–23 (`DISPUTE_SYSTEM.md`)

**Goal**: Open dispute from Trade Detail; dispute card in Disputes tab; admin chat; resolution (both outcomes); seller can voluntarily release during dispute.

**Independent Test**: Active trade → tap DISPUTE → confirm → trade status = "Dispute" → Disputes tab shows card. Admin takes dispute → "In progress" status. Chat with admin. Admin resolves → chat locked with resolution message.

- [ ] T085 Implement disputes API in `rust/src/api/disputes.rs` per `contracts/disputes.md`: `open_dispute(trade_id, reason)` sends `Dispute` `MostroMessage` via NIP-59. `submit_evidence(trade_id, text)` sends as admin-type message. `get_dispute(trade_id)`. Stream: `on_dispute_updated(trade_id)`. Handle incoming admin actions: `disputeInitiatedByYou`, `disputeInitiatedByPeer`, `adminTookDispute` (triggers admin shared key via ECDH), `adminSettled`, `adminCanceled`.
- [ ] T086 Implement admin shared key handshake in `lib/shared/providers/session_provider.dart` + `rust/src/mostro/session.rs`: when `adminTookDispute` received, extract admin pubkey from event payload, compute ECDH `adminSharedKey` using trade key + admin pubkey, store in `Session.adminSharedKey`. `DisputeChatNotifier` waits for this key before subscribing to admin messages.
- [ ] T087 Extend trade detail screen for dispute view in `lib/features/trades/screens/trade_detail_screen.dart`: when `OrderStatus == Dispute`: card 5 text "A dispute resolver has been assigned. They will contact you through the app." Status: "Order in dispute". Seller actions: CLOSE + CONTACT + CANCEL + RELEASE (4 buttons) + VIEW DISPUTE (full-width). RELEASE still available to seller during dispute (allows voluntary resolution). VIEW DISPUTE → `/dispute_details/:disputeId`.
- [ ] T088 Implement disputes list widget in `lib/features/disputes/widgets/disputes_list.dart`: driven by `userDisputeDataProvider`. Loading spinner, error + retry, empty state (gavel icon + "Your disputes will appear here"). Used in Chat screen Disputes tab.
- [ ] T089 [P] Implement dispute list item widget in `lib/features/disputes/widgets/dispute_list_item.dart`: ⚠️ warning icon + "Order dispute" + truncated order UUID + description text ("You opened this dispute" / "Counterpart opened this dispute" / resolution text). Status badge: Initiated (yellow), In progress (blue), Closed (gray). Unread dot. Tap → mark read + `/dispute_details/:disputeId`.
- [ ] T090 Implement dispute chat screen in `lib/features/disputes/screens/dispute_chat_screen.dart`: header section with "Dispute with Buyer/Seller: [handle]" + status badge "In progress" (green) + order UUID + dispute UUID + instructional text about shared key. Chat area (same bubble system: own=purple `#7856AF`, admin=dark gray). Message input (only shown when `status == in-progress`; hidden for resolved/closed disputes). Route: `/dispute_details/:disputeId`. On `initState` → mark as read.
- [ ] T091 [P] Implement dispute messages list in `lib/features/disputes/widgets/dispute_messages_list.dart`: SliverList combining: `DisputeInfoCard` (first always), optional "Admin assigned" blue card (in-progress + no messages), `DisputeMessageBubble` entries (sorted by timestamp, deduped by event ID), optional "Chat closed" lock banner (resolved/seller-refunded/closed). Auto-scroll to bottom on new message.
- [ ] T092 [P] Implement dispute message input in `lib/features/disputes/widgets/dispute_message_input.dart`: same pattern as P2P `MessageInput` (attach + text + send). Attachment uses `adminSharedKey` for encryption. Show spinner while uploading. Only rendered when dispute `status == in-progress`.
- [ ] T093 Implement dispute resolved screen in `lib/features/disputes/screens/dispute_chat_screen.dart` (terminal states): when dispute `status == resolved` (admin settled buyer) → green checkmark + "successfully completed" text + lock icon + "This dispute has been resolved. The chat is closed." When `status == seller-refunded` (admin canceled) → "Resolved" badge (blue) + green resolution box "The administrator canceled the order and refunded you. The buyer did not receive the sats." + lock message. No action buttons except back arrow.

**Checkpoint**: Full dispute flow: open → Disputes tab card → admin assigned → chat → both resolution outcomes display correctly with locked chat.

---

## Phase 13: User Story 10 — Post-Trade Rating (Priority: P2)

**V1 ref**: Section 13 (`RATING_SYSTEM.md`)

**Goal**: After trade completes both parties are prompted to rate (1–5 stars). Rating optional. Ratings appear on order book cards.

**Independent Test**: Seller releases sats → Rate button appears. Tap → rate screen with 5 stars. Select 4 → Submit enabled → tap Submit → screen closes. Counterparty's reputation score updated on their order cards.

- [ ] T094 Implement reputation API in `rust/src/api/reputation.rs` per `contracts/reputation.md`: `submit_rating(trade_id, score)` — validates 1–5, sends `RateUser` `MostroMessage`. `get_privacy_mode()`, `set_privacy_mode(enabled)`. `get_rating_for_trade(trade_id)`. Errors: `TradeNotComplete`, `PrivacyModeEnabled`, `AlreadyRated`.
- [ ] T095 Implement rate counterpart screen in `lib/features/rate/screens/rate_counterpart_screen.dart`: header "RATE" (uppercase gray). Success indicator: green double-lightning-bolt + "Successful order" text. 5-star `StarRating` widget. "X / 5" display below stars. Submit button (green filled, disabled until `_rating > 0`) + Close button (green outline, skips rating). Route: `/rate_user/:orderId`. Seller prompted at `SettledHoldInvoice`; buyer prompted at `Success`.
- [ ] T096 [P] Implement star rating widget in `lib/features/rate/widgets/star_rating.dart`: 5 tappable stars. Filled = `AppTheme.mostroGreen #8CC63F`. Empty = dark gray outline. Tap sets rating to star index + 1. Rating "X / 5" display.
- [ ] T097 Wire rate button in trade detail screen: when `OrderState.action` is `Action.rate`/`Action.rateUser`/`Action.rateReceived` → show Rate button in `_buildActionButtons()` → navigates to `/rate_user/:orderId`. After `rateReceived` → no further actions shown.

**Checkpoint**: Both buyer and seller are prompted to rate after trade completion. Star selection enables Submit. Rating submitted without error. Counterparty stars updated on order cards.

---

## Phase 14: User Story 11 — NWC Wallet Integration (Priority: P2)

**V1 ref**: Section 14 (`NWC_ARCHITECTURE.md`, Settings Screen)

**Goal**: User connects Lightning wallet via NWC URI or QR; Settings card shows balance; trades auto-pay invoices without manual screens.

**Independent Test**: Settings → Wallet → paste valid NWC URI → Connect → Settings card shows "Connected. Balance: X sats". Take buy order → invoice step skipped, "Pay with Wallet" button auto-pays. Disconnect → manual flow resumes.

- [ ] T098 Implement NWC client in `rust/src/nwc/client.rs`: parse NWC URI (`nostr+walletconnect://<pubkey>?relay=<url>&secret=<hex>`), connect to wallet relay(s) via nostr-sdk, send `pay_invoice` NWC request, handle response. `get_info()` for balance. Store encrypted credentials in secure storage.
- [ ] T099 Implement NWC API in `rust/src/api/nwc.rs` per `contracts/nwc.md`: `connect_wallet(nwc_uri)`, `disconnect_wallet()`, `get_wallet()`, `get_balance()`, `pay_invoice(bolt11)`. Streams: `on_wallet_status_changed()`, `on_payment_result()`. On NWC failure: `onFallbackToManual` path in PayLightningInvoiceScreen and AddLightningInvoiceScreen.
- [ ] T100 Implement connect wallet screen in `lib/features/settings/screens/connect_wallet_screen.dart`: chain/link icon. Text input field for NWC URI + QR scan button (opens `mobile_scanner` camera; paste-only on web via `platform_aware_qr_scanner`). Green "Connect" button. Success → redirect to `/wallet_settings`. Route: `/connect_wallet`.
- [ ] T101 Implement wallet settings screen in `lib/features/settings/screens/wallet_settings_screen.dart`: "Wallet Configuration" title. Wallet info card (alias, status, balance). Disconnect button. Route: `/wallet_settings`.
- [ ] T102 Wire NWC auto-pay into trade flows: in `add_lightning_invoice_screen.dart` — if NWC connected and `amount > 0` → render `NwcInvoiceWidget` (T053) instead of manual input; in `pay_lightning_invoice_screen.dart` — if NWC connected → render `NwcPaymentWidget` (T062) instead of QR. On any NWC failure → set `_manualMode = true` to show manual fallback.

**Checkpoint**: NWC connect/disconnect works. Both buyer (auto-invoice) and seller (auto-pay) trade paths skip manual invoice screens when NWC connected. Balance displayed in Settings.

---

## Phase 15: User Story 13 — Notifications Center (Priority: P2)

**V1 ref**: Section 15 (`NOTIFICATIONS_SYSTEM.md`, `FCM_IMPLEMENTATION.md`)

**Goal**: Bell badge counts unread notifications. Notifications screen lists trade events. Tapping navigates to relevant screen. Mark all read / clear all.

**Independent Test**: Complete a trade step → notification appears in list with correct icon/title. Bell badge increments. Tap notification → navigates to trade detail. Mark all read → badge clears.

- [ ] T103 Implement notification provider in `lib/features/notifications/providers/notifications_provider.dart`: listens to `on_trade_updated` and `on_new_message` streams from Rust. Creates typed `AppNotification` objects for each event type (rating, payment, invoice, order taken, backup reminder). Persists to Sembast. `unreadNotificationCountProvider` (int, for bell badge). `markAllAsRead()`, `clearAll()`, `markAsRead(id)`.
- [ ] T104 [P] Implement notification card widget in `lib/features/notifications/widgets/notification_card.dart`: layout per V1_FLOW_GUIDE.md §15: circular icon container (colored by type: ⭐ yellow rating, 💲 blue payment, 📄 green invoice, ➕ green order taken) + title (bold white 16sp) + subtitle (gray 14sp) + optional detail field (darker bg, blue left border, key-value pairs) + relative timestamp (gray 12sp) + green unread dot (top-right) + ⋮ overflow menu.
- [ ] T105 Extend notifications screen (T028) in `lib/features/notifications/screens/notifications_screen.dart`: overflow menu with "Mark all as read" (green ✅) and "Clear all" (red 🗑️). Backup reminder pinned first. Tapping each notification type navigates to: trade detail, rate screen, add invoice, pay invoice, etc. per notification type.
- [ ] T106 [P] Implement push notification service in `lib/features/notifications/services/push_notification_service.dart`: platform-gated FCM (Android/iOS via `firebase_messaging`) for background trade alerts. Silent push only — no message content transmitted. Service worker for Web Push. `NotificationListenerWidget` routes push tap payloads to GoRouter. Desktop: relay connection maintained by background process.

**Checkpoint**: All trade lifecycle events generate notifications. Bell badge counts correctly. Tap → correct destination screen. Mark all read / clear all works.

---

## Phase 16: User Story 14 — Settings & Preferences (Priority: P2)

**V1 ref**: Section 14 (`SETTINGS_SCREEN.md`, `NOTIFICATION_SETTINGS.md`, `LOGGING_SYSTEM.md`)

**Goal**: 8 settings cards; all preferences persist; Lightning address pre-fills in trade flows; relay toggle works.

**Independent Test**: Set default fiat to MXN → create order → MXN pre-selected. Set Lightning address → take sell order without NWC → address pre-filled. Toggle relay off → relay list shows disconnected. Language change → UI reflects new locale.

- [ ] T107 Implement settings API in `rust/src/api/settings.rs` per `contracts/settings.md`: `get_settings()`, `set_theme(theme)`, `set_language(locale)`, `set_default_fiat_code(code)`, `set_default_lightning_address(address)`, `set_logging_enabled(enabled)` (runtime-only, not persisted). `privacy_mode` field is read-only mirror of `Identity.privacy_mode` — write via `reputation.set_privacy_mode()` only. Stream: `on_settings_changed()`.
- [ ] T108 Implement settings screen in `lib/features/settings/screens/settings_screen.dart`: 8 cards (Language 🌐, Default Fiat Currency 💱, Lightning Address ⚡, NWC Wallet 👛, Relays 📡, Push Notifications 🔔, Log Report 🛠️, Mostro Node ⚡). NWC card: disconnected shows "Connect your Lightning wallet via NWC" → taps to `/connect_wallet`; connected shows "NWC — Connected. Balance: X sats" → taps to `/wallet_settings`. Route: `/settings`.
- [ ] T109 [P] Implement language selector modal in `lib/features/settings/widgets/language_selector.dart`: list of 5 languages (EN, ES, IT, FR, DE) with native name + code. Tap → `set_language()` + `context.setLocale()`.
- [ ] T110 [P] Implement fiat currency selector dialog in `lib/features/settings/widgets/currency_selector_dialog.dart`: full-screen modal, search bar (magnifying glass + "Search currencies..."), scrollable list (flag + code + full name per entry from `fiat.json`). Tap → `set_default_fiat_code()` + close.
- [ ] T111 [P] Implement relay management card in `lib/features/settings/widgets/relay_management_card.dart`: inline list with green/red status dot + relay URL + on/off toggle. "Add Relay" text button at bottom. Toggle calls `add_relay()`/`remove_relay()` or `set_relay_active()`. Validates wss:// format on add.
- [ ] T112 [P] Implement notification settings screen in `lib/features/settings/screens/notification_settings_screen.dart`: toggles for push notification categories. Route: `/notification_settings`.
- [ ] T113 [P] Implement log report screen in `lib/features/settings/screens/log_report_screen.dart`: scrollable list of `LogEntry` items (level chip, tag, message, timestamp). Toggle logging button. Share button (exports to file). Route: `/logs`.
- [ ] T114 [P] Implement Mostro node selector modal in `lib/features/settings/widgets/mostro_node_selector.dart`: shows current node pubkey (truncated) + "Trusted" badge. Modal allows entering a different node pubkey or selecting from known nodes. Validates hex pubkey format.
- [ ] T115 [P] Implement about screen in `lib/features/about/screens/about_screen.dart`: app version, Mostro docs link, daemon pubkey + relay list (from Kind 38385 event). Route: `/about`.

**Checkpoint**: All 8 settings cards functional. Language, fiat, Lightning address, relays persist and affect dependent flows. Log screen accessible.

---

## Phase 17: User Story 15 — Account & Identity Management (Priority: P2)

**V1 ref**: Section 2 (partially), Account screen (`ACCOUNT_SCREEN.md`)

**Goal**: View/copy secret words, toggle privacy mode, generate new identity.

**Independent Test**: Account screen → masked words → Show → 12 visible. Toggle privacy mode → subsequent trades use anonymous identity. Generate new user → backup reminder reactivates.

- [ ] T116 Extend account screen in `lib/features/account/screens/account_screen.dart`: add privacy mode toggle card ("Reputation mode" / "Full privacy mode") calling `set_privacy_mode()`. Add "Generate New User" option with confirmation dialog: warns this creates a new identity and old backup words won't work. On confirm → `create_identity()` (new mnemonic) → `showBackupReminder()` reactivates → navigate to `/walkthrough` or home with new red dot.
- [ ] T117 [P] Wire privacy mode display: when in Full Privacy mode, trade screens should not show reputation data (rating stars, review count). `orderNotifierProvider` respects privacy mode setting. Settings screen reflects current mode.

**Checkpoint**: All 3 account actions work: view secret words (backup confirmed), toggle privacy mode (affects subsequent trades), generate new identity (backup reminder reactivates).

---

## Final Phase: Polish & Cross-Cutting Concerns

**Purpose**: Finalize localization, responsive layouts, theme, platform-specific features, offline behavior.

- [ ] T118 Complete all ARB localization files: populate all strings in `assets/l10n/app_en.arb` from all feature screens, then translate to `app_es.arb`, `app_it.arb`, `app_fr.arb`, `app_de.arb`. Include walkthrough highlight terms in all 5 languages for `highlight_config.dart`. Run `flutter gen-l10n`. Zero untranslated strings.
- [ ] T119 Implement responsive layout breakpoints in shared widgets (mobile < 600px, tablet 600–1200px, desktop > 1200px): order book shows 1-column on mobile, 2-column on tablet, 3-column on desktop. Drawer becomes persistent sidebar on desktop. Chat room shows side-panel info on tablet+. All per Constitution Principle V.
- [ ] T120 [P] Wire theme toggle (dark/light/system) throughout: `set_theme()` → `AppTheme.darkTheme` / `AppTheme.lightTheme` / `ThemeMode.system` in `MaterialApp.router`. Defaults to System on first launch (dark appearance on most devices). Switchable from Settings. Both themes fully functional.
- [ ] T121 [P] Implement platform-aware QR scanner wrapper in `lib/shared/widgets/platform_aware_qr_scanner.dart`: on iOS/Android/desktop → camera via `mobile_scanner`. On web → paste-from-clipboard text field (no camera access). Used in Connect Wallet screen and anywhere QR scanning is needed.
- [ ] T122 [P] Implement graceful degradation for platform features: push notifications (FCM/APNs/Web Push) → fallback to polling on unsupported platforms. Camera / QR scan → paste-only fallback on web. Biometric → disabled if hardware unavailable. All per Constitution Principle V.
- [ ] T123 Wire offline message queue flushing: in `rust/src/api/nostr.rs` `flush_message_queue()` called automatically on `on_connection_state_changed(Online)` event. `outbox.rs` retries up to 10 attempts, backs off exponentially, prunes sent items.
- [ ] T124 [P] Implement countdown timer widget in `lib/shared/widgets/countdown_timer.dart`: circular progress indicator showing remaining time as "HH:MM:SS". Color-codes as time runs low (green → yellow → red thresholds). Used on Take Order screen (order expiry) and Trade Detail screen (trade step timeout).
- [ ] T125 Run full quickstart.md validation: build and smoke-test on all 5 platforms (iOS simulator, Android emulator, `flutter run -d chrome`, `flutter run -d macos`, `flutter run -d linux`). Verify `cargo test` passes, `cargo clippy -- -D warnings` clean, `flutter test` passes, `flutter analyze` clean.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: No dependencies — start immediately
- **Phase 2 (Foundation)**: Depends on Phase 1 — **BLOCKS all user story phases**
- **Phases 3–17 (User Stories)**: All depend on Phase 2 completion
  - P1 stories (3–11) can proceed in priority order or in parallel if staffed
  - P2 stories (12–17) can begin after Phase 2; recommended after P1 stories are stable
- **Final Phase (Polish)**: Depends on all desired stories being complete

### User Story Dependencies

| Story | Depends On | Reason |
|-------|-----------|--------|
| US1 First Launch | Foundation | Identity API + walkthrough |
| US2 Backup | US1 | `create_identity()` must exist |
| US3 Order Book | Foundation | Relay + order event parsing |
| US4 Create Order | US3 | FAB lives on home screen |
| US5 Take Order | US3 | Take Order launched from order card |
| US6 Buyer Trade | US5 | Continuation of take flow |
| US7 Seller Trade | US5 | Continuation of take flow |
| US8 P2P Chat | US6 or US7 | Chat requires active trade |
| US12 My Trades | US4 or US5 | Trades must exist to list them |
| US9 Dispute | US6 + US7 | Requires active trade execution |
| US10 Rating | US6 + US7 | Post-completion flow |
| US11 NWC | Foundation | Independent wallet module |
| US13 Notifications | US6 + US7 | Trade events to notify about |
| US14 Settings | Foundation | Independent preferences |
| US15 Account | US1 + US2 | Extends identity + backup screens |

### Within Each Phase

- All [P] tasks within a phase can execute in parallel
- Non-[P] tasks must wait for their direct prerequisite within the phase
- Rust API tasks generally precede their corresponding Flutter UI tasks
- Models before services; services before screens; screens before wiring

---

## Parallel Execution Examples

### Phase 2 (Foundation) — Run together:
```
T009 IndexedDB backend       T010 Shared types             T011 NIP-59 Gift Wrap
T012 Relay pool               T013 Message queue            T015 App routes scaffold
```

### Phase 3 (US1 — First Launch) — Run together after T017:
```
T018 ECDH shared key         T019 Nym identity             T022 Highlight config
T026 Placeholder images
```

### Phase 5 (US3 — Order Book) — Run together after T031:
```
T033 Order list item card    T034 Order book providers     T035 Filter dialog
T036 Bottom nav bar          T037 Drawer menu
```

### Phase 10 (US8 — P2P Chat) — Run together after T071:
```
T074 Chat list item          T075 Chat providers           T077 Message bubble
T078 Message input           T079 Info panels              T080 Image message widget
T081 File message widget     T072 Nym avatar
```

---

## Implementation Strategy

### MVP (User Stories 1–3 + US12 foundation)

1. Complete **Phase 1**: Setup
2. Complete **Phase 2**: Foundation — CRITICAL
3. Complete **Phase 3**: US1 (walkthrough + identity)
4. Complete **Phase 4**: US2 (backup reminder)
5. Complete **Phase 5**: US3 (order book — read-only, no trading yet)
6. **STOP and VALIDATE**: App runs, walks through onboarding, shows order book with live data

### Incremental Delivery

- **MVP + Create**: Add US4 → user can post orders
- **MVP + Trade**: Add US5+US6+US7 → complete P2P trades possible (Lightning + NWC)
- **+ Chat**: Add US8 → in-trade communication
- **+ My Trades**: Add US12 → trade history + status tracking
- **+ Disputes**: Add US9 → conflict resolution
- **+ Rating**: Add US10 → reputation system live
- **+ Polish**: Add US11+US13+US14+US15 + Final Phase → production-ready

### Parallel Team Strategy

With 3+ developers after Phase 2 completes:
- **Dev A**: US1 → US2 → US15 (identity + account track)
- **Dev B**: US3 → US4 → US5 (order book track)
- **Dev C**: US6 → US7 → US8 (trade execution track)
- **Dev D**: US9 → US10 → US13 (dispute + rating + notifications track)
- **Dev E**: US11 → US14 (wallet + settings track)

---

## Notes

- [P] tasks operate on different files with no dependency on incomplete tasks in the same phase
- Every screen must follow `DESIGN_SYSTEM.md` tokens exactly — no improvising colors or typography
- Before implementing any screen, read its corresponding `.specify/v1-reference/<SCREEN>.md` file
- `V1_FLOW_GUIDE.md` is the authoritative behavior spec — do not invent behavior not described there
- Tab labels on the Home screen are from the **taker's perspective**: "BUY BTC" shows sell orders
- `PaymentFailed` is NOT an `OrderStatus` — it is an `Action` notification; order stays `SettledHoldInvoice`
- `CooperativelyCanceled` is a **client-side UI state only** — protocol sends action notifications
- Nym avatar icons MUST always render in **white** regardless of `color_hue` (v1 bug fix, see `contracts/types.md`)
- `privacy_mode` single write path is `reputation.set_privacy_mode()` — never write `Settings.privacy_mode` directly
- `logging_enabled` is runtime-only — always `false` at startup regardless of stored value
- Commit after each task or logical group; stop at any checkpoint to validate independently
