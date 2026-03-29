# Dispute System Specification (Mostro Mobile v1)

> Reference for section 8 (DISPUTES) covering the in-app dispute list, admin chat, and dispute creation pipeline.

## Scope

- Route `/dispute_details/:disputeId`
- Screens & widgets: `ChatRoomsScreen` (disputes tab), `DisputesList`, `DisputeListItem`, `DisputeChatScreen`, `DisputeMessagesList`, `DisputeInfoCard`, `DisputeMessageInput`
- Providers & services: `chatTabProvider`, `userDisputeDataProvider`, `disputeDetailsProvider`, `disputeChatNotifierProvider`, `disputeReadStatusProvider`, `DisputeRepository`, `DisputeReadStatusService`
- Data models: `Dispute`, `DisputeData`, `Session.adminSharedKey`
- Storage & transport: Sembast event store (`type: dispute_chat`), NIP-59 gift wrap, admin shared-key ECDH

## Source files reviewed

- `lib/features/chat/screens/chat_rooms_list.dart`
- `lib/features/chat/widgets/chat_tabs.dart`
- `lib/features/disputes/widgets/disputes_list.dart`
- `lib/features/disputes/widgets/dispute_list_item.dart`
- `lib/features/disputes/widgets/dispute_content.dart`
- `lib/features/disputes/widgets/dispute_info_card.dart`
- `lib/features/disputes/widgets/dispute_messages_list.dart`
- `lib/features/disputes/widgets/dispute_message_input.dart`
- `lib/features/disputes/widgets/dispute_message_bubble.dart`
- `lib/features/disputes/screens/dispute_chat_screen.dart`
- `lib/features/disputes/notifiers/dispute_chat_notifier.dart`
- `lib/features/disputes/providers/dispute_providers.dart`
- `lib/features/disputes/providers/dispute_read_status_provider.dart`
- `lib/services/dispute_read_status_service.dart`
- `lib/data/repositories/dispute_repository.dart`
- `lib/data/models/dispute.dart`
- `lib/features/order/models/order_state.dart`
- `lib/data/models/session.dart`
- `lib/features/trades/screens/trade_detail_screen.dart`

---

## 1) Entry points & navigation

### Chat tab integration (`/chat_list`)
- `ChatRoomsScreen` renders a two-tab layout via `ChatTabs`. Tabs map to `ChatTabType.messages` (P2P chat) and `ChatTabType.disputes`.
- Switching tabs updates `chatTabProvider`; horizontal swipes also toggle tabs.
- The disputes tab swaps the main list for `DisputesList`, so users can reach disputes without leaving the chat module.
- A short contextual description is displayed under the tabs ("Here are your disputes" vs "Here are your chats").

### Trade Detail → Dispute button
- `TradeDetailScreen` surfaces a **Dispute** button whenever the action set contains `actions.Action.dispute` and no dispute is already in progress.
- Tapping Dispute prompts a confirmation dialog; if confirmed, it calls `DisputeRepository.createDispute(orderId)` (see §3) and shows a snackbar on success/failure.
- Once a dispute exists (`tradeState.dispute?.disputeId != null`), the CTA switches to **View dispute** which links to `/dispute_details/:disputeId`.

### Automatic navigation via Mostro events
- `AbstractMostroNotifier` listens to Mostro DM actions:
  - `disputeInitiatedByYou`, `disputeInitiatedByPeer`, `adminTookDispute`, `adminSettled`, `adminCanceled` all push `/trade_detail/:orderId` to keep both parties on the trade screen when a dispute state changes.
  - Admin assignment (`adminTookDispute`) also updates the session's admin shared key (see §4), enabling the dispute chat to decrypt admin messages.

---

## 2) Status taxonomy

Four independent status systems coexist during a dispute. Confusing them causes implementation bugs.

| Layer | Where it lives | Values during dispute lifecycle | Notes |
|---|---|---|---|
| **Order status (public)** | Kind 38383 event, tag `s` | **Does not change** when a dispute opens. Updates to `success` (admin-settle) or `canceled` (admin-cancel) only at resolution. | The public order book never shows `dispute`. |
| **Order status (internal + DMs)** | Mostrod database + gift-wrapped DMs to users | Changes to `dispute` when a dispute is opened (`setup_dispute()` in mostro-core). Then to `success` or `canceled` at resolution. | This is a real protocol order status — mostrod checks `Status::Dispute` before allowing admin-settle or admin-cancel. It reaches clients via gift wraps but is never published in kind 38383 events. |
| **Dispute status (protocol)** | Kind 38386 event, tag `s` | `initiated` → `in-progress` → `settled` \| `seller-refunded` | Authoritative source: `mostro-core::dispute::Status` enum. |
| **Local UX dispute status (v1 app)** | `Dispute.status` string field set by `OrderState.updateWith()` | `in-progress`, `resolved`, `seller-refunded`, `closed` | **Never sent to Mostro.** Client-side labels for UI rendering. `resolved` and `closed` do not exist in the protocol. |

