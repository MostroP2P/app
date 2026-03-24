# Navigation & Routes (v1 Reference)

> Mapa completo de rutas, redirecciones, deep links y sistema de navegación.

## Archivos del Código Fuente

| Archivo | Descripción |
|---------|-------------|
| `lib/core/app_routes.dart` | Definición de GoRouter con todas las rutas |
| `lib/core/app.dart` | Inicialización de router, deep links, app lifecycle |
| `lib/core/deep_link_handler.dart` | Manejo de deep links mostro: |
| `lib/core/deep_link_interceptor.dart` | Interceptor de esquemas custom para evitar asserts |
| `lib/services/deep_link_service.dart` | Servicio de parsing y navegación de deep links |
| `lib/shared/notifiers/navigation_notifier.dart` | Notifier para navegación programática |
| `lib/shared/providers/navigation_notifier_provider.dart` | Provider del NavigationNotifier |
| `lib/shared/widgets/navigation_listener_widget.dart` | Widget que escucha navegación y hace context.go |

## Sistema de Navegación

La app usa **GoRouter** con las siguientes características:
- Rutas definidas en `createRouter()` dentro de `app_routes.dart`
- `ShellRoute` que wrappea todas las rutas con widgets de infraestructura
- Redirecciones basadas en estado de autenticación (`firstRunProvider`)
- Interceptores de deep links para esquemas custom (`mostro:`)

### Arquitectura del Router

```text
MostroApp
├── appInitializerProvider (await initialization)
│   └── MaterialApp.router
│       └── GoRouter
│           ├── navigatorKey: MostroApp.navigatorKey
│           ├── redirect: firstRun check
│           ├── errorBuilder
│           └── ShellRoute (NotificationListener + NavigationListener + LogsIndicator)
│               └── routes[] (todas las pantallas)
```

## Rutas Completas

### Rutas Principales (ShellRoute)

| Ruta | Pantalla | Archivo | Descripción |
|------|----------|---------|-------------|
| `/` | `HomeScreen` | `home_screen.dart` | Libro de órdenes público |
| `/welcome` | `WelcomeScreen` | `welcome_screen.dart` | Pantalla de bienvenida |
| `/order_book` | `TradesScreen` | `trades_screen.dart` | My trades list (see `.specify/v1-reference/MY_TRADES.md`) |
| `/trade_detail/:orderId` | `TradeDetailScreen` | `trade_detail_screen.dart` | Trade detail (see `.specify/v1-reference/TRADE_EXECUTION.md`) |
| `/chat_list` | `ChatRoomsScreen` | `chat_rooms_list.dart` | Lista de chats |
| `/chat_room/:orderId` | `ChatRoomScreen` | `chat_room_screen.dart` | Chat de un trade |
| `/dispute_details/:disputeId` | `DisputeChatScreen` | `dispute_chat_screen.dart` | Chat de disputa |
| `/register` | `RegisterScreen` | `register_screen.dart` | Registro de identidad |
| `/relays` | `RelaysScreen` | `relays_screen.dart` | Gestión de relays |
| `/key_management` | `KeyManagementScreen` | `key_management_screen.dart` | Cuenta, mnemónicos |
| `/settings` | `SettingsScreen` | `settings_screen.dart` | Configuración general |
| `/about` | `AboutScreen` | `about_screen.dart` | Acerca de la app |
| `/walkthrough` | `WalkthroughScreen` | `walkthrough_screen.dart` | Tutorial inicial |
| `/add_order` | `AddOrderScreen` | `add_order_screen.dart` | Crear orden (ver `.specify/v1-reference/ORDER_CREATION.md`) |
| `/rate_user/:orderId` | `RateCounterpartScreen` | `rate_counterpart_screen.dart` | Calificar contraparte |
| `/take_sell/:orderId` | `TakeOrderScreen` | `take_order_screen.dart` | Tomar orden de venta (ver `.specify/v1-reference/TAKE_ORDER.md`) |
| `/take_buy/:orderId` | `TakeOrderScreen` | `take_order_screen.dart` | Tomar orden de compra (ver `.specify/v1-reference/TAKE_ORDER.md`) |
| `/order_confirmed/:orderId` | `OrderConfirmationScreen` | `order_confirmation_screen.dart` | Orden confirmada |
| `/pay_invoice/:orderId` | `PayLightningInvoiceScreen` | `pay_lightning_invoice_screen.dart` | Pay Lightning invoice (see `.specify/v1-reference/TRADE_EXECUTION.md`) |
| `/add_invoice/:orderId` | `AddLightningInvoiceScreen` | `add_lightning_invoice_screen.dart` | Add Lightning invoice (see `.specify/v1-reference/TRADE_EXECUTION.md`) |
| `/notifications` | `NotificationsScreen` | `notifications_screen.dart` | Historial de notificaciones |
| `/logs` | `LogsScreen` | `logs_screen.dart` | Registro de diagnóstico |
| `/wallet_settings` | `WalletSettingsScreen` | `wallet_settings_screen.dart` | Configuración de wallet |
| `/connect_wallet` | `ConnectWalletScreen` | `connect_wallet_screen.dart` | Conectar wallet NWC |
| `/notification_settings` | `NotificationSettingsScreen` | `notification_settings_screen.dart` | Preferencias de notificaciones |

