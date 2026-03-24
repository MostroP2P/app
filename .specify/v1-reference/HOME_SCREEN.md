# Home Screen (v1 Reference)

> Main screen: public order book with tabs, filters, and navigation shell.

**Route:** `/`  
**File:** `lib/features/home/screens/home_screen.dart`  
**Providers:** `lib/features/home/providers/home_order_providers.dart`

---

## Screen Layout

```
┌─────────────────────────────────────────────────────────┐
│  [☰]      [Mostro Logo 🎉]           [🔔]              │  ← MostroAppBar
├─────────────────────────────────────────────────────────┤
│                                                         │
│  ┌───────────────────┬───────────────────┐              │
│  │      BUY BTC      │      SELL BTC     │              │  ← Tab buttons
│  │     (blue ███)   │                   │              │
│  └───────────────────┴───────────────────┘              │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │ 🔍 Filter                          12 offers  │   │  ← Filter button
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│  ┌─────────────────────────────────────────────────┐   │
│  │  OrderListItem (sell order 1)                   │   │
│  ├─────────────────────────────────────────────────┤   │
│  │  OrderListItem (sell order 2)                   │   │
│  ├─────────────────────────────────────────────────┤   │
│  │  OrderListItem (sell order 3)                   │   │
│  ├─────────────────────────────────────────────────┤   │
│  │  ...                                            │   │
│  └─────────────────────────────────────────────────┘   │
│                                                         │
│                                                  [+]   │  ← AddOrderButton (FAB)
│                                                         │
│  ┌──────────┬────────────────┬──────────┐             │
│  │OrderBook │   My Trades    │   Chat   │             │  ← BottomNavBar
│  └──────────┴────────────────┴──────────┘             │
└─────────────────────────────────────────────────────────┘
```

### AppBar

- **Leading:** Hamburger menu icon → toggles `CustomDrawerOverlay`
- **Title:** `AnimatedMostroLogo` (tappable, shows happy face for 500ms)
- **Actions:** `NotificationBellWidget` + 16px spacing
- **Bottom border:** 1px white @ 10% opacity

### Drawer Overlay

The entire `HomeScreen` body is wrapped in `CustomDrawerOverlay`. The drawer slides over the content from the left (70% width), with a black @ 30% opacity overlay behind it.

### Tabs

Two tabs control the displayed order type:

| Tab | Label | Active color | Behavior |
|-----|-------|-------------|----------|
| BUY BTC | `S.of(context)!.buyBtc` | `AppTheme.buyColor` (`#2563EB`) | Shows sell orders (makers selling BTC) |
| SELL BTC | `S.of(context)!.sellBtc` | `AppTheme.sellColor` (`#DC2626`) | Shows buy orders (makers buying BTC) |

> **Counterintuitive:** "Buy BTC" tab shows sell orders because when a maker creates a sell order, the taker (you) is buying BTC. The tab label is from the taker's perspective.

**State:** `homeOrderTypeProvider` (Riverpod `StateProvider<OrderType>`)

**Swipe gesture:** Horizontal swipe changes tabs:
- Swipe left → `OrderType.buy` (show buy orders)
- Swipe right → `OrderType.sell` (show sell orders)

### Filter Button

Below tabs, a pill-shaped button shows filter status and offer count:

```
┌─────────────────────────────────────────────────────────┐
│  🔍 Filter                          12 offers            │
└─────────────────────────────────────────────────────────┘
```

- Tapping opens `OrderFilter` dialog (`lib/shared/widgets/order_filter.dart`)
- Shows total count of filtered orders
- Icon: `HeroIcons.funnel` (outline)
- Badge count updates when filters change

### Order List

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

**Spacing:** 100px bottom padding (allows FAB visibility), 6px top padding.

**Tapping an order:** Navigates to `/take_sell/:orderId` or `/take_buy/:orderId` depending on the order type.

### Pull to Refresh

```dart
RefreshIndicator(
  onRefresh: () async {
    return await ref.refresh(filteredOrdersProvider);
  },
  child: /* list or empty state */,
)
```

### Empty State

When `filteredOrders.isEmpty`:

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│                    🔍 (search_off icon)                 │
│                                                         │
│              No orders available                        │
│            Try changing your filters                     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

