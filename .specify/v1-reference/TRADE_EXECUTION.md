# Especificación de Ejecución de Trade (Mostro Mobile v1)

> Referencia detallada para la sección 5 (EJECUCIÓN DE TRADE) basada en la implementación real de Flutter/Dart.

## Alcance

Este documento cubre:

- Rutas `/pay_invoice/:orderId`, `/add_invoice/:orderId`, `/trade_detail/:orderId`
- Pantallas `PayLightningInvoiceScreen`, `AddLightningInvoiceScreen`, `TradeDetailScreen`
- Acciones de protocolo involucradas: `pay-invoice`, `add-invoice`, `hold-invoice-payment-accepted`, `fiat-sent`, `fiat-sent-ok`, `release`, `purchase-completed`, `dispute`
- Transiciones de status y disponibilidad de botones basada en rol (`OrderState`, `MostroFSM`)
- Mecánica de hold-invoice (auto-pago NWC, fallback manual, reintentos)
- Actualizaciones en tiempo real vía notifiers, manejo de sesiones, comportamiento de errores y timeouts

---

## Archivos fuente revisados

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

## 1) Puntos de entrada de ejecución de trade

### Configuración de GoRouter (`lib/core/app_routes.dart`)

| Ruta | Builder | Escenario |
| --- | --- | --- |
| `/pay_invoice/:orderId` | `PayLightningInvoiceScreen(orderId)` | El vendedor debe pagar el hold invoice emitido después de `take-buy`. |
| `/add_invoice/:orderId` | `AddLightningInvoiceScreen(orderId, lnAddress)` | El comprador debe proporcionar su invoice (o confirmar Lightning Address) después de `take-sell`. |
| `/trade_detail/:orderId` | `TradeDetailScreen(orderId)` | Vista central para ambos roles mientras el trade está activo (acciones, countdown, chat). |

### Cómo llegan los usuarios aquí

1. **Eventos de Mostro → navegación automática** (`AbstractMostroNotifier.handleEvent`):
   - `Action.payInvoice` → `navProvider.go('/pay_invoice/$orderId')` para el vendedor.
   - `Action.addInvoice` / `Action.waitingBuyerInvoice` → `navProvider.go('/add_invoice/$orderId')` para el comprador (con `?lnAddress=` cuando existen defaults).
   - `Action.holdInvoicePaymentSettled`, `Action.released`, `Action.fiatSentOk`, eventos de disputa/admin → `navProvider.go('/trade_detail/$orderId')` para mantener ambas contrapartes sincronizadas.
2. **Taps manuales** desde `TradeDetailScreen` ("Pagar invoice", "Agregar invoice", "Contactar") llaman a `context.push(...)` a las mismas rutas.
3. **Deep links/notificaciones** reusan las mismas rutas a través de `GoRouter`.

---

## 2) Flujo del vendedor — `PayLightningInvoiceScreen`

Archivo: `lib/features/order/screens/pay_lightning_invoice_screen.dart`

- Observa `orderNotifierProvider(orderId)` para obtener `paymentRequest.lnInvoice`, sats (`order.amount`), e info fiat (`order.fiatAmount`, `order.fiatCode`).
- Usa `nwcProvider` para detectar conectividad NWC y `_manualMode` para cambiar modos de UI.

### Auto-pago NWC

```dart
final showNwcPayment = isNwcConnected && !_manualMode && lnInvoice.isNotEmpty;
```

Si es `true`, la pantalla renderiza:

1. Un texto resumen con montos fiat/sats.
2. `NwcPaymentWidget` para enviar el hold invoice automáticamente.
   - `onPaymentSuccess`: `context.go('/')` y esperar a que Mostro emita `hold-invoice-payment-accepted` (que abrirá `TradeDetail`).
   - `onFallbackToManual`: establece `_manualMode = true` para revelar la UI manual.
3. Un botón rojo **Cancelar** que llama a `orderNotifier.cancelOrder()` seguido de `context.go('/')`.

### Modo de pago manual

Cuando NWC no está conectado o el usuario opta por salir:

- Muestra `PayLightningInvoiceWidget` (QR + acciones + botones de copiar).
- `onSubmit`: una vez que el usuario confirma el pago, navega a `/` y deja que Mostro actualice el estado.
- `onCancel`: igual que arriba, invoca `cancelOrder()` antes de salir.

### Notas de estado

- Si el `PaymentRequest` no ha llegado aún, la UI permanece vacía (Mostro reenviará `pay-invoice` cuando esté listo).
- `OrderState.status` permanece en `waiting-payment` durante esta fase (ver `OrderState._getStatusFromAction`).

---

## 3) Flujo del comprador — `AddLightningInvoiceScreen`

Archivo: `lib/features/order/screens/add_lightning_invoice_screen.dart`

- Hace stream del último payload de orden vía `mostroOrderStreamProvider(orderId)` (monto, datos fiat, métodos).
- Lee `nwcProvider` y `settingsProvider` para decidir entre confirmación de Lightning Address, generación de invoice NWC, o entrada manual.