### Parámetros de Ruta

| Ruta | Parámetros | Query Params | Extra |
|------|-----------|-------------|-------|
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

## Redirecciones (Guards)

### Redirección de First Run

```dart
redirect: (context, state) {
  // 1. Bloquear esquemas custom antes de que GoRouter los procese
  if (state.uri.scheme == 'mostro' ||
      (!state.uri.scheme.startsWith('http') && state.uri.scheme.isNotEmpty)) {
    return '/';  // Redirect a home, deep link se procesa manualmente
  }

  // 2. Check de first run
  final firstRunState = ref.read(firstRunProvider);

  return firstRunState.when(
    data: (isFirstRun) {
      if (isFirstRun && state.matchedLocation != '/walkthrough') {
        return '/walkthrough';  // Primera vez → tutorial
      }
      return null;  // No redirect
    },
    loading: () {
      return state.matchedLocation == '/walkthrough'
          ? null
          : '/walkthrough';  // Cargando → ir a walkthrough
    },
    error: (_, __) => null,
  );
}
```

### Redirección Post-Auth

En `app.dart`, dentro del `initAsyncValue.when(data:)`:

```dart
ref.listen<AuthState>(authNotifierProvider, (previous, state) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    if (state is AuthAuthenticated || state is AuthRegistrationSuccess) {
      context.go('/');  // Login/registro exitoso → home
    } else if (state is AuthUnregistered || state is AuthUnauthenticated) {
      context.go('/');  // Logout → home
    }
  });
});
```

## Deep Links

### Esquema `mostro:`

**URL format:**
```text
mostro:order?id={orderId}&relay={relayUrl}&relay={relayUrl2}
```

**Ejemplo:**
```text
mostro:order?id=abc123-def456-ghi789&relay=wss://relay.mostro.network&relay=wss://relay2.mostro.network
```

### Pipeline de Deep Links

```text
1. Sistema operativo envía deep link
   ↓
2. DeepLinkInterceptor (WidgetsBindingObserver)
   → Detecta esquema 'mostro:' o custom
   → Previene que GoRouter procese la URL (evita assertion errors)
   → Emite URL al customUrlStream
   ↓
3. app.dart (_initializeDeepLinkInterceptor)
   → Escucha customUrlStream
   → Llama a deepLinkHandler.handleInitialDeepLink()
   ↓
4. DeepLinkHandler
   → Parsea la URL
   → Llama a deepLinkService.processMostroLink()
   ↓
5. DeepLinkService
   → Valida formato (NostrUtils.isValidMostroUrl)
   → Parsea orderId y relays
   → Busca evento NIP-69 (kind 38383) con tag 'd' = orderId
   → Extrae OrderType del tag 'k'
   → Retorna OrderInfo
   ↓
6. DeepLinkHandler._handleMostroDeepLink
   → Muestra loading dialog
   → Llama a deepLinkService.navigateToOrder()
   ↓
7. DeepLinkService.navigateToOrder()
   → Usa postFrameCallback para navegar
   → router.push('/take_sell/{orderId}') o '/take_buy/{orderId}'
   ↓
8. TakeOrderScreen recibe el orderId
```

### Navegación desde Deep Link

```dart
String getNavigationRoute(OrderInfo orderInfo) {
  switch (orderInfo.orderType) {
    case OrderType.sell:
      return '/take_sell/${orderInfo.orderId}';  // Quiero comprar → tomo orden de venta
    case OrderType.buy:
      return '/take_buy/${orderInfo.orderId}';   // Quiero vender → tomo orden de compra
  }
}
```