**Mapping between protocol and v1 UX statuses:**

| Protocol trigger | Protocol dispute status (kind 38386) | Protocol order status (DM) | V1 local UX `Dispute.status` |
|---|---|---|---|
| User opens dispute | `initiated` | `dispute` | *(not overwritten — keeps value from action)* |
| Admin takes dispute | `in-progress` | `dispute` (unchanged) | `in-progress` |
| Admin settles | `settled` | `success` | `resolved` |
| Admin cancels | `seller-refunded` | `canceled` | `seller-refunded` |
| User completes trade / cooperative cancel | *(no protocol update to kind 38386 from client — mostrod calls `close_dispute_after_user_resolution()` server-side)* | `success` / `canceled` | `closed` |

---

## 3) Repository, data model, and dispute creation

### `DisputeRepository`
- `createDispute(orderId)` builds a `MostroMessage(action: Action.dispute, id: orderId)` and wraps it using NIP-59 gift wrap with the user's `tradeKey` and the configured Mostro pubkey (`settingsProvider.mostroPublicKey`).
- Proof-of-work difficulty uses `MostroInstance.pow`; if unavailable it logs a warning and sends with difficulty 0.
- `NostrService.publishEvent` broadcasts the wrapped event; the repository returns `true/false` to show snackbars.
- `getUserDisputes()` and `getDispute(disputeId)` never hit a remote endpoint. They walk all `sessionNotifierProvider` sessions, read each `orderNotifierProvider(orderId)` and collect `OrderState.dispute` objects.

### Data types
- `Dispute` implements `Payload` so Mostro DMs can embed it. Its `status` field is a free-form `String?` — **not** a protocol enum. When a `Dispute` arrives from Mostro (e.g., inside a `dispute-initiated-by-you` DM), the status reflects the protocol dispute status (e.g., `initiated`). However, `OrderState.updateWith()` later overwrites this field with local UX values (`resolved`, `closed`) that do not exist in the protocol. See §2 Status taxonomy for the full mapping.
- `DisputeData` is the UI view model (order ID, counterparty, user role, `DisputeDescriptionKey`, etc.). It derives `descriptionKey` from normalized statuses and stores whether the current user initiated the dispute.
- `DisputeDescriptionKey` drives localized copy ("You opened a dispute", "Waiting for admin assignment", "Admin closed the dispute"...).

### Status & action normalization (from `OrderState`)

**Order status mapping:**
- Actions `disputeInitiatedByYou`, `disputeInitiatedByPeer`, `dispute`, `adminTakeDispute`, `adminTookDispute` set the **order status** to `Status.dispute` in the v1 app. This mirrors the real protocol behavior: mostrod sets the internal order status to `dispute` via `setup_dispute()`, though this status is never published in kind 38383 public events.

**Local UX dispute status mapping** (via `OrderState.updateWith()` writing to `Dispute.status`):
- Stamps `createdAt` from the DM timestamp for sorting.
- `adminTookDispute` → local `Dispute.status = 'in-progress'`, saves `adminPubkey`, triggers `Session.setAdminPeer`. *(Matches protocol dispute status `in-progress`.)*
- `adminSettled` → local `Dispute.status = 'resolved'`, `action = 'admin-settled'`. *(Protocol dispute status is `settled`, not `resolved`. `resolved` is a v1 UX-only label.)*
- `adminCanceled` → local `Dispute.status = 'seller-refunded'`, `action = 'admin-canceled'`. *(Matches protocol dispute status `seller-refunded`.)*
- User-completed or cooperative-cancel terminal order states → local `Dispute.status = 'closed'`, `action = 'user-completed'` or `'cooperative-cancel'`. *(`closed` does not exist in the protocol. The kind 38386 dispute event is updated by mostrod via `close_dispute_after_user_resolution()` with status `settled` or `seller-refunded`, but the v1 app does not read that event — it uses its own local label.)*

---

## 4) Session & admin shared key handshake

- Sessions (`lib/data/models/session.dart`) store both the counterparty shared key (`peer`) and an optional `adminSharedKey`.
- When `adminTookDispute` arrives, `AbstractMostroNotifier` extracts the admin pubkey from the event payload (`Peer`) or existing `Dispute.adminPubkey`, calls `sessionNotifier.updateSession(orderId, setAdminPeer)` and recomputes the shared key via ECDH.
- `DisputeChatNotifier` requires `session.adminSharedKey` before subscribing. Until the key exists, it listens to `sessionNotifierProvider` and retries subscription automatically.
- Attachments (`ChatFileUploadHelper`, `EncryptedImageUploadService`, `EncryptedFileUploadService`) call `DisputeChatNotifier.getAdminSharedKey()` to fetch raw ChaCha20 keys for encryption/decryption.

