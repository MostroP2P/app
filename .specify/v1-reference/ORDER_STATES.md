# Especificación de Estados de Orden y Transiciones

> Especificación completa de todos los estados de orden, representación visual y transiciones de estado basadas en acciones del usuario.

## Resumen

Las órdenes de Mostro pasan por un ciclo de vida bien definido con 15 estados posibles. Cada estado se representa visualmente en la lista "Mis Trades" con un chip de estado coloreado, y las transiciones ocurren basadas en acciones del comprador, vendedor o admin.

> Para ver cómo se manifiestan estos estados en las pantallas de ejecución (botones disponibles, countdowns, widgets), consultar `.specify/v1-reference/TRADE_EXECUTION.md`.

## Referencia de Estados de Orden

### 1. PENDING (Pendiente)

**Visual:**
- Chip: Fondo naranja/amarillo (`#854D0E`), texto amarillo (`#FCD34D`)
- Label: "Pendiente"

**Descripción:**
La orden ha sido creada por un vendedor o comprador y está esperando que una contraparte la tome.

**Acciones Disponibles:**
- El creador puede cancelar
- El comprador puede tomar una orden de venta
- El vendedor puede tomar una orden de compra

**Transiciones:**

| Acción | Por | Siguiente Estado |
|--------|-----|------------------|
| `take-sell` | Comprador | `waiting-buyer-invoice` |
| `take-buy` | Vendedor | `waiting-payment` |

> Ver flujo detallado de toma de orden (UI + protocolo + navegación): `.specify/v1-reference/TAKE_ORDER.md`.
| `cancel` | Creador | `canceled` |

---

### 2. WAITING_BUYER_INVOICE (Esperando Invoice del Comprador)

**Visual:**
- Chip: Fondo rojo/naranja (`#7C2D12`), texto naranja (`#FED7AA`)
- Label: "Esperando Invoice"

**Descripción:**
El comprador debe proporcionar un invoice Lightning donde quiere recibir los sats. Este estado ocurre en diferentes puntos dependiendo del tipo de orden:
- **Orden de venta**: Inmediatamente después de que el comprador toma la orden (comprador toma → waitingBuyerInvoice)
- **Orden de compra**: Después de que el vendedor paga el hold invoice (vendedor paga → waitingBuyerInvoice)

> ⚠️ **Transiciones dependientes del tipo de orden**: El siguiente estado después de `add-invoice` depende del tipo de orden:
> - **Orden de venta**: `add-invoice` → `waiting-payment` (el vendedor aún necesita pagar el hold invoice)
> - **Orden de compra**: `add-invoice` → `active` (el vendedor ya pagó el hold invoice, el trade ahora está activo)

**Acciones Disponibles:**
- El comprador puede enviar invoice
- Cualquiera de las partes puede cancelar

> ⚠️ **Disputa no disponible:** Las disputas solo pueden iniciarse cuando la orden está en estado `active` o `fiat-sent`.

**Transiciones:**

| Acción | Por | Siguiente Estado (Orden Venta) | Siguiente Estado (Orden Compra) |
|--------|-----|--------------------------------|--------------------------------|
| `add-invoice` | Comprador | `waiting-payment` | `active` |
| `cancel` (comprador) | Comprador | `pending` (taker) | `canceled` (creador) |
| `cancel` (vendedor) | Vendedor | `canceled` (creador) | `pending` (taker) |

> **El comportamiento de cancelar depende del rol en la orden:** Cuando el taker cancela, la orden vuelve a `pending` y se republica para una nueva contraparte. Cuando el creador cancela, la orden queda `canceled` permanentemente.
> **Comportamiento de timeout:** Si la parte esperada no actúa dentro de `expiration_seconds` (publicado en el evento de instancia Mostro kind `38385`), Mostro automáticamente aplica la misma lógica de cancelar: si el taker no respondió, la orden vuelve a `pending`; si el creador no respondió, la orden queda `canceled`.

---

### 3. WAITING_PAYMENT (Esperando Pago)

**Visual:**
- Chip: Fondo rojo/naranja (`#7C2D12`), texto naranja (`#FED7AA`)
- Label: "Esperando Pago"

**Descripción:**
El vendedor debe pagar el hold invoice para bloquear los sats en escrow.

