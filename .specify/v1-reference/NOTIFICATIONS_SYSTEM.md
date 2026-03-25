# Notifications System (v1 Reference)

> Complete notification architecture: in-app history, push delivery via FCM, server registration, and background handling.

## Overview

Mostro Mobile v1 implements a dual-layer notification system:
1. **In-app notifications** — persistent local history of all trade events
2. **Push notifications** — silent data messages via FCM for background delivery

**Route:** `/notifications` → `NotificationsScreen`

---

## Architecture Components

### 1. Data Models

| File | Purpose |
|------|---------|
| `lib/data/models/notification.dart` | `NotificationModel` — id, type, action, title, message, timestamp, isRead, orderId, data. |
| `lib/data/models/enums/notification_type.dart` | 7 categories: `orderUpdate`, `tradeUpdate`, `payment`, `dispute`, `cancellation`, `message`, `system`. |

**Action → NotificationType Mapping:**
```dart
static NotificationType getNotificationTypeFromAction(Action action) {
  // orderUpdate: newOrder, takeSell, takeBuy, buyerTookOrder
  // payment: payInvoice, fiatSent, release, holdInvoicePaymentAccepted, etc.
  // cancellation: cancel, canceled, cooperativeCancel*, adminCancel*
  // dispute: dispute*, adminSettle*, adminTakeDispute, etc.
  // tradeUpdate: rate, rateUser, rateReceived
  // message: sendDm
  // system: cantDo, tradePubkey, fallback
}
```

### 2. Services Layer

#### PushNotificationService (`lib/services/push_notification_service.dart`)
- **Purpose:** Register device tokens with Mostro push server (plaintext HTTP in Phase 3).
- **Key Methods:**
  - `initialize()` — health check against push server
  - `registerToken(tradePubkey)` — POST `/api/register` with FCM token + trade pubkey + platform
  - `unregisterToken(tradePubkey)` — POST `/api/unregister`
  - `reRegisterAllTokens()` — called when FCM token refreshes
  - `unregisterAllTokens()` — called when user disables push in settings
- **State:** Tracks `_registeredTradePubkeys` set for re-registration.
- **Settings Integration:** `isPushEnabledInSettings` callback to respect user preferences.

#### FCMService (`lib/services/fcm_service.dart`)
- **Purpose:** Firebase Cloud Messaging integration (Android/iOS).
- **Key Responsibilities:**
  - Request permissions
  - Get/refresh FCM token
  - Handle foreground/background message delivery
  - Delete token on opt-out
- **Spec Reference:** See [FCM_IMPLEMENTATION.md](./FCM_IMPLEMENTATION.md) for complete details.

#### BackgroundNotificationService (`lib/features/notifications/services/background_notification_service.dart`)
- **Purpose:** Process notifications when app is in background or terminated.
- **Integration:** Registers handler for Firebase background messages.

### 3. State Management

| File | Role |
|------|------|
| `lib/features/notifications/notifiers/notifications_notifier.dart` | `StateNotifier<NotificationsState>` managing notification list + unread count. |
| `lib/features/notifications/notifiers/notifications_state.dart` | Immutable state (notifications list, unread count, loading flag). |
| `lib/features/notifications/notifiers/notification_temporary_state.dart` | Ephemeral state for badge display. |
| `lib/features/notifications/providers/notifications_provider.dart` | Riverpod providers: `notificationsHistoryProvider`, `unreadCountProvider`, `temporaryNotificationsProvider`. |

### 4. Persistence

**NotificationsHistoryRepository** (`lib/data/repositories/notifications_history_repository.dart`)
- **Storage:** Local database (Sembast or equivalent).
- **Methods:**
  - `addNotification()` — insert with timestamp
  - `markAsRead(id)` / `markAllAsRead()` — update isRead flag
  - `deleteNotification(id)` / `deleteAll()` — cleanup
  - `getAll()` / `getUnreadCount()` — queries

### 5. Utilities

| File | Purpose |
|------|---------|
| `notification_message_mapper.dart` | Maps `Action` + payload → localized title/message strings. |
| `notification_data_extractor.dart` | Extracts `orderId`, `disputeId`, deep-link data from notification payloads. |

---

## NotificationsScreen (`/notifications`)

### Layout

```text
┌─────────────────────────────────────────────────┐
│  ←  Notifications          [⋮] [🔔]            │  AppBar
├─────────────────────────────────────────────────┤
│  [Backup Reminder Card — if triggered]          │  Optional
├─────────────────────────────────────────────────┤
│  Order #abc123 — Buyer took your order          │  NotificationItem
│  5 minutes ago                         [Read]   │
├─────────────────────────────────────────────────┤
│  Payment — Fiat sent                            │
│  10 minutes ago                        [Read]   │
├─────────────────────────────────────────────────┤
│  ...                                            │
└─────────────────────────────────────────────────┘
```

