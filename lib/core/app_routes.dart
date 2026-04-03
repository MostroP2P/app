import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/features/account/screens/account_screen.dart';
import 'package:mostro/features/home/screens/home_screen.dart';
import 'package:mostro/features/notifications/screens/notifications_screen.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/order/screens/add_order_screen.dart';
import 'package:mostro/features/order/screens/pay_lightning_invoice_screen.dart';
import 'package:mostro/features/order/screens/my_order_screen.dart';
import 'package:mostro/features/order/screens/take_order_screen.dart';
import 'package:mostro/features/chat/screens/chat_room_screen.dart';
import 'package:mostro/features/chat/screens/chat_rooms_screen.dart';
import 'package:mostro/features/disputes/screens/dispute_chat_screen.dart';
import 'package:mostro/features/rate/screens/rate_counterpart_screen.dart';
import 'package:mostro/features/about/screens/about_screen.dart';
import 'package:mostro/features/settings/screens/connect_wallet_screen.dart';
import 'package:mostro/features/settings/screens/log_report_screen.dart';
import 'package:mostro/features/settings/screens/notification_settings_screen.dart';
import 'package:mostro/features/settings/screens/settings_screen.dart';
import 'package:mostro/features/settings/screens/wallet_settings_screen.dart';
import 'package:mostro/features/trades/screens/trade_detail_screen.dart';
import 'package:mostro/features/trades/screens/trades_screen.dart';
import 'package:mostro/features/walkthrough/providers/first_run_provider.dart';
import 'package:mostro/features/walkthrough/screens/walkthrough_screen.dart';

// ── Route name constants ───────────────────────────────────────────────────────

abstract final class AppRoute {
  static const walkthrough = '/walkthrough';
  static const home = '/';
  static const orderBook = '/order_book';
  static const addOrder = '/add_order';
  static const myOrder = '/my_order/:orderId';
  static const takeSell = '/take_sell/:orderId';
  static const takeBuy = '/take_buy/:orderId';
  static const payInvoice = '/pay_invoice/:orderId';
  static const addInvoice = '/add_invoice/:orderId';
  static const tradeDetail = '/trade_detail/:orderId';
  static const chatList = '/chat_list';
  static const chatRoom = '/chat_room/:orderId';
  static const keyManagement = '/key_management';
  static const settings = '/settings';
  static const about = '/about';
  static const notifications = '/notifications';
  static const relays = '/relays';
  static const walletSettings = '/wallet_settings';
  static const connectWallet = '/connect_wallet';
  static const rateUser = '/rate_user/:orderId';
  static const disputeDetails = '/dispute_details/:disputeId';
  static const notificationSettings = '/notification_settings';
  static const logs = '/logs';
  static const disputeChat = '/dispute_chat/:disputeId';

  /// Build a path with a single [id] substituted for the `:orderId` segment.
  static String tradeDetailPath(String orderId) =>
      '/trade_detail/$orderId';
  static String myOrderPath(String orderId) => '/my_order/$orderId';
  static String takeSellPath(String orderId) => '/take_sell/$orderId';
  static String takeBuyPath(String orderId) => '/take_buy/$orderId';
  static String payInvoicePath(String orderId) => '/pay_invoice/$orderId';
  static String addInvoicePath(String orderId) => '/add_invoice/$orderId';
  static String chatRoomPath(String orderId) => '/chat_room/$orderId';
  static String rateUserPath(String orderId) => '/rate_user/$orderId';
  static String disputeDetailsPath(String disputeId) =>
      '/dispute_details/$disputeId';
  static String disputeChatPath(String disputeId) =>
      '/dispute_chat/$disputeId';
}

// ── Router ─────────────────────────────────────────────────────────────────────

/// Riverpod container used by the router's redirect callback.
///
/// The container is populated by [MostroApp] via [routerContainer] before the
/// first navigation decision is made.
ProviderContainer? routerContainer;

