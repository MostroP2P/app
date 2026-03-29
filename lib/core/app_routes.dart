import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// ── Route name constants ───────────────────────────────────────────────────────

abstract final class AppRoute {
  static const walkthrough = '/walkthrough';
  static const home = '/';
  static const orderBook = '/order_book';
  static const addOrder = '/add_order';
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

/// Application router.
///
/// Redirect logic (first-run → walkthrough) is wired in Phase 3 (US1).
/// All routes are stubs at this stage.
final GoRouter appRouter = GoRouter(
  initialLocation: AppRoute.home,
  routes: [
    GoRoute(
      path: AppRoute.walkthrough,
      builder: (_, __) => const _Stub('Walkthrough'),
    ),
    GoRoute(
      path: AppRoute.home,
      builder: (_, __) => const _Stub('Home / Order Book'),
    ),
    GoRoute(
      path: AppRoute.orderBook,
      builder: (_, __) => const _Stub('Order Book'),
    ),
    GoRoute(
      path: AppRoute.addOrder,
      builder: (_, __) => const _Stub('Add Order'),
    ),
    GoRoute(
      path: AppRoute.takeSell,
      builder: (context, state) =>
          _Stub('Take Sell — ${state.pathParameters['orderId']}'),
    ),
    GoRoute(
      path: AppRoute.takeBuy,
      builder: (context, state) =>
          _Stub('Take Buy — ${state.pathParameters['orderId']}'),
    ),
    GoRoute(
      path: AppRoute.payInvoice,
      builder: (context, state) =>
          _Stub('Pay Invoice — ${state.pathParameters['orderId']}'),
    ),
    GoRoute(
      path: AppRoute.addInvoice,
      builder: (context, state) =>
          _Stub('Add Invoice — ${state.pathParameters['orderId']}'),
    ),
    GoRoute(
      path: AppRoute.tradeDetail,
      builder: (context, state) =>
          _Stub('Trade Detail — ${state.pathParameters['orderId']}'),
    ),
    GoRoute(
      path: AppRoute.chatList,
      builder: (_, __) => const _Stub('Chat List'),
    ),
    GoRoute(
      path: AppRoute.chatRoom,
      builder: (context, state) =>
          _Stub('Chat Room — ${state.pathParameters['orderId']}'),
    ),
    GoRoute(
      path: AppRoute.keyManagement,
      builder: (_, __) => const _Stub('Key Management'),
    ),
    GoRoute(
      path: AppRoute.settings,
      builder: (_, __) => const _Stub('Settings'),
    ),
    GoRoute(
      path: AppRoute.about,
      builder: (_, __) => const _Stub('About'),
    ),
    GoRoute(
      path: AppRoute.notifications,
      builder: (_, __) => const _Stub('Notifications'),
    ),
    GoRoute(
      path: AppRoute.relays,
      builder: (_, __) => const _Stub('Relays'),
    ),
    GoRoute(
      path: AppRoute.walletSettings,
      builder: (_, __) => const _Stub('Wallet Settings'),
    ),
    GoRoute(
      path: AppRoute.connectWallet,
      builder: (_, __) => const _Stub('Connect Wallet'),
    ),
    GoRoute(
      path: AppRoute.rateUser,
      builder: (context, state) =>
          _Stub('Rate User — ${state.pathParameters['orderId']}'),
    ),
    GoRoute(
      path: AppRoute.disputeDetails,
      builder: (context, state) =>
          _Stub('Dispute Details — ${state.pathParameters['disputeId']}'),
    ),
    GoRoute(
      path: AppRoute.notificationSettings,
      builder: (_, __) => const _Stub('Notification Settings'),
    ),
    GoRoute(
      path: AppRoute.logs,
      builder: (_, __) => const _Stub('Logs'),
    ),
    GoRoute(
      path: AppRoute.disputeChat,
      builder: (context, state) =>
          _Stub('Dispute Chat — ${state.pathParameters['disputeId']}'),
    ),
  ],
);

// ── Placeholder screen ─────────────────────────────────────────────────────────

class _Stub extends StatelessWidget {
  const _Stub(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Center(
        child: Text(name, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}
