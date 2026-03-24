# Trade Execution Specification (Mostro Mobile v1)

> Especificación de la ejecución de trades en v1: pantallas de pago/invoice, detalle de trade, lista de trades, FSM de estados, y flujo real-time de eventos.

## Alcance

Este documento cubre:

- Ruta `/pay_invoice/:orderId` — Vendedor paga hold invoice (`PayLightningInvoiceScreen`)
- Ruta `/add_invoice/:orderId` — Comprador agrega invoice LN (`AddLightningInvoiceScreen`)
- Ruta `/trade_detail/:orderId` — Detalle de trade (`TradeDetailScreen`)
- Ruta `/order_book` — Lista de trades del usuario (`TradesScreen`)
- FSM (Finite State Machine) para estados de orden (`MostroFSM`)
- Flujo de trade completo para comprador y vendedor
- Acciones de protocolo: `pay-invoice`, `add-invoice`, `fiat-sent`, `release`, `dispute`
- Transiciones de estado durante ejecución del trade
- Mecánica de hold invoice
- Actualizaciones de UI en tiempo real
- Manejo de errores y timeouts

---

## Archivos fuente analizados

### Pantallas de ejecución
- `lib/features/order/screens/pay_lightning_invoice_screen.dart` (117 líneas)
- `lib/features/order/screens/add_lightning_invoice_screen.dart` (268 líneas)
- `lib/features/trades/screens/trade_detail_screen.dart` (1103 líneas)
- `lib/features/trades/screens/trades_screen.dart` (145 líneas)

### Widgets de trades
- `lib/features/trades/widgets/mostro_message_detail_widget.dart` (324 líneas)
- `lib/features/trades/widgets/status_filter_widget.dart` (185 líneas)
- `lib/features/trades/widgets/trades_list.dart` (22 líneas)
- `lib/features/trades/widgets/trades_list_item.dart` (300 líneas)

### Widgets compartidos de pago/invoice
- `lib/shared/widgets/pay_lightning_invoice_widget.dart` (148 líneas)
- `lib/shared/widgets/nwc_payment_widget.dart` (437 líneas)
- `lib/shared/widgets/add_lightning_invoice_widget.dart` (118 líneas)
- `lib/shared/widgets/nwc_invoice_widget.dart` (365 líneas)
- `lib/shared/widgets/ln_address_confirmation_widget.dart` (126 líneas)

### FSM y estado
- `lib/core/mostro_fsm.dart` (206 líneas)
- `lib/data/models/enums/status.dart` (34 líneas)
- `lib/data/models/enums/action.dart` (69 líneas)
- `lib/features/order/models/order_state.dart` (602 líneas)

### Notifiers y protocolo
- `lib/features/order/notifiers/order_notifier.dart` (200 líneas)
- `lib/features/order/notifiers/abstract_mostro_notifier.dart` (725 líneas)
- `lib/features/order/providers/order_notifier_provider.dart` (53 líneas)
- `lib/services/mostro_service.dart` (361 líneas)

### Providers de trades
- `lib/features/trades/providers/trades_provider.dart` (83 líneas)

### Notificaciones y navegación
- `lib/features/notifications/utils/notification_data_extractor.dart` (235 líneas)
- `lib/shared/providers/navigation_notifier_provider.dart`
- `lib/shared/widgets/navigation_listener_widget.dart` (21 líneas)
- `lib/shared/widgets/notification_listener_widget.dart` (109 líneas)
- `lib/shared/widgets/mostro_reactive_button.dart` (210 líneas)

---

## 1) PayLightningInvoiceScreen — Vendedor paga hold invoice

### Ruta

```text
/pay_invoice/:orderId
```

### Archivo

`lib/features/order/screens/pay_lightning_invoice_screen.dart`

### Cuándo se navega aquí

`AbstractMostroNotifier.handleEvent()` navega automáticamente cuando recibe `Action.payInvoice` con payload `PaymentRequest`:

