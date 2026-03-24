# P2P Chat System — Implementation Architecture

This document describes how the peer-to-peer chat between trading parties works at the implementation level: how events flow from relays to the UI, how messages are persisted, what is stored encrypted vs. in plaintext, and known issues that have been fixed.

For the **protocol specification** (NIP-59, ECDH, event format), see the [Mostro P2P Chat protocol](https://mostro.network/protocol/chat.html) ([source](https://github.com/MostroP2P/protocol)).

---

## Scope

This section documents everything that powers **Mostro Mobile v1 section 7: PEER-TO-PEER CHAT**:

- Routes `/chat_list` (chat hub) and `/chat_room/:orderId` (per-trade chat room) plus the UI widgets layered on top of them (`ChatRoomsScreen`, `ChatRoomScreen`, `ChatTabs`, `MessageInput`, `MessageBubble`, etc.).
- State derived from Riverpod providers: `chatRoomsProvider`, `chatRoomsNotifierProvider`, `sortedChatRoomsProvider`, `sessionProvider`, `orderNotifierProvider`, `chatTabProvider`.
- Messaging plumbing: `ChatRoomNotifier`, `ChatRoomsNotifier`, `SubscriptionManager`, `eventStorage`, and the Blossom upload/download helpers for media.
- Read-status indicators (`ChatReadStatusService`) and navigation badges (`chatCountProvider`).
- Error handling (missing sessions, keyboard-safe layout) and lifecycle hooks (`appInitializerProvider`, `LifecycleManager`).

Everything in this file is already implemented in Dart/Flutter and needs to be mirrored (or consumed) by the new stack.

## Navigation & Entry Points

- **Bottom nav:** `BottomNavBar` assigns tab index 2 to `/chat_list`. It observes `chatCountProvider` to draw a red dot when there are unread messages (other flows bump that provider).
- **Drawer:** `ChatRoomsScreen` is wrapped by `CustomDrawerOverlay`, so the global drawer shortcuts can push `/chat_list` as well.
- **My Trades → Chat:** `TradeDetailScreen` exposes a "Contact" button that calls `context.push('/chat_room/$orderId')` so users can jump directly into the threaded chat for the active trade.
- **Notifications:** `NotificationListenerWidget` and the FCM actions route intent payloads (e.g., tapping a "new message" push) through `GoRouter`, so links such as `/chat_room/{orderId}` land on the same screen.

From the user's point of view the navigation stack is always: **Home → My Trades → Trade Detail → Chat** or Home → Chat tab.

## Chat List (`ChatRoomsScreen`, route `/chat_list`)

### Layout & tabs

- Rooted inside a `Scaffold` with `MostroAppBar`, drawer overlay, and a permanently pinned `BottomNavBar`.
- Header section renders the “Chat” title plus the `ChatTabs` component (two tabs: `messages` and `disputes`). Swiping left/right on the content area also flips between tabs via `chatTabProvider`.
- Below the tabs there is a short description copy (different per tab) and then the main content area. When tab = `ChatTabType.disputes`, the widget swaps to `DisputesList` (same component used by the disputes module).
- When tab = `messages`, `_buildBody()` renders either `EmptyStateView` (if there are no chats) or a `ListView.builder` of `ChatListItem`s. Extra bottom padding keeps content clear of the nav bar.

### Data sources & sorting

- The screen watches `sortedChatRoomsProvider`, which:
  1. Listens to `chatRoomsNotifierProvider` (a `StateNotifier<List<ChatRoom>>`).
  2. For each `ChatRoom` it re-reads `chatRoomsProvider(orderId)` to ensure the freshest in-memory state (messages, metadata) is used.
  3. Sorts chats by the session start time (`sessionProvider(orderId).startTime`), most recent first. If a session is missing it falls back to `DateTime.now()` so new chats drift to the top.
- `ChatRoomsNotifier` constructs its list from `sessionNotifierProvider.sessions`. Only sessions that (a) have an `orderId`, (b) have a `peer` or started in the last hour, and (c) already fetched at least one message are shown. This prevents empty shells from cluttering the list. Whenever a chat gains messages, `ChatRoomNotifier` calls `refreshChatList()` so the list re-sorts.
- App startup (`appInitializerProvider`) eagerly instantiates `chatRoomsProvider(orderId)` for all non-expired sessions so `_loadHistoricalMessages()` runs before the user opens the chat tab.

### Chat list item details

- `ChatListItem` composes:
  - **Avatar & handle:** `NymAvatar` + `nickNameProvider(peerPubkey)`.
  - **Context line:** “You are selling to/buying from {handle}” based on `session.role`.
  - **Last message preview:** The last entry in `chatRoom.messages` (constructor sorts ascending, so `.last` is the newest). Own messages are prefixed with the localized "You:" label.
  - **Timestamp chip:** Uses `Intl.DateFormat` to show `HH:mm`, “Yesterday”, weekday, or `MMM d` depending on age.
  - **Unread dot:** `ChatReadStatusService.hasUnreadMessages(orderId, messages, currentUserPubkey)` compares the last read timestamp (stored in `SharedPreferences`) against peer messages. If any peer message is newer, a red dot is displayed until the user enters the room. `onTap` optimistically sets `_isMarkedAsRead = true`, awaits `markChatAsRead()`, and then pushes `/chat_room/{orderId}`.
- Placeholder skeletons render while a session or peer info is missing, so the list height stays stable during provider churn.

## Chat Room (`ChatRoomScreen`, route `/chat_room/:orderId`)

### Structure & dependencies

- Watches `chatRoomsProvider(orderId)` for decrypted messages/state, `sessionProvider(orderId)` for role + peer metadata, and `orderNotifierProvider(orderId)` for live order status (passed into the info tabs).
- If the session or peer is missing, the screen immediately returns `ChatErrorScreen.sessionNotFound()` / `.peerUnavailable()` instead of trying to send messages without a shared key.
- The Scaffold includes a custom app bar (“Back”), the `PeerHeader`, optional info tabs, the message list, the composer, and (when the keyboard is hidden) the global `BottomNavBar` so users can hop elsewhere without popping the stack.
- `_selectedInfoType` toggles between `null`, `'trade'`, and `'user'`. Focusing the message input automatically clears any info panel via `_handleInfoTypeChanged(null)` so the composer never overlaps the sheet.

### Trade & user info panels

- `InfoButtons` expose two CTA-style buttons:
  - **Trade information** (`TradeInformationTab`): shows order ID, fiat amount, formatted “Buying/Selling {sats}”, localized status chip (colors from `AppTheme`), payment method, and creation date. It relies on `order.copyWith(status: orderState.status)` so the UI reflects local FSM updates.
  - **User information** (`UserInformationTab`): shows the peer avatar, handle, public key (copyable via `ClickableText`), your own handle, and the derived shared key (or “Not available” if the session has not negotiated keys yet).

### Message timeline

- `ChatMessagesList` renders `chatRoom.messages` sorted chronologically (oldest first) using a dedicated `ScrollController`. It auto-scrolls to the bottom on first load and whenever the message count changes. The controller is also plumbed into `_scrollController` on `ChatRoomScreen` so keyboard visibility triggers tiny scroll animations that keep the composer visible.
- Each message is rendered by `MessageBubble`, which detects content type via `MessageTypeUtils`:
  - Plain text → standard bubble with long-press copy-to-clipboard.
  - `image_encrypted` → `EncryptedImageMessage`, including cached previews and secure open-in-viewer handling.
  - `file_encrypted` → `EncryptedFileMessage`, including download buttons, metadata chips, and safe temporary files.
- Optimistic sends: after the user sends a message, the plaintext `NostrEvent` is appended immediately so it appears in the list before the relay echo arrives.

### Composer & attachments

- `MessageInput` maintains a `TextEditingController`, `FocusNode`, and an `_isUploadingFile` flag. The attachment icon is disabled and shows a spinner while uploads run.
- `_sendMessage()` trims whitespace, delegates to `chatRoomsProvider(orderId).notifier.sendMessage(text)`, clears the field, and re-focuses the input.
- `_selectAndUploadFile()` calls `ChatFileUploadHelper.selectAndUploadFile()` with three callbacks:
  - `getSharedKey` (from `ChatRoomNotifier`) returns the raw ChaCha20 key bytes.
  - `sendMessage` posts the JSON metadata returned by the upload services.
  - `isMounted` guards snackbar/dialog updates when the widget tree is gone.
- `ChatFileUploadHelper` enforces file-size/type limits via `FileValidationService` + `MediaValidationService`, runs a confirmation dialog, encrypts the file with ChaCha20-Poly1305, uploads to Blossom (`BlossomUploadHelper`/`BlossomClient`), and finally sends the `image_encrypted` or `file_encrypted` JSON blob back through the chat pipeline.

### Keyboard, drawer & errors

- `didChangeDependencies` listens for keyboard openings; when the keyboard opens it scrolls the list down a bit to keep the latest messages unobstructed.
- The message list is wrapped in `CustomDrawerOverlay`, so swiping from the edge still reveals the global drawer even inside a chat.
- While `ChatRoomNotifier` is still loading history, the UI shows a centered `CircularProgressIndicator`. If initialization fails, the notifier leaves `chatRoomInitializedProvider` as `false` and the UI stays in the loading state until the user backs out.

---

## State & Transport Components


| Component | File | Responsibility |
|---|---|---|
| `SubscriptionManager` | `lib/features/subscriptions/subscription_manager.dart` | Single Nostr subscription for all chats, broadcast stream |
| `ChatRoomNotifier` | `lib/features/chat/notifiers/chat_room_notifier.dart` | Per-order chat: receives events, stores to disk, decrypts, manages state |
| `ChatRoomsNotifier` | `lib/features/chat/notifiers/chat_rooms_notifier.dart` | Chat list: loads, refreshes, reloads all chats |
| `chatRoomsProvider` | `lib/features/chat/chat_room_provider.dart` | Riverpod family provider, creates and initializes `ChatRoomNotifier` |
| `EventStorage` | `lib/data/repositories/event_storage.dart` | Sembast store for gift wrap events |
| `Session` | `lib/data/models/session.dart` | Holds trade keys, peer info, computes shared key via ECDH |
| `NostrEvent` extensions | `lib/data/models/nostr_event.dart` | `p2pWrap()` / `p2pUnwrap()` — encrypt/decrypt gift wraps |

---

## Message Flow: Receiving

```text
Relay
  │  kind 1059 gift wrap events (encrypted)
  ▼
NostrService (WebSocket)
  │
  ▼
SubscriptionManager
  │  ONE subscription with ALL sharedKey pubkeys in a single NostrFilter
  │  Events dispatched via StreamController.broadcast()
  ▼
ChatRoomNotifier._onChatEvent()  (one listener per active chat)
  │
  ├─ 1. Check p-tag matches this chat's sharedKey.public → skip if not ours
  ├─ 2. Dedup: eventStore.hasItem(event.id) → skip if already stored
  ├─ 3. Store encrypted gift wrap to Sembast (kind 1059, NIP-44 encrypted content)
  ├─ 4. Decrypt: event.p2pUnwrap(sharedKey) → plaintext kind 1 event
  ├─ 5. Add to state.messages (in-memory only)
  └─ 6. Notify chat list to refresh
```

### Key detail: single subscription, multiple listeners

`SubscriptionManager` creates **one** relay subscription containing all active chat shared key pubkeys:

```dart
// subscription_manager.dart — _createFilterForType()
NostrFilter(
  kinds: [1059],
  p: sessions
      .where((s) => s.sharedKey?.public != null)
      .map((s) => s.sharedKey!.public)
      .toList(),  // ALL shared keys in ONE filter
);
```

The relay sends events for all chats through this single subscription. Events are dispatched via a `StreamController.broadcast()` to all `ChatRoomNotifier` instances. Each notifier checks the event's `p` tag to determine if the event belongs to its chat.

---

## Message Flow: Sending

```text
User types message
  │
  ▼
ChatRoomNotifier.sendMessage(text)
  │
  ├─ 1. Create kind 1 inner event, signed with tradeKey
  ├─ 2. p2pWrap(tradeKey, sharedKey.public) → kind 1059 gift wrap
  │     - Generates ephemeral key pair (single-use)
  │     - Encrypts inner event JSON with NIP-44 (ephemeral private + shared pubkey)
  │     - p-tag = sharedKey.public
  │     - Timestamp randomized to prevent time analysis
  ├─ 3. Publish wrapped event to relay
  ├─ 4. Persist wrapped event to Sembast (encrypted, kind 1059)
  ├─ 5. Add inner event (plaintext) to state.messages for immediate UI display
  └─ 6. Notify chat list to refresh
```

Step 4 ensures sent messages survive app restarts even if the relay echo never arrives (e.g., connection drops after send). When the relay echo does arrive, `_onChatEvent` skips it via the `hasItem` dedup check.

---

## Storage: What Is on Disk

Events are stored in Sembast's `events` store as encrypted gift wraps:

```dart
{
  'id': event.id,                    // event hash
  'created_at': <unix timestamp>,
  'kind': 1059,                      // gift wrap
  'content': '<NIP-44 encrypted>',   // ciphertext — NOT readable without private key
  'pubkey': '<ephemeral pubkey>',    // single-use key, does not identify the sender
  'sig': '<ephemeral signature>',
  'tags': [['p', '<sharedKey.public>']],
  'type': 'chat',                    // app metadata
  'order_id': '<orderId>',           // app metadata — links event to a specific trade
}
```

**Privacy properties:**
- The `content` field is NIP-44 encrypted. Reading it requires the ECDH shared key's private component.
- The `pubkey` is an ephemeral key generated per message. It does not identify the sender.
- The `p` tag contains the shared key's public component, not any party's real identity.
- The `order_id` is app-internal metadata not present in the Nostr event itself.

**What is NOT on disk:**
- Plaintext message content
- Sender identity (trade pubkey is inside the encrypted payload)
- Any private keys

---

## Storage: What Is in Memory

`state.messages` holds decrypted `NostrEvent` objects (kind 1) in RAM:

```dart
// After p2pUnwrap:
NostrEvent(
  kind: 1,
  content: "Let's reestablish the peer-to-peer nature of Bitcoin!",  // plaintext
  pubkey: "<sender's trade pubkey>",
  // ...
)
```

These exist **only in memory**. When the app closes, they are lost. On restart, `_loadHistoricalMessages()` reads the encrypted gift wraps from Sembast and decrypts them again.

---

## Shared Key Lifecycle

The shared key is never stored directly. It is computed via ECDH every time a `Session` has a `peer`:

```dart
// session.dart
set peer(Peer? newPeer) {
  _peer = newPeer;
  _sharedKey = NostrUtils.computeSharedKey(
    tradeKey.private,
    newPeer.publicKey,
  );
}
```

On app restart:
1. `SessionNotifier.init()` loads sessions from Sembast (peer is persisted)
2. The `Session` constructor calls `computeSharedKey` with the persisted peer's public key
3. The shared key is available in memory — no separate storage needed

---

## Initialization Sequence

### App startup (`app_init_provider.dart`)

```text
1. NostrService.init()         → relay connections
2. KeyManager.init()           → crypto keys from secure storage
3. MostroNodes.init()          → node metadata
4. SessionNotifier.init()      → loads sessions from Sembast (sharedKey computed here)
5. SubscriptionManager created → subscribes to relay with all session keys
6. For each session with peer:
   └─ Read chatRoomsProvider(orderId) → creates ChatRoomNotifier
      └─ _initializeChatRoomSafely() [async]
         ├─ _loadHistoricalMessages() → reads encrypted events from disk, decrypts
         └─ subscribe() → listens to broadcast stream
```

### Chat room initialization (`chat_room_provider.dart`)

When `chatRoomsProvider(orderId)` is first read, it:
1. Creates a `ChatRoomNotifier` with empty messages
2. Calls `_initializeChatRoomSafely()` (async, fire-and-forget)
3. Returns the notifier immediately (messages may not be loaded yet)

`_initializeChatRoomSafely()` then:
1. Calls `notifier.initialize()` → loads history from disk + subscribes to stream
2. Marks `chatRoomInitializedProvider(chatId)` as true

### Reconnection (`lifecycle_manager.dart`)

When the app returns to foreground after losing connection:
1. `NostrService` reconnects to relays
2. `reloadAllChats()` is called
3. Each `ChatRoomNotifier.reload()`:
   - Cancels current stream listener
   - Reloads messages from disk (`_loadHistoricalMessages`)
   - Re-subscribes to broadcast stream

---

## Historical Loading (`_loadHistoricalMessages`)

```text
Sembast query: WHERE type = 'chat' AND order_id = orderId
  │
  ▼
For each stored event:
  ├─ Reconstruct NostrEvent from stored map
  ├─ Verify p-tag matches session.sharedKey.public
  ├─ p2pUnwrap(sharedKey) → decrypt to kind 1 inner event
  └─ Add to historicalMessages list
  │
  ▼
Merge with existing state.messages, deduplicate by ID, sort by created_at
```

The p-tag check during loading (line 353) acts as a safety filter: even if an event was somehow stored with an incorrect `order_id`, it won't be displayed in the wrong chat because the decryption key wouldn't match.

---

## Multimedia Messages

Text messages have plain string content. Multimedia messages use JSON content:

### Sending
1. File/image encrypted with ChaCha20-Poly1305 using shared key bytes
2. Uploaded to Blossom server (encrypted blob)
3. JSON metadata sent as message content: `{ "type": "image_encrypted", "blossomUrl": "...", ... }`
4. The JSON is inside the NIP-44 gift wrap — doubly encrypted

### Receiving
1. Gift wrap arrives → decrypted to kind 1 → JSON content detected
2. `_processMessageContent()` identifies `image_encrypted` / `file_encrypted`
3. Downloads encrypted blob from Blossom, decrypts with shared key
4. Caches decrypted media in memory (`MediaCacheMixin`)

**Disk**: Only the gift wrap is stored (Blossom URL inside encrypted payload).
**Memory**: Decrypted media cached for display, cleared on dispose.

## Read Status & Notification Badges

- **Per-chat state:** `ChatReadStatusService` stores `chat_last_read_{orderId}` timestamps in `SharedPreferences`. Whenever the user opens a room, `markChatAsRead()` records `DateTime.now()`; `hasUnreadMessages()` compares that timestamp to the latest peer message so `ChatListItem` can display a red dot.
- **Global badge:** `BottomNavBar` listens to `chatCountProvider` and paints a red indicator on the chat icon when the provider value > 0. Push-notification handlers and background services are expected to increment/decrement that provider when new messages arrive outside the current room.
- **List refresh:** `ChatRoomNotifier._onChatEvent()` and `sendMessage()` call `chatRoomsNotifierProvider.notifier.refreshChatList()` so unread counts and sort order stay in sync without requiring a manual pull-to-refresh.

## Lifecycle & Reloads

- **App init:** `appInitializerProvider` loads keys, sessions, and the subscription manager, then instantiates `chatRoomsProvider(orderId)` for each recent session. This guarantees `_loadHistoricalMessages()` runs once on startup, even if the chat tab hasn’t been opened yet.
- **Foreground resume:** `LifecycleManager` listens for `AppLifecycleState.resumed`. When firing it re-subscribes to relays, reinitializes `MostroService`, asks the order repository to reload, and awaits `chatRoomsNotifierProvider.notifier.reloadAllChats()` so each `ChatRoomNotifier` cancels its old stream, reloads history from disk, and reattaches to `subscriptionManager.chat`.
- **Background hand-off:** On `AppLifecycleState.paused`, `LifecycleManager` captures the active Nostr filters and hands them to `backgroundServiceProvider` so push notifications keep streaming; it also unsubscribes the foreground `SubscriptionManager` to avoid duplicate events.

---

## Bug: Message Loss After Reconnection

### Symptom

With 2+ active trades, counterpart messages disappear after closing and reopening the app. Restoring the user brings them back.

### Root causes found and fixed

#### 1. Broadcast stream race condition (primary cause)

**Problem**: All `ChatRoomNotifier` instances listen to the same broadcast stream. When an event arrives, every notifier receives it. Before the fix, `_onChatEvent` stored the event to disk with its own `orderId` **before** checking the `p` tag to verify ownership. With multiple concurrent notifiers:

- Notifier A stores event with `order_id: "orderA"` (wrong)
- Notifier B stores same event with `order_id: "orderB"` (correct)
- Sembast upserts — last writer wins
- If A writes last, the event has the wrong `order_id` on disk
- On restart, notifier B queries `WHERE order_id = "orderB"` — doesn't find it

**Fix**: Verify the `p` tag matches `session.sharedKey.public` **before** any disk write. Only the owning notifier stores the event.

#### 2. Double subscription per chat

**Problem**: `app_init_provider.dart` explicitly called `subscribe()` on each `ChatRoomNotifier`, but creating the provider already triggers `_initializeChatRoomSafely()` → `initialize()` → `subscribe()`. This resulted in 2 listeners per chat on the broadcast stream, doubling disk write contention.

**Fix**: Removed the explicit `subscribe()` call from `app_init_provider.dart`. The provider's initialization handles subscription.

#### 3. Chat list empty after async initialization

**Problem**: `ChatRoomsNotifier.loadChats()` filters chats by `messages.isNotEmpty`, but `ChatRoomNotifier` initialization is async. When `loadChats()` runs, messages haven't loaded yet → all chats filtered out. No code called `refreshChatList()` after initialization completed.

**Fix**: `_initializeChatRoomSafely()` calls `refreshChatList()` after successful initialization.

#### 4. `reloadAllChats()` operates on empty state

**Problem**: `reloadAllChats()` iterates over `state` (the current chat list). If `state` is empty due to issue #3, nothing gets reloaded.

**Fix**: `reloadAllChats()` iterates over sessions (source of truth) instead of `state`.

#### 5. Sent messages not persisted (pre-existing)

**Problem**: `sendMessage()` only published to the relay and added to in-memory state. If the relay echo never arrived (connection drop), the sent message was lost on restart.

**Fix**: `sendMessage()` persists the wrapped event to Sembast immediately after successful publish.

#### 6. `reload()` didn't load from disk (pre-existing)

**Problem**: `reload()` only cancelled and re-subscribed to the stream. It didn't call `_loadHistoricalMessages()`, so reconnection couldn't recover messages from disk.

**Fix**: `reload()` calls `_loadHistoricalMessages()` before re-subscribing.

---

## File Reference

| File | Role |
|---|---|
| `lib/features/subscriptions/subscription_manager.dart` | Single subscription, broadcast stream, filter construction |
| `lib/features/chat/notifiers/chat_room_notifier.dart` | Per-chat event handling, storage, decryption, message state |
| `lib/features/chat/notifiers/chat_rooms_notifier.dart` | Chat list management, loadChats, refreshChatList, reloadAllChats |
| `lib/features/chat/chat_room_provider.dart` | Provider creation, async initialization |
| `lib/shared/providers/app_init_provider.dart` | App startup sequence, chat subscription setup |
| `lib/data/repositories/event_storage.dart` | Sembast wrapper for event persistence |
| `lib/data/models/session.dart` | Session model, ECDH shared key computation |
| `lib/data/models/nostr_event.dart` | p2pWrap / p2pUnwrap encryption/decryption |
| `lib/services/lifecycle_manager.dart` | Foreground/background transitions, chat reload |

## Cross References

| Topic | Document |
|-------|----------|
| Chat media pipeline | [.specify/v1-reference/ENCRYPTED_IMAGE_MESSAGING_IMPLEMENTATION.md](./ENCRYPTED_IMAGE_MESSAGING_IMPLEMENTATION.md) |
| Sessions & shared keys | [.specify/v1-reference/SESSION_AND_KEY_MANAGEMENT.md](./SESSION_AND_KEY_MANAGEMENT.md) |
| Trade detail actions (chat button) | [.specify/v1-reference/TRADE_EXECUTION.md](./TRADE_EXECUTION.md) |
| My Trades list (source of chat sessions) | [.specify/v1-reference/MY_TRADES.md](./MY_TRADES.md) |

*Dispute conversations reuse the same chat widgets; see `lib/features/disputes/*` until a dedicated spec is published.*

---

*Last Updated: March 2026*
