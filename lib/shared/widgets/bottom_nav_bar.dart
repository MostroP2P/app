import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show orderBookNotificationCountProvider;
import 'package:mostro/shared/providers/nav_providers.dart';

/// Badge count for the Chat tab. Will be wired to Rust bridge.
final chatNotificationCountProvider = StateProvider<int>((_) => 0);

/// Bottom navigation bar with 3 tabs: Order Book, My Trades, Chat.
class BottomNavBar extends ConsumerWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // On desktop the persistent sidebar provides navigation; hide bottom nav.
    if (MediaQuery.sizeOf(context).width >= AppBreakpoints.desktop) {
      return const SizedBox.shrink();
    }

    final currentIndex = ref.watch(bottomNavIndexProvider);
    final colors = Theme.of(context).extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final disabledColor = colors?.textDisabled ?? const Color(0xFF6C757D);
    final tradesCount = ref.watch(orderBookNotificationCountProvider);
    final chatCount = ref.watch(chatNotificationCountProvider);

    return BottomNavigationBar(
      currentIndex: currentIndex,
      selectedItemColor: green,
      unselectedItemColor: disabledColor,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      onTap: (index) {
        ref.read(bottomNavIndexProvider.notifier).state = index;
        switch (index) {
          case 0:
            context.go(AppRoute.home);
          case 1:
            context.go(AppRoute.orderBook);
          case 2:
            context.go(AppRoute.chatList);
          default:
            assert(false, 'Unexpected bottom nav index: $index');
        }
      },
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.list_alt_outlined),
          activeIcon: Icon(Icons.list_alt),
          label: 'Order Book',
        ),
        BottomNavigationBarItem(
          icon: _BadgeIcon(
            icon: Icons.bolt_outlined,
            count: tradesCount,
            color: colors?.destructiveRed ?? const Color(0xFFD84D4D),
          ),
          activeIcon: _BadgeIcon(
            icon: Icons.bolt,
            count: tradesCount,
            color: colors?.destructiveRed ?? const Color(0xFFD84D4D),
          ),
          label: 'My Trades',
        ),
        BottomNavigationBarItem(
          icon: _BadgeIcon(
            icon: Icons.chat_bubble_outline,
            count: chatCount,
            color: colors?.destructiveRed ?? const Color(0xFFD84D4D),
          ),
          activeIcon: _BadgeIcon(
            icon: Icons.chat_bubble,
            count: chatCount,
            color: colors?.destructiveRed ?? const Color(0xFFD84D4D),
          ),
          label: 'Chat',
        ),
      ],
    );
  }
}

/// Icon with an optional red dot badge.
class _BadgeIcon extends StatelessWidget {
  const _BadgeIcon({
    required this.icon,
    required this.count,
    required this.color,
  });

  final IconData icon;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          Positioned(
            top: -2,
            right: -4,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}