```dart
case Action.payInvoice:
  if (event.payload is PaymentRequest) {
    navProvider.go('/pay_invoice/${event.id!}');
  }
  ref.read(sessionNotifierProvider.notifier).saveSession(session);
  break;
```

También accesible manualmente desde `TradeDetailScreen` cuando el estado es `waitingPayment` y el rol es `seller`:

```dart
case actions.Action.payInvoice:
  if (userRole == Role.seller) {
    final hasPaymentRequest = tradeState.paymentRequest != null;
    if (hasPaymentRequest) {
      widgets.add(_buildNostrButton(
        S.of(context)!.payInvoiceButton,
        action: actions.Action.payInvoice,
        backgroundColor: AppTheme.mostroGreen,
        onPressed: () => context.push('/pay_invoice/$orderId'),
      ));
    }
  }
  break;
```

### Datos que muestra

Lee del `OrderState` vía `orderNotifierProvider(orderId)`:

- `orderState.paymentRequest?.lnInvoice` — la hold invoice BOLT11
- `orderState.order?.amount` — monto en sats
- `orderState.order?.fiatAmount` — monto fiat
- `orderState.order?.fiatCode` — código de moneda fiat

### Modos de pago

La pantalla tiene **dos modos** controlados por `_manualMode`:

1. **NWC auto-payment** (si wallet NWC está conectada y `_manualMode == false`):
   - Muestra `NwcPaymentWidget` con flujo: idle → checking balance → paying → success/failed
   - Pre-flight: verifica balance >= sats requeridos
   - On success: `context.go('/')` — Mostro actualizará el estado automáticamente vía event stream
   - On failure: muestra error con botón retry + opción "Pay manually" → `_manualMode = true`

2. **Manual payment** (fallback o si no hay NWC):
   - Muestra `PayLightningInvoiceWidget` con:
     - Texto descriptivo con sats, fiat amount, fiat code, orderId
     - QR code de la invoice (`QrImageView`)
     - Botones: Copy (clipboard) + Share (intenta `lightning:` URL, fallback a share sheet)
     - Botón Cancel (rojo): `context.go('/')` + `orderNotifier.cancelOrder()`

### Acciones de usuario

| Acción | Método | Protocolo |
|--------|--------|-----------|
| Pagar (NWC) | `nwcNotifier.payInvoice(lnInvoice)` | Pago directo vía NWC, Mostro detecta el pago |
| Pagar (manual) | Usuario paga externamente | Mostro detecta el pago de la hold invoice |
| Cancelar | `orderNotifier.cancelOrder()` | `Action.cancel` enviado a mostrod |

### Post-pago

Cuando Mostro detecta que la hold invoice fue pagada, envía `hold-invoice-payment-accepted` al comprador y `buyer-took-order` al vendedor. La app navega automáticamente a `/trade_detail/:orderId`.

---

## 2) AddLightningInvoiceScreen — Comprador agrega invoice

### Ruta

```text
/add_invoice/:orderId
/add_invoice/:orderId?lnAddress=user@domain.com
```

### Archivo

`lib/features/order/screens/add_lightning_invoice_screen.dart`

### Cuándo se navega aquí

`AbstractMostroNotifier.handleEvent()` maneja `Action.addInvoice` con lógica inteligente:

```dart
case Action.addInvoice:
  final sessionNotifier = ref.read(sessionNotifierProvider.notifier);
  sessionNotifier.saveSession(session);
  await _handleAddInvoiceWithAutoLightningAddress(event);
  break;
```

La función `_handleAddInvoiceWithAutoLightningAddress()`:

1. Si `status == paymentFailed` → navega a input manual (no usa LN address automática)
2. Si hay Lightning address configurada en settings y es válida → navega con `?lnAddress=...`
3. Si no → navega a input manual sin parámetros

También accesible desde `TradeDetailScreen` cuando el estado es `waitingBuyerInvoice` y el rol es `buyer`.

