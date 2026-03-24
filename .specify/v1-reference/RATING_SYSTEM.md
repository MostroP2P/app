# Rating System Specification (Mostro Mobile v1)

> Reference for section 9 (RATING) covering post-trade rating UX, protocol actions, and reputation display.

## Scope

- Route `/rate_user/:orderId`
- Screen & widgets: `RateCounterpartScreen`, `StarRating`
- Services & models: `MostroService.submitRating()`, `RatingUser`, `Rating`
- Actions: `Action.rate`, `Action.rateUser`, `Action.rateReceived`
- Reputation display in order book items (`NostrEvent.rating`)

## Source files reviewed

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

## 1) Entry points & navigation

### Route definition (`lib/core/app_routes.dart`)

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

### How users reach the rating screen

1. **Trade Detail buttons**: when `OrderState.action` is `Action.rate`, `Action.rateUser`, or `Action.rateReceived`, `TradeDetailScreen._buildActionButtons()` renders a **Rate** button that calls `context.push('/rate_user/$orderId')`.
2. **Notification tap**: `NotificationItem.onTap` checks for the same actions and navigates to `/rate_user/$orderId`.
3. There is no automatic navigation upon receiving `Action.rate` — the user must tap explicitly.

---

## 2) Rating UX (`RateCounterpartScreen`)

- Simple centered layout with a title ("Rate counterpart"), a prompt text, a star widget, the numeric "X / 5" display, and a **Submit** button.
- `StarRating` renders 5 stars; tapping a star sets the rating to that index + 1. Filled stars use `AppTheme.mostroGreen`; empty ones use `AppTheme.grey2`.
- The Submit button is disabled until `_rating > 0`.
- `_submitRating()` logs the rating, calls `OrderNotifier.submitRating(_rating)`, and pops the screen on completion.

### State flow

1. User taps a star → `_rating` updated via `setState`.
2. User taps Submit → `OrderNotifier.submitRating(int)` called.
3. `OrderNotifier.submitRating` delegates to `MostroService.submitRating(orderId, rating)`.
4. `MostroService.submitRating` wraps a `MostroMessage(action: Action.rateUser, payload: RatingUser(userRating: rating))` with NIP-59 gift wrap and publishes.
5. Mostro acknowledges with `Action.rateReceived` (no immediate status change needed).

---

## 3) Models

### `RatingUser` (`lib/data/models/rating_user.dart`)

Payload type used when submitting a rating:

```dart
class RatingUser implements Payload {
  final int userRating; // validated 1..5

  @override
  String get type => 'rating_user';
}
```

Constructor throws `ArgumentError` if value is outside 1..5.

### `Rating` (`lib/data/models/rating.dart`)

Read-only reputation snapshot attached to public orders:

```dart
class Rating {
  final int totalReviews;
  final double totalRating;  // average
  final int lastRating;
  final int maxRate;
  final int minRate;
  final int days;            // days since first rating
}
```

- Deserialized from `["rating", {...}]` array or plain JSON object.
- `Rating.empty()` provides fallback with `totalRating: 0.0`.

### `NostrEvent.rating` getter

Order events (`kind 38383`) can carry a `rating` tag. `NostrEvent.rating` getter deserializes it automatically, so widgets can display star icons based on `order.rating?.totalRating`.

---

## 4) Actions & status mapping

### Relevant actions

| Action | Origin | Purpose |
|--------|--------|---------|
| `Action.rate` | Mostro → user | Invite user to rate the counterpart |
| `Action.rateUser` | User → Mostro | Submit the rating |
| `Action.rateReceived` | Mostro → user | Acknowledgement that rating was recorded |

### `OrderState._getStatusFromAction`

```dart
case Action.rate:
case Action.rateReceived:
case Action.holdInvoicePaymentSettled:
  return Status.success;

case Action.rateUser:
  return payloadStatus ?? status; // preserve current
```

All rating actions map to `Status.success` (the trade is already completed) and do not alter it further.

### Button availability (`_roleActionMap`)

For both `Role.buyer` and `Role.seller` at `Status.success`:

```dart
Action.rate: [Action.rate, Action.rateUser, Action.rateReceived, ...],
Action.rateReceived: [],
```

This means when a `rate` action arrives, the UI exposes the **Rate** button. After `rateReceived`, no further actions are available.

---

## 5) Order book display

### `OrderListItem._buildRatingRow`

- Parses `order.rating?.totalRating`, `totalReviews`, and `days`.
- Displays numeric rating, 5-star icons (filled / half / empty), and helper text ("no reviews", "X reviews • Y days old").
- Stars use fractional logic: full star for each whole point, half star if remainder ≥ 0.5.

### Filter provider (`ratingFilterProvider`)

- `StateProvider<({double min, double max})>` defaulting to `(min: 0.0, max: 5.0)`.
- `filteredOrdersProvider` applies the filter when either bound differs from defaults:

```dart
if (ratingRange.min > 0.0 || ratingRange.max < 5.0) {
  filtered = filtered.where((o) =>
      o.rating != null &&
      o.rating!.totalRating >= ratingRange.min &&
      o.rating!.totalRating <= ratingRange.max);
}
```

Filter UI is part of `HomeScreen` but outside the scope of this document.

---

## 6) Error handling & edge cases

| Scenario | Behavior |
|----------|----------|
| Rating submitted with 0 stars | Button disabled; cannot proceed. |
| Network failure during submit | `publishEvent` throws; screen stays open, user may retry. |
| `CantDoReason.invalidRating` | Mostro returns `cantDo`; `AbstractMostroNotifier` logs but does not navigate. |
| Double-tap on Submit | UI pops after first success; subsequent taps no-op. |

---

## 7) Cross references

| Topic | Document |
|-------|----------|
| Trade Detail screen & action buttons | [TRADE_EXECUTION.md](./TRADE_EXECUTION.md) |
| Order status transitions after trade completion | [ORDER_STATUS_HANDLING.md](./ORDER_STATUS_HANDLING.md) |
| Home screen order list & filters | [HOME_SCREEN.md](./HOME_SCREEN.md) |
| Navigation routes table | [NAVIGATION_ROUTES.md](./NAVIGATION_ROUTES.md) |