### Features

1. **Pull-to-refresh** — triggers `ref.refresh(notificationsHistoryProvider)`.
2. **Actions Menu** (⋮ button) — Mark all as read, Delete all.
3. **Bell Icon** — Badge with unread count; tap navigates to `/notifications`.
4. **Empty State** — Shows when no notifications exist (bell-slash icon + message).
5. **Backup Reminder** — Persistent card prompting mnemonic backup (provider-driven).

### NotificationItem Widget

**Components:**
- **Header:** `NotificationTypeIcon` + title + timestamp (relative time).
- **Content:** Message text + optional orderId/disputeId display.
- **Footer:** "Mark as read" button (if unread) + tap action (navigate to order/dispute).

**Interaction:**
- Tap → navigates to `/trade_detail/:orderId` or `/dispute_details/:disputeId`.
- Long-press → context menu (Mark as read, Delete).

---

## Push Notification Flow

### Registration

```text
1. User creates/takes order → session established with tradeKey
2. App calls pushService.registerToken(tradeKey.public)
   ↓
3. PushNotificationService POSTs to push server:
   {
     "trade_pubkey": "abc123...",
     "token": "fcm_token_xyz...",
     "platform": "android|ios"
   }
   ↓
4. Server stores mapping: trade_pubkey → [device_tokens]
5. Mostro daemon sends NIP-59 gift wrap addressed to trade_pubkey
   ↓
6. Push server receives event, looks up device tokens, sends FCM data message
   ↓
7. FCM delivers silent push to device
8. App decrypts gift wrap, creates NotificationModel, persists to history
9. UI updates via NotificationsNotifier
```

### Token Refresh

When FCM token changes:
1. `FCMService` emits new token.
2. `PushNotificationService.reRegisterAllTokens()` re-registers all active trade pubkeys with new token.

### Unregistration

When user disables push notifications:
1. `SettingsNotifier.updatePushNotificationsEnabled(false)` calls `_unregisterPushTokens()`.
2. `PushNotificationService.unregisterAllTokens()` POSTs to `/api/unregister` for each trade pubkey.
3. `FCMService.deleteToken()` removes local FCM token.

---

## Notification Types & Icons

| Type | Icon | Actions |
|------|------|---------|
| `orderUpdate` | Shopping bag | newOrder, takeSell, takeBuy, buyerTookOrder |
| `tradeUpdate` | Star | rate, rateUser, rateReceived |
| `payment` | Zap | payInvoice, fiatSent, release, holdInvoicePayment* |
| `dispute` | Gavel | dispute*, adminSettle*, adminTakeDispute |
| `cancellation` | X Circle | cancel, canceled, cooperativeCancel*, adminCancel* |
| `message` | Chat bubble | sendDm |
| `system` | Info | cantDo, tradePubkey, fallback |

---

## Security & Privacy

### Phase 3 (Current)
- **Token Registration:** Plaintext HTTP (encrypted in transit via HTTPS).
- **Push Payload:** Silent data message with encrypted NIP-59 gift wrap.
- **Decryption:** Client-side using trade key (server never sees plaintext content).

### Phase 5 (Planned)
- **Token Encryption:** ECDH + ChaCha20-Poly1305 for privacy-preserving registration.
- **Goal:** Push server cannot link device tokens to trade identities.

---

## Integration Points

| Feature | Integration |
|---------|-------------|
| Settings | `isPushEnabledInSettings` callback gates registration; unregister on disable. |
| Trade Sessions | `registerToken()` called when session established; `unregisterToken()` on completion/cancel. |
| Background Service | Processes notifications when app is not active. |
| Deep Links | Notification taps navigate to `/trade_detail/:orderId` or `/dispute_details/:disputeId`. |
| Badge Count | `unreadCountProvider` drives app badge and in-app bell icon. |

---

## Cross-References

- [FCM_IMPLEMENTATION.md](./FCM_IMPLEMENTATION.md) — Firebase setup, message handling, background delivery.
- [NOTIFICATION_SETTINGS.md](./NOTIFICATION_SETTINGS.md) — User preferences for push, sound, vibration.
- [SETTINGS_SCREEN.md](./SETTINGS_SCREEN.md) — Settings integration (`pushNotificationsEnabled`, token unregistration).
- [TRADE_EXECUTION.md](./TRADE_EXECUTION.md) — Notification generation during trade lifecycle.
- [NAVIGATION_ROUTES.md](./NAVIGATION_ROUTES.md) — Route `/notifications`, deep-link handling.
- [LOGGING_SYSTEM.md](./LOGGING_SYSTEM.md) — Notification events logged for debugging.
