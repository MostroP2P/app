# MostroService (v1 Reference)

> Central service for Mostro protocol communication: gift wrap handling, order publishing, and message routing.

## Overview

`MostroService` (`lib/services/mostro_service.dart`) is the bridge between the app and Mostro daemon. It:
- Subscribes to encrypted gift wrap events (NIP-59)
- Decrypts messages using trade session keys
- Routes messages to order notifiers
- Publishes user actions back to Mostro
- Handles restore-specific payloads
- Links child orders to parent sessions

---

## Architecture

### Initialization & Lifecycle

```dart
class MostroService {
  final Ref ref;
  Settings _settings;
  StreamSubscription<NostrEvent>? _ordersSubscription;

  void init() {
    _ordersSubscription = ref
        .read(subscriptionManagerProvider)
        .orders
        .listen(_onData, onError: ..., cancelOnError: false);
  }

  void dispose() {
    _ordersSubscription?.cancel();
  }
}
```

**Flow:**
1. App initializes `MostroService.init()`
2. Subscribes to `SubscriptionManager.orders` stream (manages Nostr subscriptions based on active sessions)
3. All gift wrap events flow through `_onData()`
4. On dispose, cancels subscription

---

## Message Reception Pipeline

### 1. Event Deduplication

```dart
final eventStore = ref.read(eventStorageProvider);
if (await eventStore.hasItem(event.id!)) return;
await eventStore.putItem(event.id!, {...});
```

- Prevents processing duplicate events from multiple relays
- Uses `eventStorageProvider` (sembast-based local cache)

### 2. Session Matching

```dart
final sessions = ref.read(sessionNotifierProvider);
final matchingSession = sessions.firstWhereOrNull(
  (s) => s.tradeKey.public == event.recipient,
);
```

- Finds session by matching `event.recipient` (trade public key)
- If no match → log warning and skip

### 3. Gift Wrap Decryption

```dart
final privateKey = matchingSession.tradeKey.private;
final decryptedEvent = await event.unWrap(privateKey);
final result = jsonDecode(decryptedEvent.content!);
```

- Uses NIP-59 `unWrap()` from dart_nostr
- Decrypts with session's trade private key
- Parses JSON payload

### 4. Restore Payload Filtering

```dart
if (_isRestorePayload(result[0])) return;
```

**Why filter?**
- Restore process uses temporary trade key (index 1) to fetch historical orders
- These payloads (`RestoreData`, `LastTradeIndexResponse`, `OrdersResponse`) should NOT trigger UI updates
- Only relevant during active restore flow

**Detection Logic:**
```dart
bool _isRestorePayload(Map<String, dynamic> json) {
  final payload = json['restore']['payload'] ?? json['order']['payload'];
  
  // RestoreData: has 'restore_data' wrapper with 'orders' and 'disputes' arrays
  if (payload.containsKey('restore_data')) return true;
  
  // LastTradeIndexResponse: has 'trade_index' field
  if (payload.containsKey('trade_index')) return true;
  
  // OrdersResponse: has 'orders' array with OrderDetail (buyer_trade_pubkey/seller_trade_pubkey)
  if (payload['orders'] is List && 
      payload['orders'][0]?['buyer_trade_pubkey'] != null) return true;
  
  return false;
}
```

### 5. Message Storage & Routing

```dart
final msg = MostroMessage.fromJson(result[0]);
final messageStorage = ref.read(mostroStorageProvider);
await messageStorage.addMessage(messageKey, msg);

await _maybeLinkChildOrder(msg, matchingSession);
```

- Parses into `MostroMessage` model
- Stores in local database (accessed by order notifiers)
- Links child orders if `newOrder` action

---

## Child Order Linking

**Scenario:** User creates range order → Mostro splits into multiple sub-orders.

```dart
Future<void> _maybeLinkChildOrder(MostroMessage message, Session session) async {
  if (message.action != Action.newOrder || message.id == null) return;
  if (session.orderId != null || session.parentOrderId == null) return;

  await sessionNotifier.linkChildSessionToOrderId(
    message.id!,
    session.tradeKey.public,
  );
  
  ref.read(orderNotifierProvider(message.id!).notifier).subscribe();
}
```

