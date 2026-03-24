# Order Book (Referencia v1)

> Visualización del order book público y pantalla de Mis Trades.

**Order book público:** `lib/features/home/screens/home_screen.dart` (pestaña principal)  
**Mis trades:** `lib/features/trades/screens/trades_screen.dart` (ruta `/order_book`)  
**Item de lista de orden:** `lib/features/home/widgets/order_list_item.dart`  
**Modelo de orden:** `lib/data/models/order.dart`  
**Widget de filtro:** `lib/shared/widgets/order_filter.dart`

---

## Dos Contextos de Order Book

Mostro v1 separa el order book público de los trades personales del usuario:

| Contexto | Ruta | Pantalla | Fuente de datos |
|----------|------|----------|-----------------|
| Order book público | `/` | `HomeScreen` | Todas las pubkeys, filtrado por fiat + método de pago |
| Mis trades | `/order_book` | `TradesScreen` | Solo trades de la pubkey del usuario |

---

## Order Book Público (HomeScreen)

### Flujo de Datos

```dart
// lib/features/home/providers/home_order_providers.dart
final orderBookProvider = StreamProvider<List<Order>>((ref) {
  // Se suscribe a eventos Nostr kind 38302 de todas las pubkeys
  // Retorna todas las órdenes, ordenadas por created_at DESC
});

final orderBookFilterProvider = StateNotifierProvider<OrderBookFilterNotifier, OrderBookFilter>((ref) {
  return OrderBookFilterNotifier();
});

final filteredOrdersProvider = Provider<List<NostrEvent>>((ref) {
  final allOrdersAsync = ref.watch(orderEventsProvider);
  final orderType = ref.watch(homeOrderTypeProvider);
  final selectedCurrencies = ref.watch(currencyFilterProvider);
  final selectedPaymentMethods = ref.watch(paymentMethodFilterProvider);
  final ratingRange = ref.watch(ratingFilterProvider);
  final premiumRange = ref.watch(premiumRangeFilterProvider);
  // Retorna solo órdenes con status=pending, filtradas y ordenadas por expiración
  return allOrdersAsync.maybeWhen(
    data: (allOrders) { /* lógica de filtro */ return []; },
    orElse: () => [],
  );
});
```

### Providers de Filtro

No hay una única clase `OrderBookFilter`. Los filtros son instancias individuales de `StateProvider`:

```dart
// lib/features/home/providers/home_order_providers.dart
final currencyFilterProvider = StateProvider<List<String>>((ref) => []);
final paymentMethodFilterProvider = StateProvider<List<String>>((ref) => []);
final ratingFilterProvider = StateProvider<({double min, double max})>((ref) => (min: 0.0, max: 5.0));
final premiumRangeFilterProvider = StateProvider<({double min, double max})>((ref) => (min: -10.0, max: 10.0));
```

### Filtros Aplicados

El `filteredOrdersProvider` aplica estos filtros a órdenes con `status == pending`:

1. **Tipo de orden** (`homeOrderTypeProvider`): `OrderType.sell` → muestra órdenes de venta del maker (taker compra). `OrderType.buy` → muestra órdenes de compra del maker (taker vende).

2. **Moneda fiat** (`currencyFilterProvider`): lista multi-select. Si no está vacía, solo pasan órdenes cuya `currency` está en la lista seleccionada.

3. **Método de pago** (`paymentMethodFilterProvider`): lista multi-select. Si no está vacía, solo pasan órdenes cuya lista `paymentMethods` contiene algún método seleccionado (coincidencia de substring, case-insensitive).

4. **Rango de rating** (`ratingFilterProvider`): `{min: 0.0, max: 5.0}`. Filtra órdenes cuyo `rating.totalRating` está dentro del rango. Se aplica solo cuando el rango difiere del default.

5. **Rango de premium** (`premiumRangeFilterProvider`): `{min: -10.0, max: 10.0}`. Filtra órdenes cuyo `premium` (parseado como double) está dentro del rango. Se aplica solo cuando el rango difiere del default.

### Persistencia de Filtros

Los providers de filtro son Riverpod `StateProvider` — el estado persiste dentro de la sesión pero se resetea al reiniciar la app (no se almacena en disco).

### Ordenamiento de Órdenes

Las órdenes se ordenan por `expirationDate` ascendente, luego se invierte — así las órdenes que expiran pronto aparecen primero en la lista (las que expiran más urgentemente arriba).

---

## Item de Lista de Orden

**Archivo:** `lib/features/home/widgets/order_list_item.dart`

Cada orden en el order book se renderiza como un `OrderListItem`:

```text
┌─────────────────────────────────────────────────────────────┐
│  ● ●●●  NickVendedor   ★4.8(24)                            │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                                             │
│  Pago: Transferencia Bancaria    Premium: +5%               │
│  Rango: $10 - $100               SATS: 250,000              │
│                                                             │
│  🟢 En línea                                              │  ← Indicador de estado del vendedor
└─────────────────────────────────────────────────────────────┘
```

### Campos Mostrados

