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

### get_mostro_info() → MostroNodeInfo?
Fetch full Mostro daemon information from its published events. Used by
the About screen and node selector (FR-056–FR-058).

**Returns**:
```text
MostroNodeInfo {
  pubkey: String
  name: String?
  version: String?                    # Daemon software version
  expiration_hours: u32               # Pending order lifetime (default 24h)
  expiration_seconds: u32             # Waiting state timeout (default 900s)
  fee_pct: f64?                       # Maker/taker fee percentage
  max_order_amount: u64?              # Maximum order size in sats
  min_order_amount: u64?              # Minimum order size in sats
  supported_currencies: Vec<String>?  # Fiat currency codes supported
  ln_node_id: String?                 # Lightning node public key
  ln_node_alias: String?              # Lightning node alias
  is_active: bool
}
```

---

### get_known_mostro_nodes() → Vec<MostroNodeInfo>
Return the list of known Mostro nodes (hardcoded defaults + any
user-added nodes). Used by the node selector screen (FR-056).

---

### set_active_mostro(pubkey: String) → ()
Switch the active Mostro daemon. All future orders and messages will
route to this node.

**Side effects**: Updates stored active node. Re-subscribes to the
new node's relay list (kind 10002).

**Errors**: `InvalidPublicKey`, `NodeUnreachable`.

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
