# Take Order Flow Specification (Mostro Mobile v1)

> Especificación del flujo de toma de orden en v1, basada en el código real de Flutter/Dart.

## Alcance

Este documento cubre:

- Rutas `/take_sell/:orderId` y `/take_buy/:orderId`
- Pantalla `TakeOrderScreen`
- Navegación desde Home (`OrderListItem`) hasta la ejecución de `take`
- Acciones de protocolo enviadas a mostrod (`take-sell`, `take-buy`)
- Transiciones de estado asociadas al take
- Navegación posterior a la confirmación del take
- Manejo de errores y timeouts

---

## Archivos fuente analizados

### Navegación y rutas
- `lib/features/home/widgets/order_list_item.dart`
- `lib/core/app_routes.dart`
- `lib/services/deep_link_service.dart`

### Pantallas take/confirmación
- `lib/features/order/screens/take_order_screen.dart`
- `lib/features/order/screens/order_confirmation_screen.dart`

### Notifiers, estado y protocolo
- `lib/features/order/notfiers/order_notifier.dart`
- `lib/features/order/notfiers/abstract_mostro_notifier.dart`
- `lib/features/order/models/order_state.dart`
- `lib/features/order/providers/order_notifier_provider.dart`
- `lib/services/mostro_service.dart`
- `lib/data/models/enums/action.dart`
- `lib/data/models/enums/order_type.dart`
- `lib/data/models/enums/cant_do_reason.dart`

---

## 1) Entry points: cómo se llega a TakeOrderScreen

## Desde HomeScreen (tap en order card)

En `lib/features/home/widgets/order_list_item.dart`, `InkWell.onTap` decide la ruta según `order.orderType`:

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

Comportamiento real:

- Si ya existe sesión local para esa orden, NO abre take screen; abre `trade_detail`.
- Si no existe sesión:
  - `OrderType.buy` → `/take_buy/:orderId`
  - `OrderType.sell` → `/take_sell/:orderId`

## Desde router

En `lib/core/app_routes.dart`:

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

## Desde deep link

En `lib/services/deep_link_service.dart`, `getNavigationRoute()` también enruta a take:

```dart
switch (orderInfo.orderType) {
  case OrderType.sell:
    return '/take_sell/${orderInfo.orderId}';
  case OrderType.buy:
    return '/take_buy/${orderInfo.orderId}';
}
```

---

## 2) Pantalla TakeOrderScreen

Archivo: `lib/features/order/screens/take_order_screen.dart`

`TakeOrderScreen` es `ConsumerStatefulWidget` y recibe:

- `orderId`
- `orderType` (`OrderType.sell` o `OrderType.buy`)

Consulta orden pública con:

```dart
final order = ref.watch(eventProvider(widget.orderId));
```

### UI que muestra

La pantalla renderiza:

1. Monto y tipo de orden (`_buildSellerAmount`)
2. Métodos de pago (`_buildPaymentMethod`)
3. Fecha creación (`_buildCreatedOn`)
4. Order ID (`_buildOrderId`)
5. Reputación del creador (`_buildCreatorReputation`)
6. Countdown con `expiresAt` (`_CountdownWidget`)
7. Botones: `Close` + botón principal (`Buy` o `Sell`)

### Campos/formulario en take flow

No hay formulario visible persistente para take.

Sí existen `TextEditingController` internos:

- `_fiatAmountController`: se usa en diálogo para órdenes por rango
- `_lndAddressController`: se intenta leer al enviar `takeSell`, pero **no hay widget de input asociado en esta pantalla**

Implicación actual del código:

- En take normal (no rango), se envía `amount` opcional (puede ser `null`).
- En take de orden por rango, se obliga a ingresar monto dentro de `[min, max]`.
- Lightning address en take no se captura desde UI en esta pantalla (queda `null` salvo que se setee programáticamente).

---

## 3) Confirmación de take y envío al protocolo

## Botón principal y modo submit

En `_buildActionButtons`, al pulsar botón principal:

- Activa `_isSubmitting = true`
- Si orden es de rango (`maximum != null && minimum != maximum`), abre `AlertDialog` para monto
- Valida:
  - número válido
  - dentro del rango
- Si se cancela el diálogo sin monto, resetea `_isSubmitting = false`

Envío real:

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

## Creación de sesión y timeout anti-orphan

En `lib/features/order/notfiers/order_notifier.dart`:

- `takeSellOrder(...)`:
  - crea sesión con `role: Role.buyer`
  - inicia timer 10s (`startSessionTimeoutCleanup(orderId, ref)`)
  - llama `mostroService.takeSellOrder(...)`

- `takeBuyOrder(...)`:
  - crea sesión con `role: Role.seller`
  - inicia timer 10s
  - llama `mostroService.takeBuyOrder(...)`

Si mostrod no responde en 10s (`AbstractMostroNotifier`):

- elimina sesión
- muestra notificación `sessionTimeoutMessage`
- navega a `/`

---

## 4) Mensajes de protocolo enviados (mostrod)

Archivo: `lib/services/mostro_service.dart`

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

