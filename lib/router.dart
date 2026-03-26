/// App routing using go_router.
///
/// Named routes:
///   /onboarding                → OnboardingWelcomeScreen (placeholder)
///   /onboarding/create         → CreateIdentityScreen (placeholder)
///   /onboarding/import         → ImportIdentityScreen (placeholder)
///   /onboarding/pin            → PinSetupScreen (placeholder)
///   /onboarding/recovery       → RecoveryScreen (placeholder)
///   /home                      → HomeScreen (placeholder)
///   /order/:id                 → OrderDetailScreen (placeholder)
///   /trade                     → TradeScreen (placeholder)
///   /dispute                   → DisputeScreen (placeholder)
///   /history                   → HistoryScreen (placeholder)
///   /history/:id               → TradeDetailScreen (placeholder)
///   /settings                  → SettingsScreen (placeholder)
///   /settings/relays           → RelaySettingsScreen (placeholder)
///   /settings/wallet           → WalletSettingsScreen (placeholder)
///   /settings/privacy          → PrivacySettingsScreen (placeholder)
///   /settings/notifications    → NotificationSettingsScreen (placeholder)
///   /about                     → AboutScreen (placeholder)
///   /shared/:orderid           → SharedOrderScreen (placeholder — deep link)
///
/// Redirect guard: if no identity exists, redirect to /onboarding.
/// Identity check is synchronous here (Phase 3 wires real identity provider).
library router;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ─── Route names ─────────────────────────────────────────────────────────────

class Routes {
  Routes._();

  static const onboarding = 'onboarding';
  static const onboardingCreate = 'onboarding-create';
  static const onboardingImport = 'onboarding-import';
  static const onboardingPin = 'onboarding-pin';
  static const onboardingRecovery = 'onboarding-recovery';
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

// ─── Placeholder screens (replaced in Phase 3+) ──────────────────────────────

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

// ─── Router ──────────────────────────────────────────────────────────────────

/// Whether the user has completed onboarding and has an identity.
/// Phase 3 T037 replaces this stub with a real Riverpod-backed check.
bool _hasIdentity() => false;

final GoRouter appRouter = GoRouter(
  initialLocation: '/home',
  redirect: (context, state) {
    final isOnboarding = state.matchedLocation.startsWith('/onboarding');
    if (!_hasIdentity() && !isOnboarding) {
      return '/onboarding';
    }
    return null;
  },
  routes: [
    // ── Onboarding ─────────────────────────────────────────────────────────
    GoRoute(
      path: '/onboarding',
      name: Routes.onboarding,
      builder: (context, state) =>
          const _PlaceholderScreen('Welcome'),
      routes: [
        GoRoute(
          path: 'create',
          name: Routes.onboardingCreate,
          builder: (context, state) =>
              const _PlaceholderScreen('Create Identity'),
        ),
        GoRoute(
          path: 'import',
          name: Routes.onboardingImport,
          builder: (context, state) =>
              const _PlaceholderScreen('Import Identity'),
        ),
        GoRoute(
          path: 'pin',
          name: Routes.onboardingPin,
          builder: (context, state) =>
              const _PlaceholderScreen('Set PIN'),
        ),
        GoRoute(
          path: 'recovery',
          name: Routes.onboardingRecovery,
          builder: (context, state) =>
              const _PlaceholderScreen('Recovery'),
        ),
      ],
    ),

    // ── Main app ───────────────────────────────────────────────────────────
    GoRoute(
      path: '/home',
      name: Routes.home,
      builder: (context, state) =>
          const _PlaceholderScreen('Home'),
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
      builder: (context, state) =>
          const _PlaceholderScreen('Trade'),
    ),
    GoRoute(
      path: '/dispute',
      name: Routes.dispute,
      builder: (context, state) =>
          const _PlaceholderScreen('Dispute'),
    ),

    // ── History ────────────────────────────────────────────────────────────
    GoRoute(
      path: '/history',
      name: Routes.history,
      builder: (context, state) =>
          const _PlaceholderScreen('History'),
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
      builder: (context, state) =>
          const _PlaceholderScreen('Settings'),
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
      builder: (context, state) =>
          const _PlaceholderScreen('About'),
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
