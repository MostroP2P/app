# My Trades Specification (Mostro Mobile v1)

> Reference for section 6 (MY TRADES) covering the `/order_book` screen, data providers, filters, and navigation.

## Scope

- Route `/order_book`
- Screen `TradesScreen`
- Widgets: `StatusFilterWidget`, `TradesList`, `TradesListItem`
- Providers: `filteredTradesWithOrderStateProvider`, `statusFilterProvider`, `sessionNotifierProvider`, `orderNotifierProvider`
- Refresh & error handling
- Bottom navigation integration

---

## Source files reviewed

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

## 1) Entry points & navigation

### Route definition (`lib/core/app_routes.dart`)

```dart
GoRoute(
  path: '/order_book',
  builder: (context, state) => const TradesScreen(),
),
```

### How users reach `/order_book`

- **Bottom navigation bar:** second tab (`_onItemTapped` index 1) pushes `/order_book` and highlights the "My Trades" icon.
- **Drawer menu:** `CustomDrawerOverlay` wraps the screen so the side drawer can jump to the same route.
- **Programmatic navigation:** `context.push('/order_book')` is invoked after authentication or when tapping notifications relating to user trades.

`BottomNavBar` also shows a red dot (via `orderBookNotificationCountProvider`) if there are unseen trade updates.

---

## 2) Data flow & providers

### Streams

1. `orderEventsProvider` (from `order_repository_provider.dart`) emits all open orders as `NostrEvent`s.
2. `sessionNotifierProvider` stores local sessions keyed by `orderId` (maker/taker role, peer info, etc.).
3. `orderNotifierProvider(orderId)` keeps an `OrderState` per order, updated by Mostro messages.

### Filtered list provider

`filteredTradesWithOrderStateProvider` (in `trades_provider.dart`):

1. Watches `orderEventsProvider`, `sessionNotifierProvider`, and `statusFilterProvider`.
2. Copies and sorts all orders by `expirationDate` ascending, then reverses to show newest first.
3. Filters the list to only those `orderId`s that exist in local sessions (i.e., trades the user participates in).
4. Watches each `orderNotifierProvider(orderId)` so UI updates in real time when state changes (status, payment request, disputes, etc.).
5. Applies the optional status filter by checking the tracked `OrderState.status` (falls back to the raw event status if no state is available).

Returned type: `AsyncValue<List<NostrEvent>>` to support `loading` and `error` branches.

### Status filter provider

`statusFilterProvider = StateProvider<Status?>((_) => null);`
- `null` = no filter (show all trades).
- Otherwise the selected `Status` must match `OrderState.status` for each order.

---

## 3) TradesScreen layout (`lib/features/trades/screens/trades_screen.dart`)

```text
Scaffold
 ├─ MostroAppBar
 ├─ CustomDrawerOverlay
 │   └─ RefreshIndicator (pull to refresh)
 │       └─ Column
 │           ├─ Header ("My Trades" + StatusFilterWidget)
 │           └─ Expanded Container
 │               └─ tradesAsync.when(...)
 └─ BottomNavBar
```

### Refresh behavior

`RefreshIndicator.onRefresh`:

```dart
await ref.read(orderRepositoryProvider).reloadData();
ref.invalidate(filteredTradesWithOrderStateProvider);
```

This forces a new fetch from the Nostr relays and re-runs the filter provider.

### Header

- Text label "My Trades" (localized via `S.of(context)!.myTrades`).
- `StatusFilterWidget` displayed on the right (see section 4).

### Content states

`tradesAsync.when`:

| State | UI |
|-------|----|
| `data` | `TradesList(trades: trades)` (scrollable list) |
| `loading` | Centered `CircularProgressIndicator` with `AppTheme.cream1` color |
| `error` | Icon (`Icons.error_outline`), text `errorLoadingTrades`, and a "Retry" button that invalidates both `orderEventsProvider` and `filteredTradesWithOrderStateProvider` |

The list container rounds the top corners and sets a dark background to visually separate from the header.

### Drawer & bottom nav

- `CustomDrawerOverlay` keeps the global drawer accessible (account/settings/etc.).
- `BottomNavBar` is always present with safe-area padding; it keeps the `/order_book` tab highlighted when active.

---

## 4) StatusFilterWidget (`lib/features/trades/widgets/status_filter_widget.dart`)

