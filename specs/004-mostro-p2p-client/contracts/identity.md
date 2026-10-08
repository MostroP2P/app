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
Retries a data wipe a previous deletion left pending (`identity_wipe_pending`,
issue #555) before installing the new identity — safe there, since the empty
slot guarantees the tables hold nothing of a live identity. A retry that fails
again refuses the new identity: once one is installed nothing retries (the
launch reload, `load_identity_from_mnemonic`, never does), so the previous
user's rows would stay for the life of the install. A marker that cannot be
read refuses it the same way, without wiping.

**Errors**: `StorageError` if secure storage unavailable; `PendingWipeFailed`
when the pending wipe failed again or its marker cannot be read (nothing
installed, the marker stays).

---

### import_from_mnemonic(words: Vec<String>, recover: bool) → IdentityInfo
Import identity from BIP-39 mnemonic phrase. If `recover` is true,
sends `Action.restore` to Mostro daemon to recover active trades and
disputes.

**Validation**: Words MUST be valid BIP-39 English wordlist, 12 or 24 words.

**Pending wipe**: like `create_identity`, retries a pending data wipe before
installing, and refuses with `PendingWipeFailed` when it fails again — but
only while no identity is loaded (checked under the identity lock). The
Account screen deletes the current identity first, so that is every import
it makes (issue #555).

**Recovery flow** (when `recover = true`):
1. Derive master key from mnemonic (BIP-32 path N=0).
2. Send `Action.restore` to Mostro daemon via NIP-44 (Kind 14).
3. Receive list of order IDs + dispute IDs.
4. Request details for each order/dispute.
5. Sync trade key index: send `Action.last_trade_index` (rumor authored by a
   trade key; the daemon resolves the account from the identity proof) and
   raise the local counter to the reply's `trade_index` — the daemon's
   authoritative high-water mark, which includes finalized trades the restore
   payload omits (#328). If the daemon refuses (`CantDo`) or does not answer,
   fall back to the maximum trade index in the restore payload (a lower
   bound: the payload lists only non-finalized orders). The counter is only
   ever raised, never lowered; re-asking is idempotent.
6. Reconstruct local DB from daemon responses.

**Note**: Recovery only works if identity is NOT in privacy mode.

**Errors**: `InvalidMnemonic`, `StorageError`, `RecoveryFailed`,
`PrivacyModeRecoveryUnavailable`, `PendingWipeFailed`.

---

### import_from_nsec(nsec: String) → IdentityInfo
Import identity from nsec (bech32-encoded private key).

**Validation**: MUST be valid bech32 nsec format.

**Pending wipe**: gated like `import_from_mnemonic` — retries a pending data
wipe while no identity is loaded, and refuses with `PendingWipeFailed` when it
fails again (issue #555).

**Errors**: `InvalidKey`, `StorageError`, `PendingWipeFailed`.

---

### get_identity() → IdentityInfo?
Get current identity info. Returns null if no identity exists.

---

### export_encrypted_backup(passphrase: String) → String
Export identity as encrypted backup string.

**Returns**: Encrypted payload (NIP-49 compatible or custom format).

**Errors**: `NoIdentity`, `EncryptionError`.

---

### funds_at_risk() → Vec<FundsAtRisk>
What the current identity would lose if it were replaced now, most serious
first; empty when it is safe to go ahead (issue #533). Local rows only — no
relay round trip.

`FundsAtRisk { order_id, reason, amount_sats? }`, where `reason` is a marker
Dart localizes:

| `reason` | When |
|---|---|
| `SellerEscrowLocked` | the user is the seller and the trade is `active`, `fiat-sent` or `dispute` — decided on the status, so a restored row with no bolt11 counts too |
| `BondLocked` | the trade's bond is `Locked` |
| `PayoutClaimOpen` | a `bond_claims` row in a non-terminal phase, inside its window |
| `TradeInProgress` | a live trade with none of the user's sats locked (a buyer mid-trade, either side before the escrow is funded) |
| `BondInvoicePending` | a `Requested` bond whose invoice has not expired |

The Account screen calls it **before** generating a user or importing a
seed — before anything is written — and shows a warning that lists the
entries. It warns, it does not block: the safe action is the primary one, a
dismissal counts as it, and going on still leads to the usual confirmation.
A check that fails reads as empty, so it cannot lock the user out of
rotating a compromised identity.

---

### delete_identity() → ()
Delete identity from device. Irreversible.

**Side effects**: the next identity finds the app as a fresh install leaves
it (issue #533).

- Gives back the identity's relay subscriptions first — d-tag watchers,
  daemon-message watchers, chats and the bulk kind-14 feed — so nothing of
  the old user's keeps arriving.
- Unregisters every push registration.
- Wipes what the identity produced: the identity row, trade keys, trades,
  chat messages, payout claims, the outbound queue, the cached order book
  (its `is_mine` marks) and the per-order settings (chat and status cursors,
  dispute markers, invoice-step starts, wipe tombstones, retained claim
  nodes, the last restore's snapshot). `Storage::clear_identity_data`, one
  transaction on native.
- The restore snapshot also names the identity that took it. A history pass
  ignores (and drops) any snapshot that is not the loaded identity's,
  including one stored before snapshots named theirs, and any snapshot whose
  floor is above the identity's trade-key counter (the key sequence started
  over, e.g. a re-import after a failed wipe). Read otherwise, its floor and
  live set would take this identity's new takes for history and wipe them
  mid-trade (#614).
- Empties the in-memory stores: disputes, ratings, sessions, chats (unread
  count published as zero), trade-key caches; then re-issues the public
  subscriptions so the book refills with no order marked as own.
- Clears the log buffer.

**Kept**: device preferences — relays, the active and custom nodes, node
caches, the push token and toggle, developer overrides. They belong to the
device, not to the identity.

Before giving anything up, the deletion records the `identity_wipe_pending`
settings key — device-scoped on purpose, since the wipe that would drop it is
the wipe that may fail — holding the identity's public key; a successful wipe
clears it. A marker an earlier deletion left stays as it is. When the marker
cannot be written or read, the deletion is refused with `WipeNotRecorded`
while the identity is still loaded and whole: deleting without it would let
the replacement install over the rows a failed wipe kept, with nothing left
to say so. A session with no database (`init_db` failed) is refused for the
same reason, with `StorageUnavailable`: no retry can succeed before a
restart, and the Account screen says so. This keeps a possibly compromised
identity until the store comes back — deliberately, since rotating it would
leave the previous user's rows on disk with no trace (review of #573). A crash between the marker and the
wipe leaves the identity's mnemonic in secure storage, so the next launch
reloads it and drops the marker (below).

Every transition of the identity slot — `create_identity`,
`load_identity_from_mnemonic`, `import_from_mnemonic`, `import_from_nsec` and
this deletion — runs alone, from its first read of the slot to its last
write: a deletion holds that turn through the wipe. Otherwise, while it waits
on the relays, the push server or the store, a second deletion could clear
the marker it recorded, a reload of the same identity release it, or a
replacement land before the wipe and lose its rows to it. Readers of the
loaded identity never wait on a transition's I/O.

A failed wipe is never turned into a failed deletion: by then the identity
is already gone. It is reported **after** the log clear (so the failure is
the first line of the fresh history, worded without orders or
counterparties), and leaves the marker recorded ahead. `create_identity` and
`import_from_mnemonic` retry the wipe off that marker while the slot is
empty, clear it on success and refuse the new identity on failure. A refused
replacement leaves the deleted identity's mnemonic in secure storage, and
the Dart side loads that identity again in the same session — any refusal
after the deletion went through, a pending wipe or words the core rejects —
then calls `restore_identity_session`, so the session is never left without
an identity (review of #573). Should that reload fail, the next launch loads
it. Either way `load_identity_from_mnemonic` drops a marker naming its own
public key, wiping nothing — the rows are its own. Otherwise the launch
reload never touches the marker; `has_pending_identity_wipe` exposes it, and
the Account screen shows a warning while it holds (issue #555). The Dart
half — cached providers and the notifications store — is
`resetIdentityScopedState`, run by the Account screen after a generate and,
on import, **before** the recovery.

**Errors**: `NoIdentity`; `WipeNotRecorded` when the pending-wipe marker
cannot be recorded, `StorageUnavailable` when the session has no database
(in both, nothing deleted and the identity stays loaded).

---

### restore_identity_session() → ()
Rebuild, for the identity loaded again after its replacement was refused,
what its deletion gave up — what a cold start builds for it: the claim nodes,
the bulk kind-14 feed and the watched orders, its chats and trade sessions,
the book's `is_mine` marks of its own orders (from its trade rows), its
dispute chats and its push registrations. Per-trade receivers stay closed,
as after a restart. Runs as a transition of the identity slot.

**Errors**: `NoIdentity` when no identity is loaded.

---

### has_pending_identity_wipe() → bool
True while a previous deletion's data wipe is pending retry (issue #555):
the previous identity's rows are still on disk. Read by the Account screen
for its warning banner; false with no database.

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