`publishOrder(...)` envuelve el mensaje con clave de sesión (`tradeKey`) y lo publica al pubkey de Mostro.

---

## 5) Transiciones de estado después de tomar orden

Estado local: `lib/features/order/models/order_state.dart`.

Mapeo explícito en `_getStatusFromAction(...)`:

```dart
case Action.takeBuy:
  return Status.waitingBuyerInvoice;

case Action.takeSell:
  return Status.waitingPayment;
```

Además, el estado termina convergiendo por eventos de mostrod:

- `waiting-seller-to-pay` → `waiting-payment`
- `waiting-buyer-invoice` → `waiting-buyer-invoice`
- `pay-invoice` → `waiting-payment`
- `hold-invoice-payment-accepted` / `buyer-took-order` / `buyer-invoice-accepted` → `active`

### Flujo conceptual esperado en pending (según acciones take)

```text
pending --take-sell--> waiting-buyer-invoice
pending --take-buy--> waiting-payment
```

### Flujo operativo en app (post-take)

La navegación/estado final inmediata depende del primer mensaje que llegue desde mostrod (`pay-invoice`, `waiting-buyer-invoice`, `buyer-took-order`, etc.), no de una pantalla de “order confirmed”.

---

## 6) Navegación posterior al take (confirmación)

La confirmación del take NO usa `OrderConfirmationScreen`.

`OrderConfirmationScreen` (`/order_confirmed/:orderId`) está conectada al flujo de creación (`new-order`), no al take.

En take flow, `AbstractMostroNotifier.handleEvent(...)` navega según acción entrante:

- `Action.payInvoice` + payload `PaymentRequest` → `/pay_invoice/:orderId`
- `Action.addInvoice` → `/add_invoice/:orderId` (o con `?lnAddress=...` si hay default lightning address)
- `Action.buyerTookOrder` → `/trade_detail/:orderId`
- `Action.waitingSellerToPay` o `Action.waitingBuyerInvoice` (cuando aplica) → `/trade_detail/:orderId`
- `Action.fiatSentOk`, `Action.released`, `Action.purchaseCompleted`, `Action.adminSettled`, etc. → `/trade_detail/:orderId`

---

## 7) Manejo de errores en take flow

## Errores de validación local (antes de enviar)

- Monto no numérico en diálogo de rango
- Monto fuera de rango min/max
- Cierre del diálogo sin confirmar (resetea loading)

## Respuesta `cant-do` desde mostrod

`TakeOrderScreen` escucha `mostroMessageStreamProvider(orderId)` y, cuando llega `Action.cantDo`, resetea `_isSubmitting = false`.

Además, `AbstractMostroNotifier` maneja efectos secundarios:

- Si razón `pending_order_exists` → borra sesión del orderId
- Si razón `out_of_range_sats_amount` y hay requestId → cleanup de sesión por request

Los textos visibles al usuario se resuelven desde `NotificationListenerWidget` + `CantDoNotificationMapper`.

## Timeout sin respuesta de mostrod

A los 10 segundos tras enviar take:

- cleanup de sesión
- notificación temporal (`sessionTimeoutMessage`)
- navegación a home (`/`)

---

## 8) Diferencias por ruta (`/take_sell` vs `/take_buy`)

| Ruta | `orderType` en pantalla | Botón principal | Método invocado | Acción protocolo enviada |
|------|--------------------------|-----------------|-----------------|---------------------------|
| `/take_sell/:orderId` | `OrderType.sell` | `Buy` | `orderNotifier.takeSellOrder(...)` | `take-sell` |
| `/take_buy/:orderId` | `OrderType.buy` | `Sell` | `orderNotifier.takeBuyOrder(...)` | `take-buy` |

---

## 9) Diagrama de flujo end-to-end

```text
HomeScreen (OrderListItem.onTap)
  ├─ si existe sesión local -> /trade_detail/:orderId
  └─ si no existe sesión
       ├─ orderType.sell -> /take_sell/:orderId
       └─ orderType.buy  -> /take_buy/:orderId

TakeOrderScreen
  ├─ usuario pulsa botón principal
  ├─ (si rango) diálogo de monto + validación
  ├─ crea sesión + timer 10s
  └─ publica MostroMessage(action: take-sell|take-buy)

Respuesta mostrod
  ├─ cant-do -> reset loading + notificación
  ├─ pay-invoice -> /pay_invoice/:orderId
  ├─ add-invoice -> /add_invoice/:orderId
  └─ buyer-took-order / waiting-* -> /trade_detail/:orderId

Si no hay respuesta en 10s
  -> cleanup sesión + notificación timeout + /
```

---

## 10) Referencias cruzadas

- Home: `.specify/v1-reference/HOME_SCREEN.md`
- Order book: `.specify/v1-reference/ORDER_BOOK.md`
- Rutas: `.specify/v1-reference/NAVIGATION_ROUTES.md`
- Estados: `.specify/v1-reference/ORDER_STATES.md`
- Protocolo: `.specify/PROTOCOL.md`
