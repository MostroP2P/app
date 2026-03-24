# Especificación del Sistema de Calificación (Mostro Mobile v1)

> Referencia para la sección 9 (RATING) que cubre la UX de calificación post-trade, acciones del protocolo y visualización de reputación.

## Alcance

- Ruta `/rate_user/:orderId`
- Pantalla y widgets: `RateCounterpartScreen`, `StarRating`
- Servicios y modelos: `MostroService.submitRating()`, `RatingUser`, `Rating`
- Acciones: `Action.rate`, `Action.rateUser`, `Action.rateReceived`
- Visualización de reputación en items del order book (`NostrEvent.rating`)

## Archivos fuente revisados

- `lib/features/rate/rate_counterpart_screen.dart`
- `lib/features/rate/star_rating.dart`
- `lib/services/mostro_service.dart`
- `lib/data/models/rating_user.dart`
- `lib/data/models/rating.dart`
- `lib/data/models/nostr_event.dart`
- `lib/features/order/notfiers/order_notifier.dart`
- `lib/features/order/notfiers/abstract_mostro_notifier.dart`
- `lib/features/order/models/order_state.dart`
- `lib/features/trades/screens/trade_detail_screen.dart`
- `lib/features/home/widgets/order_list_item.dart`
- `lib/features/home/providers/home_order_providers.dart`
- `lib/core/app_routes.dart`
- `lib/core/mostro_fsm.dart`

---

## 1) Puntos de entrada y navegación

### Definición de ruta (`lib/core/app_routes.dart`)

```dart
GoRoute(
  path: '/rate_user/:orderId',
  pageBuilder: (context, state) =>
      buildPageWithDefaultTransition<void>(
          context: context,
          state: state,
          child: RateCounterpartScreen(
            orderId: state.pathParameters['orderId']!,
          )),
),
```

### Cómo los usuarios llegan a la pantalla de calificación

1. **Botones en Trade Detail**: cuando `OrderState.action` es `Action.rate`, `Action.rateUser`, o `Action.rateReceived`, `TradeDetailScreen._buildActionButtons()` renderiza un botón **Calificar** que llama a `context.push('/rate_user/$orderId')`.
2. **Tap en notificación**: `NotificationItem.onTap` verifica las mismas acciones y navega a `/rate_user/$orderId`.
3. No hay navegación automática al recibir `Action.rate` — el usuario debe hacer tap explícitamente.

---

## 2) UX de calificación (`RateCounterpartScreen`)

- Layout centrado simple con título ("Calificar contraparte"), texto de prompt, widget de estrellas, display numérico "X / 5", y botón **Enviar**.
- `StarRating` renderiza 5 estrellas; al hacer tap en una estrella se establece el rating a ese índice + 1. Las estrellas llenas usan `AppTheme.mostroGreen`; las vacías usan `AppTheme.grey2`.
- El botón Enviar está deshabilitado hasta que `_rating > 0`.
- `_submitRating()` loguea el rating, llama a `OrderNotifier.submitRating(_rating)`, y hace pop de la pantalla al completar.

### Flujo de estado

1. Usuario hace tap en una estrella → `_rating` actualizado vía `setState`.
2. Usuario hace tap en Enviar → se llama a `OrderNotifier.submitRating(int)`.
3. `OrderNotifier.submitRating` delega a `MostroService.submitRating(orderId, rating)`.
4. `MostroService.submitRating` envuelve un `MostroMessage(action: Action.rateUser, payload: RatingUser(userRating: rating))` con gift wrap NIP-59 y publica.
5. Mostro confirma con `Action.rateReceived` (no se necesita cambio de status inmediato).

---

## 3) Modelos

### `RatingUser` (`lib/data/models/rating_user.dart`)

Tipo de payload usado al enviar una calificación:

```dart
class RatingUser implements Payload {
  final int userRating; // validado 1..5

  @override
  String get type => 'rating_user';
}
```

El constructor lanza `ArgumentError` si el valor está fuera de 1..5.

### `Rating` (`lib/data/models/rating.dart`)

