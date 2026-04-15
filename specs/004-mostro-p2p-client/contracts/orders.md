# Contract: Orders API

**Module**: `rust/src/api/orders.rs`

Order browsing, creation, and lifecycle management. Orders are fetched from
Mostro daemon via Kind 38383 Nostr events and cached locally.

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

**Side effects**: Publishes NIP-59 Gift Wrapped message to Mostro daemon.

**Errors**: `NoIdentity`, `Offline` (queued), `ProtocolError`.

---

### take_order(order_id: String) → TradeInfo
Take an existing order, starting a trade.

**Preconditions**: No active trade in progress.

**Side effects**: Sends TakeBuy/TakeSell action to Mostro daemon via
NIP-59. Creates local Trade record.

**Errors**: `NoIdentity`, `ActiveTradeExists`, `OrderAlreadyTaken`,
`OrderNotFound`, `Offline` (queued).

---

### cancel_order(order_id: String) → ()
Cancel own untaken order.

**Preconditions**: Order MUST be owned by current user. Order status
MUST be `Pending`.

**Errors**: `NotMyOrder`, `OrderNotCancelable`, `ProtocolError`.

---

### submit_buyer_invoice(trade_id: String, bolt11: String) → ()
For sell orders: buyer submits their Lightning invoice for receiving
payment upon trade completion.

**Validation**: `bolt11` MUST be a valid Lightning invoice.

**Side effects**: Sends `AddInvoice` action to Mostro daemon.

**Errors**: `TradeNotFound`, `InvalidInvoice`, `NotBuyer`,
`WrongTradeState`.

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
call — it arrives as a NIP-59 gift-wrap (Kind 1059) from mostrod. This
section documents the full chain so Flutter providers and screens know
what to listen to. Reference: <https://mostro.network/protocol/seller_pay_hold_invoice.html>.

### Inbound gift-wrap actions consumed by `process_gift_wrap_rumor`

| Action                             | Payload variant                                     | Effect on the seller's trade row                                                 |
|------------------------------------|-----------------------------------------------------|----------------------------------------------------------------------------------|
| `WaitingBuyerInvoice`              | (status sync)                                       | `status → WaitingBuyerInvoice`                                                   |
| `PayInvoice`                       | `Payload::PaymentRequest(small_order, bolt11, amt)` | `hold_invoice ← bolt11`, `amount_sats ← amt ?? small_order.amount`, `status → WaitingPayment` |
| `BuyerTookOrder` / `HoldInvoicePaymentAccepted` | `SmallOrder` with `status = active`      | `status → Active` (routed through `map_core_status` kebab-case)                  |
| `FiatSentOk`                       | (status sync)                                       | `status → FiatSent`                                                              |
| `HoldInvoicePaymentSettled` / `Released` / `PurchaseCompleted` | (status sync)             | `status → SettledHoldInvoice`                                                    |
| `CooperativeCancelAccepted`        | (status sync)                                       | `status → CooperativelyCanceled`                                                 |
| `AdminSettled` / `AdminCanceled`   | (status sync)                                       | `status → SettledByAdmin` / `CanceledByAdmin`                                    |

`process_gift_wrap_rumor` MUST update **both** the in-memory order book
(`order_book().update_order_status`) **and** the persisted trade row
(`db.update_trade_fields`) on every status transition, otherwise UI
screens reading from the DB (e.g. `tradeInfoStreamProvider`) will miss
transitions that only affected in-memory state.

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