### Escalera de prioridad

1. **Confirmación de Lightning Address** (parámetro de ruta o configuración por defecto):
   - Renderiza `LnAddressConfirmationWidget` con `S.of(context)!.lnAddressConfirmHeader(orderId)`.
   - `onConfirm` → `_submitLnAddress()` → `orderNotifier.sendInvoice(orderId, lnAddress, null)` → `context.go('/')`.
   - `onManualFallback` → `_manualMode = true`.
2. **Generación de invoice NWC** (wallet conectado, sin LN address, monto > 0):
   - Usa `NwcInvoiceWidget` para crear un invoice en el wallet.
   - `onInvoiceConfirmed(invoice)` → `_submitInvoice(invoice, amount)`.
   - `onFallbackToManual` → `_manualMode = true`.
3. **Entrada manual** (`AddLightningInvoiceWidget`):
   - `onSubmit`: valida `invoiceController.text`, luego `orderNotifier.sendInvoice`.
   - `onCancel`: `orderNotifier.cancelOrder()` y permanece en `/`.

### Reintentos por fallo de pago

- `AbstractMostroNotifier._handleAddInvoiceWithAutoLightningAddress` previene el uso automático de Lightning Address cuando `state.status == Status.paymentFailed`; el usuario debe re-ingresar el invoice manualmente.
- Los errores se muestran vía `SnackBarHelper.showTopSnackBar` con mensajes `failedToUpdateInvoice`.

---

## 4) `TradeDetailScreen` — vista central del trade

Archivo: `lib/features/trades/screens/trade_detail_screen.dart`

### Fuentes de datos

- `orderNotifierProvider(orderId)` → `OrderState` (status, última acción, solicitud de pago, disputa, peer).
- `sessionProvider(orderId)` → rol del usuario (`Role.buyer` o `Role.seller`).
- `eventProvider(orderId)` → metadatos de orden pública (premium, rango fiat, etc.).
- `orderRepositoryProvider` → `MostroInstance` (`expirationHours`) para timers de countdown.
- `orderMessagesStreamProvider(orderId)` → feed para `MostroMessageDetail`.

### Layout

1. Cards de monto e ID de orden (`_buildSellerAmount`, `OrderIdCard`).
2. Ya sea info de reputación del creador (maker pendiente) o `MostroMessageDetail`.
3. `_CountdownWidget` (estados pending / waiting, coloreado según pasa el tiempo).
4. Fila de botones = `_buildActionButtons` + `_buildButtonRow`:
   - Extrae acciones permitidas de `OrderState.getActions(session.role)`.
   - Cada botón = `MostroReactiveButton`, que escucha `mostroMessageStreamProvider` para detener el spinner o mostrar éxito.

Ejemplo de botón:

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

| Acción UI | Rol | Status requerido | Callback |
| --- | --- | --- | --- |
| **Pagar invoice** | Vendedor | `Status.waitingPayment` y `paymentRequest` presente | `context.push('/pay_invoice/:id')` |
| **Agregar invoice** | Comprador | `Status.waitingBuyerInvoice` | `context.push('/add_invoice/:id')` |
| **Fiat enviado** | Comprador | `Status.active` | `orderNotifier.sendFiatSent()` |
| **Liberar** | Vendedor | `Status.fiatSent` (o `active` si FSM lo permite) | Diálogo de confirmación → `orderNotifier.releaseOrder()` |
| **Cancelar** | Ambos | Depende de status/acción | Diálogo de confirmación → `orderNotifier.cancelOrder()` |
| **Disputa** | Ambos | `Status.active` / `fiatSent` / `dispute` | Diálogo de confirmación → `disputeRepositoryProvider.createDispute(orderId)` |
| **Contactar** | Ambos | Contextos de cancelación cooperativa/disputa | `context.push('/chat_room/:id')` |

Botones adicionales:
- `VER DISPUTA` aparece cuando la última acción es `dispute-*` o `admin-took-dispute` y `tradeState.dispute?.disputeId` existe.
- `Status.cooperativelyCanceled` fuerza el botón "Contactar" incluso si `send-dm` no es parte del conjunto de acciones.

---

## 5) Mapeo de acción ↔ status

Derivado de `OrderState._getStatusFromAction()` y `MostroFSM`:

| Evento Mostro | Status resultante | Notas |
| --- | --- | --- |
| `take-buy` | `waiting-payment` | Vendedor toma una orden de compra → debe pagar hold invoice. |
| `take-sell` | `waiting-buyer-invoice` | Comprador toma una orden de venta → debe subir invoice. |
| `pay-invoice`, `waiting-seller-to-pay` | `waiting-payment` | Fuerza al vendedor a `PayLightningInvoiceScreen`. |
| `add-invoice`, `waiting-buyer-invoice` | `waiting-buyer-invoice` | Fuerza al comprador a `AddLightningInvoiceScreen`. |
| `hold-invoice-payment-accepted` | `active` | Hold invoice liquidado; chat + acciones habilitadas. |
| `fiat-sent`, `fiat-sent-ok` | `fiat-sent` | Comprador declaró fiat enviado; vendedor obtiene botón **Liberar**. |
| `release`, `purchase-completed`, `hold-invoice-payment-settled` | `success` / `settled-hold-invoice` | Camino de completación previo al rating. |
| `payment-failed` | `payment-failed` | Reintentos automáticos + re-entrada manual de invoice. |
| `cooperative-cancel-*` | `cooperatively-canceled` → `canceled` | Cancelación cooperativa pendiente, luego estado terminal. |
| `dispute-*`, `admin-*` | `dispute`, `settled-by-admin`, `canceled-by-admin` | TradeDetail se bloquea a UI de disputa. |

`MostroFSM.nextStatus()` se usa para asegurar que la UI nunca renderice acciones inválidas para el rol del usuario (ej., compradores nunca ven **Liberar**).

---

## 6) Actualizaciones en tiempo real y manejo de sesiones

### `OrderNotifier`

- Se suscribe a `mostroMessageStreamProvider(orderId)` y mantiene `OrderState` sincronizado (incluyendo `paymentRequest`, `peer`, `dispute`).
- Crea sesiones vía `sessionNotifier.newSession` cuando se inicia un take, almacenando el rol e info del peer.
- Expone métodos consumidos por la UI: `sendInvoice`, `sendFiatSent`, `releaseOrder`, `disputeOrder`, `cancelOrder`, etc.

### `AbstractMostroNotifier`

- Despacha navegación (`navProvider.go`) basado en acciones entrantes.
- Inicia timeouts de sesión de 10s (`startSessionTimeoutCleanup`) para limpiar takes fallidos.
- Elimina sesiones y muestra notificaciones cuando Mostro emite `canceled` (expiración, cancelación cooperativa, etc.).
- Detecta `hold-invoice-payment-accepted` para poblar `session.peer` y habilitar chat.
- Fuerza entrada manual de invoice cuando `paymentFailed` está activo.

### Vista general de trades

- `/order_book` lista los trades del usuario vía `filteredTradesWithOrderStateProvider`.
- `TradesListItem` renderiza chips de status/rol desde `orderNotifierProvider(orderId)` y navega a `/trade_detail/:orderId`.

---

## 7) Errores, timeouts y disputas

| Escenario | Comportamiento de la app |
| --- | --- |
| Expiración del lado maker | `OrderNotifier._subscribeToPublicEvents` observa `orderEventsProvider`; cuando una orden maker pendiente pasa a `canceled`, elimina la sesión y postea `orderCanceled`. |
| Timeout de taker (sin respuesta en 10s) | `startSessionTimeoutCleanup` se dispara, muestra `sessionTimeoutMessage`, y navega a home. |
| Fallo de pago de hold invoice | Mostro envía `payment-failed`; status cambia a `paymentFailed`, compradores solo ven **Agregar invoice**, vendedores solo **Pagar invoice** hasta que llegue una nueva solicitud. |
| Disputas | El botón "Disputa" dispara `disputeRepositoryProvider.createDispute`. Una vez que existe una disputa, "Ver disputa" enlaza a `/dispute_details/:id` y el chat cambia a admin shared keys (ver [DISPUTE_SYSTEM.md](./DISPUTE_SYSTEM.md)). |
| Cancelación cooperativa | Cancelación pendiente renderiza botón gris (deshabilitado) + botón "Contactar" para coordinar. |
| Errores de invoice/pago | La UI muestra mensajes `SnackBarHelper.showTopSnackBar` pero mantiene al usuario en la misma pantalla. |

**Resumen del flujo de disputa:** los participantes del trade pueden abrir una disputa una vez que la orden está `active`/`fiat-sent`; el repositorio envía un `MostroMessage(Action.dispute)` cifrado, `OrderState` transiciona a `Status.dispute`, y los admins pueden luego tomar el caso (`adminTookDispute`), liquidar (`adminSettled`), o reembolsar (`adminCanceled`). Detalles de UI, badges de no leídos, y el chat dedicado de disputa están en [DISPUTE_SYSTEM.md](./DISPUTE_SYSTEM.md).

---

## 8) Referencias cruzadas

- `.specify/v1-reference/TAKE_ORDER.md` — enlaza aquí tan pronto como se completa el take.
- `.specify/v1-reference/ORDER_STATES.md` — referencia este spec para transiciones de estado de ejecución.
- `.specify/v1-reference/NAVIGATION_ROUTES.md` — rutas `/pay_invoice`, `/add_invoice`, `/trade_detail`, `/order_book` apuntan aquí.
- `.specify/v1-reference/README.md` — incluye este documento en el índice (pantallas y navegación).
- `.specify/v1-reference/RATING_SYSTEM.md` — flujo de calificación post-trade disparado por el botón **Calificar**.
