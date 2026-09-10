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

### Relay auto-sync from the node's kind 10002 list (implicit)
There is no separate `enable_relay_auto_sync` call: the kind 10002 (NIP-65)
relay list of the **active** Mostro node is subscribed together with the
order-book and Mostro-reply filters (stable subscription id
`mostro-relay-list`), on pool start-up and again on every node switch, so
an operator adding a relay reaches running clients live.

Every `r` tag is taken regardless of its read/write marker (the daemon
writes where we read and reads where we write). URLs are normalised
(scheme/host lower-cased, trailing slash stripped; only `ws://`/`wss://`).

Applying a list is **additive only**: relays already configured (whatever
their source) are left alone, nothing is ever disconnected, and a relay the
node stops announcing is not removed. Only the newest generation per node is
applied (older/replayed events from other relays are ignored); a generation is
`(created_at, event id)` and is ordered the way NIP-01 orders revisions of a
replaceable event — newer `created_at` wins, and on a same-second tie the lower
event id does. Added relays get `RelaySource::MostroDiscovered` and are
persisted.

Removing a `MostroDiscovered` relay through `remove_relay` **blacklists**
it (persisted as `is_blacklisted = true`, `is_active = false`), so neither a
later list nor the next start brings it back; `add_relay` of the same URL
lifts the blacklist. Removing a default or user-added relay does not
blacklist it.

`initialize(None)` restores the persisted relay set (active, non-blacklisted
rows) and the blacklist; only a store with no rows falls back to the
compiled-in defaults, which are then seeded.

Persistence here is the **native** (SQLite) story. On web the IndexedDB relay
store is still a stub (#233): discovery and the blacklist work for the life of
the session, every write is logged and ignored, and a reload starts from the
compiled-in defaults again.

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

### fetch_exchange_rate(mostro_pubkey_hex: String, fiat_code: String) → f64?
Price of one BTC in `fiat_code`, as published by that node in its Kind 30078
(NIP-33, `d` tag `mostro-rates`) event.

Exists so a market-price order can be checked against the node's sats limits
before it is submitted (#337): the daemon prices such an order as
`fiat_amount / price * 1E8` from the very aggregate it publishes here, so this
is the number its range check will use. The node's own event is the source, not
a third-party API — any other quote would be a different price, and asking for
one would disclose which currency the user is about to trade.

**Returns**: the rate, or `null` whenever the node has no usable one to give:
it publishes no rates event (publishing is optional for an operator), the event
served by the relay has expired per its NIP-40 `expiration` tag, its payload is
unusable, or it quotes no such currency. Callers MUST treat `null` as "not
checkable" — see `create_order` in `orders.md`.

**Authenticity**: An event is only used once its Schnorr signature verifies
against the node's pubkey, and only the newest event that does is considered.
The kind, author and `d` tag checks say nothing on their own — a relay is free
to answer with events the filter never asked for, and `nostr-sdk` does not
guarantee that a fetched event was verified before it reaches the caller
(GHSA-f96q-5f6p-v7cj) — so an unverified event would let a relay set the price
the whole range check is measured against.

**Caching**: The rate table is cached per node — never served back to a
different one — and bounded by the event's own expiration, clamped to one hour.
The amount fields of a range order therefore cost a single relay query.

**Errors**: `NotInitialized`, `InvalidPublicKey`, or a failed relay query. A
failed query is an error rather than `null`, but callers act on both the same
way.

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
Payload is the list of newly added relay URLs, in announcement order. Lists
that add nothing new do not emit.
