# Pantalla Principal (Referencia v1)

> Pantalla principal: order book público con pestañas, filtros, y shell de navegación.

**Ruta:** `/`  
**Archivo:** `lib/features/home/screens/home_screen.dart`  
**Providers:** `lib/features/home/providers/home_order_providers.dart`

---

## Layout de Pantalla

```
┌─────────────────────────────────────────────────────────┐
│  [☰]      [Mostro Logo 🎉]           [🔔]              │  ← MostroAppBar
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌───────────────────┬───────────────────┐              │
│  │   COMPRAR BTC     │    VENDER BTC     │              │  ← Botones de pestañas
│  │     (azul ███)    │                   │              │
│  └───────────────────┴───────────────────┘              │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │ 🔍 Filtrar                        12 ofertas   │   │  ← Botón de filtro
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  OrderListItem (orden de venta 1)               │   │
│  ├─────────────────────────────────────────────────┤   │
│  │  OrderListItem (orden de venta 2)               │   │
│  ├─────────────────────────────────────────────────┤   │
│  │  OrderListItem (orden de venta 3)               │   │
│  ├─────────────────────────────────────────────────┤   │
│  │  ...                                            │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│                                                  [+]   │  ← AddOrderButton (FAB)
│                                                         │
│  ┌──────────┬────────────────┬──────────┐             │
│  │OrderBook │   Mis Trades   │   Chat   │             │  ← BottomNavBar
│  └──────────┴────────────────┴──────────┘             │
└─────────────────────────────────────────────────────────┘
```

### AppBar

- **Leading:** Icono de menú hamburguesa → alterna `CustomDrawerOverlay`
- **Title:** `AnimatedMostroLogo` (tappable, muestra cara feliz por 500ms)
- **Actions:** `NotificationBellWidget` + 16px de espacio
- **Borde inferior:** 1px blanco @ 10% opacidad

### Drawer Overlay

Todo el body del `HomeScreen` está envuelto en `CustomDrawerOverlay`. El drawer desliza sobre el contenido desde la izquierda (70% del ancho), con un overlay negro @ 30% opacidad detrás.

### Pestañas

Dos pestañas controlan el tipo de orden mostrado:

| Pestaña | Label | Color activo | Comportamiento |
|---------|-------|--------------|----------------|
| COMPRAR BTC | `S.of(context)!.buyBtc` | `AppTheme.buyColor` (`#2563EB`) | Muestra órdenes de venta (makers vendiendo BTC) |
| VENDER BTC | `S.of(context)!.sellBtc` | `AppTheme.sellColor` (`#DC2626`) | Muestra órdenes de compra (makers comprando BTC) |

> **Contraintuitivo:** La pestaña "Comprar BTC" muestra órdenes de venta porque cuando un maker crea una orden de venta, el taker (tú) está comprando BTC. El label de la pestaña es desde la perspectiva del taker.

**Estado:** `homeOrderTypeProvider` (Riverpod `StateProvider<OrderType>`)

**Gesto de swipe:** El swipe horizontal cambia de pestaña:
- Swipe izquierda → `OrderType.buy` (mostrar órdenes de compra)
- Swipe derecha → `OrderType.sell` (mostrar órdenes de venta)

### Botón de Filtro

Debajo de las pestañas, un botón con forma de píldora muestra el estado del filtro y conteo de ofertas:

```
┌─────────────────────────────────────────────────────────┐
│  🔍 Filtrar                         12 ofertas          │
└─────────────────────────────────────────────────────────┘
```

- Tap abre el diálogo `OrderFilter` (`lib/shared/widgets/order_filter.dart`)
- Muestra el conteo total de órdenes filtradas
- Icono: `HeroIcons.funnel` (outline)
- El badge se actualiza cuando cambian los filtros

### Lista de Órdenes

```dart
ListView.builder(
  itemCount: filteredOrders.length,
  padding: const EdgeInsets.only(bottom: 100, top: 6),
  itemBuilder: (context, index) {
    final order = filteredOrders[index];
    return OrderListItem(order: order);
  },
)
```

**Espaciado:** 100px de padding inferior (permite visibilidad del FAB), 6px de padding superior.

**Tap en una orden:** Navega a `/take_sell/:orderId` o `/take_buy/:orderId` dependiendo del tipo de orden. Flujo completo en `.specify/v1-reference/TAKE_ORDER.md`.

### Pull to Refresh

```dart
RefreshIndicator(
  onRefresh: () async {
    ref.refresh(filteredOrdersProvider);
  },
  child: /* lista o estado vacío */,
)
```

> **Nota:** `filteredOrdersProvider` es un `Provider<List<NostrEvent>>` síncrono — `ref.refresh()` retorna el nuevo valor inmediatamente. El callback `async` satisface la firma `Future<void>` de `onRefresh` sin esperar nada.

### Estado Vacío

Cuando `filteredOrders.isEmpty`:

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│                    🔍 (icono search_off)                │
│                                                         │
│           No hay órdenes disponibles                    │
│          Intenta cambiar tus filtros                    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

- Icono: `Icons.search_off`, white30, 48px
- Texto 1: `S.of(context)!.noOrdersAvailable` — white60, 16px
- Texto 2: `S.of(context)!.tryChangingFilters` — white38, 14px, centrado

### FAB (AddOrderButton)

```dart
Positioned(
  bottom: 80 + MediaQuery.of(context).viewPadding.bottom + 16,
  right: 16,
  child: const AddOrderButton(),
)
```

