# EncryptionService (v1 Reference)

> ChaCha20-Poly1305 AEAD encryption for secure local data storage and P2P messaging.

## Overview

`EncryptionService` (`lib/services/encryption_service.dart`) provides:
- **ChaCha20-Poly1305** authenticated encryption (AEAD)
- Secure random number generation (cryptographically strong)
- Blob serialization (nonce + ciphertext + auth tag)
- No Nostr-specific logic (NIP-44/NIP-59 encryption handled by `dart_nostr`)

**Use Cases:**
- Encrypted image uploads (Blossom)
- Encrypted file uploads
- Local sensitive data storage (future)

**NOT used for:**
- Nostr gift wrap encryption (handled by `dart_nostr` NIP-59 implementation)
- Trade message encryption (handled by `NostrService` + `dart_nostr`)

---

## Architecture

### EncryptionResult Model

```dart
class EncryptionResult {
  final Uint8List encryptedData;
  final Uint8List nonce;          // 12 bytes
  final Uint8List authTag;        // 16 bytes (Poly1305 MAC)

  Uint8List toBlob() {
    // Structure: [nonce][encrypted_data][auth_tag]
    return concatenate([nonce, encryptedData, authTag]);
  }

  static EncryptionResult fromBlob(Uint8List blob) {
    // Extract: nonce (first 12), authTag (last 16), data (middle)
  }
}
```

**Blob Format:**
```
| Nonce (12 bytes) | Encrypted Data (N bytes) | Auth Tag (16 bytes) |
```

**Why this structure?**
- Self-contained: all decryption parameters in one blob
- Standard ChaCha20-Poly1305 nonce size (12 bytes)
- Standard Poly1305 MAC size (16 bytes = 128 bits)
- No IV/salt needed (nonce serves that purpose)

---

## Core Methods

### 1. Secure Random Generation

```dart
static final SecureRandom _secureRandom = SecureRandom('Fortuna')
  ..seed(KeyParameter(_generateSeed()));

static Uint8List generateSecureRandom(int length) {
  final bytes = Uint8List(length);
  for (int i = 0; i < length; i++) {
    bytes[i] = _secureRandom.nextUint8();
  }
  return bytes;
}
```

**Implementation:**
- Uses **Fortuna CSPRNG** from PointyCastle
- Seeded with `Random.secure()` (platform crypto provider)
- Singleton instance (seeded once per app launch)

**Usage:**
- Nonce generation (if not provided by caller)
- Encryption keys (when needed)

### 2. ChaCha20-Poly1305 Encryption

```dart
static EncryptionResult encryptChaCha20Poly1305({
  required Uint8List key,          // 32 bytes (256-bit)
  required Uint8List plaintext,
  Uint8List? nonce,                // 12 bytes (auto-generated if null)
  Uint8List? additionalData,       // Optional AAD for AEAD
}) {
  // Validate key size
  if (key.length != 32) {
    throw ArgumentError('ChaCha20 key must be 32 bytes');
  }

  // Generate nonce if not provided
  nonce ??= generateSecureRandom(12);

  // Create cipher with Poly1305 MAC
  final cipher = ChaCha20Poly1305(ChaCha7539Engine(), Poly1305());
  
  // Initialize AEAD parameters
  final params = AEADParameters(
    KeyParameter(key),
    128,                            // 128-bit auth tag
    nonce,
    additionalData ?? Uint8List(0),
  );
  
  cipher.init(true, params);        // true = encrypt mode

  // Encrypt + authenticate
  final output = Uint8List(cipher.getOutputSize(plaintext.length));
  int len = cipher.processBytes(plaintext, 0, plaintext.length, output, 0);
  len += cipher.doFinal(output, len);

  // Split output: ciphertext + MAC
  final encryptedData = output.sublist(0, plaintext.length);
  final authTag = output.sublist(plaintext.length, len);

  return EncryptionResult(
    encryptedData: encryptedData,
    nonce: nonce,
    authTag: authTag,
  );
}
```

**Parameters:**
- `key` — 256-bit encryption key (must be exactly 32 bytes)
- `plaintext` — Data to encrypt
- `nonce` — 96-bit nonce (auto-generated if not provided; **MUST be unique per key**)
- `additionalData` — Optional AAD (authenticated but not encrypted)

**Output:**
- `encryptedData` — Same length as plaintext
- `authTag` — 128-bit Poly1305 MAC
- `nonce` — The nonce used (for storage/transmission)

### 3. ChaCha20-Poly1305 Decryption

```dart
static Uint8List decryptChaCha20Poly1305({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List encryptedData,
  required Uint8List authTag,
  Uint8List? additionalData,
}) {
  // Validate parameters
  if (key.length != 32) throw ArgumentError('ChaCha20 key must be 32 bytes');
  if (nonce.length != 12) throw ArgumentError('Nonce must be 12 bytes');
  if (authTag.length != 16) throw ArgumentError('Auth tag must be 16 bytes');

  // Create cipher
  final cipher = ChaCha20Poly1305(ChaCha7539Engine(), Poly1305());
  
  // Initialize AEAD parameters
  final params = AEADParameters(
    KeyParameter(key),
    128,
    nonce,
    additionalData ?? Uint8List(0),
  );
  
  cipher.init(false, params);       // false = decrypt mode

  // Combine ciphertext + MAC for input
  final cipherInput = concatenate([encryptedData, authTag]);

  // Decrypt + verify MAC
  final output = Uint8List(cipher.getOutputSize(cipherInput.length));
  int len = cipher.processBytes(cipherInput, 0, cipherInput.length, output, 0);
  len += cipher.doFinal(output, len);

  return output.sublist(0, len);
}
```