### Modos de input

La pantalla tiene **tres modos** con prioridad:

1. **LN Address confirmation** (`lnAddress != null && !_manualMode`):
   - Muestra `LnAddressConfirmationWidget` con la dirección preconfigurada
   - Botón "Confirm" → `orderNotifier.sendInvoice(orderId, lnAddress, null)`
   - Link "Enter manually" → `_manualMode = true`

2. **NWC invoice generation** (NWC conectado, no hay LN address, amount > 0):
   - Muestra `NwcInvoiceWidget` con flujo: idle → generating → generated → confirm
   - Genera invoice vía `nwcNotifier.makeInvoice(sats, description)`
   - On confirm: `orderNotifier.sendInvoice(orderId, invoice, amount)`
   - On failure: retry + fallback manual

3. **Manual input** (fallback):
   - Muestra `AddLightningInvoiceWidget` con `TextFormField` de 6 líneas
   - Submit: `orderNotifier.sendInvoice(orderId, invoice, amount)`
   - Cancel: `orderNotifier.cancelOrder()` + `context.go('/')`

### Datos reactivos

Lee la orden vía `mostroOrderStreamProvider(orderId)` que emite el último `MostroMessage` con payload `Order`.

### Protocolo enviado

```dart
// En MostroService
Future<void> sendInvoice(String orderId, String invoice, int? amount) async {
  final payload = PaymentRequest(order: null, lnInvoice: invoice, amount: amount);
  await publishOrder(
    MostroMessage(action: Action.addInvoice, id: orderId, payload: payload),
  );
}
```

---

## 3) TradeDetailScreen — Pantalla central de ejecución

### Ruta

```text
/trade_detail/:orderId
```

### Archivo

`lib/features/trades/screens/trade_detail_screen.dart` (1103 líneas)

### Cuándo se navega aquí

Es el destino principal durante la ejecución del trade. `AbstractMostroNotifier` navega aquí para múltiples acciones:

- `buyerTookOrder` → `/trade_detail/$orderId`
- `waitingSellerToPay` (taker, no maker) → `/trade_detail/$orderId`
- `waitingBuyerInvoice` (taker, no maker) → `/trade_detail/$orderId`
- `fiatSentOk` → `/trade_detail/$orderId`
- `released` → `/trade_detail/$orderId`
- `purchaseCompleted` → `/trade_detail/$orderId`
- `holdInvoicePaymentSettled` → `/trade_detail/$orderId`
- `cooperativeCancelInitiatedByPeer` → `/trade_detail/$orderId`
- `disputeInitiatedByYou/ByPeer` → `/trade_detail/$orderId`
- `adminTookDispute` → `/trade_detail/$orderId`
- `adminSettled` → `/trade_detail/$orderId`

### Estructura de la UI

```text
┌─────────────────────────────────┐
│  OrderAppBar("Order Details")   │
├─────────────────────────────────┤
│  OrderAmountCard                │ ← "You are selling/buying X sats"
│    amount, currency, priceText  │    fiat amount + currency + premium
├─────────────────────────────────┤
│  PaymentMethodCard              │ ← método de pago
├─────────────────────────────────┤
│  CreatedDateCard                │ ← fecha de creación
├─────────────────────────────────┤
│  OrderIdCard                    │ ← ID copiable
├─────────────────────────────────┤
│  MostroMessageDetail            │ ← Mensaje de Mostro (acción actual)
│    ┌─────────────────────────┐  │    con avatar + texto + status label
│    │ 🧌 [action message]    │  │
│    │ Status: Active          │  │
│    └─────────────────────────┘  │
├─────────────────────────────────┤
│  _CountdownWidget               │ ← Solo para: pending, waiting-buyer-
│    CircularCountdown             │   invoice, waiting-payment
├─────────────────────────────────┤
│  [Close] [Action Buttons...]    │ ← Botones FSM-driven
└─────────────────────────────────┘
```