/// Application router.
///
/// Redirect logic: if `firstRunComplete == false` every route is redirected to
/// `/walkthrough`. After the user taps Done or Skip the flag is persisted and
/// the redirect no longer fires.
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoute.home,
  redirect: (context, state) {
    final container = routerContainer;
    if (container == null) return null;

    final firstRunAsync = container.read(firstRunProvider);

    return firstRunAsync.when(
      data: (done) {
        if (!done && state.matchedLocation != AppRoute.walkthrough) {
          return AppRoute.walkthrough;
        }
        // Already on walkthrough or first-run completed — no redirect.
        return null;
      },
      // While loading or on error: fail-safe, no redirect (go to home).
      loading: () => null,
      error: (_, __) => null,
    );
  },
  routes: [
    GoRoute(
      path: AppRoute.walkthrough,
      builder: (_, __) => const WalkthroughScreen(),
    ),
    GoRoute(
      path: AppRoute.home,
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoute.orderBook,
      builder: (_, __) => const TradesScreen(),
    ),
    GoRoute(
      path: AppRoute.addOrder,
      builder: (context, state) {
        final type = state.uri.queryParameters['type'] ?? 'sell';
        return AddOrderScreen(orderType: type);
      },
    ),
    GoRoute(
      path: AppRoute.myOrder,
      builder: (context, state) => MyOrderScreen(
        orderId: state.pathParameters['orderId']!,
      ),
    ),
    GoRoute(
      path: AppRoute.takeSell,
      builder: (context, state) => TakeOrderScreen(
        orderId: state.pathParameters['orderId']!,
        isBuying: true, // taker is buying BTC (taking a sell order)
      ),
    ),
    GoRoute(
      path: AppRoute.takeBuy,
      builder: (context, state) => TakeOrderScreen(
        orderId: state.pathParameters['orderId']!,
        isBuying: false, // taker is selling BTC (taking a buy order)
      ),
    ),
    GoRoute(
      path: AppRoute.payInvoice,
      builder: (context, state) => PayLightningInvoiceScreen(
        orderId: state.pathParameters['orderId']!,
      ),
    ),
    GoRoute(
      path: AppRoute.addInvoice,
      builder: (context, state) => AddLightningInvoiceScreen(
        orderId: state.pathParameters['orderId']!,
      ),
    ),
    GoRoute(
      path: AppRoute.tradeDetail,
      builder: (context, state) => TradeDetailScreen(
        orderId: state.pathParameters['orderId']!,
      ),
    ),
    GoRoute(
      path: AppRoute.chatList,
      builder: (_, __) => const ChatRoomsScreen(),
    ),
    GoRoute(
      path: AppRoute.chatRoom,
      builder: (context, state) => ChatRoomScreen(
        orderId: state.pathParameters['orderId']!,
      ),
    ),
    GoRoute(
      path: AppRoute.keyManagement,
      builder: (_, __) => const AccountScreen(),
    ),
    GoRoute(
      path: AppRoute.settings,
      builder: (_, __) => const SettingsScreen(),
    ),
    GoRoute(
      path: AppRoute.about,
      builder: (_, __) => const AboutScreen(),
    ),
    GoRoute(
      path: AppRoute.notifications,
      builder: (_, __) => const NotificationsScreen(),
    ),
    GoRoute(
      path: AppRoute.relays,
      redirect: (_, __) => AppRoute.settings,
    ),
    GoRoute(
      path: AppRoute.walletSettings,
      builder: (_, __) => const WalletSettingsScreen(),
    ),
    GoRoute(
      path: AppRoute.connectWallet,
      builder: (_, __) => const ConnectWalletScreen(),
    ),
    GoRoute(
      path: AppRoute.rateUser,
      builder: (context, state) => RateCounterpartScreen(
        orderId: state.pathParameters['orderId']!,
      ),
    ),
    GoRoute(
      path: AppRoute.disputeDetails,
      builder: (context, state) => DisputeChatScreen(
        disputeId: state.pathParameters['disputeId']!,
      ),
    ),
    GoRoute(
      path: AppRoute.notificationSettings,
      builder: (_, __) => const NotificationSettingsScreen(),
    ),
    GoRoute(
      path: AppRoute.logs,
      builder: (_, __) => const LogReportScreen(),
    ),
    GoRoute(
      path: AppRoute.disputeChat,
      builder: (context, state) => DisputeChatScreen(
        disputeId: state.pathParameters['disputeId']!,
      ),
    ),
  ],
);

