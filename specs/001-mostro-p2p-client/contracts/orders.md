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
  fiat_amount: f64            # Amount in fiat
  fiat_code: String           # ISO 4217 code
  payment_method: String      # Payment method description
  premium: f64                # Price premium/discount %
  amount_sats: u64?           # Optional fixed sat amount
}
```

**Validation**:
- `fiat_amount` MUST be > 0
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