### Botones de acción (FSM-driven)

Los botones se determinan por `OrderState.getActions(role)` que mapea `(role, status, action) → List<Action>`:

| Status | Rol | Última Acción | Botones disponibles |
|--------|-----|---------------|---------------------|
| `waitingPayment` | Seller | `payInvoice` | **Pay Invoice**, Cancel |
| `waitingBuyerInvoice` | Buyer | `addInvoice` | **Add Invoice**, Cancel |
| `active` | Buyer | `holdInvoicePaymentAccepted` | **Fiat Sent**, Cancel, Dispute, Contact |
| `active` | Seller | `buyerTookOrder` | Cancel, Dispute, Contact |
| `fiatSent` | Seller | `fiatSentOk` | **Release**, Cancel, Dispute, Contact |
| `fiatSent` | Buyer | `fiatSentOk` | Cancel, Dispute, Contact |
| `success` | Either | `rate`/`purchaseCompleted` | **Rate** |
| `dispute` | Seller | `disputeInitiated*` | Contact, Cancel, **Release** |
| `dispute` | Buyer | `disputeInitiated*` | Contact, Cancel |
| `cooperativelyCanceled` | Seller | `cooperativeCancel*` | Contact, Dispute, Release, Cancel |
| `paymentFailed` | Seller | `paymentFailed` | **Pay Invoice** (retry) |
| `paymentFailed` | Buyer | `addInvoice` | **Add Invoice** |

### Implementación de botones clave

**Fiat Sent** (buyer, status `active`):

```dart
case actions.Action.fiatSent:
  if (userRole == Role.buyer) {
    widgets.add(_buildNostrButton(
      S.of(context)!.fiatSentButton,
      action: actions.Action.fiatSent,
      backgroundColor: AppTheme.mostroGreen,
      onPressed: () => ref
          .read(orderNotifierProvider(orderId).notifier)
          .sendFiatSent(),
    ));
  }
  break;
```

**Release** (seller, status `fiatSent`): Muestra `AlertDialog` de confirmación antes de ejecutar:

```dart
case actions.Action.release:
  if (userRole == Role.seller) {
    // ... AlertDialog con título y confirmación
    onPressed: () {
      Navigator.of(dialogContext).pop(true);
      ref.read(orderNotifierProvider(orderId).notifier).releaseOrder();
    },
  }
  break;
```

**Dispute**: Muestra `AlertDialog` de confirmación, luego usa `disputeRepositoryProvider`:

```dart
final repository = ref.read(disputeRepositoryProvider);
final success = await repository.createDispute(orderId);
```

### Countdown timer

Solo se muestra para tres estados:
- `pending` — usa `expiresAt` del evento público (kind 38383)
- `waitingBuyerInvoice` — countdown desde timestamp del mensaje + `expirationSeconds`
- `waitingPayment` — countdown desde timestamp del mensaje + `expirationSeconds`

Implementado con `_CountdownWidget` que usa `countdownTimeProvider` (emite cada 1 segundo) y `mostroMessageHistoryProvider` para encontrar el mensaje que disparó el estado actual.

### View Dispute button

Independiente del sistema de acciones FSM. Se muestra cuando:

```dart
if ((tradeState.action == actions.Action.disputeInitiatedByYou ||
        tradeState.action == actions.Action.disputeInitiatedByPeer ||
        tradeState.action == actions.Action.adminTookDispute) &&
    tradeState.dispute?.disputeId != null)
```

Navega a `/dispute_details/:disputeId`.

---

## 4) TradesScreen — Lista "My Trades"

### Ruta

```text
/order_book
```

### Archivo

`lib/features/trades/screens/trades_screen.dart`

### Estructura

- `MostroAppBar` + `CustomDrawerOverlay`
- Header con título "My Trades" + `StatusFilterWidget` (dropdown)
- `RefreshIndicator` para pull-to-refresh
- `TradesList` → `ListView.builder` de `TradesListItem`

