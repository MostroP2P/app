import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/drawer/screens/drawer_menu.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';
import 'package:mostro/features/home/widgets/order_list_item.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/shared/widgets/notification_bell.dart';
import 'package:mostro/shared/widgets/add_order_button.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/order_filter.dart';
import 'package:mostro/shared/widgets/order_list_skeleton.dart';

/// Home screen — public order book, pixel-exact port of the "Mostro UX
/// Redesign" mock (screen #3 · Order book with reasons to pick).
///
/// BUY/SELL tabs, FILTER pill + sort caption, offer cards, and drawer.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  bool _drawerOpen = false;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final filteredOrders = ref.watch(filteredOrdersProvider);
    // "Reason to pick" badges computed once per visible list (not per card).
    final orderReasons = ref.watch(orderReasonsProvider);
    final flags = ref.watch(currencyFlagsProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= AppBreakpoints.desktop;

    // ── Order list: responsive column count ──────────────────────────────────
    final columns =
        screenWidth >= AppBreakpoints.desktop
            ? 3
            : screenWidth >= AppBreakpoints.tablet
            ? 2
            : 1;

    Widget orderContent(void Function(String orderId, OrderType type) onTap) {
      if (filteredOrders.isEmpty) return const OrderListEmpty();
      // Mock list: 8px top, 16px sides, 90px bottom clearance, 12px card gap.
      const listPadding = EdgeInsets.fromLTRB(16, 8, 16, 90);
      if (columns == 1) {
        return ListView.separated(
          padding: listPadding,
          itemCount: filteredOrders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final order = filteredOrders[index];
            return OrderListItem(
              order: order,
              currencyFlags: flags,
              reason: orderReasons[order.id],
              onTap: () => onTap(order.id, ref.read(homeOrderTypeProvider)),
            );
          },
        );
      }
      return GridView.builder(
        padding: listPadding,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.1,
        ),
        itemCount: filteredOrders.length,
        itemBuilder: (context, index) {
          final order = filteredOrders[index];
          return OrderListItem(
            order: order,
            currencyFlags: flags,
            reason: orderReasons[order.id],
            onTap: () => onTap(order.id, ref.read(homeOrderTypeProvider)),
          );
        },
      );
    }

    void onOrderTap(String id, OrderType type) {
      final allOrders = ref.read(orderBookProvider).valueOrNull ?? [];
      final order = allOrders.where((o) => o.id == id).firstOrNull;
      if (order?.isMine == true) {
        context.push(AppRoute.myOrderPath(id));
      } else if (type == OrderType.buy) {
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
            palette: pal,
            onMenuTap: isDesktop ? null : _toggleDrawer,
          ),
        ),

        // Tabs — active: green 2px underline; inactive: disabled over 1px rule.
        Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: pal.border)),
          ),
          child: TabBar(
            controller: _tabController,
            indicatorColor: pal.green,
            indicatorWeight: 2,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: pal.green,
            unselectedLabelColor: pal.tabInactive,
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
            ),
            // Named by the visible tab, not by what it filters: the Buy BTC
            // tab lists sell orders, so deriving the id from the filtered
            // OrderType would swap the two.
            tabs: [
              Tab(
                child: Text(l10n.tabBuyBtc)
                    .withAutomationId(AutomationIds.orderBookTabBuy),
              ),
              Tab(
                child: Text(l10n.tabSellBtc)
                    .withAutomationId(AutomationIds.orderBookTabSell),
              ),
            ],
          ),
        ),

        // Filter row: FILTER pill + offer count · sort caption
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              // Flexible + ellipsis so long localized labels (de/fr) fit
              // 320px-wide screens without a RenderFlex overflow.
              Flexible(
                child: Material(
                  // bgElevated, not bgCard: with the v1 recipe bgCard equals
                  // the page tone, which would make the pill invisible (v1's
                  // filter uses its lighter input tone for the same reason).
                  color: pal.bgElevated,
                  shape: StadiumBorder(side: BorderSide(color: pal.border)),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => showOrderFilterDialog(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.filter_alt_outlined,
                            size: 16,
                            color: pal.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.filterButtonLabel,
                            style: TextStyle(
                              color: pal.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '· ${l10n.offersCount(filteredOrders.length)}',
                              style: TextStyle(
                                color: pal.textTertiary,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  l10n.sortNewest,
                  style: TextStyle(fontSize: 11, color: pal.textTertiary),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ),

        // Order list — shimmer while loading, error state, or live data.
        // The well is one step lighter than the chrome (v1's `dark1`
        // container): the cards share the chrome's tone, so this inverted
        // contrast is what makes them read as panels.
        Expanded(
          child: ColoredBox(
            color: pal.bgWell,
            child: ref
                .watch(orderBookProvider)
                .when(
                  loading: () => const OrderListSkeleton(),
                  error:
                      (e, _) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.errorLoadingOrders,
                              style: TextStyle(color: pal.textSecondary),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextButton(
                              onPressed:
                                  () => ref.invalidate(orderBookProvider),
                              child: Text(l10n.retry),
                            ),
                          ],
                        ),
                      ),
                  data: (_) => orderContent(onOrderTap),
                ),
          ),
        ),
      ],
    );

    // ── Scaffold layout ───────────────────────────────────────────────────────
    // Desktop: persistent sidebar + main content in a Row (no overlay drawer).
    // Mobile/tablet: Stack with optional overlay drawer.
    final body =
        isDesktop
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

    // The scaffold background is overridden at the theme level so shared
    // chrome that reads scaffoldBackgroundColor (bottom nav) matches the
    // mock's phone background with no seam.
    return Theme(
      data: theme.copyWith(scaffoldBackgroundColor: pal.bg),
      child: Scaffold(
        backgroundColor: pal.bg,
        body: body,
        floatingActionButton: const AddOrderButton(),
        bottomNavigationBar: const BottomNavBar(),
      ),
    );
  }
}

/// Custom app bar per the mock: hamburger left, Mostro logo centered,
/// notification bell right, 52px tall over a 1px hairline.
class _MostroAppBar extends StatelessWidget {
  const _MostroAppBar({required this.palette, required this.onMenuTap});

  final OrderBookPalette palette;

  /// Null on desktop where the persistent sidebar replaces the overlay drawer.
  final VoidCallback? onMenuTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Image.asset('assets/images/mostro_logo.webp', height: 32),
                Row(
                  children: [
                    if (onMenuTap != null)
                      IconButton(
                        onPressed: onMenuTap,
                        iconSize: 22,
                        icon: Icon(Icons.menu, color: palette.textPrimary),
                        tooltip: AppLocalizations.of(context).menuTooltip,
                      ).withAutomationId(AutomationIds.appBarDrawer),
                    const Spacer(),
                    const NotificationBell(),
                  ],
                ),
              ],
            ),
          ),
        ),
        Container(height: 1, color: palette.border),
      ],
    );
  }
}
