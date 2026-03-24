# Order Creation (`/add_order`)

> Especificación funcional y técnica de creación de órdenes en Mostro Mobile v1 (Flutter/Dart), basada en el código real.

## Archivos fuente analizados

- `lib/features/order/screens/add_order_screen.dart`
- `lib/features/order/notfiers/add_order_notifier.dart`
- `lib/features/order/providers/order_notifier_provider.dart`
- `lib/features/order/models/order_state.dart`
- `lib/features/order/widgets/*` (secciones de formulario y botones)
- `lib/data/models/order.dart`
- `lib/data/models/mostro_message.dart`
- `lib/services/mostro_service.dart`
- `lib/data/repositories/open_orders_repository.dart`
- `lib/shared/providers/order_repository_provider.dart`
- `lib/features/mostro/mostro_instance.dart`
- `lib/core/app_routes.dart`
- `lib/shared/widgets/add_order_button.dart`
- `lib/core/mostro_fsm.dart`

> Nota de consistencia en el repositorio: en esta versión no existen `create_order_provider.dart`, `order_providers.dart`, `order_repository.dart`, `order_events_provider.dart`, `user_orders_provider.dart` ni `create_order_model.dart` en las rutas solicitadas. La lógica viva está distribuida en `AddOrderScreen`, `AddOrderNotifier`, `MostroService`, `order_notifier_provider.dart` y `open_orders_repository.dart`.

---

## 1) Ruta y punto de entrada

### Ruta
- Ruta registrada: `/add_order`
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

### Entrada desde Home (FAB)
- Widget: `lib/shared/widgets/add_order_button.dart`
- Navegación:
  - Compra: `context.push('/add_order', extra: {'orderType': 'buy'})`
  - Venta: `context.push('/add_order', extra: {'orderType': 'sell'})`

`AddOrderScreen` consume `state.extra['orderType']` en `initState` para preseleccionar tipo (`buy` o `sell`). Si no viene extra, usa `sell` por defecto.

---

## 2) Pantalla `AddOrderScreen`: estado local y bootstrap

Archivo: `lib/features/order/screens/add_order_screen.dart`

Estado local principal:
- `_orderType`: `OrderType.sell` por defecto
- `_marketRate`: `true` por defecto
- `_premiumValue`: `0.0`
- `_minFiatAmount` / `_maxFiatAmount`
- `_selectedPaymentMethods`
- `_validationError` (errores de monto/rango)
- `_currentRequestId` (control de estado reactivo del botón)

Inicialización (`initState`):
1. Lee `extra.orderType`.
2. Resetea `selectedFiatCodeProvider` al default del usuario (`settings.defaultFiatCode`).
3. Precarga `defaultLightningAddress` si existe (solo se usa luego para órdenes `buy`).

---

## 3) Estructura del formulario y campos

## Campos soportados por UI

1. **Tipo de orden**
   - Determinado por el menú FAB (buy/sell).
2. **Moneda fiat**
   - `CurrencySection` + `selectedFiatCodeProvider`.
3. **Monto fiat**
   - `AmountSection` con modo simple o rango (`min`/`max`).
4. **Métodos de pago**
   - Lista multiselección + método custom de texto libre.
5. **Tipo de precio**
   - `market` (con premium/descuento) o `fixed` (monto en sats).
6. **Premium/discount**
   - `PremiumSection` (slider + input), entero clamp `[-100, 100]`.
7. **Lightning address (opcional)**
   - Visible solo cuando `orderType == buy`.

## Expiración
No hay input manual de expiración en `AddOrderScreen`. La expiración efectiva depende de la configuración del nodo Mostro (`kind 38385`), accesible por `mostroInstance.expirationHours` / `expirationSeconds`.

---

## 4) Reglas de validación (código real)

### 4.1 Validaciones de habilitación de submit
`_getSubmitCallback()` devuelve `null` (botón deshabilitado) si:
- Existe `_validationError`
- Falta monto mínimo (`_minFiatAmount == null`)
- Falta `fiatCode`
- No hay método de pago (ni seleccionado ni custom)

### 4.2 Validación de rango fiat
En `_validateAllAmounts()`:
- Si hay `min` y `max`, exige `max > min`

### 4.3 Validación de límites en sats (lado cliente)
`_validateSatsRange(double fiatAmount)`:
1. Requiere `selectedFiatCode`.
2. Requiere `exchangeRateProvider(fiatCode)` con valor.
3. Requiere `mostroInstance` cargada.
4. Convierte fiat a sats:

```dart
int _calculateSatsFromFiat(double fiatAmount, double exchangeRate) {
  return (fiatAmount / exchangeRate * 100000000).round();
}
```

5. Compara contra:
- `mostroInstance.minOrderAmount`
- `mostroInstance.maxOrderAmount`

Si sale del rango, bloquea submit y muestra error inline.