### Provider de datos

`filteredTradesWithOrderStateProvider` combina:
1. `orderEventsProvider` — stream de eventos públicos (kind 38383)
2. `sessionNotifierProvider` — sesiones locales del usuario
3. `statusFilterProvider` — filtro de status seleccionado
4. `orderNotifierProvider` por cada orderId — para status reactivo real

Filtra las órdenes que tienen sesión local (= trades del usuario), ordena por `expirationDate` descendente, y aplica filtro de status si hay uno seleccionado.

### StatusFilterWidget

`PopupMenuButton` con opciones: All, Pending, Waiting Payment, Waiting Invoice, Active, Fiat Sent, Success, Canceled, Settled Hold Invoice.

### TradesListItem

Cada item muestra:
- "Buying Bitcoin" / "Selling Bitcoin" según rol
- Status chip coloreado (usa `orderState.status` reactivo)
- Role chip: "Created by you" / "Taken by you"
- Premium/discount chip si != 0
- Flag + monto fiat + moneda
- Métodos de pago
- Flecha de navegación → `context.push('/trade_detail/${trade.orderId}')`

---

## 5) Finite State Machine (MostroFSM)

### Archivo

`lib/core/mostro_fsm.dart`

### Estructura

`MostroFSM` es una clase con constructor privado y mapas estáticos de transiciones:

```dart
static final Map<Status, Map<Role, Map<Action, Status>>> _transitions = { ... };
```

### API

```dart
static Status? nextStatus(Status current, Role role, Action action)
static List<Action> possibleActions(Status current, Role role)
```

### Tabla de transiciones completa (del código)

| Estado actual | Rol | Acción | Estado siguiente |
|---------------|-----|--------|------------------|
| `pending` | Buyer | `takeSell` | `waitingBuyerInvoice` |
| `pending` | Seller | `takeBuy` | `waitingPayment` |
| `pending` | Either | `cancel` | `canceled` |
| `waitingBuyerInvoice` | Buyer | `addInvoice` | `waitingPayment` |
| `waitingBuyerInvoice` | Either | `cancel` | `canceled` |
| `waitingPayment` | Seller | `payInvoice` | `active` |
| `waitingPayment` | Either | `paymentFailed` | `paymentFailed` |
| `waitingPayment` | Either | `cancel` | `canceled` |
| `paymentFailed` | Buyer | `addInvoice` | `waitingPayment` |
| `paymentFailed` | Seller | `payInvoice` | `active` |
| `paymentFailed` | Either | `cancel` | `canceled` |
| `active` | Buyer | `fiatSent` | `fiatSent` |
| `active` | Buyer | `holdInvoicePaymentAccepted` | `active` |
| `active` | Seller | `buyerTookOrder` | `active` |
| `active` | Either | `cancel` | `canceled` |
| `active` | Either | `dispute` | `dispute` |
| `fiatSent` | Buyer | `holdInvoicePaymentSettled` | `settledHoldInvoice` |
| `fiatSent` | Seller | `release` | `settledHoldInvoice` |
| `fiatSent` | Seller | `cancel` | `canceled` |
| `fiatSent` | Either | `disputeInitiatedByYou` | `dispute` |
| `success` | Either | `rate` | `success` |
| `dispute` | Admin | `adminSettle`/`adminSettled` | `settledByAdmin` |
| `dispute` | Admin | `adminCancel`/`adminCanceled` | `canceledByAdmin` |

> **Nota:** `MostroFSM` NO se usa activamente para transiciones de estado en v1. Las transiciones reales se manejan en `OrderState._getStatusFromAction()`. `MostroFSM` existe como helper/referencia.

---

## 6) OrderState — Motor de estado real

### Archivo

`lib/features/order/models/order_state.dart`

### Estructura

