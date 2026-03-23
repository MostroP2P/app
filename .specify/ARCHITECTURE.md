# Architecture Decision Record: Rust Core + Flutter Shell

> ⚠️ **CRITICAL**: This document defines the boundary between Rust and Dart.
> Every implementation decision must follow these rules. No exceptions.

## The Golden Rule

```
┌─────────────────────────────────────────────────────────────────┐
│  RUST handles: Protocol, Crypto, Network, Business Logic        │
│  DART handles: UI, Platform APIs, Device I/O                    │
└─────────────────────────────────────────────────────────────────┘
```

## Why This Architecture?

### Rust Core (via nostr-sdk)

| Responsibility | Rationale |
|----------------|-----------|
| **Nostr protocol** | nostr-sdk is the most complete, audited implementation |
| **Cryptography** | NIP-44, NIP-59, signatures — security-critical, must be in one place |
| **Key management** | BIP-32/39 derivation, seed storage — zero room for error |
| **Relay connections** | WebSocket management, subscription handling, reconnection logic |
| **Message serialization** | Mostro protocol messages, Gift Wrap encryption/decryption |
| **Order state machine** | Business logic that must be consistent across platforms |
| **Local storage encryption** | SQLite with encrypted fields, ChaCha20-Poly1305 |

### Dart/Flutter (Native SDKs)

| Responsibility | Rationale |
|----------------|-----------|
| **QR code scanning** | `mobile_scanner` uses native camera APIs — optimized, battle-tested |
| **Push notifications** | Firebase/APNs have official Dart SDKs, no Rust equivalent |
| **Biometric auth** | `local_auth` wraps iOS Face ID / Android BiometricPrompt |
| **Deep links** | `go_router` + platform URL handling — standard Flutter pattern |
| **File picker** | `file_picker` accesses native file system dialogs |
| **Permissions** | `permission_handler` abstracts iOS/Android permission models |
| **Clipboard** | `flutter/services.dart` — trivial platform channel |
| **Share sheet** | `share_plus` invokes native share UI |

## Data Flow

```
┌──────────────────────────────────────────────────────────────────────┐
│                           FLUTTER (Dart)                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  │
│  │   Camera    │  │   Push      │  │  Biometric  │  │    File     │  │
│  │  (QR scan)  │  │   Notif     │  │    Auth     │  │   Picker    │  │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  │
│         │                │                │                │         │
│         ▼                ▼                ▼                ▼         │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │                         UI Layer                               │   │
│  │   • Screens, Widgets, Navigation                               │   │
│  │   • Riverpod state management                                  │   │
│  │   • Theming, responsive layouts                                │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                              │                                        │
│                              ▼                                        │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │              flutter_rust_bridge (generated)                   │   │
│  │   • Async function calls                                       │   │
│  │   • Type marshalling (Rust structs ↔ Dart classes)            │   │
│  │   • Stream support for real-time events                        │   │
│  └───────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌──────────────────────────────────────────────────────────────────────┐
│                           RUST CORE                                   │
│  ┌───────────────────────────────────────────────────────────────┐   │
│  │                     rust/src/api/                              │   │
│  │   • Exposed functions with #[frb] attribute                    │   │
│  │   • Flutter-compatible wrapper types                           │   │
│  │   • Error handling (Result → Dart exceptions)                  │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                              │                                        │
│         ┌────────────────────┼────────────────────┐                  │
│         ▼                    ▼                    ▼                  │
│  ┌─────────────┐      ┌─────────────┐      ┌─────────────┐          │
│  │  nostr-sdk  │      │ mostro-core │      │   Storage   │          │
│  │             │      │             │      │             │          │
│  │ • NIP-59    │      │ • Messages  │      │ • SQLite    │          │
│  │ • Relays    │      │ • Order     │      │ • Encrypted │          │
│  │ • Events    │      │   state     │      │   fields    │          │
│  └─────────────┘      └─────────────┘      └─────────────┘          │
└──────────────────────────────────────────────────────────────────────┘
```

## Example: QR Code → Lightning Payment

This example shows the correct boundary:

```
1. User taps "Scan QR" button
   └── Flutter: UI event

2. Camera opens, scans QR
   └── Dart: mobile_scanner (native camera API)

3. QR content extracted: "lnbc1..."
   └── Dart: String from scanner

4. Pass invoice string to Rust
   └── flutter_rust_bridge: parseInvoice(invoice)

5. Rust validates and parses invoice
   └── Rust: lightning-invoice crate

6. Rust returns structured data
   └── Rust → Dart: Invoice { amount_msat, description, expiry, ... }

7. Flutter displays payment confirmation
   └── Dart: UI with invoice details

8. User confirms, Flutter calls Rust
   └── flutter_rust_bridge: payInvoice(invoice)

9. Rust handles NWC payment or returns invoice for manual payment
   └── Rust: nostr-sdk NWC, or returns QR data for external wallet
```

