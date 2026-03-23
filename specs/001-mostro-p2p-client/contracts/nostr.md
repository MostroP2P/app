# Contract: Nostr / Relay Management API

**Module**: `rust/src/api/nostr.rs`

Relay connection management, subscription handling, connection state, and
auto-sync from Mostro daemon's kind 10002 relay list events.

## Functions

### initialize(relays: Vec<String>?) → ()
Initialize the Nostr client with relay list. If no relays provided,
uses preconfigured defaults.

**Side effects**: Connects to relays, starts subscriptions for orders
and messages.

**Errors**: `AlreadyInitialized`, `NoRelays`.

---

### add_relay(url: String) → RelayInfo
Add a new relay and connect to it.

**Validation**: `url` MUST be a valid wss:// or ws:// URL.

**Errors**: `InvalidUrl`, `RelayAlreadyExists`.

---

### remove_relay(url: String) → ()
Remove a relay and disconnect.

**Preconditions**: Cannot remove last active relay.

**Errors**: `RelayNotFound`, `LastRelay`.

---

### get_relays() → Vec<RelayInfo>
Get all configured relays with current status.

---

### get_connection_state() → ConnectionState
Get overall connection state (Online if at least one relay connected,
Offline if none, Reconnecting if attempting).

---

### flush_message_queue() → u32
Attempt to send all queued offline messages. Returns count of
successfully sent messages.

**Preconditions**: At least one relay connected.

## Streams

### on_connection_state_changed() → Stream<ConnectionState>
Emits when overall connection state changes.

### on_relay_status_changed() → Stream<RelayInfo>
Emits when any individual relay's status changes.

---

## Auto-Sync Functions

### enable_relay_auto_sync(mostro_pubkey: String) → ()
Subscribe to Mostro daemon's kind 10002 relay list events. When the
daemon publishes updated relays, auto-add them locally (additive only —
never disconnects existing relays during sync).

**Side effects**: Creates Nostr subscription for kind 10002 from the
specified pubkey.

**Errors**: `NotConnected`.

---

### get_mostro_settings() → MostroSettings?
Fetch Mostro daemon configuration from its published events.

**Returns**:
```
MostroSettings {
  mostro_pubkey: String
  expiration_hours: u32       # Pending order lifetime (default 24h)
  expiration_seconds: u32     # Waiting state timeout (default 900s)
}
```

---

### register_push_token(token: String, platform: String) → ()
Register a push notification token with the push server for background
trade event notifications.

**Side effects**: Sends token to push server. Server monitors relays
for tradeKey.public in p-tag and sends silent push. No message content
is transmitted.

**Errors**: `PushServerUnavailable`.

### on_relay_auto_synced() → Stream<Vec<String>>
Emits when new relays are auto-synced from daemon's kind 10002 events.
Payload is the list of newly added relay URLs.