```dart
class OrderState {
  final Status status;
  final Action action;
  final Order? order;
  final PaymentRequest? paymentRequest;
  final CantDo? cantDo;
  final Dispute? dispute;
  final Peer? peer;
  final PaymentFailed? paymentFailed;
}
```

### Método `updateWith(MostroMessage)`

Es el motor principal de transiciones. Cada mensaje de Mostro pasa por aquí:

1. Si `action == cantDo` → preserva estado, solo actualiza `cantDo`
2. Determina nuevo status via `_getStatusFromAction(action, payloadStatus)`
3. Preserva/actualiza `PaymentRequest`, `Peer`, `Dispute`, `PaymentFailed`
4. Maneja auto-cierre de disputas cuando la orden llega a estado terminal

### Mapeo Action → Status (del código real)

```text
waitingSellerToPay, payInvoice     → waitingPayment
waitingBuyerInvoice                → waitingBuyerInvoice
addInvoice (normal)                → waitingBuyerInvoice
addInvoice (after paymentFailed)   → paymentFailed (preserva)
takeBuy                            → waitingBuyerInvoice
takeSell                           → waitingPayment
buyerTookOrder, holdInvoicePaymentAccepted, buyerInvoiceAccepted → active
fiatSent, fiatSentOk               → fiatSent
released, release                  → settledHoldInvoice
purchaseCompleted, rate, rateReceived, holdInvoicePaymentSettled → success
canceled, cancel, adminCanceled, cooperativeCancelAccepted, holdInvoicePaymentCanceled → canceled
cooperativeCancelInitiatedByYou/Peer → cooperativelyCanceled
disputeInitiatedByYou/Peer, dispute, adminTakeDispute, adminTookDispute → dispute
adminSettle, adminSettled          → settledByAdmin
paymentFailed                      → paymentFailed
```

### Método `getActions(Role)`

Retorna las acciones disponibles para un rol dado el estado actual y la última acción. Es el mapeo triple estático:

```dart
static final Map<Role, Map<Status, Map<Action, List<Action>>>> actions = { ... };
```

Este mapeo determina qué botones muestra `TradeDetailScreen`.

---

## 7) Protocolo — Mensajes enviados al servidor

### Archivo

`lib/services/mostro_service.dart`

Todos los mensajes se envían como `MostroMessage` wrapeados con NIP-59 Gift Wrap.

| Acción del usuario | Método en `OrderNotifier` | Método en `MostroService` | `Action` enviado |
|--------------------|---------------------------|---------------------------|------------------|
| Pagar hold invoice | (externo / NWC) | — | Mostro detecta pago |
| Enviar invoice | `sendInvoice(orderId, invoice, amount)` | `sendInvoice(...)` | `add-invoice` |
| Marcar fiat enviado | `sendFiatSent()` | `sendFiatSent(orderId)` | `fiat-sent` |
| Liberar sats | `releaseOrder()` | `releaseOrder(orderId)` | `release` |
| Cancelar | `cancelOrder()` | `cancelOrder(orderId)` | `cancel` |
| Disputar | `disputeOrder()` | `disputeOrder(orderId)` | `dispute` |
| Calificar | `submitRating(rating)` | `submitRating(orderId, rating)` | `rate-user` |

### Preparación de child orders para range orders

`sendFiatSent()` y `releaseOrder()` llaman a `_prepareChildOrderIfNeeded()` que:
1. Verifica si la orden es de rango (`minAmount` y `maxAmount` definidos)
2. Si el monto restante >= `minAmount`, genera una nueva `tradeKey` y sesión child
3. Envía payload `NextTrade(key, index)` junto con la acción

---

## 8) Flujo de eventos en tiempo real

### Pipeline completo

