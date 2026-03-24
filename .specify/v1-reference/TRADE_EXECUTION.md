# Trade Execution Specification (Mostro Mobile v1)

> Flujo completo de ejecución de trades (sección 5), basado en el código real de Flutter/Dart.

## Alcance

Esta especificación cubre:

- Rutas `/pay_invoice/:orderId`, `/add_invoice/:orderId` y `/trade_detail/:orderId`
- Pantallas `PayLightningInvoiceScreen`, `AddLightningInvoiceScreen` y `TradeDetailScreen`
- Acciones de protocolo involucradas: `pay-invoice`, `add-invoice`, `hold-invoice-payment-accepted`, `fiat-sent`, `fiat-sent-ok`, `release`, `purchase-completed`, `dispute`
- Transiciones de estado y botones mostrados según rol/estado (`OrderState`, `MostroFSM`)
- Mecánica de hold invoices (NWC auto-pay, fallback manual, reintentos)
- Actualización en tiempo real vía notifiers y manejo de errores/timeout

---

## Archivos fuente analizados

### Pantallas y widgets
- `lib/features/order/screens/pay_lightning_invoice_screen.dart`
- `lib/shared/widgets/nwc_payment_widget.dart`
- `lib/shared/widgets/pay_lightning_invoice_widget.dart`
- `lib/features/order/screens/add_lightning_invoice_screen.dart`
- `lib/shared/widgets/nwc_invoice_widget.dart`
- `lib/shared/widgets/ln_address_confirmation_widget.dart`
- `lib/features/trades/screens/trade_detail_screen.dart`
- `lib/features/trades/widgets/trades_list.dart`
- `lib/features/trades/widgets/trades_list_item.dart`

### Estado, notifiers y servicios
- `lib/features/order/notifiers/order_notifier.dart`
- `lib/features/order/notifiers/abstract_mostro_notifier.dart`
- `lib/features/order/models/order_state.dart`
- `lib/core/mostro_fsm.dart`
- `lib/data/models/enums/action.dart`
- `lib/data/models/enums/status.dart`
- `lib/shared/providers/session_notifier_provider.dart`
- `lib/shared/providers/order_repository_provider.dart`
- `lib/services/mostro_service.dart`

---

## 1) Entry points de Trade Execution

### Navegación declarada en `lib/core/app_routes.dart`

| Ruta | Builder | Escenario |
| --- | --- | --- |
| `/pay_invoice/:orderId` | `PayLightningInvoiceScreen(orderId)` | Seller debe pagar la hold invoice emitida por Mostro tras `take-buy`. |
| `/add_invoice/:orderId` | `AddLightningInvoiceScreen(orderId, lnAddress)` | Buyer debe subir su invoice (o confirmar lightning address) tras `take-sell`. |
| `/trade_detail/:orderId` | `TradeDetailScreen(orderId)` | Vista central para ambos roles durante la ejecución (acciones, contador, botones). |

### Cómo se llega ahí

1. **Eventos de Mostro → navegación automática** (`AbstractMostroNotifier.handleEvent`):
   - `Action.payInvoice` → `navProvider.go('/pay_invoice/$orderId')` para el seller.
   - `Action.addInvoice` / `Action.waitingBuyerInvoice` → `navProvider.go('/add_invoice/$orderId')` para el buyer (con query `?lnAddress=` si hay lightning address por defecto).
   - `Action.holdInvoicePaymentSettled`, `Action.released`, `Action.fiatSentOk`, disputas, etc. → `navProvider.go('/trade_detail/$orderId')` para mantener a ambos roles sincronizados.
2. **Taps manuales** desde `TradeDetailScreen` (botones "Pagar invoice", "Agregar invoice", "Contactar") usan `context.push()` hacia las mismas rutas.
3. **Deep links / notif**: cualquier `GoRoute` se resuelve igual si se abre desde un enlace.

---

## 2) Seller flow — `PayLightningInvoiceScreen`

Archivo: `lib/features/order/screens/pay_lightning_invoice_screen.dart`

