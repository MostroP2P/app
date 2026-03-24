# Authentication & Identity — v1 Reference

This document describes the authentication and identity system used in mostro-mobile v1.

## Overview

Mostro uses a **hierarchical deterministic (HD) key system** based on BIP-39 mnemonics and BIP-32 derivation. Users have a master key (seed phrase) that generates unique trade keys for each order, providing pseudonymity and forward secrecy.

**Key principles:**
- No traditional username/password — identity is the keypair
- Master key never leaves the device (stored in secure storage)
- Each order uses a different derived key (trade key)
- Users can restore identity from mnemonic

---

## Authentication Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      FIRST RUN FLOW                               │
└─────────────────────────────────────────────────────────────────┘

App Launch
    │
    ├── First time? ──→ /walkthrough ──→ Generate Master Key
    │                                          │
    │                                      Show Backup Reminder
    │                                          │
    │                                          ▼
    │                                    / (HomeScreen) — see HOME_SCREEN.md
    │
    └── Not first time ──→ Check master key exists
                              │
                              ├── Has master key ──→ / (HomeScreen) — see HOME_SCREEN.md
                              │
                              └── No master key ──→ Generate Master Key
                                                              │
                                                          Show Backup Reminder
                                                              │
                                                              ▼
                                                        / (HomeScreen) — see HOME_SCREEN.md

┌─────────────────────────────────────────────────────────────────┐
│                    KEY GENERATION                                │
└─────────────────────────────────────────────────────────────────┘

1. Generate 24-word BIP-39 mnemonic (entropy: 256 bits)
2. Derive BIP-32 extended private key from mnemonic
3. Store mnemonic in secure storage (encrypted)
4. Store extended private key in secure storage
5. Set trade key index to 2 (first trade key = index 2; index 1 is reserved for the restore temp key)

┌─────────────────────────────────────────────────────────────────┐
│                    RESTORE FLOW (Import)                        │
└─────────────────────────────────────────────────────────────────┘

User imports mnemonic
    │
    ├── Validate mnemonic (BIP-39 word list)
    │
    ├── Derive master key from mnemonic
    │
    ├── Clear all existing data (sessions, orders, chats)
    │
    ├── Store new mnemonic and master key
    │
    ├── Send restore-session request to Mostro via Nostr
    │   (wrapped with temp trade key index 1)
    │
    ├── Receive: List of orders + disputes + last trade index
    │
    ├── For each order:
    │   ├── Derive trade key for that order's index
    │   ├── Determine role (buyer/seller) from trade keys
    │   ├── Create session with shared key (ECDH with peer)
    │   └── Subscribe to Nostr events for that trade key
    │
    ├── Set trade key index to (lastTradeIndex + 1)
    │
    └── Navigate to HomeScreen

┌─────────────────────────────────────────────────────────────────┐
│                    KEY DERIVATION (BIP-32)                        │
└─────────────────────────────────────────────────────────────────┘

