# Especificación de Mis Trades (Mostro Mobile v1)

> Referencia para la sección 6 (MIS TRADES) que cubre la pantalla `/order_book`, providers de datos, filtros y navegación.

## Alcance

- Ruta `/order_book`
- Pantalla `TradesScreen`
- Widgets: `StatusFilterWidget`, `TradesList`, `TradesListItem`
- Providers: `filteredTradesWithOrderStateProvider`, `statusFilterProvider`, `sessionNotifierProvider`, `orderNotifierProvider`
- Refresh y manejo de errores
- Integración con navegación inferior

---

## Archivos fuente revisados

- `lib/features/trades/screens/trades_screen.dart`
- `lib/features/trades/widgets/status_filter_widget.dart`
- `lib/features/trades/widgets/trades_list.dart`
- `lib/features/trades/widgets/trades_list_item.dart`
- `lib/features/trades/providers/trades_provider.dart`
- `lib/shared/providers/order_repository_provider.dart`
- `lib/shared/providers/session_notifier_provider.dart`
- `lib/shared/providers/time_provider.dart`
- `lib/shared/widgets/bottom_nav_bar.dart`
- `lib/shared/widgets/custom_drawer_overlay.dart`

---

## 1) Puntos de entrada y navegación

### Definición de ruta (`lib/core/app_routes.dart`)

```dart
GoRoute(
  path: '/order_book',
  builder: (context, state) => const TradesScreen(),
),
```

### Cómo los usuarios llegan a `/order_book`

- **Barra de navegación inferior:** segunda pestaña (`_onItemTapped` índice 1) hace push a `/order_book` y resalta el icono "Mis Trades".
- **Menú drawer:** `CustomDrawerOverlay` envuelve la pantalla para que el drawer lateral pueda saltar a la misma ruta.
- **Navegación programática:** Después del redirect post-auth a `/`, los manejadores de notificaciones de trade (o acciones rápidas) invocan `context.push('/order_book')` para que el usuario llegue directamente a Mis Trades.

`BottomNavBar` también muestra un punto rojo (vía `orderBookNotificationCountProvider`) si hay actualizaciones de trade no vistas.

---

## 2) Flujo de datos y providers

### Streams

1. `orderEventsProvider` (de `order_repository_provider.dart`) emite todas las órdenes abiertas como `NostrEvent`s.
2. `sessionNotifierProvider` almacena sesiones locales por clave `orderId` (rol maker/taker, info del peer, etc.).
3. `orderNotifierProvider(orderId)` mantiene un `OrderState` por orden, actualizado por mensajes de Mostro.

### Provider de lista filtrada

`filteredTradesWithOrderStateProvider` (en `trades_provider.dart`):

1. Observa `orderEventsProvider`, `sessionNotifierProvider`, y `statusFilterProvider`.
2. Copia y ordena todas las órdenes por `expirationDate` ascendente, luego invierte para mostrar las más nuevas primero.
3. Filtra la lista a solo aquellos `orderId`s que existen en sesiones locales (es decir, trades en los que participa el usuario).
4. Observa cada `orderNotifierProvider(orderId)` para que la UI se actualice en tiempo real cuando cambia el estado (status, solicitud de pago, disputas, etc.).
5. Aplica el filtro de status opcional verificando el `OrderState.status` rastreado (hace fallback al status del evento raw si no hay state disponible).

Tipo retornado: `AsyncValue<List<NostrEvent>>` para soportar ramas de `loading` y `error`.

### Provider de filtro de status

`statusFilterProvider = StateProvider<Status?>((_) => null);`
- `null` = sin filtro (mostrar todos los trades).
- De lo contrario, el `Status` seleccionado debe coincidir con `OrderState.status` para cada orden.

---

## 3) Layout de TradesScreen (`lib/features/trades/screens/trades_screen.dart`)

```text
Scaffold
 ├─ MostroAppBar
 ├─ CustomDrawerOverlay
 │   └─ RefreshIndicator (pull to refresh)
 │       └─ Column
 │           ├─ Header ("Mis Trades" + StatusFilterWidget)
 │           └─ Expanded Container
 │               └─ tradesAsync.when(...)
 └─ BottomNavBar
```

### Comportamiento de refresh

`RefreshIndicator.onRefresh`:

```dart
await ref.read(orderRepositoryProvider).reloadData();
ref.invalidate(filteredTradesWithOrderStateProvider);
```

Esto fuerza un nuevo fetch desde los relays Nostr y re-ejecuta el provider de filtro.

### Header

- Label de texto "Mis Trades" (localizado vía `S.of(context)!.myTrades`).
- `StatusFilterWidget` mostrado a la derecha (ver sección 4).

### Estados del contenido

`tradesAsync.when`:

| Estado | UI |
|--------|----|
| `data` | `TradesList(trades: trades)` (lista scrolleable) |
| `loading` | `CircularProgressIndicator` centrado con color `AppTheme.cream1` |
| `error` | Icono (`Icons.error_outline`), texto `errorLoadingTrades`, y botón "Reintentar" que invalida tanto `orderEventsProvider` como `filteredTradesWithOrderStateProvider` |

El contenedor de lista redondea las esquinas superiores y establece un fondo oscuro para separar visualmente del header.

### Drawer y nav inferior

