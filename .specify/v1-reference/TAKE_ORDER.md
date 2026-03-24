# Take Order Flow Specification (Mostro Mobile v1)

> Specification of the order taking flow in v1, based on real Flutter/Dart code.

## Scope

This document covers:

- Routes `/take_sell/:orderId` and `/take_buy/:orderId`
- `TakeOrderScreen` screen
- Navigation from Home (`OrderListItem`) to `take` execution
- Protocol actions sent to mostrod (`take-sell`, `take-buy`)
- State transitions associated with take
- Post-take confirmation navigation
- Error and timeout handling

---

## Source Files Analyzed

### Navigation and routes
- `lib/features/home/widgets/order_list_item.dart`
- `lib/core/app_routes.dart`
- `lib/services/deep_link_service.dart`

### Take/confirmation screens
- `lib/features/order/screens/take_order_screen.dart`
- `lib/features/order/screens/order_confirmation_screen.dart`

### Notifiers, state and protocol
- `lib/features/order/notifiers/order_notifier.dart`
- `lib/features/order/notifiers/abstract_mostro_notifier.dart`
- `lib/features/order/models/order_state.dart`
- `lib/features/order/providers/order_notifier_provider.dart`
- `lib/services/mostro_service.dart`
- `lib/data/models/enums/action.dart`
- `lib/data/models/enums/order_type.dart`
- `lib/data/models/enums/cant_do_reason.dart`

---

## 1) Entry Points: How to Reach TakeOrderScreen

## From HomeScreen (tap on order card)

In `lib/features/home/widgets/order_list_item.dart`, `InkWell.onTap` decides the route based on `order.orderType`:

```dart
onTap: () {
  final sessions = ref.watch(sessionNotifierProvider);
  final session = sessions.firstWhereOrNull((s) => s.orderId == order.orderId);
  if (session != null && session.role != null) {
    context.push('/trade_detail/${session.orderId}');
    return;
  }
  order.orderType == OrderType.buy
      ? context.push('/take_buy/${order.orderId}')
      : context.push('/take_sell/${order.orderId}');
},
```

Actual behavior:

- If a local session already exists for that order, does NOT open take screen; opens `trade_detail`.
- If no session exists:
  - `OrderType.buy` → `/take_buy/:orderId`
  - `OrderType.sell` → `/take_sell/:orderId`

## From router

In `lib/core/app_routes.dart`:

```dart
GoRoute(
  path: '/take_sell/:orderId',
  builder: (context, state) => TakeOrderScreen(
    orderId: state.pathParameters['orderId']!,
    orderType: OrderType.sell,
  ),
),
GoRoute(
  path: '/take_buy/:orderId',
  builder: (context, state) => TakeOrderScreen(
    orderId: state.pathParameters['orderId']!,
    orderType: OrderType.buy,
  ),
),
```

## From deep link

In `lib/services/deep_link_service.dart`, `getNavigationRoute()` also routes to take:

```dart
switch (orderInfo.orderType) {
  case OrderType.sell:
    return '/take_sell/${orderInfo.orderId}';
  case OrderType.buy:
    return '/take_buy/${orderInfo.orderId}';
}
```

---

## 2) TakeOrderScreen Screen

File: `lib/features/order/screens/take_order_screen.dart`

`TakeOrderScreen` is a `ConsumerStatefulWidget` and receives:

- `orderId`
- `orderType` (`OrderType.sell` or `OrderType.buy`)

Queries public order with:

```dart
final order = ref.watch(eventProvider(widget.orderId));
```

### UI displayed

The screen renders:

1. Amount and order type (`_buildSellerAmount`)
2. Payment methods (`_buildPaymentMethod`)
3. Creation date (`_buildCreatedOn`)
4. Order ID (`_buildOrderId`)
5. Creator reputation (`_buildCreatorReputation`)
6. Countdown with `expiresAt` (`_CountdownWidget`)
7. Buttons: `Close` + main button (`Buy` or `Sell`)

