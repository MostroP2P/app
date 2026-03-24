# Order Creation (`/add_order`)

> Functional and technical specification for order creation in Mostro Mobile v1 (Flutter/Dart), based on real code.

## Source Files Analyzed

- `lib/features/order/screens/add_order_screen.dart`
- `lib/features/order/notifiers/add_order_notifier.dart`
- `lib/features/order/providers/order_notifier_provider.dart`
- `lib/features/order/models/order_state.dart`
- `lib/features/order/widgets/*` (form sections and buttons)
- `lib/data/models/order.dart`
- `lib/data/models/mostro_message.dart`
- `lib/services/mostro_service.dart`
- `lib/data/repositories/open_orders_repository.dart`
- `lib/shared/providers/order_repository_provider.dart`
- `lib/features/mostro/mostro_instance.dart`
- `lib/core/app_routes.dart`
- `lib/shared/widgets/add_order_button.dart`
- `lib/core/mostro_fsm.dart`

> Repository consistency note: in this version there are no `create_order_provider.dart`, `order_providers.dart`, `order_repository.dart`, `order_events_provider.dart`, `user_orders_provider.dart` or `create_order_model.dart` at the requested paths. The live logic is distributed across `AddOrderScreen`, `AddOrderNotifier`, `MostroService`, `order_notifier_provider.dart` and `open_orders_repository.dart`.

---

## 1) Route and Entry Point

### Route
- Registered route: `/add_order`
- Router: `lib/core/app_routes.dart`

```dart
GoRoute(
  path: '/add_order',
  pageBuilder: (context, state) => buildPageWithDefaultTransition<void>(
    context: context,
    state: state,
    child: AddOrderScreen(),
  ),
),
```

### Entry from Home (FAB)
- Widget: `lib/shared/widgets/add_order_button.dart`
- Navigation:
  - Buy: `context.push('/add_order', extra: {'orderType': 'buy'})`
  - Sell: `context.push('/add_order', extra: {'orderType': 'sell'})`

`AddOrderScreen` consumes `state.extra['orderType']` in `initState` to preselect type (`buy` or `sell`). If no extra is provided, defaults to `sell`.

---

## 2) `AddOrderScreen` Screen: Local State and Bootstrap

File: `lib/features/order/screens/add_order_screen.dart`

Main local state:
- `_orderType`: `OrderType.sell` by default
- `_marketRate`: `true` by default
- `_premiumValue`: `0.0`
- `_minFiatAmount` / `_maxFiatAmount`
- `_selectedPaymentMethods`
- `_validationError` (amount/range errors)
- `_currentRequestId` (reactive button state control)

Initialization (`initState`):
1. Reads `extra.orderType`.
2. Resets `selectedFiatCodeProvider` to user default (`settings.defaultFiatCode`).
3. Preloads `defaultLightningAddress` if it exists (only used later for `buy` orders).

---

## 3) Form Structure and Fields

## UI Supported Fields

1. **Order type**
   - Determined by FAB menu (buy/sell).
2. **Fiat currency**
   - `CurrencySection` + `selectedFiatCodeProvider`.
3. **Fiat amount**
   - `AmountSection` with simple or range mode (`min`/`max`).
4. **Payment methods**
   - Multi-select list + custom free text method.
5. **Price type**
   - `market` (with premium/discount) or `fixed` (amount in sats).
6. **Premium/discount**
   - `PremiumSection` (slider + input), integer clamped `[-100, 100]`.
7. **Lightning address (optional)**
   - Visible only when `orderType == buy`.

## Expiration
There is no manual expiration input in `AddOrderScreen`. Effective expiration depends on Mostro node configuration (`kind 38385`), accessible via `mostroInstance.expirationHours` / `expirationSeconds`.

---

## 4) Validation Rules (Real Code)

### 4.1 Submit Enablement Validations
`_getSubmitCallback()` returns `null` (button disabled) if:
- `_validationError` exists
- Minimum amount is missing (`_minFiatAmount == null`)
- `fiatCode` is missing
- No payment method (neither selected nor custom)

### 4.2 Fiat Range Validation
In `_validateAllAmounts()`:
- If `min` and `max` exist, requires `max > min`

### 4.3 Sats Limits Validation (Client Side)
`_validateSatsRange(double fiatAmount)`:
1. Requires `selectedFiatCode`.
2. Requires `exchangeRateProvider(fiatCode)` with a value.
3. Requires loaded `mostroInstance`.
4. Converts fiat to sats:

```dart
int _calculateSatsFromFiat(double fiatAmount, double exchangeRate) {
  return (fiatAmount / exchangeRate * 100000000).round();
}
```

5. Compares against:
- `mostroInstance.minOrderAmount`
- `mostroInstance.maxOrderAmount`

If out of range, blocks submit and shows inline error.

### 4.4 Format Validations
- Numeric inputs use `FilteringTextInputFormatter.digitsOnly`.
- For fixed price, `satsAmount` must be a positive integer from numeric text.

