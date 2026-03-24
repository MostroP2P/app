# Manejo de Estados de Orden

Este documento describe cómo la app móvil procesa, mapea y muestra los estados de orden recibidos del daemon Mostro. Cubre el mapeo de acción-a-estado, comportamiento específico por rol, el flujo de restauración, y presentación en la UI.

## Resumen

El daemon Mostro se comunica con la app vía mensajes gift wrap cifrados (NIP-59). Cada mensaje contiene una **acción** que describe qué pasó. La app mapea estas acciones a valores internos de **estado** que determinan qué ve el usuario y qué operaciones están disponibles.

Los archivos clave involucrados son:

- `lib/data/models/enums/status.dart` — Definición del enum Status
- `lib/data/models/enums/action.dart` — Definición del enum Action
- `lib/features/order/models/order_state.dart` — Mapeo de acción-a-estado (`_getStatusFromAction`)
- `lib/features/restore/restore_manager.dart` — Mapeo de estado-a-acción para restauración (`_getActionFromStatus`)
- `lib/features/trades/widgets/mostro_message_detail_widget.dart` — Display de Detalles de Orden
- `lib/features/trades/widgets/trades_list_item.dart` — Chips de lista de Mis Trades

## Enum de Estado

La app define los siguientes estados:

| Estado | Valor del Protocolo | Descripción |
|--------|---------------------|-------------|
| `pending` | `pending` | Orden publicada, esperando contraparte |
| `waitingBuyerInvoice` | `waiting-buyer-invoice` | Esperando que el comprador provea un invoice Lightning |
| `waitingPayment` | `waiting-payment` | Esperando que el vendedor pague el hold invoice |
| `active` | `active` | Ambas partes emparejadas, trade en progreso |
| `fiatSent` | `fiat-sent` | Comprador confirmó pago fiat enviado |
| `settledHoldInvoice` | `settled-hold-invoice` | Vendedor liberó, pago Lightning al comprador en progreso |
| `success` | `success` | Trade completado exitosamente |
| ~~`paymentFailed`~~ | ~~`payment-failed`~~ | **NO es un estado del protocolo** — estado solo de UI en v1. Ver nota abajo. |
| `canceled` | `canceled` | Orden cancelada (timeout, directa, o hold invoice cancelado) |
| `cooperativelyCanceled` | `cooperatively-canceled` | Cancelación cooperativa en progreso o completada |
| `canceledByAdmin` | `canceled-by-admin` | Admin canceló la orden durante una disputa |
| `settledByAdmin` | `settled-by-admin` | Admin resolvió una disputa liberando sats |
| `completedByAdmin` | `completed-by-admin` | Estado reservado, no usado activamente |
| `dispute` | `dispute` | Orden está en disputa |
| `expired` | `expired` | Orden expiró, tratada como cancelada |
| `inProgress` | `in-progress` | Estado interno usado durante restauración |

> ⚠️ **Nota sobre `paymentFailed`:** Esto NO es un estado del protocolo Mostro. La app móvil v1 lo creó como un estado solo de UI. En el protocolo, cuando el pago Lightning al comprador falla:
> 1. Mostro envía notificación `Action::PaymentFailed` (no un cambio de estado)
> 2. La orden permanece en estado `settled-hold-invoice`
> 3. Mostro reintenta automáticamente
> 4. Si todos los reintentos fallan, Mostro envía `Action::AddInvoice` para que el comprador provea nuevo invoice
> 
> **v2 NO debería incluir `PaymentFailed` como estado.** Manejarlo como una notificación transitoria en `SettledHoldInvoice`.

## Mapeo de Acción-a-Estado

Cuando la app recibe un mensaje gift wrap de Mostro, `_getStatusFromAction()` en `order_state.dart` determina el nuevo estado. Este mapeo es dirigido por acción, no específico de rol — la diferenciación por rol sucede naturalmente porque Mostro envía diferentes acciones al comprador y vendedor.

### Esperando Pago

| Acción | Estado | Cuándo |
|--------|--------|--------|
| `waitingSellerToPay` | `waitingPayment` | Vendedor debe pagar el hold invoice |
| `payInvoice` | `waitingPayment` | Vendedor recibe el invoice a pagar |
| `takeSell` | `waitingPayment` | Vendedor toma una orden de compra |

### Esperando Invoice del Comprador

| Acción | Estado | Cuándo |
|--------|--------|--------|
| `waitingBuyerInvoice` | `waitingBuyerInvoice` | Comprador debe proveer un invoice Lightning |
| `addInvoice` | `waitingBuyerInvoice` | Comprador recibe solicitud de agregar invoice (o permanece `settledHoldInvoice` si es después de fallo de pago) |
| `takeBuy` | `waitingBuyerInvoice` | Comprador toma una orden de venta |

### Activo