Snapshot de reputación de solo lectura adjunto a órdenes públicas:

```dart
class Rating {
  final int totalReviews;
  final double totalRating;  // promedio
  final int lastRating;
  final int maxRate;
  final int minRate;
  final int days;            // días desde la primera calificación
}
```

- Deserializado desde array `["rating", {...}]` u objeto JSON plano.
- `Rating.empty()` provee fallback con `totalRating: 0.0`.

### Getter `NostrEvent.rating`

Los eventos de orden (`kind 38383`) pueden llevar un tag `rating`. El getter `NostrEvent.rating` lo deserializa automáticamente, así los widgets pueden mostrar iconos de estrellas basados en `order.rating?.totalRating`.

---

## 4) Acciones y mapeo de status

### Acciones relevantes

| Acción | Origen | Propósito |
|--------|--------|-----------|
| `Action.rate` | Mostro → usuario | Invita al usuario a calificar a la contraparte |
| `Action.rateUser` | Usuario → Mostro | Envía la calificación |
| `Action.rateReceived` | Mostro → usuario | Confirmación de que la calificación fue registrada |

### `OrderState._getStatusFromAction`

```dart
case Action.rate:
case Action.rateReceived:
case Action.holdInvoicePaymentSettled:
  return Status.success;

case Action.rateUser:
  return payloadStatus ?? status; // preserva el actual
```

Todas las acciones de calificación mapean a `Status.success` (el trade ya está completado) y no lo alteran más.

### Disponibilidad de botones (`_roleActionMap`)

Para `Role.buyer` y `Role.seller` en `Status.success`:

```dart
Action.rate: [Action.rate, Action.rateUser, Action.rateReceived, ...],
Action.rateReceived: [],
```

Esto significa que cuando llega una acción `rate`, la UI expone el botón **Calificar**. Después de `rateReceived`, no hay más acciones disponibles.

---

## 5) Visualización en order book

### `OrderListItem._buildRatingRow`

- Parsea `order.rating?.totalRating`, `totalReviews`, y `days`.
- Muestra rating numérico, iconos de 5 estrellas (llenas / medias / vacías), y texto de ayuda ("sin reseñas", "X reseñas • Y días de antigüedad").
- Las estrellas usan lógica fraccional: estrella completa por cada punto entero, media estrella si el resto ≥ 0.5.

### Provider de filtro (`ratingFilterProvider`)

- `StateProvider<({double min, double max})>` con default `(min: 0.0, max: 5.0)`.
- `filteredOrdersProvider` aplica el filtro cuando algún límite difiere de los defaults:

```dart
if (ratingRange.min > 0.0 || ratingRange.max < 5.0) {
  filtered = filtered.where((o) =>
      o.rating != null &&
      o.rating!.totalRating >= ratingRange.min &&
      o.rating!.totalRating <= ratingRange.max);
}
```

La UI del filtro es parte de `HomeScreen` pero está fuera del alcance de este documento.

---

## 6) Manejo de errores y casos borde

| Escenario | Comportamiento |
|-----------|----------------|
| Rating enviado con 0 estrellas | Botón deshabilitado; no puede proceder. |
| Fallo de red durante envío | `publishEvent` lanza excepción; pantalla permanece abierta, usuario puede reintentar. |
| `CantDoReason.invalidRating` | Mostro retorna `cantDo`; `AbstractMostroNotifier` loguea pero no navega. |
| Doble tap en Enviar | UI hace pop después del primer éxito; taps subsecuentes no hacen nada. |

---

## 7) Referencias cruzadas

| Tema | Documento |
|------|-----------|
| Pantalla Trade Detail y botones de acción | [TRADE_EXECUTION.md](./TRADE_EXECUTION.md) |
| Transiciones de status de orden después de completar trade | [ORDER_STATUS_HANDLING.md](./ORDER_STATUS_HANDLING.md) |
| Pantalla principal, lista de órdenes y filtros | [HOME_SCREEN.md](./HOME_SCREEN.md) |
| Tabla de rutas de navegación | [NAVIGATION_ROUTES.md](./NAVIGATION_ROUTES.md) |
