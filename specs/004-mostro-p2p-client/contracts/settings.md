# Contract: Settings API

**Module**: `rust/src/api/settings.rs`

User-configurable app preferences. All settings are persisted locally.
`logging_enabled` is runtime-only (not persisted — always false at startup).
`privacy_mode` in `AppSettings` is a read-only mirror of `Identity.privacy_mode`.
To change privacy mode, call `set_privacy_mode()` in the Reputation API
(`rust/src/api/reputation.rs`), which is the single write path.

## Functions

### get_settings() → AppSettings
Return all current user preferences.

**Returns**:
```text
AppSettings {
  theme: ThemeMode                 # System | Dark | Light (default: System)
  language: String                 # BCP-47 locale code (default: device locale)
  default_fiat_code: String?       # ISO 4217 code, e.g. "USD" (default: null — show all)
  default_lightning_address: String?  # Lightning address for auto-fill when selling
  logging_enabled: bool            # Runtime-only; always false at startup
  privacy_mode: bool               # Mirrors Identity.privacy_mode; false when no Identity exists
}
```

---

### set_theme(theme: ThemeMode) → ()
Persist the user's theme preference.

**Errors**: `StorageError`.

---

### set_language(locale: String) → ()
Persist the user's language preference.

**Validation**: `locale` MUST be one of the BCP-47 codes supported at
initial release per FR-020d: `en`, `es`, `it`, `fr`, `de`.

**Errors**: `UnsupportedLocale`, `StorageError`.

---

### set_default_fiat_code(code: String?) → ()
Set the default fiat currency for new orders. Pass null to clear
(show all currencies).

**Validation** (applied only when `code` is non-null):
- If no active Mostro node is selected: perform format-only validation
  (accept any syntactically valid ISO 4217 code). Do NOT return
  `UnsupportedCurrency`.
- If an active node exists but `MostroNodeInfo.supported_currencies` is
  `null` (list unknown): likewise perform format-only validation and do
  NOT return `UnsupportedCurrency`.
- Only return `UnsupportedCurrency` when an active node provides a
  non-null `supported_currencies` Vec and `code` is not in that Vec.

**Errors**: `UnsupportedCurrency`, `StorageError`.

---

### set_default_lightning_address(address: String?) → ()
Set a default Lightning Address to auto-fill when selling (buyer
submits invoice). Pass null to clear.

**Validation**: If non-null, MUST match `user@domain` format.

**Errors**: `InvalidLightningAddress`, `StorageError`.

---

### set_logging_enabled(enabled: bool) → ()
Enable or disable diagnostic logging at runtime. Not persisted —
resets to false on next app launch.

---

## Mostro Node Selection

### get_mostro_pubkey() → String
Return the active Mostro node's pubkey (hex) — the user-selected override, or
the compiled-in `DEFAULT_MOSTRO_PUBKEY` when none has been selected.

---

### set_active_mostro_node(pubkey: String) → ()
The single entry point for selecting / switching the active Mostro node.

Validates `pubkey`, persists it as the active node's **identity**, updates the
in-memory override (so outgoing events target the new node immediately), and
re-targets the live feeds to it: the order book is cleared, the Kind 38383
(orders) and Kind 14 (Mostro replies) filters are re-subscribed — author-pinned
to the new node via stable subscription IDs so the old filters are replaced in
place — the node's current orders are refetched, and its PoW requirement is
refreshed.

The switch is **purely local**: no Nostr message is sent to either node. Pass
`DEFAULT_MOSTRO_PUBKEY` to return to the default node.

**Persistence**: only the pubkey is stored, under key `active_mostro_pubkey` in
the generic `settings` key-value table. Node **metadata** (name, fees, accepted
currencies, limits — the `MostroNodeInfo` model) is a separate concern deferred
to the M5 node registry; it is NOT persisted as the active selection.

**Errors**: `InvalidPubkey` if `pubkey` is not a valid 64-char hex key;
`StorageError` on a persistence failure.

---

### rehydrate_active_mostro_node() → ()
Load the persisted active pubkey into the in-memory override. Call once at
startup, after `init_db` and **before** the relay pool starts subscribing, so
the first subscription already targets the user's selected node. No-op when
nothing has been persisted (the compiled-in default then applies) or when the
DB is unavailable.

---

## Streams

### on_settings_changed() → Stream<AppSettings>
Emits whenever any setting is updated.

---

## Default Configuration (Hardcoded Seed Values)

These values are compiled into the app as defaults. They are used on first launch
before the user adds or removes anything.

### Default Relays

| URL | Purpose |
|-----|---------|
| `wss://relay.mostro.network` | Primary Mostro relay |
| `wss://nos.lol` | General Nostr relay (fallback) |

These are stored as `RelayInfo` entries with `user_added: false`. They cannot be
removed by the user from the UI (only user-added relays are deletable), but they
can be disabled.

### Default Mostro Node

| Field | Value |
|-------|-------|
| `pubkey` | `82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390` |
| `name` | `Mostro` |

When no `active_mostro_pubkey` has been persisted (first launch, or after the
user picks "Use Default"), this compiled-in pubkey is the active node. The user
switches to another one from Settings → Mostro Node via `set_active_mostro_node`.

### Rust Constants (suggested location: `rust/src/config.rs`)

```rust
pub const DEFAULT_RELAYS: &[&str] = &[
    "wss://relay.mostro.network",
    "wss://nos.lol",
];

pub const DEFAULT_MOSTRO_PUBKEY: &str =
    "82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390";

pub const DEFAULT_MOSTRO_NAME: &str = "Mostro";
```