| Acción | Estado | Cuándo |
|--------|--------|--------|
| `buyerTookOrder` | `active` | Vendedor es notificado que un comprador tomó su orden |
| `holdInvoicePaymentAccepted` | `active` | Comprador es notificado que el vendedor pagó el hold invoice |
| `buyerInvoiceAccepted` | `active` | Invoice del comprador fue aceptado |

### Fiat Enviado

| Acción | Estado | Cuándo |
|--------|--------|--------|
| `fiatSent` | `fiatSent` | Comprador confirma pago fiat |
| `fiatSentOk` | `fiatSent` | Contraparte es notificada que fiat fue enviado |

### Hold Invoice Liquidado (Intermedio)

| Acción | Estado | Cuándo |
|--------|--------|--------|
| `released` | `settledHoldInvoice` | **Comprador** recibe esto cuando vendedor libera sats |
| `release` | `settledHoldInvoice` | Vendedor inicia liberación |

Este es un estado intermedio **solo para el comprador**. Significa que el vendedor liberó los sats y el pago Lightning al comprador está en progreso pero no confirmado aún. El vendedor nunca ve este estado porque recibe `holdInvoicePaymentSettled` en su lugar, que mapea directamente a `success`.

### Éxito

| Acción | Estado | Cuándo |
|--------|--------|--------|
| `purchaseCompleted` | `success` | Comprador recibe confirmación de que el pago LN completó |
| `holdInvoicePaymentSettled` | `success` | **Vendedor** recibe esto cuando el hold invoice se liquida |
| `rate` | `success` | Usuario recibe prompt de calificación |
| `rateReceived` | `success` | Confirmación de calificación recibida |

### Fallo de Pago (Acción, No Estado)

> ⚠️ **Nota v2:** `paymentFailed` NO es un cambio de estado. Ver nota del protocolo arriba.

| Acción | Estado | Cuándo |
|--------|--------|--------|
| `paymentFailed` | (sin cambio) | Pago Lightning al comprador falló — orden permanece `settledHoldInvoice` |

Cuando se recibe la acción `paymentFailed`, la orden permanece en estado `settled-hold-invoice`. La app debería mostrar una notificación de que el pago falló y Mostro está reintentando. Cuando `addInvoice` sigue (después de que todos los reintentos fallan), pedir al comprador un nuevo invoice mientras permanece en `settled-hold-invoice`.

### Cancelado

| Acción | Estado | Cuándo |
|--------|--------|--------|
| `canceled` | `canceled` | Mostro cancela la orden (timeout, explícita) |
| `cancel` | `canceled` | Acción de cancelar iniciada |
| `cooperativeCancelAccepted` | `canceled` | Ambas partes aceptaron cancelación cooperativa |
| `holdInvoicePaymentCanceled` | `canceled` | Hold invoice fue cancelado |
| `adminCanceled` | `canceled` | Admin canceló la orden |
| `adminCancel` | `canceled` | Acción de cancelar del admin |

### Cancelación Cooperativa

| Acción | Estado | Cuándo |
|--------|--------|--------|
| `cooperativeCancelInitiatedByYou` | `cooperativelyCanceled` | Usuario inició cancelación cooperativa |
| `cooperativeCancelInitiatedByPeer` | `cooperativelyCanceled` | Contraparte inició cancelación cooperativa |

Este es un estado pendiente. Una vez que la otra parte acepta, el estado cambia a `canceled` vía `cooperativeCancelAccepted`.

### Disputa

| Acción | Estado | Cuándo |
|--------|--------|--------|
| `disputeInitiatedByYou` | `dispute` | Usuario abrió una disputa |
| `disputeInitiatedByPeer` | `dispute` | Contraparte abrió una disputa |
| `dispute` | `dispute` | Acción general de disputa |
| `adminTakeDispute` | `dispute` | Admin tomó la disputa |
| `adminTookDispute` | `dispute` | Admin tomó la disputa (confirmación) |

_Para comportamiento de UI (badges de lista, chat de disputa, mensajería con admin) ver [DISPUTE_SYSTEM.md](./DISPUTE_SYSTEM.md)._ 

### Resolución de Admin

| Acción | Estado | Cuándo |
|--------|--------|--------|
| `adminSettle` | `settledByAdmin` | Admin resuelve disputa liberando sats al usuario |
| `adminSettled` | `settledByAdmin` | Confirmación de liquidación del admin |

### Auto-Cierre de Disputa en Estado Terminal

Cuando una orden con una disputa activa alcanza un estado terminal a través de acción del usuario (no admin), la disputa se cierra automáticamente. Esto se maneja en `OrderState.updateWith()` después del bloque de manejo de disputa del admin.

