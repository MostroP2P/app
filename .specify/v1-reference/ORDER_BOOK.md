# Order Book (v1 Reference)

> Public order book display and the My Trades screen.

**Public order book:** `lib/features/home/screens/home_screen.dart` (home tab)  
**My trades:** `lib/features/trades/screens/trades_screen.dart` (`/order_book` route)  
**Order list item:** `lib/features/home/widgets/order_list_item.dart`  
**Order model:** `lib/data/models/order.dart`  
**Filter widget:** `lib/shared/widgets/order_filter.dart`

---

## Two Order Book Contexts

Mostro v1 separates the public order book from the user's personal trades:

| Context | Route | Screen | Data source |
|---------|-------|--------|-------------|
| Public order book | `/` | `HomeScreen` | All pubkeys, filtered by fiat + payment method |
| My trades | `/order_book` | `TradesScreen` | User's own pubkey trades only |

---

## Public Order Book (HomeScreen)

### Data Flow

```dart
// lib/features/home/providers/home_order_providers.dart
final orderBookProvider = StreamProvider<List<Order>>((ref) {
  // Subscribes to Nostr kind 38302 events from all pubkeys
  // Returns all orders, sorted by created_at DESC
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
  // Returns only status=pending orders, filtered and sorted by expiration
  return allOrdersAsync.maybeWhen(
    data: (allOrders) { /* filter logic */ return []; },
    orElse: () => [],
  );
});
```

### Filter Providers

There is no single `OrderBookFilter` class. Filters are individual `StateProvider` instances:

```dart
// lib/features/home/providers/home_order_providers.dart
final currencyFilterProvider = StateProvider<List<String>>((ref) => []);
final paymentMethodFilterProvider = StateProvider<List<String>>((ref) => []);
final ratingFilterProvider = StateProvider<({double min, double max})>((ref) => (min: 0.0, max: 5.0));
final premiumRangeFilterProvider = StateProvider<({double min, double max})>((ref) => (min: -10.0, max: 10.0));
```

### Filters Applied

The `filteredOrdersProvider` applies these filters to orders with `status == pending`:

1. **Order type** (`homeOrderTypeProvider`): `OrderType.sell` → show maker's sell orders (taker buys). `OrderType.buy` → show maker's buy orders (taker sells).

2. **Fiat currency** (`currencyFilterProvider`): multi-select list. If non-empty, only orders whose `currency` is in the selected list pass through.

3. **Payment method** (`paymentMethodFilterProvider`): multi-select list. If non-empty, only orders whose `paymentMethods` list contains any selected method (substring match, case-insensitive).

4. **Rating range** (`ratingFilterProvider`): `{min: 0.0, max: 5.0}`. Filters orders whose `rating.totalRating` falls within range. Applied only when range differs from default.

5. **Premium range** (`premiumRangeFilterProvider`): `{min: -10.0, max: 10.0}`. Filters orders whose `premium` (parsed as double) falls within range. Applied only when range differs from default.

### Filter Persistence

Filter providers are Riverpod `StateProvider` — state persists within the session but resets on app restart (not stored to disk).

### Order Sorting

Orders are sorted by `expirationDate` ascending, then reversed — so orders expiring sooner appear first in the list (most urgently expiring at top).

---

## Order List Item

**File:** `lib/features/home/widgets/order_list_item.dart`

Each order in the order book renders as an `OrderListItem`:

```text
┌─────────────────────────────────────────────────────────────┐
│  ● ●●●  SellerNick     ★4.8(24)                            │
│  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━ │
│                                                             │
│  Payment: Bank Transfer          Premium: +5%               │
│  Range: $10 - $100               SATS: 250,000              │
│                                                             │
│  🟢 Online                                                │  ← Seller status indicator
└─────────────────────────────────────────────────────────────┘
```

### Fields Displayed

| Field | Source | Notes |
|-------|--------|-------|
| Avatar | User profile | Colored circle with initials or avatar image |
| Nick | `order.maker_pubkey` lookup | From user profile (NIP-05 or just hex) |
| Rating | User profile `total_rating` | Star rating + review count |
| Payment method | `order.payment_method` | String from protocol |
| Amount range | `order.amount` (min-max) | Fiat amount range |
| Premium | `order.premium` | Percentage (+/-), colored green/red |
| SATS | Calculated | `fiat_amount / exchange_rate * 100000000`, rounded |
| Status | `order.status` | Online indicator for seller |

### Status Indicator

Seller online status is determined by whether their Nostr connection is active. The `OrderListItem` shows a green dot if the seller is currently connected to Nostr relays.

### SATS Calculation