- Icon: `Icons.search_off`, white30, 48px
- Text 1: `S.of(context)!.noOrdersAvailable` — white60, 16px
- Text 2: `S.of(context)!.tryChangingFilters` — white38, 14px, centered

### FAB (AddOrderButton)

```dart
Positioned(
  bottom: 80 + MediaQuery.of(context).viewPadding.bottom + 16,
  right: 16,
  child: const AddOrderButton(),
)
```

- Position: 16px from right, above bottom nav bar (80px + safe area bottom + 16px)
- Navigates to `/add_order` on tap
- Full spec: see `ORDER_CREATION.md`

### Bottom Nav Bar

Fixed at bottom (80px height). Three tabs: Order Book, My Trades, Chat. See `NAVIGATION_ROUTES.md` for full spec.

---

## Providers

### homeOrderTypeProvider

```dart
final homeOrderTypeProvider = StateProvider<OrderType>((ref) => OrderType.sell);
```

Controls which tab is active. `OrderType.sell` = "Buy BTC" tab active (show sell orders). `OrderType.buy` = "Sell BTC" tab active (show buy orders).

### filteredOrdersProvider

Main data provider. Reads:
- `homeOrderTypeProvider` — determines which orders to show
- `orderBookFilterProvider` — fiat currency, payment method, amount range filters

Returns a filtered, sorted list of `Order` models.

```dart
final filteredOrdersProvider = Provider<List<Order>>((ref) {
  final orderType = ref.watch(homeOrderTypeProvider);
  final filter = ref.watch(orderBookFilterProvider);
  final allOrders = ref.watch(orderBookProvider);
  // Filter and return
});
```

---

## Skeleton Loading

The order list uses shimmer/skeleton loading while data is being fetched. The `OrderListItem` widget renders skeleton placeholders when `order.isSkeleton == true`.

See `ARCHITECTURE.md` → Loading States section for skeleton implementation details.

---

## State Flow

```
App launch
  → firstRunProvider checks storage
    → isFirstRun=true → /walkthrough
    → isFirstRun=false → /
      
HomeScreen mounted
  → filteredOrdersProvider fetches order book from Nostr
  → orderBookProvider subscribes to kind 38302 events
  → Orders update in real-time via Nostr events

User taps tab
  → homeOrderTypeProvider.set(OrderType.buy|sell)
  → filteredOrdersProvider recomputes
  → ListView rebuilds

User taps filter
  → showDialog(OrderFilter)
  → user sets filters
  → orderBookFilterProvider updates
  → filteredOrdersProvider recomputes

User taps order
  → context.push('/take_sell/$orderId') or '/take_buy/$orderId'
  → TakeOrderScreen

User taps FAB
  → context.push('/add_order')
  → AddOrderScreen

User swipes right on content
  → homeOrderTypeProvider = OrderType.sell

User swipes left on content
  → homeOrderTypeProvider = OrderType.buy
```

---

## Theme Colors

| Element | Color | Hex |
|---------|-------|-----|
| Background | `AppTheme.backgroundDark` | `#0D0F14` |
| List background | `AppTheme.dark1` | `#141720` |
| Input/button bg | `AppTheme.backgroundInput` | `#1E2230` |
| BUY tab active | `AppTheme.buyColor` | `#2563EB` |
| SELL tab active | `AppTheme.sellColor` | `#DC2626` |
| Inactive text | `AppTheme.textInactive` | `#6B7280` |
| Border | white @ 10% | — |
| AppBar bg | `AppTheme.backgroundDark` | `#0D0F14` |
| NavBar bg | `AppTheme.backgroundNavBar` | — |

---

## Cross-References

- **Navigation & Routing:** `.specify/v1-reference/NAVIGATION_ROUTES.md`
- **Drawer Menu:** `.specify/v1-reference/DRAWER_MENU.md`
- **Order Book:** `.specify/v1-reference/ORDER_BOOK.md`
- **Order Creation:** `.specify/v1-reference/ORDER_CREATION.md`
- **Take Order:** `.specify/v1-reference/TAKE_ORDER.md`
- **AppBar component:** `lib/shared/widgets/mostro_app_bar.dart`
- **Order list item:** `lib/features/home/widgets/order_list_item.dart`
- **Order filter:** `lib/shared/widgets/order_filter.dart`
- **Bottom nav:** `lib/shared/widgets/bottom_nav_bar.dart`