### Manejo de Errores de Deep Link

| Error | Mensaje (i18n) | Acción |
|-------|---------------|--------|
| URL inválida | `deepLinkInvalidFormat` | Snackbar error |
| Fallo de parseo | `deepLinkParseError` | Snackbar error |
| Order ID inválido | `deepLinkInvalidOrderId` | Snackbar error |
| Sin relays | `deepLinkNoRelays` | Snackbar error |
| Orden no encontrada | `deepLinkOrderNotFound` | Snackbar error |
| Error general | `failedToOpenOrder` | Snackbar error |

## Navegación Programática

### NavigationNotifier

```dart
// Shared provider
final navigationProvider =
    StateNotifierProvider<NavigationNotifier, NavigationState>(
        (ref) => NavigationNotifier());

// Listener widget (en el ShellRoute)
class NavigationListenerWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<NavigationState>(navigationProvider, (previous, next) {
      if (next.path.isNotEmpty) {
        context.go(next.path);  // Navegación imperativa
      }
    });
    return child;
  }
}
```

**Uso:**
```dart
// En cualquier lugar de la app
ref.read(navigationProvider.notifier).go('/settings');
```

### Navegación Directa con GoRouter

La mayoría de la navegación usa `context.push()` o `context.go()` directamente:

```dart
// Push (añade a la pila, con back button)
context.push('/add_order');
context.push('/take_sell/${order.orderId}');
context.push('/chat_room/${session.orderId}');

// Go (reemplaza la ruta actual, sin back button)
context.go('/');

// Push con query params
context.push('/add_invoice/$orderId?lnAddress=user@lnaddress.com');

// Push con extra data
context.push('/add_order', extra: {'orderType': 'buy'});
```

## Navegación desde BottomNavBar

El `BottomNavBar` determina la ruta activa comparando `GoRouterState.of(context).uri.toString()`:

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

**Navegación:**
- Tab 0 → `context.push('/')`
- Tab 1 → `context.push('/order_book')`
- Tab 2 → `context.push('/chat_list')`

**Nota:** Usa `context.push()` en vez de `context.go()` para que funcione correctamente con la navegación anidada del ShellRoute.

## Navegación desde Drawer

El drawer (`CustomDrawerOverlay`) usa `context.push(route)` para cada item:

```dart
_buildMenuItem(...) {
  onTap: () {
    ref.read(drawerProvider.notifier).closeDrawer();
    context.push(route);  // Push en vez de go
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

## Transiciones

Todas las rutas usan `buildPageWithDefaultTransition`:

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

**Tipo de transición:** Fade de 150ms ease-in-out (sin slide).

## Flujo de App Inicialización

```text
1. MostroApp initState()
   → LifecycleManager provider
   → DeepLinkInterceptor initialization
   → _processInitialDeepLink()
   ↓
2. build() → appInitializerProvider
   → Inicializa NostrService
   → Inicializa KeyManager
   → Inicializa MostroNodes
   → Inicializa SessionManager
   → Suscribe SubscriptionManager
   → Recupera sesiones activas
   ↓
3. Crea router con createRouter(ref)
   → redirect: firstRun check
   → routes: ShellRoute + all screens
   ↓
4. MaterialApp.router
   → Configura deep link handler
   → Configura notification launch handler
   → Configura locale
   ↓
5. App visible
```

## Cross References

| Reference | Document |
|------------|-----------|
| Home screen | [HOME_SCREEN.md](./HOME_SCREEN.md) |
| Drawer menu | [DRAWER_MENU.md](./DRAWER_MENU.md) |
| Bottom nav | [DRAWER_MENU.md](./DRAWER_MENU.md) |
| Order creation | [.specify/v1-reference/ORDER_CREATION.md](./ORDER_CREATION.md) |
| Take order | [.specify/v1-reference/TAKE_ORDER.md](./TAKE_ORDER.md) |
| My trades | [.specify/v1-reference/MY_TRADES.md](./MY_TRADES.md) |
| Trade detail | [.specify/v1-reference/TRADE_EXECUTION.md](./TRADE_EXECUTION.md) |
| Auth | [AUTHENTICATION.md](./AUTHENTICATION.md) |
| Sessions | [SESSION_AND_KEY_MANAGEMENT.md](./SESSION_AND_KEY_MANAGEMENT.md) |
| Deep links Nostr | [NOSTR.md](./NOSTR.md) |