- Observa `orderNotifierProvider(orderId)` para obtener `paymentRequest.lnInvoice`, monto en sats (`order.amount`) y fiat (`order.fiatAmount` + `order.fiatCode`).
- Determina si hay conexión NWC (`nwcProvider`) y si el usuario aún no forzó modo manual (`_manualMode`).

### Autopago NWC

```dart
def final showNwcPayment = isNwcConnected && !_manualMode && lnInvoice.isNotEmpty;
```

Cuando `true`, renderiza:

1. Mensaje descriptivo con monto fiat/sats.
2. `NwcPaymentWidget` (auto-paga la hold invoice). Callbacks clave:
   - `onPaymentSuccess`: navega a `/` y espera que Mostro emita `hold-invoice-payment-accepted` → `TradeDetailScreen` se actualizará sola.
   - `onFallbackToManual`: setea `_manualMode = true` para mostrar la UI manual.
3. Botón **Cancelar** → `orderNotifier.cancelOrder()` y redirige a `/`.

### Pago manual

Cuando no hay NWC o se fuerza fallback:

- Muestra `PayLightningInvoiceWidget` (teclado numérico/QR + estatus de invoice).
- `onSubmit`: tras confirmar pago, navega a `/` (Mostro actualizará estado).
- `onCancel`: igual que arriba, invoca `cancelOrder()`.

### Estado/errores relevantes

- Si `paymentRequest` no existe aún, la pantalla queda vacía (no se muestran botones). Mostro volverá a pedir la pantalla cuando reciba `pay-invoice` o `waiting-seller-to-pay`.
- `OrderState.status` pasa a `waiting-payment` durante esta fase (`OrderState._getStatusFromAction`).

---

## 3) Buyer flow — `AddLightningInvoiceScreen`

Archivo: `lib/features/order/screens/add_lightning_invoice_screen.dart`

- Consume `mostroOrderStreamProvider(orderId)` para refrescar datos de la orden (amount, fiat, métodos).
- Lee `nwcProvider` y `settingsProvider` para decidir entre **Lightning Address confirm**, **NWC invoice** o **entrada manual**.

### Prioridad de flujos

1. **Lightning Address** (`lnAddress` en la ruta o default del usuario):
   - Renderiza `LnAddressConfirmationWidget` con `S.of(context)!.lnAddressConfirmHeader(orderId)`.
   - `onConfirm` → `_submitLnAddress()` llama `orderNotifier.sendInvoice(orderId, lnAddress, null)` y regresa a `/`.
   - `onManualFallback` → `_manualMode = true`.
2. **NWC Invoice** (wallet conectada, no hay LN address, amount > 0):
   - `NwcInvoiceWidget` genera invoice desde la wallet.
   - `onInvoiceConfirmed(invoice)` → `_submitInvoice(invoice, amount)`.
   - `onFallbackToManual` → `_manualMode = true`.
3. **Entrada manual** (`AddLightningInvoiceWidget`):
   - `onSubmit`: valida `invoiceController.text`, luego `orderNotifier.sendInvoice`.
   - `onCancel`: `orderNotifier.cancelOrder()`.

### Reintentos y payment failed

- `AbstractMostroNotifier._handleAddInvoiceWithAutoLightningAddress` evita usar auto LN address si el estado actual es `Status.paymentFailed` (obliga a flujo manual para evitar loops de pago fallido).
- Errores (`catch (e)`) muestran `SnackBarHelper.showTopSnackBar` con `S.of(context)!.failedToUpdateInvoice`.

---

## 4) TradeDetailScreen — vista central de ejecución

Archivo: `lib/features/trades/screens/trade_detail_screen.dart`

### Data sources

- `orderNotifierProvider(orderId)` → `OrderState` (status, action, invoice, peer, dispute).
- `sessionProvider(orderId)` → rol (`Role.buyer` o `Role.seller`) + peer.
- `eventProvider(orderId)` → Nostr event original para metadata (premium, amounts).
- `orderRepositoryProvider` → `MostroInstance` (horas de expiración) para countdown.
- `orderMessagesStreamProvider` → historial de mensajes (se usa en `MostroMessageDetail`).

