# Navigation & Routes (v1 Reference)

> Complete route map, redirects, deep links, and navigation system.

## Source Code Files

| File | Description |
|------|-------------|
| `lib/core/app_routes.dart` | GoRouter definition with all routes |
| `lib/core/app.dart` | Router initialization, deep links, app lifecycle |
| `lib/core/deep_link_handler.dart` | Deep link handling for mostro: scheme |
| `lib/core/deep_link_interceptor.dart` | Custom scheme interceptor to avoid asserts |
| `lib/services/deep_link_service.dart` | Deep link parsing and navigation service |
| `lib/shared/notifiers/navigation_notifier.dart` | Notifier for programmatic navigation |
| `lib/shared/providers/navigation_notifier_provider.dart` | NavigationNotifier provider |
| `lib/shared/widgets/navigation_listener_widget.dart` | Widget that listens to navigation and calls context.go |

## Navigation System

The app uses **GoRouter** with the following features:
- Routes defined in `createRouter()` inside `app_routes.dart`
- `ShellRoute` that wraps all routes with infrastructure widgets
- Redirects based on authentication state (`firstRunProvider`)
- Deep link interceptors for custom schemes (`mostro:`)

### Router Architecture

```text
MostroApp
├── appInitializerProvider (await initialization)
│   └── MaterialApp.router
│       └── GoRouter
│           ├── navigatorKey: MostroApp.navigatorKey
│           ├── redirect: firstRun check
│           ├── errorBuilder
│           └── ShellRoute (NotificationListener + NavigationListener + LogsIndicator)
│               └── routes[] (all screens)
```

## Complete Routes

### Main Routes (ShellRoute)

| Route | Screen | File | Description |
|-------|--------|------|-------------|
| `/` | `HomeScreen` | `home_screen.dart` | Public order book |
| `/welcome` | `WelcomeScreen` | `welcome_screen.dart` | Welcome screen |
| `/order_book` | `TradesScreen` | `trades_screen.dart` | My trades list (see `.specify/v1-reference/MY_TRADES.md`) |
| `/trade_detail/:orderId` | `TradeDetailScreen` | `trade_detail_screen.dart` | Trade detail (see `.specify/v1-reference/TRADE_EXECUTION.md`) |
| `/chat_list` | `ChatRoomsScreen` | `chat_rooms_list.dart` | Chat hub (see `P2P_CHAT_SYSTEM.md`) |
| `/chat_room/:orderId` | `ChatRoomScreen` | `chat_room_screen.dart` | Trade chat room (see `P2P_CHAT_SYSTEM.md`) |
| `/dispute_details/:disputeId` | `DisputeChatScreen` | `dispute_chat_screen.dart` | Dispute chat (see `DISPUTE_SYSTEM.md`) |
| `/rate_user/:orderId` | `RateCounterpartScreen` | `rate_counterpart_screen.dart` | Post-trade rating (see `RATING_SYSTEM.md`) |
| `/register` | `RegisterScreen` | `register_screen.dart` | Identity registration |
| `/relays` | `RelaysScreen` | `relays_screen.dart` | Relay management |
| `/key_management` | `KeyManagementScreen` | `key_management_screen.dart` | Account, mnemonics |
| `/settings` | `SettingsScreen` | `settings_screen.dart` | General settings |
| `/about` | `AboutScreen` | `about_screen.dart` | About the app |
| `/walkthrough` | `WalkthroughScreen` | `walkthrough_screen.dart` | Initial tutorial |
| `/add_order` | `AddOrderScreen` | `add_order_screen.dart` | Create order (see `.specify/v1-reference/ORDER_CREATION.md`) |
| `/rate_user/:orderId` | `RateCounterpartScreen` | `rate_counterpart_screen.dart` | Rate counterpart |
| `/take_sell/:orderId` | `TakeOrderScreen` | `take_order_screen.dart` | Take sell order (see `.specify/v1-reference/TAKE_ORDER.md`) |
| `/take_buy/:orderId` | `TakeOrderScreen` | `take_order_screen.dart` | Take buy order (see `.specify/v1-reference/TAKE_ORDER.md`) |
| `/order_confirmed/:orderId` | `OrderConfirmationScreen` | `order_confirmation_screen.dart` | Order confirmed |
| `/pay_invoice/:orderId` | `PayLightningInvoiceScreen` | `pay_lightning_invoice_screen.dart` | Pay Lightning invoice (see `.specify/v1-reference/TRADE_EXECUTION.md`) |
| `/add_invoice/:orderId` | `AddLightningInvoiceScreen` | `add_lightning_invoice_screen.dart` | Add Lightning invoice (see `.specify/v1-reference/TRADE_EXECUTION.md`) |
| `/notifications` | `NotificationsScreen` | `notifications_screen.dart` | Notification history |
| `/logs` | `LogsScreen` | `logs_screen.dart` | Diagnostic log |
| `/wallet_settings` | `WalletSettingsScreen` | `wallet_settings_screen.dart` | Wallet settings |
| `/connect_wallet` | `ConnectWalletScreen` | `connect_wallet_screen.dart` | Connect NWC wallet |
| `/notification_settings` | `NotificationSettingsScreen` | `notification_settings_screen.dart` | Notification preferences |