**Exceptions:**
- `EncryptionException` — MAC verification failed (data tampered or wrong key)
- `ArgumentError` — Invalid key/nonce/tag size

---

## Convenience Methods

### Encrypt to Blob

```dart
static Uint8List encryptToBlob({
  required Uint8List key,
  required Uint8List plaintext,
  Uint8List? additionalData,
}) {
  final result = encryptChaCha20Poly1305(
    key: key,
    plaintext: plaintext,
    additionalData: additionalData,
  );
  return result.toBlob();
}
```

**Use Case:** Encrypting data for storage (database, file system).

### Decrypt from Blob

```dart
static Uint8List decryptFromBlob({
  required Uint8List key,
  required Uint8List blob,
  Uint8List? additionalData,
}) {
  final result = EncryptionResult.fromBlob(blob);
  return decryptChaCha20Poly1305(
    key: key,
    nonce: result.nonce,
    encryptedData: result.encryptedData,
    authTag: result.authTag,
    additionalData: additionalData,
  );
}
```

**Use Case:** Decrypting data from storage.

---

## Security Properties

### ChaCha20-Poly1305 (AEAD)

**Why ChaCha20-Poly1305?**
- **Fast** — Optimized for software (no AES-NI needed)
- **Secure** — No known practical attacks
- **Authenticated** — Poly1305 MAC detects tampering
- **Standard** — IETF RFC 8439, widely adopted (TLS 1.3, WireGuard, Signal)

**Properties:**
- **Confidentiality** — ChaCha20 stream cipher (256-bit key)
- **Authenticity** — Poly1305 MAC (128-bit tag)
- **Integrity** — Any modification detected during decryption

### Nonce Uniqueness

**Critical Rule:** Never reuse a nonce with the same key.

**Implementation:**
- Nonces auto-generated from `SecureRandom` (collision probability negligible)
- Nonce stored with ciphertext (part of blob)
- No nonce counter/sequence needed (random nonces safe for ChaCha20-Poly1305)

### Key Management

**EncryptionService does NOT manage keys.**

**Callers must:**
- Derive keys securely (e.g., from master key via HD derivation)
- Never reuse keys across different contexts
- Store keys securely (secure enclave, encrypted storage)

---

## Usage Examples

### Encrypted Image Upload

**Scenario:** Encrypt image before uploading to Blossom server.

```dart
// Generate ephemeral key (or derive from session key)
final key = EncryptionService.generateSecureRandom(32);

// Encrypt image bytes
final imageBytes = await file.readAsBytes();
final encryptedBlob = EncryptionService.encryptToBlob(
  key: key,
  plaintext: imageBytes,
);

// Upload blob to Blossom
final blobUrl = await blossomClient.upload(encryptedBlob);

// Share key + URL with recipient (via encrypted chat message)
await sendChatMessage({
  'type': 'image',
  'url': blobUrl,
  'key': base64Encode(key),
});
```

### Decryption on Receive

```dart
// Receive chat message with encrypted image reference
final blobUrl = message['url'];
final keyBase64 = message['key'];

// Download blob
final encryptedBlob = await http.get(Uri.parse(blobUrl)).then((r) => r.bodyBytes);

// Decrypt
final key = base64Decode(keyBase64);
final imageBytes = EncryptionService.decryptFromBlob(
  key: key,
  blob: encryptedBlob,
);

// Display image
return Image.memory(imageBytes);
```

---

## Error Handling

### EncryptionException

```dart
class EncryptionException implements Exception {
  final String message;
  EncryptionException(this.message);
  
  @override
  String toString() => 'EncryptionException: $message';
}
```

**Thrown when:**
- MAC verification fails during decryption → data corrupted or wrong key
- Cipher initialization fails (invalid parameters)

**Logging:**
```dart
logger.e('❌ ChaCha20-Poly1305 decryption failed: $e');
```

---

## Limitations & Future Work

### Current Limitations

1. **No Key Derivation** — Callers must provide ready-to-use keys
2. **No Key Rotation** — No built-in support for re-encrypting data with new keys
3. **No Compression** — Plaintext encrypted as-is (consider zlib compression before encryption)
4. **No Streaming** — Entire plaintext loaded into memory

### Future Enhancements

- **HKDF Integration** — Key derivation from master secrets
- **Streaming API** — Encrypt/decrypt large files in chunks
- **Compression** — Automatic gzip/zlib before encryption
- **Key Rotation Helpers** — Re-encrypt stored data with new keys

---

## Cross-References

- [ENCRYPTED_IMAGE_MESSAGING_IMPLEMENTATION.md](./ENCRYPTED_IMAGE_MESSAGING_IMPLEMENTATION.md) — Uses EncryptionService for image encryption
- [P2P_CHAT_SYSTEM.md](./P2P_CHAT_SYSTEM.md) — Encrypted file sharing in chat
- [NOSTR.md](./NOSTR.md) — Nostr gift wrap encryption (separate from EncryptionService, handled by dart_nostr)
