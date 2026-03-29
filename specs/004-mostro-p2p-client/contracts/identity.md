# Contract: Identity API

**Module**: `rust/src/api/identity.rs`

Identity management — key generation, import, export, secure storage, and
BIP-32 trade key derivation (`m/44'/1237'/38383'/0/N`). All cryptographic
operations happen in Rust. Flutter receives only public information and
status. Supports session recovery via Mostro daemon.

## Functions

### create_identity() → IdentityCreationResult
Create a new Nostr keypair with BIP-39 mnemonic.

**Returns**:
```text
IdentityCreationResult {
  public_key: String       # Hex-encoded public key
  mnemonic_words: Vec<String>  # 12-word BIP-39 mnemonic (show once, user must back up)
}
```

**Side effects**: Stores encrypted private key in platform secure storage.

**Errors**: `StorageError` if secure storage unavailable.

---

### import_from_mnemonic(words: Vec<String>, recover: bool) → IdentityInfo
Import identity from BIP-39 mnemonic phrase. If `recover` is true,
sends `Action.restore` to Mostro daemon to recover active trades and
disputes.

**Validation**: Words MUST be valid BIP-39 English wordlist, 12 or 24 words.

**Recovery flow** (when `recover = true`):
1. Derive master key from mnemonic (BIP-32 path N=0).
2. Send `Action.restore` to Mostro daemon via NIP-59.
3. Receive list of order IDs + dispute IDs.
4. Request details for each order/dispute.
5. Sync trade key index.
6. Reconstruct local DB from daemon responses.

**Note**: Recovery only works if identity is NOT in privacy mode.

**Errors**: `InvalidMnemonic`, `StorageError`, `RecoveryFailed`,
`PrivacyModeRecoveryUnavailable`.

---

### import_from_nsec(nsec: String) → IdentityInfo
Import identity from nsec (bech32-encoded private key).

**Validation**: MUST be valid bech32 nsec format.

**Errors**: `InvalidKey`, `StorageError`.

---

### get_identity() → IdentityInfo?
Get current identity info. Returns null if no identity exists.

---

### export_encrypted_backup(passphrase: String) → String
Export identity as encrypted backup string.

**Returns**: Encrypted payload (NIP-49 compatible or custom format).

**Errors**: `NoIdentity`, `EncryptionError`.

---

### delete_identity() → ()
Delete identity from device. Irreversible.

**Side effects**: Clears all local data (orders, messages, trades, settings).

**Errors**: `NoIdentity`.

---

### set_pin(pin: String) → ()
Set or update device unlock PIN.

**Validation**: PIN MUST be 4-8 digits.

**Errors**: `NoIdentity`, `StorageError`.

---

### enable_biometric() → bool
Enable biometric unlock. Returns true if biometric hardware available.

**Errors**: `BiometricUnavailable`, `NoIdentity`.

---

### unlock(pin: String) → bool
Unlock the app with PIN. Returns true if correct.

**Errors**: `NoIdentity`, `MaxAttemptsExceeded`.

---

### derive_trade_key() → TradeKeyInfo
Derive a new trade-specific key for an order. Auto-increments the
trade key index.

**Returns**:
```text
TradeKeyInfo {
  index: u32           # BIP-32 index N
  public_key: String   # Trade key public key (hex)
}
```

**Side effects**: Increments `trade_key_index` on Identity. Persists
new index to storage.

**Errors**: `NoIdentity`.

---

### get_trade_key(index: u32) → TradeKeyInfo
Get a previously derived trade key by index. Used during recovery
and for re-deriving keys for existing trades.

**Errors**: `NoIdentity`, `InvalidIndex`.

---

### get_nym_identity(pubkey: String) → NymIdentity
Derive a deterministic pseudonym, icon index, and color hue from any
public key. Same input always yields the same output across sessions
and devices.

**Returns**: See `NymIdentity` in types.md
(`pseudonym: String`, `icon_index: u8 (0–36)`, `color_hue: u16 (0–359)`)

**Errors**: `InvalidPublicKey`.

## Streams

### on_identity_changed() → Stream<IdentityInfo?>
Emits when identity is created, imported, or deleted.

### on_recovery_progress() → Stream<RecoveryProgress>
Emits during session recovery to update UI progress.

```text
RecoveryProgress {
  phase: String          # "connecting", "fetching_orders", "syncing"
  current: u32           # Current item being processed
  total: u32             # Total items to process
}
```
