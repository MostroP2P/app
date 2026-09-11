import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart'
    show orderBookNotificationCountProvider;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/providers/nav_providers.dart';

/// Badge count for the Chat tab. Will be wired to Rust bridge.
final chatNotificationCountProvider = StateProvider<int>((_) => 0);

const double _barHeight = 68;

/// Bottom navigation bar with 3 tabs: Order Book, My Trades, Chat.
///
/// Order-book handoff 4b: 68 tall on the navigation surface under a hairline,
/// each destination a 20-dp icon over a 10-dp label, lime when active.
class BottomNavBar extends ConsumerWidget {
  const BottomNavBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // On desktop the persistent sidebar provides navigation; hide bottom nav.
    if (MediaQuery.sizeOf(context).width >= AppBreakpoints.desktop) {
      return const SizedBox.shrink();
    }

    final currentIndex = ref.watch(bottomNavIndexProvider);
    final palette = OrderBookPalette.of(context);
    final tradesCount = ref.watch(orderBookNotificationCountProvider);
    final chatCount = ref.watch(chatNotificationCountProvider);
    final l10n = AppLocalizations.of(context);

    void select(int index) {
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
    }

    final destinations = [
      (
        id: AutomationIds.navOrderBook,
        icon: Icons.list_alt_outlined,
        activeIcon: Icons.list_alt,
        label: l10n.bottomNavBook,
        badge: 0,
      ),
      (
        id: AutomationIds.navTrades,
        icon: Icons.bolt_outlined,
        activeIcon: Icons.bolt,
        label: l10n.bottomNavTrades,
        badge: tradesCount,
      ),
      (
        id: AutomationIds.navChat,
        icon: Icons.chat_bubble_outline,
        activeIcon: Icons.chat_bubble,
        label: l10n.navChat,
        badge: chatCount,
      ),
    ];

    // Material (not a coloured box) so the items' ink splashes paint on it.
    return Material(
      color: palette.surfaceNav,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: palette.navBorder)),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
          child: SizedBox(
            height: _barHeight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Row(
                children: [
                  for (final (index, destination) in destinations.indexed)
                    Expanded(
                      // The identifier names the whole destination, so the
                      // tap action and selected state travel with it.
                      child: _NavItem(
                        icon:
                            index == currentIndex
                                ? destination.activeIcon
                                : destination.icon,
                        label: destination.label,
                        badgeCount: destination.badge,
                        isActive: index == currentIndex,
                        palette: palette,
                        onTap: () => select(index),
                      ).withAutomationId(destination.id),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.badgeCount,
    required this.isActive,
    required this.palette,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final int badgeCount;
  final bool isActive;
  final OrderBookPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = isActive ? palette.limeText : palette.textTertiary;

    return Semantics(
      selected: isActive,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 20, color: color),
                if (badgeCount > 0)
                  Positioned(
                    top: -2,
                    right: -4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: palette.notif,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