### 4.4 Validaciones de formato
- Inputs numéricos usan `FilteringTextInputFormatter.digitsOnly`.
- En precio fijo, `satsAmount` debe ser entero positivo de texto numérico.

### 4.5 Sanitización de método custom
Antes de enviar:
- Reemplaza caracteres problemáticos `[,"\\\[\]{}]` por espacios
- Colapsa espacios múltiples
- `trim()`

---

## 5) Construcción del modelo `Order`

Al enviar (`_submitOrder()`), se construye `Order` (`lib/data/models/order.dart`) con esta lógica:

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

Implicaciones:
- **Orden simple**: usa `fiatAmount` fijo y `min/max` nulos.
- **Orden por rango**: usa `fiatAmount = 0` y llena `minAmount/maxAmount`.
- **Market price**: `amount = 0`, `premium != 0` posible.
- **Fixed price**: `amount = satsAmount`, `premium = 0`.

---

## 6) Flujo de creación por Nostr (request/response)

## 6.1 Notifier de creación
Provider: `addOrderNotifierProvider(tempOrderId)` en `order_notifier_provider.dart`.
Implementación: `AddOrderNotifier`.

- Genera `requestId` desde UUID + timestamp (`_requestIdFromOrderId`).
- Crea sesión temporal con `sessionNotifier.newSession(requestId: ..., role: ...)`.
- Inicia timer de limpieza de 10s para evitar sesiones huérfanas.
- Publica `MostroMessage(action: Action.newOrder, requestId, payload: order)`.

## 6.2 Publicación del mensaje
`MostroService.publishOrder()`:
- Obtiene sesión por `requestId`.
- Lee PoW de `mostroInstance?.pow ?? 0`.
- Empaqueta con `MostroMessage.wrap(...)` (NIP-59 gift wrap).
- Publica evento con `nostrService.publishEvent(event)`.

## 6.3 Confirmación
`AddOrderNotifier.subscribe()` escucha `addOrderEventsProvider(requestId)`:
- Si llega `Action.newOrder` con payload `Order`, ejecuta `_confirmOrder(...)`:
  1. cancela timer
  2. `session.orderId = message.id`
  3. persiste sesión
  4. activa `orderNotifierProvider(message.id!).subscribe()`
  5. navega a `/order_confirmed/{orderId}`

## 6.4 Errores `cant-do`
- `out_of_range_sats_amount`:
  - resetea estado y genera nuevo `requestId` para reintento
- `invalid_fiat_currency`:
  - elimina sesión temporal y navega a `/`

---

## 7) Máquina de estados y acciones implicadas

### Estado inicial local
`OrderState(action: Action.newOrder, status: Status.pending)`.

### Mapeo en `order_state.dart` relevante a creación
- `Action.newOrder` → usa `payloadStatus` (normalmente `pending`)
- `Action.takeBuy` → `waitingBuyerInvoice`
- `Action.takeSell` → `waitingPayment`
- `Action.waitingSellerToPay` / `payInvoice` → `waitingPayment`
- `Action.waitingBuyerInvoice` / `addInvoice` → `waitingBuyerInvoice` (con excepción cuando está en `paymentFailed`)

### `mostro_fsm.dart`
Existe helper FSM (`MostroFSM`) pero el flujo operativo en v1 para UI y transición real en runtime se centra en `OrderState.updateWith()` + mensajes de Mostro.

---

## 8) ¿Qué pasa después de crear la orden?

1. Usuario llega a `/order_confirmed/:orderId` (`OrderConfirmationScreen`).
2. Al volver a Home, la orden aparece en Order Book cuando:
   - el evento público (`kind 38383`) está en `Status.pending`
   - el tipo coincide con el tab seleccionado (`buy/sell`)
3. El listado público proviene de `orderEventsProvider` (`order_repository_provider.dart`), alimentado por `OpenOrdersRepository.eventsStream`.
4. Filtros de Home (`currency`, `payment methods`, `rating`, `premium`) se aplican sobre ese stream.

---

## 9) Diferencias importantes: BUY vs SELL al crear

- **BUY**
  - Puede incluir `buyerInvoice` (lightning address opcional desde la creación).
  - Rol de sesión inicial: `Role.buyer`.
- **SELL**
  - No muestra campo lightning address en la UI de creación.
  - Rol de sesión inicial: `Role.seller`.

---

## 10) Referencias cruzadas

- Home y FAB: `.specify/v1-reference/HOME_SCREEN.md`
- Rutas y navegación: `.specify/v1-reference/NAVIGATION_ROUTES.md`
- Estados y transiciones: `.specify/v1-reference/ORDER_STATES.md`
- Relación con tomar órdenes (counterpart flow): `.specify/v1-reference/TAKE_ORDER.md` *(referencia conceptual; el archivo puede no estar presente en esta rama)*
- Libro de órdenes: `.specify/v1-reference/ORDER_BOOK.md`