> ⚠️ **Transiciones dependientes del tipo de orden**: El siguiente estado después de `pay-invoice` depende del tipo de orden:
> - **Orden de venta** (vendedor creó): `pay-invoice` → `active` (hold invoice pagado, comprador ya proveyó invoice)
> - **Orden de compra** (comprador creó): `pay-invoice` → `waiting-buyer-invoice` (hold invoice pagado, ahora esperando que comprador provea su invoice LN de recepción)

**Acciones Disponibles:**
- El vendedor puede pagar el hold invoice
- Cualquiera de las partes puede cancelar

> ⚠️ **Disputa no disponible:** Las disputas solo pueden iniciarse cuando la orden está en estado `active` o `fiat-sent`.

**Transiciones:**

| Acción | Por | Siguiente Estado (Orden Venta) | Siguiente Estado (Orden Compra) |
|--------|-----|--------------------------------|--------------------------------|
| `pay-invoice` | Vendedor | `active` | `waiting-buyer-invoice` |
| `cancel` (comprador) | Comprador | `pending` (taker) | `canceled` (creador) |
| `cancel` (vendedor) | Vendedor | `canceled` (creador) | `pending` (taker) |

---

### 4. ACTIVE (Activo)

**Visual:**
- Chip: Fondo azul (`#1E3A8A`), texto azul (`#93C5FD`)
- Label: "Activo"

**Descripción:**
Los sats están bloqueados en escrow (hold invoice pagado). El comprador ahora debe enviar el fiat al vendedor. Este es el estado principal de trading.

**Acciones Disponibles:**
- El comprador puede marcar fiat como enviado
- Cualquiera de las partes puede solicitar cancelación cooperativa (ver sección 9)
- Cualquiera de las partes puede iniciar disputa

**Transiciones:**

| Acción | Por | Siguiente Estado |
|--------|-----|------------------|
| `fiat-sent` | Comprador | `fiat-sent` |
| `cancel` | Cualquiera | `active` (cancelación cooperativa solicitada — ver sección 9) |
| `cancel` | Ambas partes | `canceled` |
| `dispute` | Cualquiera | `dispute` |

> **Cancelación cooperativa:** En estado `active`, cancelar no es unilateral. Cuando una parte envía `cancel`, la orden permanece `active`. Solo cuando la contraparte también envía `cancel`, la orden transiciona a `canceled`.

---

### 5. FIAT_SENT (Fiat Enviado)

**Visual:**
- Chip: Fondo verde (`#065F46`), texto verde (`#6EE7B7`)
- Label: "Fiat Enviado"

**Descripción:**
El comprador ha marcado el fiat como enviado. El vendedor debe verificar recepción y liberar los sats del escrow.

**Acciones Disponibles:**
- El vendedor puede liberar sats
- Cualquiera de las partes puede solicitar cancelación cooperativa (ver sección 9)
- Cualquiera de las partes puede iniciar disputa si algo está mal

**Transiciones:**

| Acción | Por | Siguiente Estado |
|--------|-----|------------------|
| `release` | Vendedor | `settled-hold-invoice` |
| `cancel` | Cualquiera | `fiat-sent` (cancelación cooperativa solicitada — ver sección 9) |
| `cancel` | Ambas partes | `canceled` |
| `dispute` | Cualquiera | `dispute` |

---

### 6. SETTLED_HOLD_INVOICE (Hold Invoice Liquidado)

**Visual:**
- Chip: Fondo naranja/amarillo (`#854D0E`), texto amarillo (`#FCD34D`)
- Label: "Liquidado"

**Descripción:**
El vendedor ha liberado los sats. El hold invoice está siendo liquidado y los sats están siendo ruteados al invoice del comprador. Este es normalmente un estado transitorio antes de completar, pero el comprador puede necesitar actuar si el pago Lightning falla.

**Acciones Disponibles:**
- **Vendedor**: Ninguna requerida, pero puede `rate` sin esperar a que complete el pago del comprador
- **Comprador**: `add-invoice` (solo si el pago falla y todos los reintentos se agotan)

**Transiciones:**

| Acción | Por | Siguiente Estado |
|--------|-----|------------------|
| (automático) | Sistema | `success` |
| `rate` | Vendedor | `settled-hold-invoice` |
| `add-invoice` | Comprador | `settled-hold-invoice` |

> **Fallo de pago:** Si el pago Lightning al invoice del comprador falla, Mostro reintenta automáticamente. En el primer fallo, el comprador recibe `payment-failed` con intentos restantes. Si todos los reintentos se agotan, Mostro envía `add-invoice` y el comprador debe proporcionar un nuevo invoice. La orden permanece en `settled-hold-invoice` durante todo el proceso — ver sección "Acción: PAYMENT_FAILED" para detalles.