| Campo | Fuente | Notas |
|-------|--------|-------|
| Avatar | Perfil de usuario | Círculo coloreado con iniciales o imagen de avatar |
| Nick | búsqueda de `order.maker_pubkey` | Del perfil de usuario (NIP-05 o solo hex) |
| Rating | `total_rating` del perfil de usuario | Rating de estrellas + conteo de reseñas |
| Método de pago | `order.payment_method` | String del protocolo |
| Rango de monto | `order.amount` (min-max) | Rango de monto fiat |
| Premium | `order.premium` | Porcentaje (+/-), coloreado verde/rojo |
| SATS | Calculado | `fiat_amount / exchange_rate * 100000000`, redondeado |
| Estado | `order.status` | Indicador de en línea para vendedor |

### Indicador de Estado

El estado en línea del vendedor se determina por si su conexión Nostr está activa. El `OrderListItem` muestra un punto verde si el vendedor está actualmente conectado a los relays Nostr.

### Cálculo de SATS

```dart
sats = (order.fiat_amount / current_exchange_rate) * 100_000_000
```

La tasa de cambio se obtiene de la API de precios (configurada en settings). El monto de sats mostrado es aproximado — el monto exacto se calcula al momento del trade.

### Estados

| Estado | Render |
|--------|--------|
| Cargando | Shimmer skeleton (placeholder animado) |
| Datos | Widget `OrderListItem` completo |
| Error | No se muestra individualmente — error a nivel de provider |
| Vacío | `Center` con icono + texto "No hay órdenes disponibles" |

### Navegación al Tap

```dart
InkWell(
  onTap: () {
    if (order.kind == 'sell') {
      context.push('/take_sell/${order.id}');
    } else {
      context.push('/take_buy/${order.id}');
    }
  },
)
```

- Orden de venta (maker vendiendo BTC) → `/take_sell/:orderId` (taker compra BTC)
- Orden de compra (maker comprando BTC) → `/take_buy/:orderId` (taker vende BTC)
- Flujo completo de toma: `.specify/v1-reference/TAKE_ORDER.md`

---

## Mis Trades (`/order_book`)

Este documento ahora se enfoca en el order book público. Para una especificación completa de la pantalla de Mis Trades (ruta `/order_book`, `TradesScreen`, filtro de status, items de lista, providers, refresh y navegación), ver `.specify/v1-reference/MY_TRADES.md`.

---

## Diálogo de Filtro de Orden

**Archivo:** `lib/shared/widgets/order_filter.dart`

Se dispara desde `HomeScreen` vía:

```dart
showDialog<void>(
  context: context,
  builder: (context) => const Dialog(child: OrderFilter()),
)
```

### Campos de Filtro

El diálogo `OrderFilter` lee y escribe los providers de filtro individuales:

| Provider | Tipo | Default | Unidad |
|----------|------|---------|--------|
| `currencyFilterProvider` | `List<String>` | `[]` (todos) | Códigos de moneda fiat |
| `paymentMethodFilterProvider` | `List<String>` | `[]` (todos) | Nombres de método de pago |
| `ratingFilterProvider` | `({double min, double max})` | `(0.0, 5.0)` | Rating de estrellas |
| `premiumRangeFilterProvider` | `({double min, double max})` | `(-10.0, 10.0)` | Porcentaje |

### Layout de UI

El diálogo `OrderFilter` contiene:
- **Selector de moneda fiat:** Chips multi-select o dropdown con monedas soportadas
- **Selector de método de pago:** Chips multi-select con métodos de pago disponibles
- **Rango de rating:** Slider para rating de estrellas min/max (0.0–5.0)
- **Rango de premium:** Slider para porcentaje de premium min/max (-10%–+10%)
- **Botón reset:** Limpia todos los filtros (resetea providers a defaults)

### Filtros Disponibles

| Filtro | Provider | Default |
|--------|----------|---------|
| Moneda fiat | `currencyFilterProvider` | Todas las monedas |
| Método de pago | `paymentMethodFilterProvider` | Todos los métodos |
| Rating | `ratingFilterProvider` | 0.0–5.0 estrellas |
| Premium | `premiumRangeFilterProvider` | -10%–+10% |

---

## Referencias Cruzadas

- **HomeScreen:** `.specify/v1-reference/HOME_SCREEN.md`
- **Navegación:** `.specify/v1-reference/NAVIGATION_ROUTES.md`
- **Tomar Orden:** `.specify/v1-reference/TAKE_ORDER.md`
- **Creación de Orden:** `.specify/v1-reference/ORDER_CREATION.md`
- **Estados de Orden:** `.specify/v1-reference/ORDER_STATES.md`
- **Ejecución de Trade:** `.specify/v1-reference/TRADE_EXECUTION.md`
- **Widget de item de lista de orden:** `lib/features/home/widgets/order_list_item.dart`
- **Widget de filtro de orden:** `lib/shared/widgets/order_filter.dart`
- **Pantalla de trades (spec detallado):** `.specify/v1-reference/MY_TRADES.md`
- **Implementación del widget:** `lib/features/trades/screens/trades_screen.dart`
