# Contract: Settings API

**Module**: `rust/src/api/settings.rs`

User-configurable app preferences. All settings are persisted locally.
`logging_enabled` is runtime-only in the Rust store; the Flutter layer persists
it and re-applies it on launch, so the user's choice survives a restart.
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
  logging_enabled: bool            # Runtime-only in Rust; re-applied by Flutter on launch
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
Enable or disable verbose diagnostic logging at runtime. Applies the global log
filter synchronously: `Debug` while enabled, otherwise the build default
(`Debug` in debug builds, `Info` in release).

Not persisted in the Rust store — the Flutter layer owns persistence and calls
this once at startup with the saved value.

---

## Mostro Node Selection

### get_mostro_pubkey() → String
Return the active Mostro node's pubkey (hex) — the user-selected override, or
the compiled-in `DEFAULT_MOSTRO_PUBKEY` when none has been selected.

---

### set_active_mostro_node(pubkey: String) → ()
The single entry point for selecting / switching the active Mostro node.

Normalizes `pubkey` to lowercase hex (the registry compares case-sensitively),
validates it, persists it as the active node's **identity**, updates the
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
currencies, limits — the `MostroNodeInfo` model) is NOT persisted as the active
selection; display metadata lives in the node registry below.

**Errors**: `InvalidPubkey` if `pubkey` is not a valid 64-char hex key;
`StorageError` on a persistence failure.

---

## Node Registry (`api/nodes.rs`)

The selector in Settings → Mostro Node lists `MostroNodeEntry` rows merged
from three sources: the compiled-in trusted registry
(`config::TRUSTED_MOSTRO_NODES`, mirrored from mostro.community and from v1's
`communities.dart`), user-added custom nodes, and cached kind 0 display
metadata (name, picture, about, website). Selection itself still goes through
`set_active_mostro_node` — the registry only manages the list.

### list_mostro_nodes() → Vec<MostroNodeEntry>
Trusted nodes first (registry order), then custom nodes (insertion order),
each flagged `is_active` against the current override. An active pubkey not
present in the registry (selected before the registry existed) is
auto-imported as a custom node so the selector always shows what the app is
actually using. Custom entries whose pubkey has since joined the trusted
registry are dropped (and the cleanup persisted) — otherwise a promotion
would leave a duplicate row that `remove_custom_mostro_node` refuses to
delete.

### add_custom_mostro_node(input: String, name: Option<String>) → MostroNodeEntry
Accepts a 64-char hex pubkey or `npub1…` (normalized to lowercase hex). A
user-given `name` takes precedence over kind 0 metadata.
**Errors** (stable markers, localized in Dart): `PrivateKeyNotAllowed` (nsec
input), `InvalidPubkey`, `NodeAlreadyExists` (trusted or already added),
`NotInitialized`.

### remove_custom_mostro_node(pubkey: String) → ()
Removes a user-added node; removing an absent one is a no-op.
**Errors**: `CannotRemoveActiveNode`, `NodeIsTrusted`, `NotInitialized`.

### refresh_mostro_node_metadata() → Vec<MostroNodeEntry>
Fetches kind 0 profile events for all known nodes in one relay query (10s
timeout), updates the persisted cache, and returns the refreshed registry.
Best-effort with partial updates: whatever arrives within the window is
cached, even when some authors never answered; only an outright query failure
errors, leaving the cache untouched. `picture`/`website` are kept only when
`https://` — a kind 0 event is attacker-controlled input.

**Persistence**: `custom_mostro_nodes` (JSON array) and
`mostro_node_metadata` (JSON map, pubkey → metadata) in the generic
`settings` key-value table.

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
| `wss://mostro-p2p.tech` | Mostro relay (default node's kind 10002 list) |
| `wss://relay.shadowbip.com` | Mostro relay (default node's kind 10002 list) |

The set mirrors the default node's own kind 10002 relay list. Public relays
rate-limit and cap replays differently (`relay.mostro.network` stops at 300
stored events per REQ, `nos.lol` at 500), so seeding all four keeps the order
book reachable when one of them is throttling the client.

These are stored as `RelayInfo` entries with `user_added: false`. They cannot be
removed by the user from the UI (only user-added relays are deletable), but they
can be disabled.

### Default Mostro Node

| Field | Value |
|-------|-------|
| `pubkey` | `82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390` |
| `name` | `Mostro` |

When no `active_mostro_pubkey` has been persisted (first launch), this
compiled-in pubkey is the active node. It is also part of the trusted node
registry (region `🌐`), so returning to it is a normal selection in
Settings → Mostro Node via `set_active_mostro_node`.

### Rust Constants (suggested location: `rust/src/config.rs`)

```rust
pub const DEFAULT_RELAYS: &[&str] = &[
    "wss://relay.mostro.network",
    "wss://nos.lol",
    "wss://mostro-p2p.tech",
    "wss://relay.shadowbip.com",
];

pub const DEFAULT_MOSTRO_PUBKEY: &str =
    "82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390";

pub const DEFAULT_MOSTRO_NAME: &str = "Mostro";
```