- Renders a `PopupMenuButton` with the current filter text: `"Status | All"` or `"Status | Active"`, etc.
- Popup options:
  - `ALL`
  - `pending`, `waiting-payment`, `waiting-buyer-invoice`
  - `active`
  - `fiat-sent`
  - `success`
  - `canceled`
  - `settled-hold-invoice`
- Selecting "All" sets the provider to `null`; otherwise it parses the `Status` enum string via `Status.fromString`.
- Styling: lucide `filter` icon, small pill with border.

This widget does not rebuild the list manually—it just updates `statusFilterProvider`, and the provider chain handles the re-filtering.

---

## 5) TradesList & TradesListItem

### TradesList (`lib/features/trades/widgets/trades_list.dart`)

- Simple `ListView.builder` with bottom padding equal to `MediaQuery.viewPadding.bottom + 16` so content stays above the nav bar.

### TradesListItem (`lib/features/trades/widgets/trades_list_item.dart`)

**Data sources per row**
- `timeProvider`: forces re-builds every minute to keep countdown/labels fresh.
- `sessionProvider(orderId)`: determines the user role for this trade (buyer vs seller, maker vs taker).
- `orderNotifierProvider(orderId)`: reactive `OrderState` for status chips and payment-related data.
- `currencyCodesProvider` (exchange service) for flag emojis.

**Layout**

```text
┌─────────────────────────────────────────────┐
│ Buying Bitcoin / Selling Bitcoin            │
│ [StatusChip] [RoleChip] [Premium chip]      │
│ 🇺🇸 10 - 100 USD                            │
│ Bank Transfer                              │
│                    chevron icon             │
└─────────────────────────────────────────────┘
```

**Status chip**
- Colors pulled from `AppTheme` (`statusActiveBackground`, `statusPendingBackground`, etc.).
- Labels localized via `S.of(context)` (Active, Pending, Waiting Payment, Waiting Invoice, Payment Failed, Fiat Sent, Canceled, Cooperatively Canceled, Settled, Dispute, Expired, Success).
- Uses `orderState.status` to stay in sync with Mostro updates.

**Role chip**
- `Created by you` if the user is the maker (session role matches order kind).
- `Taken by you` otherwise.
- Colors: `AppTheme.createdByYouChip` vs `AppTheme.takenByYouChip`.

**Premium chip**
- Rendered when `trade.premium` is present and non-zero.
- Green background for positive premiums, red for discounts.
- Text format: `+5%` or `-3%`.

**Amounts & payment methods**
- Flag emoji via `CurrencyUtils.getFlagFromCurrencyData` + fiat amount range (e.g., `50 - 200 BRL`).
- Payment methods joined by comma; falls back to `S.of(context)!.bankTransfer` if list is empty.

**Tap handling**

```dart
onTap: () => context.push('/trade_detail/${trade.orderId}');
```

This jumps directly into the Trade Detail flow (see `TRADE_EXECUTION.md`).

---

## 6) Real-time updates & sessions

- **Session requirement:** Only trades with a local session appear (user is either maker or taker). When an order expires or is canceled, `OrderNotifier` may delete the session, automatically removing it from the list.
- **Order state streaming:** Because each row watches `orderNotifierProvider`, the status chip changes instantly when Mostro emits events (e.g., from `waiting-payment` → `active` → `fiat-sent`).
- **Notifications:** `BottomNavBar` can highlight the My Trades tab when `orderBookNotificationCountProvider > 0`; other parts of the app increment/decrement this count when new events arrive.

---

## 7) Error & empty handling

- **Empty list:** `TradesList` simply renders no rows, so the surrounding container shows only the background; there is no special "empty state" widget in v1.
- **Provider error:** Error branch shows an icon, message, and Retry button that re-fetches from relays.
- **Pull-to-refresh:** Users can always drag down to force a reload if the list looks stale.

---

## 8) Cross-references

- `.specify/v1-reference/ORDER_BOOK.md` – overview of public vs. private order books.
- `.specify/v1-reference/TRADE_EXECUTION.md` – describes the `/trade_detail` screen opened from each row.
- `.specify/v1-reference/TAKE_ORDER.md` – explains how sessions are created when taking an order.
- `.specify/v1-reference/NAVIGATION_ROUTES.md` – route table (`/order_book`).
- `.specify/v1-reference/README.md` – index (Screens & Navigation section).
