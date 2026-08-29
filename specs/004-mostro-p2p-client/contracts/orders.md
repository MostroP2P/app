# Contract: Orders API

**Module**: `rust/src/api/orders.rs`

Order browsing, creation, and lifecycle management. Orders are fetched from
Mostro daemon via Kind 38383 Nostr events and cached locally.

### Daemon confirmation & request correlation

Every request that expects a daemon reply (`create_order`, `take_order`,
`send_invoice`) carries a random u64 `request_id` nonce. The daemon echoes
it in its reply (success or `CantDo`), and **only a reply echoing the exact
nonce may resolve or consume the pending request** — stale events replayed
by relays carry a different (or no) `request_id` and touch nothing. Each
call waits up to 10 s; on timeout it returns `NoDaemonResponse` and nothing
is persisted. A genuine late reply is still reconciled where meaningful
(create), or logged and dropped (take / add-invoice).

## Functions

### get_orders(filters: OrderFilters?) → Vec<OrderInfo>
Fetch available orders. Returns cached orders if offline, live orders
if connected. Merges local cache with relay data.

**Parameters**:
```text
OrderFilters {
  kind: OrderKind?          # Buy or Sell
  fiat_code: String?        # ISO 4217 filter
  payment_method: String?   # Payment method filter
}
```

**Returns**: List of orders sorted by creation time (newest first).

---

### get_order(order_id: String) → OrderInfo?
Get single order details by ID. Returns from local cache or fetches
from relay.

---

### create_order(params: NewOrderParams) → OrderInfo
Publish a new order to the Mostro network.

**Parameters**:
```text
NewOrderParams {
  kind: OrderKind             # Buy or Sell
  fiat_amount: f64?           # Fixed amount in fiat (null if range)
  fiat_amount_min: f64?       # Min amount for range orders (null if fixed)
  fiat_amount_max: f64?       # Max amount for range orders (null if fixed)
  fiat_code: String           # ISO 4217 code
  payment_method: String      # Payment method description
  premium: f64                # Price premium/discount %
  amount_sats: u64?           # Optional fixed sat amount
}
```

**Validation**:
- Either `fiat_amount` OR both `fiat_amount_min` and `fiat_amount_max` MUST be provided (not both)
- If range: `fiat_amount_min` MUST be > 0 and < `fiat_amount_max`
- `fiat_code` MUST be valid ISO 4217
- `payment_method` MUST not be empty

**Side effects**: Sends the new-order message to the Mostro daemon and waits for its confirmation. The order is created only once the daemon confirms it; the public order book is populated exclusively from the daemon's Kind 38383 event (the order is **not** inserted optimistically). On no confirmation within the timeout the order is treated as not created — nothing is persisted to My Trades and nothing is added to the book.

**Errors**: `NoIdentity`, `Offline` (queued), `NoDaemonResponse` (daemon did not confirm within the timeout), `ProtocolError`.

---

### take_order(order_id: String, role: TradeRole, fiat_amount: f64?) → TradeInfo
Take an existing order, starting a trade. `fiat_amount` is required for
range orders and must fall within `[fiat_amount_min, fiat_amount_max]`.

**Validation**:
- Order MUST exist in the book, not be own (`CannotTakeOwnOrder`) and be
  `Pending` (`OrderAlreadyTaken`)
- `role` MUST match the order kind (buyers take sell orders, sellers take
  buy orders)

**Side effects**: Sends TakeBuy/TakeSell (NIP-44 kind 14, with the
correlation nonce) and waits for the daemon's first reply, which varies by
role and daemon config — `add-invoice` (buyer: calculated sats in an Order
payload), `pay-invoice` (seller: hold invoice in a PaymentRequest payload),
or a direct progression message. Only on a correlated reply is the trade
created: the TradeInfo is built from the reply's real data (status,
calculated `amount_sats`, `hold_invoice`), persisted to My Trades, the
order book entry is synced, and the trade session/subscriptions start.
That persistence half runs under the per-order lock (see *Per-order
serialization*), acquired after the reply and never around the wait for it.
On rejection or timeout **nothing is persisted** — no phantom trade.