Master Key (Extended Private Key, BIP-32)
    │
    ├── derivationPath = "m/44'/1237'/0'" (NIP-06 compliant)
    │
    └── Trade Key Derivation:
        │
        ├── Master Key + index 0 ──→ Master Trade Key (index 0)
        │   └── Used for: Nostr identity (kind 0 events, profile)
        │
        ├── Master Key + index 1 ──→ Temp Trade Key (index 1)
        │   └── Used for: Restore process only (ephemeral; disposed after restore)
        │
        └── Master Key + index N ──→ Trade Key N (N ≥ 2)
            └── Used for: Individual order (N = order's trade index)

Note: Trade index 0 is the master identity key, index 1 is an ephemeral temp key used only during restore, and indices 2+ are for orders. After initialization, the first trade key is set to index 2; subsequent trades increment from there. After restore, the next trade key is set to (lastTradeIndex + 1), which may be index 2 or higher depending on prior trade history.
```

---

## Screens & Routes

### `/walkthrough`
**Purpose:** First-run onboarding (IntroductionScreen library)

**Screens (6 slides):**
1. Welcome to Mostro Mobile
2. Easy Onboarding — guided walkthrough
3. Trade with Confidence — seamless peer-to-peer
4. Encrypted Chat — NIP-59 gift wrap encryption
5. Take an Offer — order book browsing
6. Create Your Own Offer — custom order creation

**Behavior:**
- Skip/Done button → marks first run complete → shows backup reminder → navigates to `/`
- After completion, stores `firstRunComplete = true` in SharedPreferences

**Source:** `lib/features/walkthrough/screens/walkthrough_screen.dart`

---

### `/key_management`
**Purpose:** Account management, key viewing, import/export

**Accessible from:** Drawer menu → "Account"

**Sections:**

#### 1. Secret Words Card
- Displays 24-word BIP-39 mnemonic
- **Masking:** Shows first 2 + last 2 words, middle masked as `••• ••• ••• •••`
- **Toggle:** Eye icon to show/hide full mnemonic
- **Info dialog:** Explains what secret words are
- **Backup reminder dismiss:** When user views mnemonic, backup reminder is dismissed

#### 2. Privacy Card
- **Reputation Mode** (default): Standard privacy, reputation linked to pubkey
- **Full Privacy Mode**: Maximum anonymity, master key not shared with Mostro
- Radio button selection

#### 3. Current Trade Index Card (Debug only)
- Shows next trade key index
- Increments with each new order

#### 4. Generate New User Button
- **Warning dialog:** "This will delete all your data"
- Deletes: sessions, storage, orders, chats, notifications
- Generates new mnemonic and master key
- Shows backup reminder

#### 5. Import User Button
- Opens `ImportMnemonicDialog`
- Validates mnemonic (BIP-39)
- Calls `restoreService.importMnemonicAndRestore()`

#### 6. Refresh User Button
- Opens confirmation dialog
- Calls `restoreService.initRestoreProcess()`
- Re-fetches data from Mostro without changing keys

**Source:** `lib/features/key_manager/key_management_screen.dart`

---

## Key Components

### KeyManager (`lib/features/key_manager/key_manager.dart`)

```dart
class KeyManager {
  NostrKeyPairs? masterKeyPair;  // Master trade key (index 0)
  String? _masterKeyHex;          // Extended private key (BIP-32)
  int? tradeKeyIndex;             // Next trade key index to use

  Future<void> init();
  Future<bool> hasMasterKey();
  Future<void> generateAndStoreMasterKey();  // Generate + store mnemonic
  Future<void> importMnemonic(String mnemonic);
  Future<String?> getMnemonic();
  Future<NostrKeyPairs> deriveTradeKey();     // Derives next key, increments index
  NostrKeyPairs deriveTradeKeyPair(int index);  // Derives specific key
  Future<int> getCurrentKeyIndex();
  Future<void> setCurrentKeyIndex(int index);
}
```

**Storage:** Uses `KeyStorage` (secure storage)

### KeyDerivator (`lib/features/key_manager/key_derivator.dart`)

```dart
class KeyDerivator {
  // Derivation path: m/44'/1237'/0' (NIP-06 compliant for Nostr)
  
  String generateMnemonic();           // BIP-39, 24 words
  bool isMnemonicValid(String mnemonic);
  String masterPrivateKeyFromMnemonic(String mnemonic);
  String extendedKeyFromMnemonic(String mnemonic);  // BIP-32 base58
  String derivePrivateKey(String extendedPrivateKey, int index);
  String privateToPublicKey(String privateKeyHex);
}
```

**Dependencies:**
- `bip39` — BIP-39 mnemonic generation and validation
- `bip32` — BIP-32 HD key derivation
- `dart_nostr` — Nostr key pairs

### Session (`lib/data/models/session.dart`)

```dart
class Session {
  final NostrKeyPairs masterKey;      // Master trade key (index 0)
  final NostrKeyPairs tradeKey;        // Order-specific derived key
  final int keyIndex;                  // Trade key index
  final bool fullPrivacy;             // Privacy mode flag
  final DateTime startTime;
  String? orderId;
  String? parentOrderId;               // For range order child sessions
  Role? role;                         // buyer, seller
  Peer? peer;                         // Counterparty
  NostrKeyPairs? sharedKey;           // ECDH shared key with peer
  String? adminPubkey;                // Admin pubkey (for disputes)
  NostrKeyPairs? adminSharedKey;       // ECDH shared key with admin
}
```

**Key features:**
- Computes shared key via ECDH when peer is set
- Stores role (buyer/seller) per order
- Tracks parent order for range orders
- JSON serializable for persistence

### SessionNotifier (`lib/shared/notifiers/session_notifier.dart`)

```dart
class SessionNotifier extends StateNotifier<List<Session>> {
  // Manages multiple sessions (one per active order)
  
  Future<void> init();                    // Load sessions from storage, clean expired
  Future<Session> newSession({...});      // Create new session, derive trade key
  Future<void> saveSession(Session);      // Persist session
  Session? getSessionByOrderId(String);
  Session? getSessionByTradeKey(String);
  Future<void> reset();                   // Delete all sessions
  Future<void> deleteSession(String);
  void updateSessionWithSharedKey(...);   // Set peer, compute shared key
  NostrKeyPairs calculateSharedKey(...);   // ECDH computation
}
```

**Session lifecycle:**
1. `newSession()` — derives trade key, creates session
2. `saveSession()` — persists to storage, registers push token
3. Expires after `Config.sessionExpirationHours` (24h default)
4. Cleanup runs every `Config.cleanupIntervalMinutes` (5 min)

### FirstRunNotifier (`lib/features/walkthrough/providers/first_run_provider.dart`)

```dart
// SharedPreferences key: "first_run_complete"
// true = first run, false = not first run

class FirstRunNotifier extends StateNotifier<AsyncValue<bool>> {
  Future<bool> _checkIfFirstRun();
  Future<void> markFirstRunComplete();  // Sets to false
  Future<void> resetFirstRun();        // Sets to true (for testing)
}
```

### BackupReminderNotifier (`lib/features/notifications/providers/backup_reminder_provider.dart`)

```dart
// SharedPreferences key: "backup_reminder_dismissed"
// Shows reminder until user views mnemonic

class BackupReminderNotifier extends StateNotifier<bool> {
  // state = true = show reminder, false = dismissed
  Future<void> showBackupReminder();     // Called on first run or new key
  Future<void> dismissBackupReminder();  // Called when user views mnemonic
}
```

---

## Restore Service (`lib/features/restore/restore_manager.dart`)

### Flow:

```
1. Clear all existing data
   - Sessions, orders, chats, notifications, storage

2. Create temp subscription (key index 1)
   - Subscribe to Nostr events (kind 1059, gift wrap)
   - Limit 0 = only new events, no historical

3. Stage 1: Request Restore Data
   - Send `Action::restore-session` wrapped with temp trade key
   - Receive: Map<orderId, tradeIndex> + List<disputes>

4. Stage 2: Request Order Details
   - Send Action::orders with order IDs
   - Receive: Full order details (status, amounts, pubkeys)

5. Stage 3: Request Last Trade Index
   - Send Action::lastTradeIndex
   - Receive: Last used trade index number

6. Restore Sessions
   - For each order:
     - Derive trade key for that index
     - Determine role by comparing trade pubkeys
     - Create session with shared key
     - Subscribe to chat events
   - Wait 10 seconds for historical messages

7. Update State
   - Convert orders to MostroMessages
   - Handle disputes (determine if user or peer initiated)
   - Navigate to HomeScreen
   - Clear notification tray
```

### Privacy Mode Considerations:

```dart
// If fullPrivacyMode = true:
// - Master key NOT included in gift wrap
// - Only trade key encrypts the message
// - Mostro cannot link orders to user's identity

// If fullPrivacyMode = false:
// - Master key included in gift wrap
// - Both keys encrypt the message
// - Mostro can link orders to identity
```

### Status → Action Mapping (for Restore):

| Status | Action | Role Context |
|--------|--------|-------------|
| `pending` | `newOrder` | — |
| `waitingBuyerInvoice` | `addInvoice` (buyer) / `waitingBuyerInvoice` (seller) | Buyer needs to add invoice |
| `waitingPayment` | `payInvoice` (seller) / `waitingSellerToPay` (buyer) | Seller needs to pay |
| `active` | `holdInvoicePaymentAccepted` (buyer) / `buyerTookOrder` (seller) | Trade in progress |
| `fiatSent` | `fiatSentOk` | Buyer confirmed fiat sent |
| `settledHoldInvoice` | `released` (buyer) / `holdInvoicePaymentSettled` (seller) | Release in progress |
| `success` | `purchaseCompleted` | Trade complete |
| `dispute` | `disputeInitiatedByYou` / `disputeInitiatedByPeer` | Depends on who initiated |
| `canceled` | `canceled` | — |
| `canceledByAdmin` | `adminCanceled` | — |
| `settledByAdmin` | `adminSettled` | — |
| `expired` | `canceled` | — |

---

## Data Storage

### Secure Storage (KeyStorage)
- **Mnemonic:** 24-word BIP-39 seed phrase
- **Master Key:** BIP-32 extended private key (base58)
- **Trade Key Index:** Next index to use
- **Backend:** Platform-specific secure storage (iOS Keychain, Android Keystore)

### Session Storage (SessionStorage)
- JSON serialization of Session objects
- Keyed by orderId
- Expiration: 24 hours

### SharedPreferences
- `first_run_complete` — bool
- `backup_reminder_dismissed` — bool

---

## Security Considerations

1. **Master key never leaves device** — stored in secure storage
2. **Each order = different key** — provides pseudonymity
3. **Shared key computed per session** — ECDH with counterparty
4. **Sessions expire** — 24h default, prevents stale state
5. **Full privacy mode** — master key not shared with Mostro
6. **Restore clears all data** — prevents data leakage on import

---

## Comparison: v1 vs v2 (Planned)

| Feature | v1 | v2 (Planned) |
|---------|-----|--------------|
| Master key storage | Secure storage | Rust secure storage |
| Key derivation | Dart (bip39, bip32) | Rust (bip39, bip32) |
| Mnemonic display | Dart UI | Rust → Dart (via FFI) |
| Session management | Dart StateNotifier | Rust session manager |
| Restore flow | Dart Nostr client | Rust nostr-sdk |
| Privacy modes | Reputation / Full | Same + Nym identity |

---

---

## Related Documentation

### UI Specification

For screen layouts, component styles, and UI implementation details, see: **[ACCOUNT_SCREEN.md](./ACCOUNT_SCREEN.md)**

This document covers:
- Screen layout and visual hierarchy
- Component styling (cards, buttons, icons)
- Mnemonic masking UI
- Privacy mode radio buttons
- Confirmation dialogs
- Debug-only Trade Index section

### Core
- `lib/features/key_manager/key_manager.dart`
- `lib/features/key_manager/key_derivator.dart`
- `lib/features/key_manager/key_storage.dart`
- `lib/features/key_manager/key_management_screen.dart`
- `lib/features/key_manager/import_mnemonic_dialog.dart`

### Session
- `lib/data/models/session.dart`
- `lib/shared/notifiers/session_notifier.dart`
- `lib/data/repositories/session_storage.dart`

### Onboarding
- `lib/features/walkthrough/screens/walkthrough_screen.dart`
- `lib/features/walkthrough/providers/first_run_provider.dart`

### Restore
- `lib/features/restore/restore_manager.dart`
- `lib/features/restore/restore_progress_notifier.dart`
- `lib/features/restore/restore_overlay.dart`

### Backup
- `lib/features/notifications/providers/backup_reminder_provider.dart`

### Models
- `lib/data/models/enums/action.dart` (NIP-59 actions)
- `lib/data/models/enums/role.dart` (buyer/seller)
- `lib/data/models/peer.dart`