```text
1. Relay Nostr → kind 1059 (Gift Wrap)
   ↓
2. SubscriptionManager._handleEvent(orders, event)
   → _ordersController.add(event)
   ↓
3. MostroService._onData(event)
   → event.unWrap(privateKey)  // Descifra NIP-59
   → MostroMessage.fromJson(result)
   → mostroStorage.addMessage(key, msg)  // Persiste en Sembast
   ↓
4. mostroMessageStreamProvider(orderId)
   → MostroStorage.watchLatestMessage(orderId)  // Stream reactivo
   ↓
5. AbstractMostroNotifier.subscribe()
   → ref.listen(mostroMessageStreamProvider)
   → state = state.updateWith(msg)      // Actualiza OrderState
   → handleEvent(msg)                    // Side effects: navegación, notificaciones
   ↓
6. UI reacciona
   → orderNotifierProvider(orderId)      // Widgets rebuilden con nuevo estado
   → Botones, mensajes, countdown se actualizan
```

### Verificación de timestamp

Solo mensajes con timestamp < 60 segundos de antigüedad disparan navegación y notificaciones. Mensajes más antiguos solo actualizan estado (`state.updateWith`), excepto disputas que siempre se procesan.

### Deduplicación

```dart
final eventKey = '${event.id}_${event.action}_${event.timestamp}';
if (_processedEventIds.contains(eventKey)) return;
_processedEventIds.add(eventKey);
```

---

## 9) Flujo completo de trade — Perspectiva del vendedor (sell order)

```text
1. Vendedor crea orden → pending
2. Comprador toma la orden (take-sell)
   → Vendedor recibe: waiting-buyer-invoice → /trade_detail
3. Comprador envía invoice (add-invoice)
   → Vendedor recibe: pay-invoice con PaymentRequest → /pay_invoice
4. Vendedor paga hold invoice (manual o NWC)
   → Ambos reciben: hold-invoice-payment-accepted → active
   → Chat habilitado, peer asignado
5. Comprador marca fiat enviado (fiat-sent)
   → Vendedor recibe: fiat-sent-ok → /trade_detail
   → Botones: Release, Cancel, Dispute, Contact
6. Vendedor libera sats (release) — con confirmación AlertDialog
   → Vendedor recibe: hold-invoice-payment-settled → success
   → Botón: Rate
7. Vendedor califica → success (rate action)
```

## 10) Flujo completo de trade — Perspectiva del comprador (sell order)

```text
1. Comprador toma orden de venta (take-sell)
   → Comprador recibe: add-invoice → /add_invoice (con LN address o manual)
2. Comprador envía invoice
   → Comprador recibe: waiting-seller-to-pay → /trade_detail (esperando)
3. Vendedor paga hold invoice
   → Comprador recibe: hold-invoice-payment-accepted → active
   → Botones: Fiat Sent, Cancel, Dispute, Contact
4. Comprador marca fiat enviado
   → Comprador recibe: fiat-sent-ok → /trade_detail (esperando release)
5. Vendedor libera sats
   → Comprador recibe: released → settled-hold-invoice ("Paying sats")
6. Pago Lightning completa
   → Comprador recibe: purchase-completed → success
   → Botón: Rate
```

---

## 11) Manejo de errores y edge cases

### Payment Failed (post-release)

Cuando Mostro intenta pagar la invoice del comprador y falla:

1. Mostro envía `payment-failed` con `paymentAttempts` y `paymentRetriesInterval`
2. App muestra mensaje informativo, Mostro reintenta automáticamente
3. Si todos los reintentos fallan, Mostro envía `add-invoice`
4. App navega a `/add_invoice/:orderId` en modo manual (no auto Lightning address)
5. La orden permanece en `settled-hold-invoice` durante todo el proceso

### Timeout del countdown

Para `waitingBuyerInvoice` y `waitingPayment`:
- Timer visual basado en `expirationSeconds` del Mostro instance (kind 38385, default 900s = 15min)
- Cuando expira, Mostro cancela la contraparte que no actuó
- Si es el taker → orden vuelve a `pending`
- Si es el maker → orden se cancela