### UI principal

1. **Amount & Order ID cards** (`_buildSellerAmount`, `OrderIdCard`).
2. **Detalles dinámicos**: reputación del creador o `MostroMessageDetail` según el estado.
3. **Countdown** (`DynamicCountdownWidget`) configurado con `order.expiresAt`. Cambia de color cuando se acerca a timeout.
4. **Botonera** construida por `_buildActionButtons` + `_buildButtonRow`:
   - Usa `OrderState.getActions(session.role)` para obtener acciones habilitadas.
   - Cada acción se renderiza con `MostroReactiveButton`, que escucha `mostroMessageStreamProvider` para resetear loading/mostrar check.
   - Ejemplos:

```dart
MostroReactiveButton(
  label: S.of(context)!.payInvoiceButton,
  action: actions.Action.payInvoice,
  backgroundColor: AppTheme.mostroGreen,
  orderId: orderId,
  onPressed: () => context.push('/pay_invoice/$orderId'),
)
```

### Acciones clave por rol

| Acción UI | Rol | Estado necesario | Callback |
| --- | --- | --- | --- |
| **Pagar invoice** | Seller | `Status.waitingPayment` con `paymentRequest` presente | `context.push('/pay_invoice/:id')` |
| **Agregar invoice** | Buyer | `Status.waitingBuyerInvoice` | `context.push('/add_invoice/:id')` |
| **FIAT ENVIADO** | Buyer | `Status.active` | `orderNotifier.sendFiatSent()` |
| **LIBERAR** | Seller | `Status.fiatSent` o `Status.active` (según `OrderState.actions`) | `orderNotifier.releaseOrder()` tras diálogo de confirmación |
| **Cancelar** | Ambos | Depende del estado; muestra diálogo y llama `orderNotifier.cancelOrder()` |
| **Disputa** | Ambos | `Status.active`, `Status.fiatSent`, etc. | Crea disputa vía `disputeRepositoryProvider.createDispute` |
| **Contactar** | Ambos | Estados cooperativos/disputa | `context.push('/chat_room/:id')` |

### Botones adicionales

- `VIEW DISPUTE` aparece si `tradeState.action` ∈ {`dispute-initiated-by-*`, `admin-took-dispute`} y existe `tradeState.dispute?.disputeId`.
- `Status.cooperativelyCanceled` fuerza mostrar botón de contacto aunque `send-dm` no esté en las acciones actuales.

---

## 5) Mapeo de acciones ↔ estados

Se deriva de `OrderState._getStatusFromAction()` + `MostroFSM`:

| Evento Mostro | Estado resultante | Descripción |
| --- | --- | --- |
| `take-buy` | `waiting-payment` | Seller tomó orden de compra, debe pagar hold invoice. |
| `take-sell` | `waiting-buyer-invoice` | Buyer tomó orden de venta, debe subir invoice. |
| `pay-invoice` / `waiting-seller-to-pay` | `waiting-payment` | Seller ve pantalla de pago. |
| `add-invoice` / `waiting-buyer-invoice` | `waiting-buyer-invoice` | Buyer ve pantalla de invoice (auto LN addr si aplica). |
| `hold-invoice-payment-accepted` | `active` | Hold invoice pagada, chat habilitado, ambos roles pasan a TradeDetail. |
| `fiat-sent` / `fiat-sent-ok` | `fiat-sent` | Buyer declaró pago fiat; seller habilita botón **LIBERAR**. |
| `release` / `purchase-completed` / `hold-invoice-payment-settled` | `success` / `settled-hold-invoice` | Fondos liberados; `TradeDetail` muestra botón **CALIFICAR**. |
| `payment-failed` | `payment-failed` | Mostro reintenta: buyer debe reenviar invoice manualmente, seller vuelve a `pay-invoice` tras nuevo request. |
| `cooperative-cancel-*` | `cooperatively-canceled` → `canceled` | Botones muestran estado de cancelación pendiente. |
| `dispute-*`, `admin-*` | `dispute`, `settled-by-admin`, `canceled-by-admin` | TradeDetail fuerza botón "Ver disputa" y restringe otras acciones. |