### Route Parameters

| Route | Parameters | Query Params | Extra |
|-------|------------|--------------|-------|
| `/trade_detail/:orderId` | `orderId` (String) | — | — |
| `/chat_room/:orderId` | `orderId` (String) | — | — |
| `/dispute_details/:disputeId` | `disputeId` (String) | — | — |
| `/rate_user/:orderId` | `orderId` (String) | — | — |
| `/take_sell/:orderId` | `orderId` (String) | — | `OrderType.sell` |
| `/take_buy/:orderId` | `orderId` (String) | — | `OrderType.buy` |
| `/order_confirmed/:orderId` | `orderId` (String) | — | — |
| `/pay_invoice/:orderId` | `orderId` (String) | — | — |
| `/add_invoice/:orderId` | `orderId` (String) | `lnAddress` (String?) | — |
| `/add_order` | — | — | `{orderType: 'buy'\|'sell'}` |

## Redirects (Guards)

### First Run Redirect

```dart
redirect: (context, state) {
  // 1. Block custom schemes before GoRouter processes them
  if (state.uri.scheme == 'mostro' ||
      (!state.uri.scheme.startsWith('http') && state.uri.scheme.isNotEmpty)) {
    return '/';  // Redirect to home, deep link processed manually
  }

  // 2. First run check
  final firstRunState = ref.read(firstRunProvider);

  return firstRunState.when(
    data: (isFirstRun) {
      if (isFirstRun && state.matchedLocation != '/walkthrough') {
        return '/walkthrough';  // First time → tutorial
      }
      return null;  // No redirect
    },
    loading: () {
      return state.matchedLocation == '/walkthrough'
          ? null
          : '/walkthrough';  // Loading → go to walkthrough
    },
    error: (_, __) => null,
  );
}
```

### Post-Auth Redirect

In `app.dart`, inside `initAsyncValue.when(data:)`:

```dart
ref.listen<AuthState>(authNotifierProvider, (previous, state) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    if (state is AuthAuthenticated || state is AuthRegistrationSuccess) {
      context.go('/');  // Login/registration success → home
    } else if (state is AuthUnregistered || state is AuthUnauthenticated) {
      context.go('/');  // Logout → home
    }
  });
});
```

## Deep Links

### `mostro:` Scheme

**URL format:**
```text
mostro:order?id={orderId}&relay={relayUrl}&relay={relayUrl2}
```

**Example:**
```text
mostro:order?id=abc123-def456-ghi789&relay=wss://relay.mostro.network&relay=wss://relay2.mostro.network
```

### Deep Link Pipeline

```text
1. Operating system sends deep link
   ↓
2. DeepLinkInterceptor (WidgetsBindingObserver)
   → Detects 'mostro:' or custom scheme
   → Prevents GoRouter from processing the URL (avoids assertion errors)
   → Emits URL to customUrlStream
   ↓
3. app.dart (_initializeDeepLinkInterceptor)
   → Listens to customUrlStream
   → Calls deepLinkHandler.handleInitialDeepLink()
   ↓
4. DeepLinkHandler
   → Parses the URL
   → Calls deepLinkService.processMostroLink()
   ↓
5. DeepLinkService
   → Validates format (NostrUtils.isValidMostroUrl)
   → Parses orderId and relays
   → Fetches NIP-69 event (kind 38383) with tag 'd' = orderId
   → Extracts OrderType from tag 'k'
   → Returns OrderInfo
   ↓
6. DeepLinkHandler._handleMostroDeepLink
   → Shows loading dialog
   → Calls deepLinkService.navigateToOrder()
   ↓
7. DeepLinkService.navigateToOrder()
   → Uses postFrameCallback to navigate
   → router.push('/take_sell/{orderId}') or '/take_buy/{orderId}'
   ↓
8. TakeOrderScreen receives the orderId
```

### Navigation from Deep Link

```dart
String getNavigationRoute(OrderInfo orderInfo) {
  switch (orderInfo.orderType) {
    case OrderType.sell:
      return '/take_sell/${orderInfo.orderId}';  // I want to buy → take sell order
    case OrderType.buy:
      return '/take_buy/${orderInfo.orderId}';   // I want to sell → take buy order
  }
}
```

### Deep Link Error Handling

| Error | Message (i18n) | Action |
|-------|----------------|--------|
| Invalid URL | `deepLinkInvalidFormat` | Error snackbar |
| Parse failure | `deepLinkParseError` | Error snackbar |
| Invalid order ID | `deepLinkInvalidOrderId` | Error snackbar |
| No relays | `deepLinkNoRelays` | Error snackbar |
| Order not found | `deepLinkOrderNotFound` | Error snackbar |
| General error | `failedToOpenOrder` | Error snackbar |