### Cancelación de orden (canceled action de Mostro)

```dart
case Action.canceled:
  final currentSession = ref.read(sessionProvider(orderId));
  if (currentSession != null) {
    await sessionNotifier.deleteSession(orderId);
    notifProvider.showCustomMessage('orderCanceled');
    navProvider.go('/');
  }
  break;
```

### Republicación de orden (maker recibe new-order durante waiting)

Cuando el taker no actúa y Mostro envía `new-order` estando en `waitingBuyerInvoice` o `waitingPayment`:

```dart
case Action.newOrder:
  if (currentSession != null &&
      (state.status == Status.waitingBuyerInvoice ||
          state.status == Status.waitingPayment)) {
    notifProvider.showCustomMessage('orderTimeoutMaker');
  }
  break;
```

### MostroReactiveButton — Feedback visual

Los botones de acción usan `MostroReactiveButton` que:
- Muestra spinner al presionar
- Escucha `mostroMessageStreamProvider` para detectar respuesta
- Si recibe `cantDo` o la acción esperada → resetea loading
- Timeout de 10 segundos si no hay respuesta
- Se oculta automáticamente si la acción ya no está disponible para el rol/estado actual

---

## 12) MostroMessageDetail — Widget de mensaje

### Archivo

`lib/features/trades/widgets/mostro_message_detail_widget.dart`

Muestra un card con avatar de Mostro + texto descriptivo de la última acción + label de status. El texto se genera con `_getActionText()` que hace switch sobre `tradeState.action` y usa strings localizados con variables como monto, moneda, nym de la contraparte, etc.

Diferencia entre maker y taker para `waitingSellerToPay` y `waitingBuyerInvoice`:
- **Maker**: "Your order has been taken! Waiting for counterpart..."
- **Taker**: "Waiting for seller to pay..." / "Please provide a Lightning invoice..."

---

## 13) Diagrama de flujo end-to-end

```text
[TAKE_ORDER completa]
  ├─ Seller recibe pay-invoice → /pay_invoice/:orderId
  │     ├─ NWC auto-pay → success → Mostro detecta pago
  │     └─ Manual QR → pago externo → Mostro detecta pago
  │
  ├─ Buyer recibe add-invoice → /add_invoice/:orderId
  │     ├─ LN Address auto → confirmación → submit
  │     ├─ NWC generate → confirm → submit
  │     └─ Manual input → submit
  │
  └─ Mostro envía hold-invoice-payment-accepted
       → Ambos en /trade_detail/:orderId (status: active)
       → Chat habilitado
       │
       ├─ Buyer: "Fiat Sent" button
       │     → Mostro envía fiat-sent-ok al seller
       │     → Seller ve: Release, Cancel, Dispute, Contact
       │
       ├─ Seller: "Release" button (con confirmación)
       │     → Buyer: released → settled-hold-invoice
       │     → Buyer: purchase-completed → success
       │     → Seller: hold-invoice-payment-settled → success
       │
       ├─ Either: "Dispute" button (con confirmación)
       │     → dispute status → View Dispute button → /dispute_details
       │
       └─ Either: "Cancel" button
             → Si pre-escrow: cancela directamente
             → Si active/fiatSent: cooperative cancel flow
```

---

## 14) Referencias cruzadas

- Flujo de toma de orden (previo a ejecución): `.specify/v1-reference/TAKE_ORDER.md`
- Estados y transiciones completas: `.specify/v1-reference/ORDER_STATES.md`
- Navegación y rutas: `.specify/v1-reference/NAVIGATION_ROUTES.md`
- Arquitectura general: `.specify/v1-reference/ARCHITECTURE.md`
- Sistema de chat P2P: `.specify/v1-reference/P2P_CHAT_SYSTEM.md`
- Integración NWC: `.specify/v1-reference/NWC_ARCHITECTURE.md`
- Protocolo Mostro: `.specify/PROTOCOL.md`