**Conditions:**
- Message is `Action.newOrder` with order ID
- Session has `parentOrderId` but no `orderId` (waiting for child assignment)
- Links session to new child order ID
- Activates order notifier subscription

---

## Message Publishing

All user actions flow through `publishOrder()`:

```dart
Future<void> publishOrder(MostroMessage message) async {
  final settings = ref.read(settingsProvider);
  final mostroPubkey = settings.mostroPublicKey;
  final nostrService = ref.read(nostrServiceProvider);
  
  final sessions = ref.read(sessionNotifierProvider);
  final session = sessions.firstWhereOrNull(
    (s) => s.orderId == message.id || s.requestId == message.requestId,
  );
  
  final pow = ref.read(mostroInstanceProvider)?.pow ?? 0;
  
  final wrappedEvent = await MostroMessage.wrap(
    message,
    mostroPubkey,
    session.tradeKey.private,
    pow: pow,
  );
  
  await nostrService.publishEvent(wrappedEvent);
}
```

**Steps:**
1. Find matching session by `orderId` or `requestId`
2. Fetch PoW difficulty from Mostro instance config
3. Wrap message with NIP-59 gift wrap (`MostroMessage.wrap`)
4. Publish to Nostr relays via `nostrService`

### Common Actions

| Method | Action | Payload |
|--------|--------|---------|
| `submitOrder(order)` | `newOrder` | `Order` |
| `takeBuyOrder(orderId, amount?)` | `takeBuy` | `Amount?` |
| `takeSellOrder(orderId, amount?, lnAddress?)` | `takeSell` | `PaymentRequest? / Amount?` |
| `cancelOrder(orderId)` | `cancel` | — |
| `disputeOrder(orderId)` | `dispute` | — |
| `submitRating(orderId, rating)` | `rateUser` | `RatingUser` |

---

## Integration Points

| Component | Integration |
|-----------|-------------|
| **SubscriptionManager** | Provides `orders` stream with gift wrap events |
| **SessionNotifier** | Manages active sessions (trade keys, order IDs) |
| **OrderNotifier** | Consumes messages from `mostroStorageProvider` |
| **NostrService** | Handles Nostr relay connections and event publishing |
| **MostroInstanceProvider** | Supplies PoW difficulty and Mostro pubkey |
| **EventStorageProvider** | Deduplicates events across relays |

---

## Error Handling

```dart
try {
  final decryptedEvent = await event.unWrap(privateKey);
  // ... processing
} catch (e) {
  logger.e('Error processing event', error: e);
}
```

- All decryption/parsing errors are logged but don't crash the stream
- `cancelOnError: false` ensures subscription stays alive after errors

---

## Security Considerations

### Gift Wrap Privacy (NIP-59)
- Each trade uses ephemeral key pair (HD-derived from master key)
- Mostro daemon cannot link trades to user identity (only sees trade pubkeys)
- Messages encrypted end-to-end (only trade parties can decrypt)

### PoW (Proof of Work)
- Optional anti-spam measure configured by Mostro instance
- Client performs PoW before publishing (difficulty from `MostroInstance.pow`)
- Currently used for rate limiting, not authentication

---

## Cross-References

- [NOSTR.md](./NOSTR.md) — NostrService, relay pool, subscription management
- [SESSION_AND_KEY_MANAGEMENT.md](./SESSION_AND_KEY_MANAGEMENT.md) — Trade key derivation, session lifecycle
- [TRADE_EXECUTION.md](./TRADE_EXECUTION.md) — How order actions trigger MostroService calls
- [ORDER_CREATION.md](./ORDER_CREATION.md) — `submitOrder()` flow
- [TAKE_ORDER.md](./TAKE_ORDER.md) — `takeBuyOrder()` / `takeSellOrder()` flows
- [../PROTOCOL.md](../PROTOCOL.md) — Mostro protocol specification