### Fields/form in take flow

No persistent visible form for take.

Internal `TextEditingController` do exist:

- `_fiatAmountController`: used in dialog for range orders
- `_lndAddressController`: read attempt when sending `takeSell`, but **no input widget associated in this screen**

Current code implication:

- In normal take (non-range), sends optional `amount` (can be `null`).
- In range order take, forces entering amount within `[min, max]`.
- Lightning address in take is not captured from UI in this screen (stays `null` unless set programmatically).

---

## 3) Take Confirmation and Protocol Submission

## Main button and submit mode

In `_buildActionButtons`, when pressing main button:

- Activates `_isSubmitting = true`
- If range order (`maximum != null && minimum != maximum`), opens `AlertDialog` for amount
- Validates:
  - valid number
  - within range
- If dialog is cancelled without amount, resets `_isSubmitting = false`

Actual submission:

```dart
if (widget.orderType == OrderType.buy) {
  await orderDetailsNotifier.takeBuyOrder(order.orderId!, enteredAmountOrNull);
} else {
  await orderDetailsNotifier.takeSellOrder(
    order.orderId!,
    enteredAmountOrNull,
    lndAddressOrNull,
  );
}
```

## Session creation and anti-orphan timeout

In `lib/features/order/notifiers/order_notifier.dart`:

- `takeSellOrder(...)`:
  - creates session with `role: Role.buyer`
  - starts 10s timer (`startSessionTimeoutCleanup(orderId, ref)`)
  - calls `mostroService.takeSellOrder(...)`

- `takeBuyOrder(...)`:
  - creates session with `role: Role.seller`
  - starts 10s timer
  - calls `mostroService.takeBuyOrder(...)`

If mostrod doesn't respond in 10s (`AbstractMostroNotifier`):

- deletes session
- shows notification `sessionTimeoutMessage`
- navigates to `/`

---

## 4) Protocol Messages Sent (mostrod)

File: `lib/services/mostro_service.dart`

## take-buy

```dart
Future<void> takeBuyOrder(String orderId, int? amount) async {
  final amt = amount != null ? Amount(amount: amount) : null;
  await publishOrder(
    MostroMessage(action: Action.takeBuy, id: orderId, payload: amt),
  );
}
```

## take-sell

```dart
Future<void> takeSellOrder(String orderId, int? amount, String? lnAddress) async {
  final payload = lnAddress != null
      ? PaymentRequest(order: null, lnInvoice: lnAddress, amount: amount)
      : amount != null
          ? Amount(amount: amount)
          : null;

  await publishOrder(
    MostroMessage(action: Action.takeSell, id: orderId, payload: payload),
  );
}
```

`publishOrder(...)` wraps the message with session key (`tradeKey`) and publishes to Mostro pubkey.

---

## 5) State Transitions After Taking Order

Local state: `lib/features/order/models/order_state.dart`.

Explicit mapping in `_getStatusFromAction(...)`:

```dart
case Action.takeBuy:
  return Status.waitingBuyerInvoice;

case Action.takeSell:
  return Status.waitingPayment;
```

Additionally, state converges via mostrod events:

- `waiting-seller-to-pay` → `waiting-payment`
- `waiting-buyer-invoice` → `waiting-buyer-invoice`
- `pay-invoice` → `waiting-payment`
- `hold-invoice-payment-accepted` / `buyer-took-order` / `buyer-invoice-accepted` → `active`

### Expected conceptual flow from pending (based on take actions)

```text
pending --take-sell--> waiting-buyer-invoice
pending --take-buy--> waiting-payment
```

### Operational flow in app (post-take)

The immediate final navigation/state depends on the first message from mostrod (`pay-invoice`, `waiting-buyer-invoice`, `buyer-took-order`, etc.), not on an "order confirmed" screen.

---

## 6) Post-Take Navigation (Confirmation)