---

### 7. SUCCESS (Éxito)

**Visual:**
- Chip: Fondo verde (`#065F46`), texto verde (`#6EE7B7`)
- Label: "Éxito"

**Descripción:**
Trade completado exitosamente. Los sats han sido recibidos por el comprador. Ambas partes ahora pueden calificarse mutuamente.

**Acciones Disponibles:**
- Cualquiera de las partes puede calificar a la contraparte

**Transiciones:**

| Acción | Por | Siguiente Estado |
|--------|-----|------------------|
| `rate` | Cualquiera | `success` (permanece, pero flag de calificado establecido) |

---

### 8. CANCELED (Cancelado)

**Visual:**
- Chip: Fondo gris (`#1F2937`), texto gris (`#D1D5DB`)
- Label: "Cancelado"

**Descripción:**
La orden fue cancelada por una parte antes de completar. No se intercambiaron fondos.

**Acciones Disponibles:**
- Ninguna (estado terminal)

---

### 9. COOPERATIVELY_CANCELED (Cancelación Cooperativa)

**Visual:**
- Chip: Fondo rojo/naranja (`#7C2D12`), texto naranja (`#FED7AA`)
- Label: "Cancelando"

**Descripción:**
`cooperativelyCanceled` es un **estado de UI del lado cliente**, no un cambio de estado de orden a nivel de protocolo.

> ⚠️ **Importante:** El protocolo Mostro NO cambia el estado de la orden cuando se solicita una cancelación cooperativa. La orden permanece en su estado actual (`active`, `fiat-sent`, etc.). Mostro solo envía acciones de notificación (`cooperative-cancel-initiated-by-you` / `cooperative-cancel-initiated-by-peer`) para informar a ambas partes.

**Flujo del Protocolo:**
1. Una parte envía `action: "cancel"` a Mostro
2. Mostro envía `cooperative-cancel-initiated-by-you` al solicitante
3. Mostro envía `cooperative-cancel-initiated-by-peer` a la contraparte
4. **El estado de la orden NO cambia** — si estaba `active`, permanece `active`

**Qué Pasa Después:**

| Acción de Contraparte | Resultado |
|-----------------------|-----------|
| Acepta cancelar (envía `cancel`) | Mostro envía `cooperative-cancel-accepted` → orden → `canceled` |
| Envía `fiat-sent` | Trade continúa normalmente → orden → `fiat-sent` |
| Envía `release` | Trade completa → orden → `settled-hold-invoice` |
| Abre `dispute` | Escalado → orden → `dispute` |
| No hace nada | Trade permanece en estado actual, solicitud de cancelar pendiente |

**Display de UI:**
La app muestra el chip "Cancelando" como un **overlay visual** sobre el estado actual para indicar que se solicitó una cancelación, pero el estado subyacente de la orden no ha cambiado.

---

### 10. DISPUTE (Disputa)

**Visual:**
- Chip: Fondo rojo (`#7F1D1D`), texto rojo (`#FCA5A5`)
- Label: "Disputa"

**Descripción:**
Una disputa ha sido iniciada por cualquiera de las partes. Un admin revisará el caso y tomará una resolución.

**Acciones Disponibles:**
- Ambas partes pueden enviar evidencia vía chat
- El vendedor puede `release` (resuelve el trade y auto-cierra la disputa)
- Cualquiera de las partes puede solicitar cancelación cooperativa (ver sección 9)
- Admin puede liquidar (liberar al comprador)
- Admin puede cancelar (devolver al vendedor)

**Transiciones:**

| Acción | Por | Siguiente Estado |
|--------|-----|------------------|
| `admin-settle` | Admin | `settled-by-admin` |
| `admin-cancel` | Admin | `canceled-by-admin` |
| `release` | Vendedor | `settled-hold-invoice` (disputa auto-cerrada) |
| `cancel` | Cualquiera | `dispute` (cancelación cooperativa solicitada) |
| `cancel` | Ambas partes | `canceled` (disputa auto-cerrada) |

---

### 11. SETTLED_BY_ADMIN (Liquidado por Admin)

**Visual:**
- Chip: Fondo púrpura (`#581C87`), texto púrpura (`#C084FC`)
- Label: "Liquidado"