**Errors**: `OrderNotFound`, `CannotTakeOwnOrder`, `OrderAlreadyTaken`,
`InvalidRole`, `FiatAmountRequired`/`OutOfRange` (range orders),
`BondRequired` (daemon requires an anti-abuse bond — not supported yet),
`NoDaemonResponse`, plus daemon `CantDo` reasons passed through as errors.

---

### cancel_order(order_id: String) → ()
Cancel own untaken order.

**Preconditions**: Order MUST be owned by current user. Order status
MUST be `Pending`.

**Errors**: `NotMyOrder`, `OrderNotCancelable`, `ProtocolError`.

---

### send_invoice(order_id: String, invoice_or_address: String, amount_sats: u64) → ()
For sell orders: buyer submits a bolt11 invoice or a Lightning Address for
receiving payment. For LN addresses (`user@domain`) `amount_sats` is
required so the daemon can resolve the address; bolt11 invoices encode
their own amount.

**Side effects**: Sends `AddInvoice` (with the correlation nonce) and waits
for the daemon's acknowledgement — its reply (`waiting-seller-to-pay`,
`buyer-invoice-accepted`, …) is also a status update and is processed
normally. The UI advances only on acknowledgement.

**Errors**: `InvalidInvoice` (daemon CantDo), `NoDaemonResponse` (stay on
the invoice step), `TradeNotFound`.

---

### confirm_fiat_received(trade_id: String) → ()
Seller confirms fiat payment received. Triggers fund release.

**Side effects**: Sends `Release` action to Mostro daemon.

**Errors**: `TradeNotFound`, `NotSeller`, `WrongTradeState`.

---

### mark_fiat_sent(trade_id: String) → ()
Buyer marks fiat payment as sent.

**Side effects**: Sends `FiatSent` action to Mostro daemon.

**Errors**: `TradeNotFound`, `NotBuyer`, `WrongTradeState`.

---

### request_cooperative_cancel(trade_id: String) → ()
Request cooperative cancellation of active trade.

**Side effects**: Sends cooperative cancel request to Mostro daemon.
Counterparty receives notification.

**Errors**: `TradeNotFound`, `WrongTradeState`, `ProtocolError`.

---

### accept_cooperative_cancel(trade_id: String) → ()
Accept a cooperative cancel request from the counterparty.

**Side effects**: Sends acceptance to Mostro daemon. Trade is canceled
and escrowed funds returned.

**Errors**: `TradeNotFound`, `NoPendingCancelRequest`, `ProtocolError`.

---

### get_active_trade() → TradeInfo?
Get the current active trade. Returns null if no trade is active.

---

### get_trade_history() → Vec<TradeHistoryEntry>
Get completed trades ordered by completion time (newest first).

---

### share_order(order_id: String) → OrderShareInfo
Generate a shareable deep link and QR data for an order.

**Returns**:
```text
OrderShareInfo {
  deep_link: String     # mostro://order/<id>
  qr_data: String       # Data to encode in QR code
  order: OrderInfo
}
```

---

### resolve_deep_link(uri: String) → String?
Parse a `mostro://order/<id>` deep link and return the order ID.
Returns null if URI is not a valid Mostro deep link.

## Streams

### on_orders_updated() → Stream<Vec<OrderInfo>>
Emits whenever the order list changes (new orders, status updates,
expirations). Used to keep the UI order list in sync.

