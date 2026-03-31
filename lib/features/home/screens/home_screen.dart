import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/drawer/screens/drawer_menu.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/widgets/order_list_item.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/shared/widgets/notification_bell.dart';
import 'package:mostro/shared/widgets/add_order_button.dart';
import 'package:mostro/shared/widgets/order_filter.dart';

/// Home screen — public order book with BUY/SELL tabs, filter, and drawer.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool _drawerOpen = false;
  bool _showHappyFace = false;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        ref.read(homeOrderTypeProvider.notifier).state =
            _tabController.index == 0 ? OrderType.buy : OrderType.sell;
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _toggleDrawer() => setState(() => _drawerOpen = !_drawerOpen);

  void _triggerHappyFace() {
    if (_showHappyFace) return;
    setState(() => _showHappyFace = true);
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _showHappyFace = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final filteredOrders = ref.watch(filteredOrdersProvider);
    final flags = ref.watch(currencyFlagsProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= AppBreakpoints.desktop;

    // ── Order list: responsive column count ──────────────────────────────────
    final columns = screenWidth >= AppBreakpoints.desktop
        ? 3
        : screenWidth >= AppBreakpoints.tablet
            ? 2
            : 1;

    Widget orderContent(void Function(String orderId, OrderType type) onTap) {
      if (filteredOrders.isEmpty) return const OrderListEmpty();
      if (columns == 1) {
        return ListView.separated(
          padding: const EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.xs,
            bottom: 100,
          ),
          itemCount: filteredOrders.length,
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
          itemBuilder: (context, index) {
            final order = filteredOrders[index];
            return OrderListItem(
              order: order,
              currencyFlags: flags,
              onTap: () => onTap(order.id, ref.read(homeOrderTypeProvider)),
            );
          },
        );
      }
      return GridView.builder(
        padding: const EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.xs,
          bottom: 100,
        ),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: AppSpacing.sm,
          mainAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.1,
        ),
        itemCount: filteredOrders.length,
        itemBuilder: (context, index) {
          final order = filteredOrders[index];
          return OrderListItem(
            order: order,
            currencyFlags: flags,
            onTap: () => onTap(order.id, ref.read(homeOrderTypeProvider)),
          );
        },
      );
    }

    void onOrderTap(String id, OrderType type) {
      if (type == OrderType.buy) {
        context.push(AppRoute.takeSellPath(id));
      } else {
        context.push(AppRoute.takeBuyPath(id));
      }
    }

    // ── Main content column ───────────────────────────────────────────────────
    final mainContent = Column(
      children: [
        // AppBar (hidden hamburger on desktop — sidebar is always visible)
        SafeArea(
          bottom: false,
          child: _MostroAppBar(
            green: green,
            showHappyFace: _showHappyFace,
            onMenuTap: isDesktop ? null : _toggleDrawer,
            onLogoTap: _triggerHappyFace,
          ),
        ),

        // Tabs
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: green,
            labelColor: colors?.textPrimary,
            unselectedLabelColor: colors?.textSecondary,
            tabs: const [
              Tab(text: 'BUY BTC'),
              Tab(text: 'SELL BTC'),
            ],
          ),
        ),

        // Filter pill
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          child: GestureDetector(
            onTap: () => showOrderFilterDialog(context),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: colors?.backgroundInput,
                borderRadius: BorderRadius.circular(AppRadius.button),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_alt_outlined,
                    size: 16,
                    color: colors?.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'FILTER',
                    style: TextStyle(
                      color: colors?.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${filteredOrders.length} offers',
                    style: TextStyle(
                      color: colors?.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Order list (responsive)
        // TODO: Add RefreshIndicator when orderBookProvider is backed
        // by the Rust bridge (Phase 7). Currently mock data — refresh is a no-op.
        Expanded(child: orderContent(onOrderTap)),
      ],
    );

    // ── Scaffold layout ───────────────────────────────────────────────────────
    // Desktop: persistent sidebar + main content in a Row (no overlay drawer).
    // Mobile/tablet: Stack with optional overlay drawer.
    final body = isDesktop
        ? Row(
            children: [
              const DrawerMenu(persistent: true),
              const VerticalDivider(width: 1),
              Expanded(child: mainContent),
            ],
          )
        : Stack(
            children: [
              mainContent,
              if (_drawerOpen)
                DrawerMenu(
                  onClose: () => setState(() => _drawerOpen = false),
                ),
            ],
          );

    return Scaffold(
      body: body,
      floatingActionButton: const AddOrderButton(),
      bottomNavigationBar: const BottomNavBar(),
    );
  }
}

/// Custom app bar: hamburger, Mostro logo (tappable), notification bell.
class _MostroAppBar extends StatelessWidget {
  const _MostroAppBar({
    required this.green,
    required this.showHappyFace,
    required this.onMenuTap,
    required this.onLogoTap,
  });

  final Color green;
  final bool showHappyFace;
  /// Null on desktop where the persistent sidebar replaces the overlay drawer.
  final VoidCallback? onMenuTap;
  final VoidCallback onLogoTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          if (onMenuTap != null)
            IconButton(
              onPressed: onMenuTap,
              icon: const Icon(Icons.menu, size: 24),
              tooltip: 'Menu',
            ),
          const Spacer(),
          GestureDetector(
            onTap: onLogoTap,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: showHappyFace
                  ? Icon(
                      Icons.sentiment_very_satisfied,
                      key: const ValueKey('happy'),
                      size: 28,
                      color: green,
                    )
                  : Icon(
                      Icons.psychology,
                      key: const ValueKey('skull'),
                      size: 28,
                      color: green,
                    ),
            ),
          ),
          const Spacer(),
          const NotificationBell(),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }
}