**Descripción:**
Admin resolvió la disputa a favor del comprador. Los sats fueron liberados al comprador.

**Acciones Disponibles:**
- Ninguna (estado terminal)

---

### 12. CANCELED_BY_ADMIN (Cancelado por Admin)

**Visual:**
- Chip: Fondo gris (`#1F2937`), texto gris (`#D1D5DB`)
- Label: "Cancelado"

**Descripción:**
Admin resolvió la disputa a favor del vendedor. Los sats fueron devueltos al vendedor.

**Acciones Disponibles:**
- Ninguna (estado terminal)

---

### 13. COMPLETED_BY_ADMIN (Completado por Admin)

**Visual:**
- Chip: Fondo verde (`#065F46`), texto verde (`#6EE7B7`)
- Label: "Completado"

**Descripción:**
Estado reservado en enum mostro-core. No implementado en el protocolo (no existe acción `admin-complete` en mostrod o docs del protocolo). Mobile v1 lo trata como equivalente a `settled-by-admin`.

**Acciones Disponibles:**
- Ninguna (estado terminal, reservado/no usado)

---

### 14. EXPIRED (Expirado)

**Visual:**
- Chip: Fondo gris (`#1F2937`), texto gris (`#D1D5DB`)
- Label: "Expirado"

**Descripción:**
La orden estaba en estado `pending` y no fue tomada antes de `expires_at` (determinado por Mostro basado en `expiration_hours` publicado en el evento de instancia kind `38385`). Cuando la orden expira, Mostro actualiza el estado del evento reemplazable (kind 38383) a `canceled`.

> **Sin notificación directa:** Mostro no envía un mensaje al creador cuando una orden expira. El cliente detecta expiración observando el evento reemplazable actualizado en los relays.

**Acciones Disponibles:**
- Ninguna (estado terminal)

---

### 15. IN_PROGRESS (En Progreso)

**Visual:**
- Chip: Fondo azul (`#1E3A8A`), texto azul (`#93C5FD`)
- Label: "En Progreso"

**Descripción:**
`in-progress` es un **estado de disputa** (event kind 38386), no un estado de orden. Significa que un admin ha tomado la disputa vía `admin-take-dispute`. La orden misma permanece en estado `dispute`. Mientras la disputa está en `initiated` o `in-progress`, los usuarios aún pueden resolverla ellos mismos vía `release` o cancelación cooperativa, lo cual auto-cierra la disputa. Ver sección 10 (DISPUTE) para todas las transiciones disponibles.

**Transiciones:**

| Acción | Por | Siguiente Estado |
|--------|-----|------------------|
| `admin-settle` | Admin | `settled-by-admin` |
| `admin-cancel` | Admin | `canceled-by-admin` |

---

## Acción: PAYMENT_FAILED (No es un Estado)

> ⚠️ **IMPORTANTE**: `payment-failed` NO es un estado de orden en el protocolo Mostro. Es solo una `Action` enviada como notificación. El estado de la orden NO cambia cuando se recibe esta acción.

**Cuándo sucede:**
Después de que el vendedor libera los sats, Mostro intenta pagar el invoice Lightning del comprador. Si el pago falla:

1. **Primer fallo**: Mostro envía `Action::PaymentFailed` al comprador
   - Payload incluye `payment_attempts` restantes y `payment_retries_interval`
   - Mostro reintentará automáticamente
   - La orden permanece en estado `settled-hold-invoice`

2. **Todos los reintentos agotados**: Mostro envía `Action::AddInvoice` al comprador
   - El comprador debe proporcionar un nuevo invoice Lightning
   - La orden permanece en estado `settled-hold-invoice`

**Puntos clave:**
- `PaymentFailed` se envía al **comprador**, no al vendedor
- El estado de la orden permanece `settled-hold-invoice` durante todo el proceso
- Los sats permanecen bloqueados en escrow hasta que el pago tiene éxito o el admin interviene
- La app mobile v1 creó un estado "PaymentFailed" solo de UI para propósitos de display, pero esto no es un estado del protocolo

---

## Diagramas de Flujo Completos

### Flujo de Orden de Venta (Vendedor Crea, Comprador Toma)