```dart
sats = (order.fiat_amount / current_exchange_rate) * 100_000_000
```

The exchange rate is fetched from the price API (configured in settings). The sats amount shown is approximate — the exact amount is calculated at trade time.

### States

| State | Render |
|-------|--------|
| Loading | Skeleton shimmer (animated placeholder) |
| Data | Full `OrderListItem` widget |
| Error | Not individually shown — error at provider level |
| Empty | `Center` with icon + "No orders available" text |

### Tap Navigation

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

- Sell order (maker selling BTC) → `/take_sell/:orderId` (taker buys BTC)
- Buy order (maker buying BTC) → `/take_buy/:orderId` (taker sells BTC)
- Flujo completo de toma: `.specify/v1-reference/TAKE_ORDER.md`

---

## My Trades (`/order_book`)

**Route:** `/order_book`  
**Screen:** `TradesScreen` (`lib/features/trades/screens/trades_screen.dart`)

The My Trades screen shows orders where the current user is either the maker or the taker. It uses a different provider (`userOrdersProvider`) that filters by the user's pubkey.

### Data Flow

```dart
final userOrdersProvider = StreamProvider<List<Order>>((ref) {
  // Subscribes to kind 38302 events where:
  // - order.maker_pubkey == current_user_pubkey
  // - OR order.taker_pubkey == current_user_pubkey
});
```

### Tab Chips

The `TradesScreen` uses a chip-based filter for order status:

```dart
// lib/features/trades/widgets/order_status_chips.dart
enum OrderStatusFilter {
  all,
  active,       // pending, active
  completed,    // success
  disputed,    // dispute
  canceled,    // canceled, cooperatively_canceled
}
```

Each chip filters the displayed orders by their `status` field.

### Status → Chip Mapping

| Status(es) | Chip label | Color |
|------------|-----------|-------|
| `pending`, `active`, `waiting-buyer-invoice`, `waiting-payment`, `fiat-sent` | Active | `AppTheme.activeColor` |
| `success` | Completed | Green |
| `dispute` | Disputed | Orange |
| `canceled`, `cooperatively-canceled`, `canceled-by-admin` | Canceled | Red |
| (all) | All | Neutral |

### Trade Detail Navigation

```dart
context.push('/trade_detail/$orderId');
```

See `TRADE_EXECUTION.md` for full trade detail screen spec.

---

## Order Filter Dialog

**File:** `lib/shared/widgets/order_filter.dart`

Triggered from `HomeScreen` via:

```dart
showDialog<void>(
  context: context,
  builder: (context) => const Dialog(child: OrderFilter()),
)
```

### Filter Fields

The `OrderFilter` dialog reads and writes the individual filter providers:

| Provider | Type | Default | Unit |
|----------|------|---------|------|
| `currencyFilterProvider` | `List<String>` | `[]` (all) | Fiat currency codes |
| `paymentMethodFilterProvider` | `List<String>` | `[]` (all) | Payment method names |
| `ratingFilterProvider` | `({double min, double max})` | `(0.0, 5.0)` | Star rating |
| `premiumRangeFilterProvider` | `({double min, double max})` | `(-10.0, 10.0)` | Percentage |

### UI Layout

The `OrderFilter` dialog contains:
- **Fiat currency selector:** Multi-select chips or dropdown with supported currencies
- **Payment method selector:** Multi-select chips with available payment methods
- **Rating range:** Slider for min/max star rating (0.0–5.0)
- **Premium range:** Slider for min/max premium percentage (-10%–+10%)
- **Reset button:** Clears all filters (resets providers to defaults)

### Available Filters

| Filter | Provider | Default |
|--------|----------|---------|
| Fiat currency | `currencyFilterProvider` | All currencies |
| Payment method | `paymentMethodFilterProvider` | All methods |
| Rating | `ratingFilterProvider` | 0.0–5.0 stars |
| Premium | `premiumRangeFilterProvider` | -10%–+10% |

---

## Cross-References

- **HomeScreen:** `.specify/v1-reference/HOME_SCREEN.md`
- **Navigation:** `.specify/v1-reference/NAVIGATION_ROUTES.md`
- **Take Order:** `.specify/v1-reference/TAKE_ORDER.md`
- **Order Creation:** `.specify/v1-reference/ORDER_CREATION.md`
- **Order States:** `.specify/v1-reference/ORDER_STATES.md`
- **Trade Execution:** `.specify/v1-reference/TRADE_EXECUTION.md`
- **Order list item widget:** `lib/features/home/widgets/order_list_item.dart`
- **Order filter widget:** `lib/shared/widgets/order_filter.dart`
- **Trades screen:** `lib/features/trades/screens/trades_screen.dart`