---

## 5) Dispute list UX & unread state

### `DisputesList`
- Driven by `userDisputeDataProvider`, which memoizes `DisputeData` list, sorts by `createdAt` DESC, and rebuilds whenever sessions or order states change.
- Loading state: centered spinner. Error state: icon + "Retry" button that invalidates the provider.
- Empty state: gavel icon + helper text ("Your disputes will appear here").

### `DisputeListItem`
- Wraps `DisputeContent` and `DisputeIcon`; tapping marks the dispute as read via `DisputeReadStatusService.markDisputeAsRead(disputeId)` then pushes `/dispute_details/:id`.
- `DisputeContent` pulls:
  - `DisputeHeader` (status badge color-coded via `DisputeStatusBadge`).
  - Order ID (`DisputeOrderId`).
  - Description text (`DisputeDescription`) which, for `status == in-progress`, shows the last admin/user message fetched from `disputeChatNotifierProvider`.
  - Unread dot: `FutureBuilder` calls `DisputeReadStatusService.hasUnreadMessages(...)`, comparing message timestamps against the stored `SharedPreferences` key (`dispute_last_read_{id}`).
- `disputeReadStatusProvider` is a `StateProvider.family<int, String>` used solely to trigger rebuilds when a dispute is marked as read (timestamp bump).

### Tab description copy
- When `ChatTabType.disputes` is active, `ChatRoomsScreen` shows `S.disputesDescription` ("Here you talk with admins"), reinforcing that this is a separate space from P2P chat.

---

## 6) Dispute detail & chat screen

### `DisputeChatScreen`
- Receives `disputeId` from GoRouter, `watch(disputeDetailsProvider(disputeId))` to load the latest `Dispute` (or show "not found").
- On `initState`, it marks the dispute as read and updates `disputeReadStatusProvider`.
- Converts the domain model (`Dispute`) into `DisputeData` using both `sessionNotifierProvider` and `orderNotifierProvider` to pull role/counterparty data.
- Layout:
  1. `DisputeCommunicationSection` → `DisputeMessagesList`
  2. `DisputeMessageInput` rendered **only** when the local UX `DisputeData.status == 'in-progress'`. Disputes with any other local status (`initiated`, `resolved`, `seller-refunded`, `closed`) become read-only logs.

### `DisputeMessagesList`
- Combines informational UI and chat messages into a single scroll view:
  - `SliverToBoxAdapter` shows a blue "Admin assigned" card if status = `in-progress` and there are no messages yet.
  - First list item is always `DisputeInfoCard` (order ID, dispute ID, user role, counterparty nickname via `nickNameProvider`).
  - Remainder: `DisputeMessageBubble` entries sorted by timestamp, deduped by message ID.
  - For terminal local UX statuses (`resolved`, `seller-refunded`, `closed`), an extra "Chat closed" lock banner is appended. These are all v1 app-local values; see §2 for protocol equivalents.
- Handles empty chat gracefully: waiting-for-admin copy, no-messages-yet placeholders, etc.
- Auto-scrolls to the bottom whenever new messages arrive and the user is near the bottom.

### `DisputeMessageInput`
- Shares the same UX pattern as P2P chat: attach button (wired to `ChatFileUploadHelper.selectAndUploadFile`), text box, send button.
- Attachment workflow uses the admin shared key instead of the counterparty shared key.
- While a file upload is in progress, the attach icon is replaced by a `CircularProgressIndicator`.

---

## 7) Messaging pipeline & storage

### Provider & state
- `disputeChatNotifierProvider` is a `StateNotifierProvider.family<DisputeChatNotifier, DisputeChatState, String>`.
- `DisputeChatState` stores `messages`, `isLoading`, and `error` (global error, e.g., failed history fetch). `DisputeChatMessage` wraps `NostrEvent` with `isPending` and per-message `error` fields for optimistic UI.

### Initialization & history
- `initialize()` loads history and subscribes once (idempotent guard `_isInitialized`).
- Historic events are stored in Sembast with `type: 'dispute_chat'` and `dispute_id: <id>`. Each record keeps the full gift wrap payload (`kind`, `content`, `tags`, etc.).
- `_loadHistoricalMessages()` filters by `type` + `dispute_id`, unwraps each gift wrap with `session.adminSharedKey`, converts to `DisputeChatMessage`, deduplicates by inner event ID, and sorts ascending.

