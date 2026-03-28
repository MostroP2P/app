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

## Order List Item (Order Card)

**File:** `lib/features/home/widgets/order_list_item.dart`
**Screenshot:** https://i.nostr.build/vwXlnPQhL3ROs13b.jpg

Each pending order in the order book renders as a card with rounded corners (~12dp radius) on a dark card background (`AppTheme.backgroundCard`). The card has consistent internal padding and contains 5 rows:

```text
┌──────────────────────────────────────────────────┐
│  SELLING                          a moment ago   │  Row 1: Status pill + timestamp
│                                                  │
│  150 - 230                        PEN  🇵🇪      │  Row 2: Fiat amount + currency + flag
│                                                  │
│  Market Price (+5.0%)                            │  Row 3: Price type + premium
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │ 💳  Yape, Plin                             │  │  Row 4: Payment methods (nested card)
│  └────────────────────────────────────────────┘  │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │ 4.7 ★★★★★     👤 9      📅 142            │  │  Row 5: Stats (nested card)
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

### Row 1: Status Label + Timestamp

| Element | Position | Style |
|---------|----------|-------|
| Status label ("SELLING" / "BUYING") | Left, inside a pill/chip | Uppercase, small font, `textSecondary` color, `backgroundInput` pill background, fully rounded corners |
| Timestamp ("a moment ago", "4 hours ago") | Right-aligned | Small font, `textSecondary` color, relative time format |

### Row 2: Fiat Amount + Currency + Flag

| Element | Position | Style |
|---------|----------|-------|
| Fiat amount or range | Left | Large bold font (biggest text on card), `textPrimary` (white). Shows "150 - 230" for range orders or "2000" for fixed amount |
| Currency code | Right of amount | Medium bold font, `textPrimary` (white), e.g. "PEN", "ARS", "VES" |
| Country flag | Right of currency code | Small flag emoji/icon matching the fiat currency country |

### Row 3: Price Type + Premium

| Element | Position | Style |
|---------|----------|-------|
| Price label | Left | Small font, `textSecondary` color |
| Content varies by price type: | | |
| — Market price with premium | | "Market Price (+5.0%)" — premium value in green (`mostroGreen`) if positive, red if negative |
| — Market price no premium | | "Market Price" |
| — Fixed price | | Shows sats amount |

### Row 4: Payment Methods (Nested Card)

A nested card/container with slightly darker background (`backgroundInput`) and medium rounded corners (~10dp):

| Element | Position | Style |
|---------|----------|-------|
| Payment icon | Left | Small payment app icon or generic card icon in yellow/gold |
| Payment methods list | Right of icon | Medium font, `textPrimary` (white), comma-separated list of methods. Truncated with "..." if too long to fit one line. E.g. "Mercado Pago, MODO, CVU, Belo, Le..." |

### Row 5: Trader Stats (Nested Card)

A nested card/container with same style as Row 4. Contains three data groups spread horizontally:

| Element | Position | Style |
|---------|----------|-------|
| **Rating value** | Left | Medium bold font, `textPrimary` (white), e.g. "4.7" |
| **Star rating** | Right of value | 5 star icons — filled stars in yellow/gold (`AppTheme.yellow`), empty stars in gray outline. Partial fill for fractional ratings (e.g. 4.7 = 4 full + ~70% filled) |
| **Trade count** | Center-right | User silhouette icon (`textSecondary` gray) + count in `textPrimary` (white), e.g. "👤 9" — total number of completed trades |
| **Days active** | Far right | Calendar/grid icon (`textSecondary` gray) + count in `textPrimary` (white), e.g. "📅 142" — days since account creation |

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
- Full take order flow: [TAKE_ORDER.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/TAKE_ORDER.md)

### States

| State | Render |
|-------|--------|
| Loading | Skeleton shimmer (animated placeholder) |
| Data | Full order card as described above |
| Error | Not individually shown — error at provider level |
| Empty | `Center` with icon + "No orders available" text |

---

## My Trades (`/order_book`)

This document focuses on the public order book. For a complete specification of the My Trades screen (route `/order_book`, `TradesScreen`, status filter, list items, providers, refresh, and navigation), see [MY_TRADES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/MY_TRADES.md).

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

---

## Cross-References

- **HomeScreen:** [HOME_SCREEN.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/HOME_SCREEN.md)
- **Navigation:** [NAVIGATION_ROUTES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/NAVIGATION_ROUTES.md)
- **Take Order:** [TAKE_ORDER.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/TAKE_ORDER.md)
- **Order Creation:** [ORDER_CREATION.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_CREATION.md)
- **Order States:** [ORDER_STATES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/ORDER_STATES.md)
- **Trade Execution:** [TRADE_EXECUTION.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/TRADE_EXECUTION.md)
- **My Trades:** [MY_TRADES.md](https://github.com/MostroP2P/app/blob/main/.specify/v1-reference/MY_TRADES.md)
- **Design System:** [DESIGN_SYSTEM.md](https://github.com/MostroP2P/mobile/blob/main/docs/architecture/DESIGN_SYSTEM.md)
