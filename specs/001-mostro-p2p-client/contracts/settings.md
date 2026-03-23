# Contract: Settings API

**Module**: `rust/src/api/settings.rs`

User-configurable app preferences. All settings are persisted locally.
`logging_enabled` is runtime-only (not persisted — always false at startup).
`privacy_mode` is authoritative on `Identity`; settings mirrors it.

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
  privacy_mode: bool               # Mirrors Identity.privacy_mode
}
```

---

### set_theme(theme: ThemeMode) → ()
Persist the user's theme preference.

**Errors**: `StorageError`.

---

### set_language(locale: String) → ()
Persist the user's language preference.

**Validation**: `locale` MUST be a valid BCP-47 locale code supported
by the app (one of the 10 supported locales).

**Errors**: `UnsupportedLocale`, `StorageError`.

---

### set_default_fiat_code(code: String?) → ()
Set the default fiat currency for new orders. Pass null to clear
(show all currencies).

**Validation**: If non-null, `code` MUST be a valid ISO 4217 code
supported by the active Mostro node.

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

### set_privacy_mode(enabled: bool) → ()
Toggle privacy mode. Delegates to `Identity` — updates
`Identity.privacy_mode` as the authoritative source, then mirrors
to settings.

**Errors**: `NoIdentity`, `StorageError`.

## Streams

### on_settings_changed() → Stream<AppSettings>
Emits whenever any setting is updated.