### Live subscription
- `_subscribe()` builds a `NostrRequest` for kind `1059` events where the `p` tag matches `session.adminSharedKey.public`.
- `NostrService.subscribeToEvents()` feeds `_onChatEvent`:
  1. Verify event kind & `p` tag.
  2. Skip duplicates using `eventStore.hasItem(wrapperEventId)`.
  3. Persist the encrypted wrapper (`type: dispute_chat`).
  4. `p2pUnwrap` with the admin shared key (single-layer gift wrap).
  5. Skip empty content; create `DisputeChatMessage` and append to state (dedupe, sort).
  6. Fire-and-forget `_processMessageContent()` to pre-download Blossom files/images.

### Sending messages
- `sendMessage(text)` creates the inner rumor event (kind 1) **before** wrapping so the optimistic UI uses the final message ID.
- The UI appends a pending bubble, wraps the rumor with `session.adminSharedKey.public`, publishes via `nostrService.publishEvent`, and persists the wrapper to Sembast.
- On failure, the pending bubble flips `error` and `isPending=false`.
- The relay echo eventually arrives via `_onChatEvent`, which dedupes by ID.

### Multimedia support
- `DisputeMessageBubble` inspects the message via `MessageTypeUtils` (text, encrypted image, encrypted file).
- Image/file widgets reuse the shared cache mixin (`MediaCacheMixin`) provided by `DisputeChatNotifier`.
- Attachment download requires `getAdminSharedKey()`; missing shared keys throw an exception and display errors in logs.

### Read state & badges
- `DisputeReadStatusService` stores timestamps in `SharedPreferences` and exposes `hasUnreadMessages(disputeId, messages, isFromUser)` to check for any admin messages newer than the last read time.
- `DisputeChatScreen` marks the dispute as read on `initState`; `DisputeListItem` also marks as read when tapping from the list to keep both entry points in sync.

---

## 8) Dispute lifecycle & order status integration

### Initiation
1. User taps **Dispute** in Trade Detail.
2. `DisputeRepository.createDispute` sends the gift wrap event.
3. Mostro responds with `disputeInitiatedByYou` (for initiator) and `disputeInitiatedByPeer` (for the counterpart).
4. `OrderState` stores the `Dispute` payload and transitions the **order status** to `Status.dispute`. This is a real protocol order status — mostrod also sets it internally via `setup_dispute()` — but it is only communicated via DMs, never in kind 38383 public events. The UI shows the red "Dispute" chip.

### Admin assignment
1. When an admin takes the dispute, Mostro sends `adminTookDispute` with a `Peer` payload representing the admin.
2. `OrderState.updateWith()` marks the dispute `status: in-progress` and copies the admin pubkey.
3. `Session.setAdminPeer` computes `adminSharedKey`, enabling dispute chat encryption.
4. `DisputeMessagesList` shows the blue "Admin assigned" card until the first message arrives.

### Resolution paths
- **Admin settled** (`adminSettled`):
  - *Protocol*: dispute event (kind 38386) → `settled`; order event (kind 38383) → `success`; order DM status → `success`.
  - *V1 app*: local `Dispute.status = 'resolved'` (UX-only, does not exist in protocol), `action = 'admin-settled'`.
  - *UI effect*: `DisputeMessagesList` hides the input and shows the lock banner. `DisputeStatusContent` renders "Admin released the sats".
- **Admin canceled** (`adminCanceled`):
  - *Protocol*: dispute event (kind 38386) → `seller-refunded`; order event (kind 38383) → `canceled`; order DM status → `canceled`.
  - *V1 app*: local `Dispute.status = 'seller-refunded'` (matches protocol), `action = 'admin-canceled'`.
- **User completed / cooperative cancel** (trade resolves without admin):
  - *Protocol*: mostrod calls `close_dispute_after_user_resolution()` updating the kind 38386 event to `settled` (release) or `seller-refunded` (cancel). Order events update normally.
  - *V1 app*: local `Dispute.status = 'closed'` (UX-only, does not exist in protocol), `action = 'user-completed'` or `'cooperative-cancel'`. The app does not read the updated kind 38386 event.

### Unread + notification flows
- Because `DisputeReadStatusService` works off timestamps, any new message (admin or user) increments the badge automatically until the user opens the chat.
- The P2P chat badge (`chatCountProvider`) is independent; disputes currently rely on the red dot inside the list items.

---

## 9) Cross-references

| Topic | Document |
|-------|----------|
| Trade Detail actions & dispute button | [TRADE_EXECUTION.md](./TRADE_EXECUTION.md) |
| Order status transitions & dispute closure | [ORDER_STATUS_HANDLING.md](./ORDER_STATUS_HANDLING.md) |
| P2P chat architecture (shared widgets, media pipeline) | [P2P_CHAT_SYSTEM.md](./P2P_CHAT_SYSTEM.md) |
| Session & key management (admin shared key storage) | [SESSION_AND_KEY_MANAGEMENT.md](./SESSION_AND_KEY_MANAGEMENT.md) |
| Navigation routes table | [NAVIGATION_ROUTES.md](./NAVIGATION_ROUTES.md) |