- Posición: 16px desde la derecha, sobre la barra de navegación inferior (80px + área segura inferior + 16px)
- Navega a `/add_order` al hacer tap
- Spec completo: ver `ORDER_CREATION.md`

### Barra de Navegación Inferior

Fija en la parte inferior (80px de altura). Tres pestañas: Order Book, Mis Trades, Chat. Ver `NAVIGATION_ROUTES.md` para spec completo.

---

## Providers

### homeOrderTypeProvider

```dart
final homeOrderTypeProvider = StateProvider<OrderType>((ref) => OrderType.sell);
```

Controla qué pestaña está activa. `OrderType.sell` = pestaña "Comprar BTC" activa (muestra órdenes de venta). `OrderType.buy` = pestaña "Vender BTC" activa (muestra órdenes de compra).

### filteredOrdersProvider

Provider principal de datos. Lee:
- `homeOrderTypeProvider` — determina qué órdenes mostrar (compra vs venta)
- `currencyFilterProvider` — lista de monedas fiat seleccionadas
- `paymentMethodFilterProvider` — lista de métodos de pago seleccionados
- `ratingFilterProvider` — rango de rating min/max `({double min, double max})`
- `premiumRangeFilterProvider` — rango de premium min/max `({double min, double max})`

Retorna una lista filtrada y ordenada de `NostrEvent` (órdenes en status pending).

```dart
final filteredOrdersProvider = Provider<List<NostrEvent>>((ref) {
  final allOrdersAsync = ref.watch(orderEventsProvider);
  final orderType = ref.watch(homeOrderTypeProvider);
  final selectedCurrencies = ref.watch(currencyFilterProvider);
  final selectedPaymentMethods = ref.watch(paymentMethodFilterProvider);
  final ratingRange = ref.watch(ratingFilterProvider);
  final premiumRange = ref.watch(premiumRangeFilterProvider);

  return allOrdersAsync.maybeWhen(
    data: (allOrders) {
      // Ordenar por expiración, filtrar por tipo + status=pending, aplicar filtros del usuario
      return filtered.toList();
    },
    orElse: () => [],
  );
});
```

---

## Carga con Skeleton

La lista de órdenes usa carga shimmer/skeleton mientras se obtienen los datos. El widget `OrderListItem` renderiza placeholders skeleton cuando `order.isSkeleton == true`.

Ver `ARCHITECTURE.md` → sección de Estados de Carga para detalles de implementación del skeleton.

---

## Flujo de Estado

```
Lanzamiento de app
  → firstRunProvider verifica almacenamiento
    → isFirstRun=true → /walkthrough
    → isFirstRun=false → /
      
HomeScreen montado
  → filteredOrdersProvider obtiene order book desde Nostr
  → orderBookProvider se suscribe a eventos kind 38302
  → Las órdenes se actualizan en tiempo real vía eventos Nostr

Usuario hace tap en pestaña
  → homeOrderTypeProvider.set(OrderType.buy|sell)
  → filteredOrdersProvider recomputa
  → ListView se reconstruye

Usuario hace tap en filtro
  → showDialog(OrderFilter)
  → usuario establece filtros
  → orderBookFilterProvider actualiza
  → filteredOrdersProvider recomputa

Usuario hace tap en orden
  → context.push('/take_sell/$orderId') o '/take_buy/$orderId'
  → TakeOrderScreen
  → (flujo de toma detallado en .specify/v1-reference/TAKE_ORDER.md)

Usuario hace tap en FAB
  → context.push('/add_order')
  → AddOrderScreen

Usuario hace swipe derecha en contenido
  → homeOrderTypeProvider = OrderType.sell

Usuario hace swipe izquierda en contenido
  → homeOrderTypeProvider = OrderType.buy
```

---

## Colores del Tema

| Elemento | Color | Hex |
|----------|-------|-----|
| Fondo | `AppTheme.backgroundDark` | `#0D0F14` |
| Fondo de lista | `AppTheme.dark1` | `#141720` |
| Fondo de input/botón | `AppTheme.backgroundInput` | `#1E2230` |
| Pestaña COMPRAR activa | `AppTheme.buyColor` | `#2563EB` |
| Pestaña VENDER activa | `AppTheme.sellColor` | `#DC2626` |
| Texto inactivo | `AppTheme.textInactive` | `#6B7280` |
| Borde | blanco @ 10% | — |
| Fondo de AppBar | `AppTheme.backgroundDark` | `#0D0F14` |
| Fondo de NavBar | `AppTheme.backgroundNavBar` | — |

---

## Referencias Cruzadas

- **Navegación y Rutas:** `.specify/v1-reference/NAVIGATION_ROUTES.md`
- **Menú Drawer:** `.specify/v1-reference/DRAWER_MENU.md`
- **Order Book:** `.specify/v1-reference/ORDER_BOOK.md`
- **Creación de Orden:** `.specify/v1-reference/ORDER_CREATION.md`
- **Tomar Orden:** `.specify/v1-reference/TAKE_ORDER.md`
- **Componente AppBar:** `lib/shared/widgets/mostro_app_bar.dart`
- **Item de lista de órdenes:** `lib/features/home/widgets/order_list_item.dart`
- **Filtro de órdenes:** `lib/shared/widgets/order_filter.dart`
- **Nav inferior:** `lib/shared/widgets/bottom_nav_bar.dart`