## Forbidden Patterns

### ❌ NEVER do crypto in Dart

```dart
// WRONG - crypto in Dart
import 'package:cryptography/cryptography.dart';
final encrypted = await aes.encrypt(data, secretKey: key);
```

```rust
// CORRECT - crypto in Rust, exposed via bridge
#[frb]
pub fn encrypt_data(data: Vec<u8>, key: Vec<u8>) -> Result<Vec<u8>, ApiError> {
    // ChaCha20-Poly1305 encryption here
}
```

### ❌ NEVER make network calls from Dart (for Nostr)

```dart
// WRONG - WebSocket in Dart for Nostr
final ws = WebSocket.connect('wss://relay.damus.io');
ws.add(jsonEncode(['REQ', subId, filter]));
```

```rust
// CORRECT - nostr-sdk handles all relay connections
#[frb]
pub async fn subscribe_orders(filter: OrderFilter) -> Result<Stream<Order>, ApiError> {
    let client = get_nostr_client()?;
    // nostr-sdk subscription
}
```

### ❌ NEVER store keys in Dart

```dart
// WRONG - key in Dart memory/storage
final prefs = await SharedPreferences.getInstance();
prefs.setString('nsec', nsec); // NEVER
```

```rust
// CORRECT - keys stay in Rust, encrypted at rest
#[frb]
pub async fn store_identity(mnemonic: String, pin: String) -> Result<(), ApiError> {
    // Derive keys, encrypt with PIN, store in SQLite
    // Keys never leave Rust
}
```

### ✅ DO use Dart for platform features

```dart
// CORRECT - QR scanning in Dart
final controller = MobileScannerController();
MobileScanner(
  controller: controller,
  onDetect: (capture) {
    final code = capture.barcodes.first.rawValue;
    // Pass to Rust for processing
    rustApi.parseInvoice(invoice: code);
  },
);
```

```dart
// CORRECT - Push notifications in Dart
FirebaseMessaging.onMessage.listen((message) {
  // Notification received, update UI
  // Content was already minimal (privacy)
});
```

## Platform-Specific Considerations

| Feature | iOS | Android | Web | Desktop |
|---------|-----|---------|-----|---------|
| QR Scan | ✅ Camera | ✅ Camera | ⚠️ File upload / paste | ⚠️ File upload / paste |
| Push | ✅ APNs | ✅ FCM | ⚠️ Web Push (limited) | ❌ Not available |
| Biometric | ✅ Face ID / Touch ID | ✅ Fingerprint / Face | ❌ N/A | ⚠️ OS-dependent |
| Deep Links | ✅ Universal Links | ✅ App Links | ✅ URL routing | ⚠️ Protocol handler |
| File Access | ✅ Sandboxed | ✅ Scoped storage | ✅ File API | ✅ Full access |

## Dependencies Summary

### Rust (Cargo.toml)

```toml
[dependencies]
flutter_rust_bridge = "2.x"
nostr-sdk = "0.44"
mostro-core = { git = "..." }
tokio = { version = "1", features = ["rt-multi-thread"] }
sqlx = { version = "0.8", features = ["sqlite"] }
chacha20poly1305 = "0.10"
bip32 = "0.5"
bip39 = "2.0"
```

### Dart (pubspec.yaml)

```yaml
dependencies:
  flutter_rust_bridge: ^2.0.0
  riverpod: ^2.0.0
  go_router: ^14.0.0
  mobile_scanner: ^5.0.0        # QR scanning
  local_auth: ^2.0.0            # Biometrics
  firebase_messaging: ^15.0.0   # Push (mobile)
  permission_handler: ^11.0.0   # Runtime permissions
  share_plus: ^9.0.0            # Native share
  file_picker: ^8.0.0           # File selection
```

## Checklist for New Features

Before implementing any feature, answer:

1. **Does it involve crypto or keys?** → Rust only
2. **Does it involve Nostr protocol?** → Rust only  
3. **Does it involve network calls to relays?** → Rust only
4. **Does it involve device hardware (camera, sensors)?** → Dart native SDK
5. **Does it involve OS-level APIs (notifications, permissions)?** → Dart native SDK
6. **Is it pure UI/UX?** → Dart/Flutter

When in doubt: **Rust for logic, Dart for I/O.**