Take confirmation does NOT use `OrderConfirmationScreen`.

`OrderConfirmationScreen` (`/order_confirmed/:orderId`) is connected to the creation flow (`new-order`), not to take.

In take flow, `AbstractMostroNotifier.handleEvent(...)` navigates based on incoming action:

- `Action.payInvoice` + `PaymentRequest` payload → `/pay_invoice/:orderId`
- `Action.addInvoice` → `/add_invoice/:orderId` (or with `?lnAddress=...` if default lightning address exists)
- `Action.buyerTookOrder` → `/trade_detail/:orderId`
- `Action.waitingSellerToPay` or `Action.waitingBuyerInvoice` (when applicable) → `/trade_detail/:orderId`
- `Action.fiatSentOk`, `Action.released`, `Action.purchaseCompleted`, `Action.adminSettled`, etc. → `/trade_detail/:orderId`

> For the full description of what happens **after** these redirects (screens `/pay_invoice`, `/add_invoice`, `/trade_detail` plus execution buttons), see [TRADE_EXECUTION.md](./TRADE_EXECUTION.md).
>
> That document details the buyer/seller flows, reactive buttons, valid actions, and state transitions during trade execution.

---

## 7) Error Handling in Take Flow

## Local validation errors (before sending)

- Non-numeric amount in range dialog
- Amount outside min/max range
- Dialog closed without confirming (resets loading)

## `cant-do` response from mostrod

`TakeOrderScreen` listens to `mostroMessageStreamProvider(orderId)` and, when `Action.cantDo` arrives, resets `_isSubmitting = false`.

Additionally, `AbstractMostroNotifier` handles side effects:

- If reason `pending_order_exists` → deletes session for orderId
- If reason `out_of_range_sats_amount` and requestId exists → cleanup session by request

User-visible texts are resolved from `NotificationListenerWidget` + `CantDoNotificationMapper`.

## Timeout without mostrod response

At 10 seconds after sending take:

- session cleanup
- temporary notification (`sessionTimeoutMessage`)
- navigation to home (`/`)

---

## 8) Differences by Route (`/take_sell` vs `/take_buy`)

| Route | `orderType` in screen | Main button | Method invoked | Protocol action sent |
|-------|----------------------|-------------|----------------|----------------------|
| `/take_sell/:orderId` | `OrderType.sell` | `Buy` | `orderNotifier.takeSellOrder(...)` | `take-sell` |
| `/take_buy/:orderId` | `OrderType.buy` | `Sell` | `orderNotifier.takeBuyOrder(...)` | `take-buy` |

---

## 9) End-to-End Flow Diagram

```text
HomeScreen (OrderListItem.onTap)
  ├─ if local session exists -> /trade_detail/:orderId
  └─ if no session exists
       ├─ orderType.sell -> /take_sell/:orderId
       └─ orderType.buy  -> /take_buy/:orderId

TakeOrderScreen
  ├─ user presses main button
  ├─ (if range) amount dialog + validation
  ├─ create session + 10s timer
  └─ publish MostroMessage(action: take-sell|take-buy)

mostrod response
  ├─ cant-do -> reset loading + notification
  ├─ pay-invoice -> /pay_invoice/:orderId
  ├─ add-invoice -> /add_invoice/:orderId
  └─ buyer-took-order / waiting-* -> /trade_detail/:orderId

If no response in 10s
  -> cleanup session + timeout notification + /
```

---

## 10) Cross References

- Home: [HOME_SCREEN.md](./HOME_SCREEN.md)
- Order book: [ORDER_BOOK.md](./ORDER_BOOK.md)
- Routes: [NAVIGATION_ROUTES.md](./NAVIGATION_ROUTES.md)
- States: [ORDER_STATES.md](./ORDER_STATES.md)
- Trade execution: [TRADE_EXECUTION.md](./TRADE_EXECUTION.md)
- Protocol: [../PROTOCOL.md](../PROTOCOL.md)
