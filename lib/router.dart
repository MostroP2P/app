/// App routing using go_router — Phase 3 update (T037).
///
/// Identity-based redirect guard: anonymous users → /onboarding.
/// go_router reacts to identity state via [routerNotifier] which is fed by
/// [MostroApp] via ref.listen(identityProvider, …).
///
/// Named routes are in [Routes].
library router;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/identity_provider.dart';
import 'screens/home/home_screen.dart';
import 'screens/onboarding/welcome_screen.dart';
import 'screens/onboarding/create_identity_screen.dart';
import 'screens/onboarding/import_identity_screen.dart';
import 'screens/onboarding/pin_setup_screen.dart';

// ─── Route names ─────────────────────────────────────────────────────────────

class Routes {
  Routes._();

  static const onboarding = 'onboarding';
  static const onboardingCreate = 'onboarding-create';
  static const onboardingImport = 'onboarding-import';
  static const onboardingPin = 'onboarding-pin';
  static const home = 'home';
  static const orderDetail = 'order-detail';
  static const trade = 'trade';
  static const dispute = 'dispute';
  static const history = 'history';
  static const tradeDetail = 'trade-detail';
  static const settings = 'settings';
  static const settingsRelays = 'settings-relays';
  static const settingsWallet = 'settings-wallet';
  static const settingsPrivacy = 'settings-privacy';
  static const settingsNotifications = 'settings-notifications';
  static const about = 'about';
  static const sharedOrder = 'shared-order';
}

// ─── Placeholder screens (to be replaced in later phases) ───────────────────

class _PlaceholderScreen extends StatelessWidget {
  const _PlaceholderScreen(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(child: Text(title)),
    );
  }
}

// ─── Router notifier ─────────────────────────────────────────────────────────

/// Bridges Riverpod identity state into a [Listenable] so go_router can
/// re-evaluate redirect guards whenever identity changes.
///
/// Feed it from [MostroApp.build] via:
///   `ref.listen(identityProvider, (_, s) => routerNotifier.update(s));`
class RouterNotifier extends ChangeNotifier {
  AsyncValue<IdentityInfo?>? _lastState;

  /// Called by MostroApp whenever identityProvider emits a new value.
  void update(AsyncValue<IdentityInfo?> state) {
    if (state != _lastState) {
      _lastState = state;
      notifyListeners();
    }
  }

  /// True while identity state is still being resolved from storage.
  /// Redirects are deferred until loading completes to avoid onboarding flash.
  bool get isLoading =>
      _lastState == null || _lastState is AsyncLoading<IdentityInfo?>;

  bool get hasIdentity => _lastState?.valueOrNull != null;
}

/// Singleton notifier — accessed both in [appRouter] and [MostroApp].
final routerNotifier = RouterNotifier();

// ─── Router ──────────────────────────────────────────────────────────────────

final GoRouter appRouter = GoRouter(
  initialLocation: '/onboarding',
  refreshListenable: routerNotifier,
  redirect: (context, state) {
    // Defer all redirects while identity is still loading to avoid a flash
    // of the onboarding screen on warm starts with an existing identity.
    if (routerNotifier.isLoading) return null;

    final isOnboarding = state.matchedLocation.startsWith('/onboarding');

    if (routerNotifier.hasIdentity && state.matchedLocation == '/onboarding') {
      // Identity loaded — skip onboarding root → go home.
      return '/home';
    }
    if (!routerNotifier.hasIdentity && !isOnboarding) {
      // No identity — redirect to onboarding.
      return '/onboarding';
    }
    return null;
  },
  routes: [
    // ── Onboarding ─────────────────────────────────────────────────────────
    GoRoute(
      path: '/onboarding',
      name: Routes.onboarding,
      builder: (context, state) => const WelcomeScreen(),
      routes: [
        GoRoute(
          path: 'create',
          name: Routes.onboardingCreate,
          builder: (context, state) => const CreateIdentityScreen(),
        ),
        GoRoute(
          path: 'import',
          name: Routes.onboardingImport,
          builder: (context, state) => const ImportIdentityScreen(),
        ),
        GoRoute(
          path: 'pin',
          name: Routes.onboardingPin,
          builder: (context, state) => const PinSetupScreen(),
        ),
      ],
    ),

    // ── Main app ───────────────────────────────────────────────────────────
    GoRoute(
      path: '/home',
      name: Routes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/order/:id',
      name: Routes.orderDetail,
      builder: (context, state) {
        final id = state.pathParameters['id']!;
        return _PlaceholderScreen('Order $id');
      },
    ),
    GoRoute(
      path: '/trade',
      name: Routes.trade,
      builder: (context, state) => const _PlaceholderScreen('Trade'),
    ),
    GoRoute(
      path: '/dispute',
      name: Routes.dispute,
      builder: (context, state) => const _PlaceholderScreen('Dispute'),
    ),

    // ── History ────────────────────────────────────────────────────────────
    GoRoute(
      path: '/history',
      name: Routes.history,
      builder: (context, state) => const _PlaceholderScreen('History'),
      routes: [
        GoRoute(
          path: ':id',
          name: Routes.tradeDetail,
          builder: (context, state) {
            final id = state.pathParameters['id']!;
            return _PlaceholderScreen('Trade History $id');
          },
        ),
      ],
    ),

    // ── Settings ───────────────────────────────────────────────────────────
    GoRoute(
      path: '/settings',
      name: Routes.settings,
      builder: (context, state) => const _PlaceholderScreen('Settings'),
      routes: [
        GoRoute(
          path: 'relays',
          name: Routes.settingsRelays,
          builder: (context, state) =>
              const _PlaceholderScreen('Relay Settings'),
        ),
        GoRoute(
          path: 'wallet',
          name: Routes.settingsWallet,
          builder: (context, state) =>
              const _PlaceholderScreen('Wallet Settings'),
        ),
        GoRoute(
          path: 'privacy',
          name: Routes.settingsPrivacy,
          builder: (context, state) =>
              const _PlaceholderScreen('Privacy Settings'),
        ),
        GoRoute(
          path: 'notifications',
          name: Routes.settingsNotifications,
          builder: (context, state) =>
              const _PlaceholderScreen('Notification Settings'),
        ),
      ],
    ),

    // ── Misc ───────────────────────────────────────────────────────────────
    GoRoute(
      path: '/about',
      name: Routes.about,
      builder: (context, state) => const _PlaceholderScreen('About'),
    ),

    // ── Deep link ─────────────────────────────────────────────────────────
    GoRoute(
      path: '/shared/:orderid',
      name: Routes.sharedOrder,
      builder: (context, state) {
        final orderId = state.pathParameters['orderid']!;
        return _PlaceholderScreen('Shared Order $orderId');
      },
    ),
  ],
);