```text
┌──────────┐    takeSell     ┌──────────────────┐
│  PENDING │ ───────────────▶ │ WAITING_BUYER_   │
│          │                  │ INVOICE          │
└──────────┘                  └──────────┬───────┘
                                         │
                                         │ addInvoice
                                         ▼
                              ┌──────────────────┐
                              │ WAITING_PAYMENT  │
                              └──────────┬───────┘
                                         │
                                         │ payInvoice
                                         ▼
                              ┌──────────────────┐
                              │     ACTIVE       │
                              └──────────┬───────┘
                                         │
                                         │ fiatSent
                                         ▼
                              ┌──────────────────┐
                              │    FIAT_SENT     │
                              └──────────┬───────┘
                                         │
                                         │ release
                                         ▼
                              ┌──────────────────┐
                              │ SETTLED_HOLD_    │
                              │ INVOICE          │
                              └──────────┬───────┘
                                         │
                                         │ (auto)
                                         ▼
                              ┌──────────────────┐
                              │     SUCCESS      │
                              └──────────────────┘
```

### Flujo de Orden de Compra (Comprador Crea, Vendedor Toma)

```text
┌──────────┐    takeBuy      ┌──────────────────┐
│  PENDING │ ───────────────▶ │ WAITING_PAYMENT  │
│          │                  │                  │
└──────────┘                  └──────────┬───────┘
                                         │
                                         │ payInvoice
                                         ▼
                              ┌──────────────────┐
                              │ WAITING_BUYER_   │
                              │ INVOICE          │
                              └──────────┬───────┘
                                         │
                                         │ (comprador agrega invoice)
                                         ▼
                              ┌──────────────────┐
                              │     ACTIVE       │
                              └──────────┬───────┘
                                         │
                                         │ fiatSent
                                         ▼
                              ┌──────────────────┐
                              │    FIAT_SENT     │
                              └──────────┬───────┘
                                         │
                                         │ release
                                         ▼
                              ┌──────────────────┐
                              │ SETTLED_HOLD_    │
                              │ INVOICE          │
                              └──────────┬───────┘
                                         │
                                         │ (auto)
                                         ▼
                              ┌──────────────────┐
                              │     SUCCESS      │
                              └──────────────────┘
```

## Colores de Chips de Estado

| Estado | Fondo | Texto | Token de Color Semántico |
|--------|-------|-------|--------------------------|
| `pending` | `#854D0E` (amber-900) | `#FCD34D` (amber-300) | `statusPending` |
| `waiting-buyer-invoice` | `#7C2D12` (orange-900) | `#FED7AA` (orange-200) | `statusWaiting` |
| `waiting-payment` | `#7C2D12` (orange-900) | `#FED7AA` (orange-200) | `statusWaiting` |
| `active` | `#1E3A8A` (blue-900) | `#93C5FD` (blue-300) | `statusActive` |
| `fiat-sent` | `#065F46` (emerald-900) | `#6EE7B7` (emerald-300) | `statusSuccess` |
| `settled-hold-invoice` | `#854D0E` (amber-900) | `#FCD34D` (amber-300) | `statusPending` |
| `success` | `#065F46` (emerald-900) | `#6EE7B7` (emerald-300) | `statusSuccess` |
| `canceled` / `canceled-by-admin` | `#1F2937` (gray-800) | `#D1D5DB` (gray-300) | `statusInactive` |
| `cooperatively-canceled` | `#7C2D12` (orange-900) | `#FED7AA` (orange-200) | `statusWaiting` |
| `dispute` | `#7F1D1D` (red-900) | `#FCA5A5` (red-300) | `statusDispute` |
| `settled-by-admin` | `#581C87` (purple-900) | `#C084FC` (purple-300) | `statusSettled` |
| `completed-by-admin` | `#065F46` (emerald-900) | `#6EE7B7` (emerald-300) | `statusSuccess` |
| `expired` | `#1F2937` (gray-800) | `#D1D5DB` (gray-300) | `statusInactive` |

### Chips de Rol

| Rol | Fondo | Texto |
|-----|-------|-------|
| `createdByYou` | `#1565C0` (blue-800) | Blanco |
| `takenByYou` | `#2DA69D` (teal) | Blanco |

---

## Referencias Cruzadas

- **Flujo de Toma de Orden:** `.specify/v1-reference/TAKE_ORDER.md`
- **Ejecución de Trade:** `.specify/v1-reference/TRADE_EXECUTION.md`
- **Rutas de Navegación:** `.specify/v1-reference/NAVIGATION_ROUTES.md`
- **Order Book / Entrada tap desde Home:** `.specify/v1-reference/ORDER_BOOK.md`, `.specify/v1-reference/HOME_SCREEN.md`