`MostroFSM.nextStatus()` también se usa para verificar que solo se expongan acciones válidas por rol (p. ej. buyer nunca ve **LIBERAR**).

---

## 6) Actualización en tiempo real y manejo de sesiones

### OrderNotifier (`lib/features/order/notifiers/order_notifier.dart`)

- Suscribe `mostroMessageStreamProvider(orderId)` y mantiene `OrderState` sincronizado (incluye `paymentRequest`, `peer`, `dispute`).
- Crea sesiones (`sessionNotifier.newSession`) al tomar orden y almacena el rol.
- Expone métodos para UI: `sendInvoice`, `payInvoice` (vía `mostroService`), `sendFiatSent`, `releaseOrder`, `disputeOrder`, `cancelOrder`.

### AbstractMostroNotifier (`abstract_mostro_notifier.dart`)

Responsable de side-effects al recibir eventos:

- Navegación automática (`navProvider.go(...)`) según la acción recibida.
- `startSessionTimeoutCleanup` (10 s) para limpiar sesiones si Mostro no responde al take.
- Cancela la sesión y muestra notificación si Mostro envía `canceled` (timeout/expiración).
- Detecta `hold-invoice-payment-accepted` para poblar `session.peer` (clave para chat).
- En `paymentFailed`, marca estado y obliga a buyer a flujo manual (no auto LN address).

### Trade updates / Deck

- `trades_screen.dart` lista mis trades (`filteredTradesWithOrderStateProvider`). Cada item abre `/trade_detail/:orderId` usando `context.push`.
- `TradesListItem` muestra `StatusChip` + `RoleChip` calculados en tiempo real (`orderNotifierProvider`).

---

## 7) Manejo de errores, timeouts y disputas

| Escenario | Qué hace la app |
| --- | --- |
| **Payment timeout / cancelación automática** | `OrderNotifier._subscribeToPublicEvents` escucha `orderEventsProvider`; si el estado público pasa a `canceled` y el usuario era maker (`Status.pending`), elimina la sesión y muestra notificación `orderCanceled`. |
| **Session timeout (taker no recibe respuesta)** | `AbstractMostroNotifier.startSessionTimeoutCleanup` muestra snackbar `sessionTimeoutMessage` y vuelve a `/`. |
| **Payment failed (hold invoice)** | Mostro envía `Action.paymentFailed`; `OrderState` entra en `Status.paymentFailed`. Buyer solo ve botón **Agregar invoice**; seller solo ve **Pagar invoice** hasta que Mostro reinstala la hold invoice. |
| **Disputas** | Botón **Disputa** abre diálogo → `disputeRepositoryProvider.createDispute`. Una vez creada, `TradeDetail` muestra "Ver disputa" y `chat_room` incluye admins cuando llega `admin-took-dispute`. |
| **Cancelaciones cooperativas** | Cuando uno inicia, el otro ve botón gris "Cancelación pendiente" + botón "Contactar" para coordinar.
| **Errores al enviar invoice/pago** | UI usa `SnackBarHelper.showTopSnackBar` con mensajes localizados y mantiene al usuario en la misma pantalla.

---

## 8) Cross-references

- `.specify/v1-reference/TAKE_ORDER.md` → sección "Navegación posterior" debe enlazar aquí para la fase posterior a `Take`.
- `.specify/v1-reference/ORDER_STATES.md` → transiciones de `waiting-payment`, `active`, `fiat-sent`, `success` referencian este documento.
- `.specify/v1-reference/NAVIGATION_ROUTES.md` → filas de `/pay_invoice`, `/add_invoice`, `/trade_detail` apuntan a este spec.
- `.specify/v1-reference/README.md` → agregar entrada "TRADE_EXECUTION.md" en el índice.