### on_trade_updated() → Stream<TradeUpdate>
Push channel for daemon-driven trade lifecycle changes. Every status a
Kind 14 dispatch arm syncs is emitted here after the in-memory book
update and the DB persistence **attempt** — a DB write failure (or a
memory-only session, where `db()` is `None`) is logged and does not
suppress the notification, so listeners must not assume the trade row
already reflects the status. Also emitted by the stale-state sweep's
maker resync. Two consumer needs:
changes the 2s status polling cannot observe (a never-active trade is
**wiped** from the DB on the daemon's `Canceled` — no row left to poll —
and after a taker-timeout republish the book reads `pending` again), and
action requests the user must react to promptly — `WaitingBuyerInvoice` /
`WaitingPayment` drive the app-wide auto-navigation to the add-invoice /
pay-invoice screens (`TradeActionListener`, which resolves the trade role
so the counterparty's informational copy of those statuses never
navigates). Take replies produce no emission: the take waiter consumes
them before the dispatch arms run. Screens filter by `order_id`.

```text
TradeUpdate {
  order_id: String
  status: OrderStatus   # the status just persisted; Pending on maker resync
}
```

### on_order_status_changed(order_id: String) → Stream<OrderStatus>
Emits when a specific order's status changes.

### on_trade_step_changed() → Stream<TradeInfo>
Emits when the active trade's step changes. Used to update the
trade progress stepper.

### on_cooperative_cancel_requested() → Stream<String>
Emits when the counterparty requests a cooperative cancel.
Payload is the trade ID.

### on_trade_timeout_tick() → Stream<TradeTimeoutInfo>
Emits countdown updates for time-limited trade states.

```text
TradeTimeoutInfo {
  trade_id: String
  seconds_remaining: u32
  state: TradeStep
}
```

---

## Seller hold-invoice flow (Nostr → DB → UI)

The seller never receives the bolt11 hold invoice via a synchronous API
call — it arrives as a Kind 14 (NIP-44) message from mostrod. This
section documents the full chain so Flutter providers and screens know
what to listen to. Reference: <https://mostro.network/protocol/seller_pay_hold_invoice.html>.

### Kind-14 delivery & decryption coverage

Receiving a daemon Kind 14 takes two independent layers, and BOTH must
cover the trade or its messages are lost (dropped as
`no-matching-p-tag`, observable in the logs with the map size):

- **Delivery** — the bulk `mostro-dm` relay subscription, author-pinned to
  the active node, whose `#p` filter must include the trade key's pubkey.
- **Decryption** — the refreshable coverage map (`global_dm_keys`,
  pubkey → keys+index) the event loop decrypts against.

Coverage invariants:

- **Both subscription entry points seed in full.** Startup
  (`_run_order_subscription`) and node switch derive every known trade key
  (indexes `1..=identity.trade_key_index`) and seed the map through the
  shared `seed_global_dm_coverage()` before subscribing. A session that
  does not rehydrate leaves every previous session's trade deaf: statuses
  freeze at whatever the public Kind 38383 shows (masked `in-progress`),
  requests like add-invoice never reach the user, and the daemon
  eventually cancels by timeout (#277 cause 3).
- **Seeding is a union, never a replace** — a key derived concurrently by
  a create/take in flight must survive the seed.
- **Mid-session keys join incrementally**: every derive path calls
  `ensure_global_dm_coverage`, which inserts the key and re-issues the
  relay filter under the same stable subscription id.
- **The relay filter is always rebuilt from the full map** — never from
  session-local state. A rebuild from a subset silently unsubscribes the
  missing trades at the relay.
- The temporary 30-minute per-trade receivers (see #182) are an
  additional delivery path, not a substitute: they exist only for trades
  touched this session and mask coverage gaps while they run.

### Inbound Kind 14 actions consumed by `dispatch_mostro_message`

| Action                             | Payload variant                                     | Effect on the local trade row                                                    |
|------------------------------------|-----------------------------------------------------|----------------------------------------------------------------------------------|
| `WaitingBuyerInvoice`              | (status sync)                                       | `status → WaitingBuyerInvoice`                                                   |
| `AddInvoice`                       | `Payload::Order(small_order)`                       | Maker-buyer path (a taker's nonce-correlated copy is consumed by the take interception, even when late): `status → WaitingBuyerInvoice` (payload status, fallback `status_for_action`), `amount_sats ← small_order.amount` when > 0 — synced to book **and** DB so `tradeAmountProvider` sees the sats. Keyed by the message's order id (`trade_index` is `None`). The follow-up `AddInvoice` with a `Payload::Peer` (counterparty reputation) is ignored. |
| `PayInvoice`                       | `Payload::PaymentRequest(small_order, bolt11, amt)` | `hold_invoice ← bolt11`, `amount_sats ← amt ?? small_order.amount`, `status → WaitingPayment` |
| `BuyerTookOrder` / `HoldInvoicePaymentAccepted` | `SmallOrder` with `status = active`      | `status → Active` (routed through `map_core_status` kebab-case)                  |
| `FiatSentOk`                       | (status sync)                                       | `status → FiatSent`                                                              |
| `HoldInvoicePaymentSettled` / `Released` / `PurchaseCompleted` | (status sync)             | `status → SettledHoldInvoice`                                                    |
| `CooperativeCancelAccepted`        | (status sync)                                       | `status → CooperativelyCanceled`                                                 |
| `AdminSettled` / `AdminCanceled`   | (status sync)                                       | `status → SettledByAdmin` / `CanceledByAdmin`                                    |
| `Canceled`                         | (none)                                              | Never-active trade (pending/waiting): row + in-memory session **deleted**; otherwise `status → Canceled` (history kept). See below. |

A sync that would move a trade out of a **hard-terminal** status
(`Canceled` / `CanceledByAdmin` / `CooperativelyCanceled` / `Expired` /
`Success` / `SettledByAdmin` / `CompletedByAdmin`) is skipped entirely —
no book/DB write, no emission, and no session side effect either (the
guard runs before the peer-key/chat setup of the escrow-locked arm). Relays deliver the startup backlog
newest-first, so such a message is an out-of-order replay, not a real
transition; mostrod never reopens a finished trade. `SettledHoldInvoice`
and `Dispute` still progress and are deliberately not in the set.
`Canceled` applies the same guard — a stale timeout-cancel replayed over
an order that was later re-taken and completed must not overwrite the
outcome; its wipe path is unaffected, since it starts from non-terminal
waiting states.

Every arm above that syncs a status also emits a `TradeUpdate` (see
`on_trade_updated`) after the in-memory book update and the DB
persistence attempt — DB failures are logged, never suppress the
emission, and leave the row behind the book. `Canceled` included, which
emits whether it wiped the row or kept it as history.

### Per-order serialization

`dispatch_mostro_message` and `take_order`'s persistence block both check
local state and mutate the order book, the trade row and the session
several `await`s later. Those two halves are **one operation per
`order_id`**, held under a per-order mutex (#259).

Without it, a delivery that passed its check can be overtaken by a retake
of the same order while it is suspended: the retake persists its own
state, then the suspended handler resumes and writes the previous
generation's outcome over it. The `Canceled` arm is the reachable case —
it has mutated book and DB with no generation check of its own.

Invariants:

- **The lock is keyed by `order_id`, never global.** One stalled handler
  must not stop every other trade.
- **`dispatch_mostro_message` takes it once the message kind is parsed**,
  covering the local→daemon id reconcile, the waiter interception and
  every per-action arm. A message carrying no order id owns no order state
  and takes no lock.
- **No caller may hold it while waiting for a daemon reply.** That reply is
  delivered by `dispatch_mostro_message`, which takes the same lock, so
  `take_order` acquires it only *after* its wait resolves — around the
  persistence block alone. Holding it across the wait deadlocks the take
  until its 10 s timeout.
- **The take reply hands the guard off.** The dispatcher that resolves a
  waiting `take_order` sends its own guard through the waiter channel
  (`Wake.order_guard`), so consumed-reply → persistence is one critical
  section: released instead, a second daemon message already queued on the
  FIFO mutex would beat the woken task and run its arm against a trade row
  and session that do not exist yet. The guard rides *inside* the channel
  value, so every losing path releases it by dropping — a timed-out
  waiter's failed send, a receiver dropped with the reply unread. Only the
  take reply carries a guard: an add-invoice's effects are persisted by
  the dispatch arms themselves (still holding it), and a create's gap is
  owned by the reconcile block and the Kind 38383 fingerprint path.
- **The registry tracks live work, not history**: entries no handler holds
  any more are dropped on the next acquisition, so it does not grow with
  every order ever dispatched.
- **A generation gate backs the lock**, read under it so it cannot
  interleave with a retake's rebind: a message addressed to a trade key
  *older* than the one currently bound to its order (`trade_keys` binding)
  belongs to a superseded attempt and is dropped whole — the lock
  serializes concurrent handlers, the gate rejects the late ones.
  Strictly-older only: a retake's first reply arrives on the NEW key while
  the binding still holds the old index (`take_order` rebinds only after
  that reply resolves its waiter), and the identity counter only grows, so
  newer-than-bound is always legitimate. No binding fails open (a create's
  confirmation precedes any binding for the daemon id). `BondSlashed` is
  exempt: it never writes order state, and a trailing slash notice
  addressed to the slashed (superseded) generation is by-design delivery
  (#197).

### Daemon cancellation semantics

- A trade still in `Pending` / `WaitingBuyerInvoice` / `WaitingPayment` when
  the daemon's `Canceled` arrives never went active — no peer, no chat, no
  exchange (typically a waiting-state timeout). Its trade row and in-memory
  session are **deleted**, mirroring v1's session cleanup; chat messages are
  untouched (none can exist before Active). Trades that progressed keep
  their row (and chat) as history, marked `Canceled`. `InProgress` rows are
  conservatively kept: that status only enters via the Kind 38383 sync,
  where mostrod masks both waiting AND active phases as `in-progress`.
- The handler MUST NOT remove the order from the in-memory book: on a
  taker-responsible timeout mostrod republishes the order as `pending`
  BEFORE sending `Canceled`, so a blind remove races the republish and
  loses the order until restart. The book is fed only by Kind 38383 events;
  a genuine cancel arrives as a status update and the UI filters it out.

### Stale-state sweep

Covers cancellations whose gift wrap the app never received (closed or
offline when the daemon's waiting window expired). Runs 60s after the
order subscription starts, then every 30 minutes: waiting trades past
their window (`timeout_at`, else `started_at + 900`) are checked against
the public book — `pending` republish wipes taker rows and resyncs maker
rows to `Pending`; an outright cancel wipes; absence from the book or the
ambiguous `in-progress` marker changes nothing. Every action requires a
positive daemon signal; the clock only triggers the check. The sweep also
drops keyless in-memory sessions older than 24h and logs counters.

`process_gift_wrap_rumor` MUST update **both** the in-memory order book
(`order_book().update_order_status`) **and** the persisted trade row
(`db.update_trade_fields`) on every status transition, otherwise UI
screens reading from the DB (e.g. `tradeInfoStreamProvider`) will miss
transitions that only affected in-memory state.

### Public status vs. trade status

The `s` tag of a Kind 38383 event is NIP-69's four-bucket view of an order
(`pending`, `in-progress`, `success`, `canceled`), not its protocol status.
mostrod publishes `in-progress` when an order leaves the book and then stops
publishing altogether while the trade is private: `Active`, `FiatSent`,
`Dispute` and `SettledHoldInvoice` never reach the wire (`create_status_tags`
returns `create_event = false`, so no event is emitted at all). `WaitingTakerBond`
publishes as `pending`; `WaitingMakerBond` publishes nothing.

Therefore `OrderStatus::InProgress` on this client means **taken, real state
unknown** — never that the escrow is locked. The fine-grained states are only
ever learned from daemon messages, so:

- Both wire ingest paths (`ingest_order_event`, `subscribe_single_order`) MUST
  gate the status through `wire_status_applies`: a wire status may only fill an
  unknown or still-`Pending` local status, or announce a terminal one. It MUST
  NOT overwrite a status already learned from a daemon message, in the trade row
  or in the order book.
- UI MUST NOT treat `InProgress` as `Active`. Actions the daemon gates on
  `Active`/`FiatSent` (dispute, fiat-sent) are rejected with `CantDo` in that
  state (issue #203).

### `update_trade_fields(order_id, status?, hold_invoice?, amount_sats?)` (DB contract)

SQLite native backend updates the `trades.data` JSON column atomically
via `json_set` layering. Constraints:

- Numeric parameters (`amount_sats`) MUST be wrapped via `json(?)` so
  SQLite parses them as JSON numbers. Binding a plain `sats.to_string()`
  through `?` stores the value as a JSON **string**, which breaks
  `serde_json::from_str::<TradeInfo>` on the next read and causes
  `list_trades()` to silently skip the row (see `sqlite.rs::list_trades`
  which logs a warn and continues). This is a permanent corruption of
  the row until a subsequent update rewrites the field.
- Enum parameters (`status`) follow the same rule — already implemented
  via `serde_json::to_string(&status)` + `json(?)`.
- String parameters (`hold_invoice`) are bound as raw text; SQLite's
  `json_set` auto-quotes and escapes them into a valid JSON string.
- The `WHERE` clause is `json_extract(data, '$.order.id') = ?`. An
  UPDATE matching zero rows is NOT an error; callers MUST ensure the
  trade row has been inserted via `save_trade` before the first update.

Web backend (`indexeddb.rs::update_trade_fields`) is currently a stub
and does not yet persist — feature-gated via `#[cfg(target_arch = "wasm32")]`.
It logs a `log::warn!` on every call so web builds fail loudly (not
silently) when seller pay-invoice flows hit this path; a full
read-modify-write port of the sqlite.rs logic using `indexed_db_futures`
is tracked as follow-up work.

### One-time migration: `amount_sats` string → integer repair

A previous version of `update_trade_fields` bound `amount_sats` as a raw
text parameter, so `json_set` stored it as a JSON **string** instead of
a JSON integer, silently corrupting the row for future deserialization.
`SqliteStorage::migrate` now runs a one-time repair on boot that walks
the `trades` table and rewrites any row where
`json_type(data, '$.order.amount_sats') = 'text'` to cast the value back
into a JSON integer via `CAST(... AS INTEGER)` inside `json_set`. The
migration logs the number of rows repaired (or 0 if none) so affected
installations self-heal on the next app start.

### Flutter-side live subscriptions (all platforms)

The seller pay-invoice flow uses two complementary providers from
`lib/features/order/providers/trade_state_provider.dart`:

- **`tradeInfoStreamProvider(orderId)`** — polls `listTrades()` every
  1 s, yields the full `TradeInfo`, and **terminates as soon as
  `holdInvoice != null`**. Used by `PayLightningInvoiceScreen` to
  resolve the bolt11 + amount for rendering the QR. Consumers that
  need post-invoice updates MUST compose this with
  `tradeStatusProvider`.
- **`tradeStatusProvider(orderId)`** — polls `getOrder()` every 2 s
  with a `listTrades()` fallback when the order has left the in-memory
  order book. Runs until the status is terminal. `PayLightningInvoiceScreen`
  subscribes via `ref.listen` and navigates to `/trade_detail/:orderId`
  on `Active` (or later non-cancel statuses), and away to `/home` on
  any cancellation/expiry. This is the single source of truth for
  advancing past the pay-invoice screen; the NWC widget's local
  `onPaymentSuccess` callback only flips a spinner flag and does not
  navigate.