### 4.5 Custom Method Sanitization
Before sending:
- Replaces problematic characters `[,"\\\[\]{}]` with spaces
- Collapses multiple spaces
- `trim()`

---

## 5) Building the `Order` Model

When submitting (`_submitOrder()`), an `Order` (`lib/data/models/order.dart`) is built with this logic:

```dart
final fiatAmount = _maxFiatAmount != null ? 0 : _minFiatAmount;
final minAmount = _maxFiatAmount != null ? _minFiatAmount : null;
final maxAmount = _maxFiatAmount;

final order = Order(
  kind: _orderType,
  fiatCode: fiatCode,
  fiatAmount: fiatAmount!,
  minAmount: minAmount,
  maxAmount: maxAmount,
  paymentMethod: paymentMethods.join(','),
  amount: _marketRate ? 0 : satsAmount,
  premium: _marketRate ? _premiumValue.toInt() : 0,
  buyerInvoice: buyerInvoice,
);
```

Implications:
- **Simple order**: uses fixed `fiatAmount` and null `min/max`.
- **Range order**: uses `fiatAmount = 0` and fills `minAmount/maxAmount`.
- **Market price**: `amount = 0`, `premium != 0` possible.
- **Fixed price**: `amount = satsAmount`, `premium = 0`.

---

## 6) Creation Flow via Nostr (Request/Response)

## 6.1 Creation Notifier
Provider: `addOrderNotifierProvider(tempOrderId)` in `order_notifier_provider.dart`.
Implementation: `AddOrderNotifier`.

- Generates `requestId` from UUID + timestamp (`_requestIdFromOrderId`).
- Creates temporary session with `sessionNotifier.newSession(requestId: ..., role: ...)`.
- Starts 10s cleanup timer to avoid orphan sessions.
- Publishes `MostroMessage(action: Action.newOrder, requestId, payload: order)`.

## 6.2 Message Publishing
`MostroService.publishOrder()`:
- Gets session by `requestId`.
- Reads PoW from `mostroInstance?.pow ?? 0`.
- Wraps with `MostroMessage.wrap(...)` (NIP-59 gift wrap).
- Publishes event with `nostrService.publishEvent(event)`.

## 6.3 Confirmation
`AddOrderNotifier.subscribe()` listens to `addOrderEventsProvider(requestId)`:
- If `Action.newOrder` arrives with `Order` payload, executes `_confirmOrder(...)`:
  1. cancels timer
  2. `session.orderId = message.id`
  3. persists session
  4. activates `orderNotifierProvider(message.id!).subscribe()`
  5. navigates to `/order_confirmed/{orderId}`

## 6.4 `cant-do` Errors
- `out_of_range_sats_amount`:
  - resets state and generates new `requestId` for retry
- `invalid_fiat_currency`:
  - deletes temporary session and navigates to `/`

---

## 7) State Machine and Implied Actions

### Initial Local State
`OrderState(action: Action.newOrder, status: Status.pending)`.

### Mapping in `order_state.dart` Relevant to Creation
- `Action.newOrder` → uses `payloadStatus` (normally `pending`)
- `Action.takeBuy` → `waitingBuyerInvoice`
- `Action.takeSell` → `waitingPayment`
- `Action.waitingSellerToPay` / `payInvoice` → `waitingPayment`
- `Action.waitingBuyerInvoice` / `addInvoice` → `waitingBuyerInvoice` (with exception when in `paymentFailed`)

### `mostro_fsm.dart`
FSM helper (`MostroFSM`) exists but the operational flow in v1 for UI and real runtime transition centers on `OrderState.updateWith()` + Mostro messages.

---

## 8) What Happens After Creating the Order?

1. User arrives at `/order_confirmed/:orderId` (`OrderConfirmationScreen`).
2. When returning to Home, the order appears in Order Book when:
   - the public event (`kind 38383`) is in `Status.pending`
   - the type matches the selected tab (`buy/sell`)
3. The public listing comes from `orderEventsProvider` (`order_repository_provider.dart`), fed by `OpenOrdersRepository.eventsStream`.
4. Home filters (`currency`, `payment methods`, `rating`, `premium`) are applied on that stream.

---

## 9) Important Differences: BUY vs SELL When Creating

- **BUY**
  - Can include `buyerInvoice` (optional lightning address from creation).
  - Initial session role: `Role.buyer`.
- **SELL**
  - Does not show lightning address field in creation UI.
  - Initial session role: `Role.seller`.

---

## 10) Cross References

- Home and FAB: [HOME_SCREEN.md](./HOME_SCREEN.md)
- Routes and navigation: [NAVIGATION_ROUTES.md](./NAVIGATION_ROUTES.md)
- States and transitions: [ORDER_STATES.md](./ORDER_STATES.md)
- Relation to taking orders (counterpart flow): [TAKE_ORDER.md](./TAKE_ORDER.md)
- Order book: [ORDER_BOOK.md](./ORDER_BOOK.md)
