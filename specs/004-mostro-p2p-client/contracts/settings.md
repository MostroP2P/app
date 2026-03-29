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

## Streams

### on_settings_changed() → Stream<AppSettings>
Emits whenever any setting is updated.