- `CustomDrawerOverlay` mantiene el drawer global accesible (cuenta/configuración/etc.).
- `BottomNavBar` siempre está presente con padding de área segura; mantiene resaltada la pestaña `/order_book` cuando está activa.

---

## 4) StatusFilterWidget (`lib/features/trades/widgets/status_filter_widget.dart`)

- Renderiza un `PopupMenuButton` con el texto del filtro actual: `"Status | Todos"` o `"Status | Activo"`, etc.
- Opciones del popup:
  - `TODOS`
  - `pending`, `waiting-payment`, `waiting-buyer-invoice`
  - `active`
  - `fiat-sent`
  - `success`
  - `canceled`
  - `settled-hold-invoice`
- Seleccionar "Todos" establece el provider a `null`; de lo contrario parsea el string del enum `Status` vía `Status.fromString`.
- Estilo: icono lucide `filter`, pill pequeña con borde.

Este widget no reconstruye la lista manualmente—solo actualiza `statusFilterProvider`, y la cadena de providers maneja el re-filtrado.

---

## 5) TradesList y TradesListItem

### TradesList (`lib/features/trades/widgets/trades_list.dart`)

- Simple `ListView.builder` con padding inferior igual a `MediaQuery.viewPadding.bottom + 16` para que el contenido quede sobre la nav bar.

### TradesListItem (`lib/features/trades/widgets/trades_list_item.dart`)

**Fuentes de datos por fila**
- `timeProvider`: fuerza re-builds cada minuto para mantener countdown/labels frescos.
- `sessionProvider(orderId)`: determina el rol del usuario para este trade (comprador vs vendedor, maker vs taker).
- `orderNotifierProvider(orderId)`: `OrderState` reactivo para chips de status y datos relacionados con pago.
- `currencyCodesProvider` (servicio de exchange) para emojis de bandera.

**Layout**

```text
┌─────────────────────────────────────────────┐
│ Comprando Bitcoin / Vendiendo Bitcoin       │
│ [ChipStatus] [ChipRol] [Chip de premium]    │
│ 🇺🇸 10 - 100 USD                            │
│ Transferencia Bancaria                      │
│                    icono chevron            │
└─────────────────────────────────────────────┘
```

**Chip de status**
- Colores extraídos de `AppTheme` (`statusActiveBackground`, `statusPendingBackground`, etc.).
- Labels localizados vía `S.of(context)` (Activo, Pendiente, Esperando Pago, Esperando Invoice, Pago Fallido, Fiat Enviado, Cancelado, Cancelado Cooperativamente, Liquidado, Disputa, Expirado, Éxito).
- Usa `orderState.status` para mantenerse sincronizado con actualizaciones de Mostro.

**Chip de rol**
- `Creado por ti` si el usuario es el maker (el rol de sesión coincide con el tipo de orden).
- `Tomado por ti` de lo contrario.
- Colores: `AppTheme.createdByYouChip` vs `AppTheme.takenByYouChip`.

**Chip de premium**
- Renderizado cuando `trade.premium` está presente y no es cero.
- Fondo verde para premiums positivos, rojo para descuentos.
- Formato de texto: `+5%` o `-3%`.

**Montos y métodos de pago**
- Emoji de bandera vía `CurrencyUtils.getFlagFromCurrencyData` + rango de monto fiat (ej., `50 - 200 BRL`).
- Métodos de pago unidos por coma; hace fallback a `S.of(context)!.bankTransfer` si la lista está vacía.

**Manejo de tap**

```dart
onTap: () => context.push('/trade_detail/${trade.orderId}');
```

Esto salta directamente al flujo de Trade Detail (ver `TRADE_EXECUTION.md`).

---

## 6) Actualizaciones en tiempo real y sesiones

- **Requisito de sesión:** Solo aparecen trades con sesión local (el usuario es maker o taker). Cuando una orden expira o se cancela, `OrderNotifier` puede eliminar la sesión, removiéndola automáticamente de la lista.
- **Streaming de estado de orden:** Porque cada fila observa `orderNotifierProvider`, el chip de status cambia instantáneamente cuando Mostro emite eventos (ej., de `waiting-payment` → `active` → `fiat-sent`).
- **Notificaciones:** `BottomNavBar` puede resaltar la pestaña de Mis Trades cuando `orderBookNotificationCountProvider > 0`; otras partes de la app incrementan/decrementan este conteo cuando llegan nuevos eventos.

---

## 7) Manejo de error y vacío

- **Lista vacía:** `TradesList` simplemente no renderiza filas, así que el contenedor circundante solo muestra el fondo; no hay widget especial de "estado vacío" en v1.
- **Error de provider:** La rama de error muestra un icono, mensaje, y botón Reintentar que re-fetcha desde los relays.
- **Pull-to-refresh:** Los usuarios siempre pueden arrastrar hacia abajo para forzar una recarga si la lista parece desactualizada.

---

## 8) Referencias cruzadas

- `.specify/v1-reference/ORDER_BOOK.md` – vista general de order books público vs privado.
- `.specify/v1-reference/TRADE_EXECUTION.md` – describe la pantalla `/trade_detail` abierta desde cada fila.
- `.specify/v1-reference/TAKE_ORDER.md` – explica cómo se crean las sesiones al tomar una orden.
- `.specify/v1-reference/NAVIGATION_ROUTES.md` – tabla de rutas (`/order_book`).
- `.specify/v1-reference/README.md` – índice (sección Pantallas y Navegación).