| Orden alcanza | `dispute.status` | `dispute.action` | Disparador |
|---------------|------------------|------------------|------------|
| `success` | `closed` | `user-completed` | Vendedor recibe `holdInvoicePaymentSettled` |
| `settledHoldInvoice` | `closed` | `user-completed` | Comprador recibe `released` |
| `canceled` | `closed` | `cooperative-cancel` | Ambos reciben `cooperativeCancelAccepted` |

El estado de disputa `closed` es distinto de `resolved` (admin liquidó) y `seller-refunded` (admin canceló). La cadena de UI lo maneja automáticamente:

- `DisputeChatScreen`: input desaparece (solo se renderiza para `in-progress`)
- `DisputeMessagesList`: muestra mensaje "Chat cerrado" con icono de candado
- `DisputeStatusBadge`: badge gris "Cerrado"
- `DisputeStatusContent`: mensaje de resolución específico por rol
- Descripción de lista de disputas: diferencia por `dispute.action`

### Acciones Informativas (Sin Cambio de Estado)

Estas acciones preservan el estado actual:

- `rateUser` — Calificar a un usuario
- `invoiceUpdated` — Invoice fue actualizado
- `sendDm` — Mensaje directo
- `tradePubkey` — Intercambio de clave pública de trade
- `adminAddSolver` — Admin asignó un solver
- `newOrder` — Usa estado del payload si está disponible

## Comportamiento Específico por Rol

Mostro envía diferentes acciones al comprador y vendedor para el mismo evento. La app no necesita lógica basada en rol en `_getStatusFromAction()` porque la diferenciación de rol es manejada por el protocolo mismo.

### Vendedor Libera Sats — Qué Ve Cada Parte

```text
Vendedor libera
    │
    ├── Comprador recibe: Action.released
    │   └── Estado: settledHoldInvoice ("Pagando sats")
    │       └── Después: Action.purchaseCompleted → Estado: success
    │
    └── Vendedor recibe: Action.holdInvoicePaymentSettled
        └── Estado: success (inmediatamente)
```

La parte del vendedor está hecha cuando libera, así que ve éxito de inmediato. El comprador debe esperar a que el pago Lightning realmente complete.

### Ciclo de Fallo de Pago (Solo Comprador)

> ⚠️ **Nota v2:** `paymentFailed` es una notificación de Acción, NO un estado. La orden permanece en `settled-hold-invoice` durante todo este ciclo.

```text
Action.released → settledHoldInvoice ("Pagando sats")
    │
    └── Pago LN falla
        │
        Action.paymentFailed → settledHoldInvoice (estado sin cambio, mostrar notificación)
            │
            └── Mostro reintenta automáticamente (hasta N veces)
                │
                ├── Éxito: Action.purchaseCompleted → success
                │
                └── Todos los reintentos fallan:
                    Action.addInvoice → settledHoldInvoice (comprador provee nuevo invoice)
                        │
                        └── Mostro paga nuevo invoice → success
```

## Flujo de Restauración

Cuando la app restaura sesiones después de reinicio, recibe órdenes con un estado pero sin acción. El método `_getActionFromStatus()` en `restore_manager.dart` sintetiza la acción apropiada basada en el estado y el rol del usuario.

| Estado | Acción Comprador | Acción Vendedor |
|--------|------------------|-----------------|
| `pending` | `newOrder` | `newOrder` |
| `waitingBuyerInvoice` | `addInvoice` | `waitingBuyerInvoice` |
| `waitingPayment` | `waitingSellerToPay` | `payInvoice` |
| `active` | `holdInvoicePaymentAccepted` | `buyerTookOrder` |
| `fiatSent` | `fiatSentOk` | `fiatSentOk` |
| `settledHoldInvoice` | `released` | `holdInvoicePaymentSettled` |
| `success` | `purchaseCompleted` | `purchaseCompleted` |
| `canceled` | `canceled` | `canceled` |
| `canceledByAdmin` | `adminCanceled` | `adminCanceled` |
| `cooperativelyCanceled` | `cooperativeCancelAccepted` | `cooperativeCancelAccepted` |
| `settledByAdmin` | `adminSettled` | `adminSettled` |
| `completedByAdmin` | `adminSettled` | `adminSettled` |
| `dispute` | `disputeInitiatedByPeer` | `disputeInitiatedByPeer` |
| `expired` | `canceled` | `canceled` |
| `inProgress` | `buyerTookOrder` | `buyerTookOrder` |

La diferenciación por rol en restauración es crítica para `settledHoldInvoice`: el comprador ve el estado intermedio "Pagando sats", mientras el vendedor ve éxito.

## Presentación en UI

Los estados se muestran en dos contextos con diferentes niveles de detalle.

### Lista de Mis Trades (Labels Cortos)

Los chips de estado en la lista de trades usan labels cortos para display compacto:

| Estado | Label | Color |
|--------|-------|-------|
| `active` | Activo | Verde |
| `pending` | Pendiente | Amarillo |
| `waitingPayment` | Esperando pago | Naranja |
| `waitingBuyerInvoice` | Esperando invoice | Naranja |
| `fiatSent` | Fiat enviado | Verde |
| `canceled` | Cancelado | Gris |
| `cooperativelyCanceled` | Cancelando | Naranja |
| `canceledByAdmin` | Cancelado | Gris |
| `settledByAdmin` | Liquidado | Verde |
| `settledHoldInvoice` | Pagando sats | Amarillo |
| `completedByAdmin` | Completado | Verde |
| `dispute` | Disputa | Rojo |
| `expired` | Expirado | Gris |
| `success` | Éxito | Verde |

### Detalles de Orden (Labels Descriptivos)

La pantalla de Detalles de Orden muestra labels descriptivos, amigables al usuario:

| Estado | Label |
|--------|-------|
| `active` | Orden activa |
| `pending` | Orden pendiente |
| `waitingPayment` | Esperando pago del vendedor |
| `waitingBuyerInvoice` | Esperando invoice del comprador |
| `fiatSent` | Fiat enviado |
| `canceled` | Orden cancelada |
| `cooperativelyCanceled` | Cancelación cooperativa |
| `canceledByAdmin` | Orden cancelada por un administrador |
| `settledByAdmin` | Sats liberados por un administrador |
| `settledHoldInvoice` | Pagando sats |
| `completedByAdmin` | Sats liberados por un administrador |
| `dispute` | Orden en disputa |
| `expired` | Orden expirada |
| `success` | Orden exitosa |

Todos los labels están localizados en inglés, español, italiano y francés.

## Decisiones Clave de Diseño

### Por Qué `released` Mapea a `settledHoldInvoice` en Lugar de `success`

Cuando el vendedor libera sats, el pago Lightning al comprador no ha completado aún. Mapear `released` a `success` daba al comprador una falsa sensación de completación. Si el pago subsecuentemente fallaba, el comprador ya había visto "Éxito" lo cual era incorrecto. El estado intermedio `settledHoldInvoice` ("Pagando sats") refleja con precisión el estado: los sats están siendo pagados pero no recibidos aún.

El vendedor ve `success` inmediatamente porque recibe `holdInvoicePaymentSettled`, no `released`. Su parte del trade está completa.

### Manejo de Acción `paymentFailed` (Nota v2)

> ⚠️ **Comportamiento v1 (deprecated):** v1 creó un estado `paymentFailed` solo de UI y lo preservaba cuando `addInvoice` llegaba.
>
> **Comportamiento v2:** `paymentFailed` es una notificación de Acción, no un cambio de estado. La orden permanece en `settled-hold-invoice`. Cuando el comprador recibe `paymentFailed`, mostrar una notificación explicando que el pago falló y Mostro está reintentando. Cuando `addInvoice` llega después de que todos los reintentos fallan, pedir un nuevo invoice mientras permanece en `settled-hold-invoice`.

### Por Qué `cooperativelyCanceled` Tiene un Chip Distinto

En la lista de Mis Trades, `cooperativelyCanceled` muestra "Cancelando" en naranja en lugar de "Cancelado" en gris. Esto es porque `cooperativelyCanceled` es un estado pendiente — una parte inició la cancelación pero la otra no ha aceptado aún. Mostrar "Cancelado" era engañoso ya que la orden no estaba realmente cancelada. El color naranja coincide con otros estados de espera (`waitingPayment`, `waitingBuyerInvoice`) para señalar que todavía se requiere acción del usuario. El estado final `canceled` (de `cooperativeCancelAccepted`) muestra el chip gris "Cancelado".

### Por Qué las Disputas se Auto-Cierran en Estado Terminal en Lugar de Suscribirse a Kind 38386

Mostro publica eventos de disputa actualizados (kind 38386) cuando una disputa se resuelve, pero la app móvil no se suscribe a ese tipo de evento. En su lugar, la app infiere cierre de disputa del estado terminal de la orden. Este enfoque fue elegido porque:

1. **Sin expansión de protocolo** — no se necesitan nuevas suscripciones o tipos de mensaje
2. **Sin cambios de backend** — Mostro ya maneja todo correctamente de su lado
3. **Datos ya disponibles** — `OrderState` mantiene tanto el estado de la orden como el objeto de disputa en `updateWith()`
4. **Lógica simple** — "orden terminada = disputa terminada"

El campo `dispute.action` (`user-completed` vs `cooperative-cancel`) distingue la razón de cierre, siguiendo el mismo patrón usado para resoluciones de admin (`admin-settled` vs `admin-canceled`). Esto permite a la UI mostrar diferentes mensajes tanto en la lista de disputas como en la pantalla de detalle de disputa sin necesitar los datos del evento kind 38386.