## Programmatic Navigation

### NavigationNotifier

```dart
// Shared provider
final navigationProvider =
    StateNotifierProvider<NavigationNotifier, NavigationState>(
        (ref) => NavigationNotifier());

// Listener widget (in the ShellRoute)
class NavigationListenerWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<NavigationState>(navigationProvider, (previous, next) {
      if (next.path.isNotEmpty) {
        context.go(next.path);  // Imperative navigation
      }
    });
    return child;
  }
}
```

**Usage:**
```dart
// Anywhere in the app
ref.read(navigationProvider.notifier).go('/settings');
```

### Direct Navigation with GoRouter

Most navigation uses `context.push()` or `context.go()` directly:

```dart
// Push (adds to stack, with back button)
context.push('/add_order');
context.push('/take_sell/${order.orderId}');
context.push('/chat_room/${session.orderId}');

// Go (replaces current route, no back button)
context.go('/');

// Push with query params
context.push('/add_invoice/$orderId?lnAddress=user@lnaddress.com');

// Push with extra data
context.push('/add_order', extra: {'orderType': 'buy'});
```

## Navigation from BottomNavBar

The `BottomNavBar` determines the active route by comparing `GoRouterState.of(context).uri.toString()`:

```dart
bool _isActive(BuildContext context, int index) {
  final currentLocation = GoRouterState.of(context).uri.toString();
  switch (index) {
    case 0: return currentLocation == '/';          // Order Book (Home)
    case 1: return currentLocation == '/order_book';  // My Trades
    case 2: return currentLocation == '/chat_list';   // Chat
  }
}
```

**Navigation:**
- Tab 0 → `context.push('/')`
- Tab 1 → `context.push('/order_book')`
- Tab 2 → `context.push('/chat_list')`

**Note:** Uses `context.push()` instead of `context.go()` so it works correctly with the nested ShellRoute navigation.

## Navigation from Drawer

The drawer (`CustomDrawerOverlay`) uses `context.push(route)` for each item:

```dart
_buildMenuItem(...) {
  onTap: () {
    ref.read(drawerProvider.notifier).closeDrawer();
    context.push(route);  // Push instead of go
  },
}
```

## Error Handler

```dart
errorBuilder: (context, state) {
  logger.w('GoRouter error: ${state.error}');
  return Scaffold(
    body: Center(
      child: Column(
        children: [
          Icon(Icons.error, size: 64),
          Text('Navigation Error: ${state.error}'),
          ElevatedButton(
            onPressed: () => context.go('/'),
            child: Text(S.of(context)!.deepLinkGoHome),
          ),
        ],
      ),
    ),
  );
}
```

## Transitions

All routes use `buildPageWithDefaultTransition`:

```dart
CustomTransitionPage buildPageWithDefaultTransition<T>({
  required BuildContext context,
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<T>(
    key: state.pageKey,
    child: child,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurveTween(curve: Curves.easeInOut).animate(animation),
        child: child,
      );
    },
    transitionDuration: const Duration(milliseconds: 150),
  );
}
```

**Transition type:** 150ms ease-in-out fade (no slide).

## App Initialization Flow

```text
1. MostroApp initState()
   → LifecycleManager provider
   → DeepLinkInterceptor initialization
   → _processInitialDeepLink()
   ↓
2. build() → appInitializerProvider
   → Initialize NostrService
   → Initialize KeyManager
   → Initialize MostroNodes
   → Initialize SessionManager
   → Subscribe SubscriptionManager
   → Recover active sessions
   ↓
3. Create router with createRouter(ref)
   → redirect: firstRun check
   → routes: ShellRoute + all screens
   ↓
4. MaterialApp.router
   → Configure deep link handler
   → Configure notification launch handler
   → Configure locale
   ↓
5. App visible
```

## Cross References

| Reference | Document |
|-----------|----------|
| Home screen | [HOME_SCREEN.md](./HOME_SCREEN.md) |
| Drawer menu | [DRAWER_MENU.md](./DRAWER_MENU.md) |
| Bottom nav | [DRAWER_MENU.md](./DRAWER_MENU.md) |
| Order creation | [ORDER_CREATION.md](./ORDER_CREATION.md) |
| Take order | [TAKE_ORDER.md](./TAKE_ORDER.md) |
| My trades | [MY_TRADES.md](./MY_TRADES.md) |
| Trade detail | [TRADE_EXECUTION.md](./TRADE_EXECUTION.md) |
| Auth | [AUTHENTICATION.md](./AUTHENTICATION.md) |
| Sessions | [SESSION_AND_KEY_MANAGEMENT.md](./SESSION_AND_KEY_MANAGEMENT.md) |
| Deep links Nostr | [NOSTR.md](./NOSTR.md) |
