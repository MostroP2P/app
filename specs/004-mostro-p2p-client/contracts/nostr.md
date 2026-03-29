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
  expiration_hours: u32               # Pending order lifetime; default 24 if omitted by daemon
  expiration_seconds: u32             # Waiting state timeout; default 900 if omitted by daemon
  fee_pct: f64?                       # Maker/taker fee percentage
  max_order_amount: u64?              # Maximum order size in sats
  min_order_amount: u64?              # Minimum order size in sats
  supported_currencies: Vec<String>?  # Fiat currency codes supported (null = unknown)
  ln_node_id: String?                 # Lightning node public key
  ln_node_alias: String?              # Lightning node alias
  is_active: bool
}
```

> `expiration_hours` and `expiration_seconds` may be absent in daemon-published events.
> The client MUST treat missing values as `24` and `900` respectively so that callers
> always receive concrete `u32` values. Deserialization/constructor MUST apply these
> defaults (e.g. `#[serde(default = "default_expiration_hours")]`).

---

### get_known_mostro_nodes() → Vec<MostroNodeInfo>
Return the list of hardcoded default Mostro nodes bundled with the app.
Used by the node selector screen (FR-056). To switch the active node,
call `set_active_mostro(pubkey)`. No API for adding arbitrary nodes is
provided; the list is fixed at compile time.

---

### set_active_mostro(pubkey: String) → ()
Switch the active Mostro daemon. All future orders and messages will
route to this node.

**Execution model**: Returns immediately after validating `pubkey`
format and persisting the new active node to storage. Re-subscription
to the new node's kind 10002 relay list happens asynchronously in the
background and does NOT block the return.

**Atomicity**: The active node is updated in storage before the
subscription attempt begins. If subscription fails, the stored active
node is NOT rolled back — the caller must call `set_active_mostro`
again with a different pubkey to recover.

**Validation**: `pubkey` MUST be a valid 64-char hex string (32 bytes).
`InvalidPublicKey` is returned synchronously on format failure, before
any network attempt.

**Timeout / retry**: The background subscription attempt times out
after 30 seconds. If it fails, it is retried up to 3 times with
exponential backoff. After all retries are exhausted the new node's
relay connections surface `RelayStatus.Error` via
`on_relay_status_changed()`; if those relays were the only active ones,
the overall `ConnectionState` transitions to `Offline` via
`on_connection_state_changed()`. No separate `NodeUnreachable` event
type is emitted — callers detect unreachability through the standard
relay-status and connection-state streams.

**Errors**: `InvalidPublicKey` (synchronous, format validation only).

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
