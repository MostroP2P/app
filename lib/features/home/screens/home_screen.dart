import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/create_order_palette.dart';
import 'package:mostro/features/drawer/screens/drawer_menu.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';
import 'package:mostro/features/home/widgets/order_book_list.dart';
import 'package:mostro/features/home/widgets/order_list_empty.dart';
import 'package:mostro/features/home/widgets/order_sort_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/shared/widgets/add_order_button.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart';
import 'package:mostro/shared/widgets/notification_bell.dart';
import 'package:mostro/shared/widgets/order_filter.dart';
import 'package:mostro/shared/widgets/pill_segmented.dart';
import 'package:mostro/features/home/widgets/order_list_skeleton.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/shared/mascot/mostro_mascot.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';
import 'package:mostro/src/rust/api/types.dart' show TradeUpdate;

/// Side margin of every row on the screen (handoff 4b).
const double _sideInset = 18;

/// Buy/Sell switch: the list cross-fades, with no slide.
const Duration _switchDuration = Duration(milliseconds: 150);

/// Where tapping [order] leads: its own screen for an order of ours, the take
/// flow for its side otherwise.
///
/// Decided by the order, never by the tab on screen: during the tab
/// cross-fade the outgoing list is still tappable while the tab already names
/// the other side.
@visibleForTesting
String routeForOrder(OrderItem order) {
  if (order.isMine) return AppRoute.myOrderPath(order.id);
  return order.kind == 'sell'
      ? AppRoute.takeSellPath(order.id)
      : AppRoute.takeBuyPath(order.id);
}

/// Home screen — the public order book (order-book handoff, variant 4b).
///
/// App bar, Buy/Sell segmented tabs, filter row with the order count and the
/// sort, the order cards, and the create-order button (variant 4d).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _drawerOpen = false;

  void _toggleDrawer() => setState(() => _drawerOpen = !_drawerOpen);

  void _openOrder(String id) {
    final allOrders = ref.read(orderBookProvider).valueOrNull ?? [];
    final order = allOrders.where((o) => o.id == id).firstOrNull;
    // Taken or cancelled between the frame that showed it and the tap.
    if (order == null) return;
    context.push(routeForOrder(order));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pal = OrderBookPalette.of(context);
    final filteredOrders = ref.watch(filteredOrdersProvider);
    // Highlight chips computed once per visible list (not per card).
    final orderReasons = ref.watch(orderReasonsProvider);
    final flags = ref.watch(currencyFlagsProvider);
    final orderType = ref.watch(homeOrderTypeProvider);
    final sort = ref.watch(orderSortProvider);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isDesktop = screenWidth >= AppBreakpoints.desktop;

    // ── Order list: responsive column count ──────────────────────────────────
    final columns =
        isDesktop
            ? 3
            : screenWidth >= AppBreakpoints.tablet
            ? 2
            : 1;

    // Shimmer while loading, error state, empty state, or the live list.
    final book = ref.watch(orderBookProvider);
    final orders = book.when(
      loading: () => const OrderListSkeleton(),
      error:
          (_, __) => _OrderBookError(
            palette: pal,
            onRetry: () => ref.invalidate(orderBookProvider),
          ),
      data:
          (_) =>
              filteredOrders.isEmpty
                  ? const OrderListEmpty()
                  : OrderBookList(
                    orders: filteredOrders,
                    currencyFlags: flags,
                    reasons: orderReasons,
                    columns: columns,
                    onOrderTap: _openOrder,
                  ),
    );

    // ── Main content column ───────────────────────────────────────────────────
    final mainContent = Column(
      children: [
        _OrderBookAppBar(
          palette: pal,
          onMenuTap: isDesktop ? null : _toggleDrawer,
        ),
        _SideTabs(
          palette: pal,
          selected: orderType,
          onSelected:
              (type) => ref.read(homeOrderTypeProvider.notifier).state = type,
        ),
        _FilterRow(
          palette: pal,
          count: filteredOrders.length,
          sort: sort,
          // Loading or failed: there is no book yet to count or to sort.
          showsOrders: book.hasValue,
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: _switchDuration,
            layoutBuilder:
                (current, previous) => Stack(
                  fit: StackFit.expand,
                  children: [...previous, if (current != null) current],
                ),
            // Keyed by side only: a book update within the same tab rebuilds
            // the list in place instead of fading it.
            child: KeyedSubtree(key: ValueKey(orderType), child: orders),
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
    // chrome that reads scaffoldBackgroundColor matches the page with no seam.
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

// ── App bar ───────────────────────────────────────────────────────────────────

/// Hamburger left, mascot centred, notification bell right.
class _OrderBookAppBar extends StatelessWidget {
  const _OrderBookAppBar({required this.palette, required this.onMenuTap});

  final OrderBookPalette palette;

  /// Null on desktop, where the persistent sidebar replaces the overlay drawer.
  final VoidCallback? onMenuTap;

  /// Material's minimum touch target.
  static const double _target = 48;

  /// Space between a 48-dp target and its 22-dp glyph, taken out of the
  /// mock's paddings so the glyphs — not the targets — sit where it puts them.
  static const double _glyphInset = (_target - 22) / 2;

  @override
  Widget build(BuildContext context) {
    // The mock's 44 includes the status bar; below a taller one keep 12.
    final top = math.max(44.0, MediaQuery.paddingOf(context).top + 12);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        _sideInset - _glyphInset,
        top - _glyphInset,
        _sideInset - _glyphInset,
        // The target reaches 1 dp past the mock's 12 below the glyph.
        math.max(0, 12 - _glyphInset),
      ),
      child: SizedBox(
        height: _target,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const _HeaderMascot(),
            Row(
              children: [
                if (onMenuTap != null)
                  IconButton(
                    onPressed: onMenuTap,
                    style: IconButton.styleFrom(
                      minimumSize: const Size.square(_target),
                      padding: const EdgeInsets.all(_glyphInset),
                    ),
                    iconSize: 22,
                    icon: Icon(Icons.menu_rounded, color: palette.textBody),
                    tooltip: AppLocalizations.of(context).menuTooltip,
                  ).withAutomationId(AutomationIds.appBarDrawer),
                const Spacer(),
                NotificationBell(
                  iconColor: palette.textBody,
                  iconSize: 22,
                  dotColor: palette.notif,
                  dotRingColor: palette.bg,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Buy / Sell ────────────────────────────────────────────────────────────────

/// Pill-shaped segmented control. The Buy BTC tab lists sell orders (the
/// taker buys) and vice versa, so the automation ids follow the visible
/// label, not the side they filter.
class _SideTabs extends StatelessWidget {
  const _SideTabs({
    required this.palette,
    required this.selected,
    required this.onSelected,
  });

  final OrderBookPalette palette;
  final OrderType selected;
  final ValueChanged<OrderType> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final create = CreateOrderPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _sideInset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.tabTrack,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              Expanded(
                child: _SideTab(
                  label: l10n.tabBuyBtc,
                  isSelected: selected == OrderType.buy,
                  palette: palette,
                  activeStyle: PillActiveStyle(
                    fill: palette.tabActiveFill,
                    border: palette.tabActiveBorder,
                    ink: palette.limeInk,
                  ),
                  onTap: () => onSelected(OrderType.buy),
                ).withAutomationId(AutomationIds.orderBookTabBuy),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _SideTab(
                  label: l10n.tabSellBtc,
                  isSelected: selected == OrderType.sell,
                  palette: palette,
                  // Coral, like the Sell tab of create order (5a/5b).
                  activeStyle: PillActiveStyle(
                    fill: create.sellActiveBg,
                    border: create.sellActiveBorder,
                    ink: create.sellInk,
                  ),
                  onTap: () => onSelected(OrderType.sell),
                ).withAutomationId(AutomationIds.orderBookTabSell),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideTab extends StatelessWidget {
  const _SideTab({
    required this.label,
    required this.isSelected,
    required this.palette,
    required this.activeStyle,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final OrderBookPalette palette;
  final PillActiveStyle activeStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(999));

    return Semantics(
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      // The fill sits under the Material and the InkWell on it, so the ripple
      // paints over the active tab's tint instead of beneath it.
      child: AnimatedContainer(
        duration: _switchDuration,
        // Both halves carry the 1px border (transparent when inactive) so
        // switching does not shift their height.
        decoration: BoxDecoration(
          color: isSelected ? activeStyle.fill : Colors.transparent,
          borderRadius: radius,
          border: Border.all(
            color: isSelected ? activeStyle.border : Colors.transparent,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected ? activeStyle.ink : palette.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Filter row ────────────────────────────────────────────────────────────────

/// "Filter" chip + order count · current sort, which opens the sort picker.
class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.palette,
    required this.count,
    required this.sort,
    required this.showsOrders,
  });

  final OrderBookPalette palette;
  final int count;
  final OrderSort sort;

  /// Whether the book has loaded. Until it has, only the filter chip shows:
  /// "0 orders" and a sort picker over nothing would both be misleading.
  final bool showsOrders;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(_sideInset, 14, _sideInset, 12),
      child: Row(
        children: [
          Flexible(
            child: Material(
              color: palette.chipFill,
              shape: StadiumBorder(side: BorderSide(color: palette.chipBorder)),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => showOrderFilterDialog(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.filter_alt_outlined,
                        size: 14,
                        color: palette.limeIcon,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          l10n.filterButtonLabel,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: palette.textStrong,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showsOrders) ...[
            const SizedBox(width: 8),
            // The whole word, never "15 o…": on a very narrow screen it wraps.
            Flexible(
              child: Text(
                l10n.ordersCount(count),
                style: TextStyle(fontSize: 12, color: palette.textTertiary),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: InkWell(
                  onTap: () => showOrderSortSheet(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            orderSortLabel(l10n, sort),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.sortLabel,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: palette.sortLabel,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _OrderBookError extends StatelessWidget {
  const _OrderBookError({required this.palette, required this.onRetry});

  final OrderBookPalette palette;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.errorLoadingOrders,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: palette.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: palette.limeText),
              child: Text(l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}

// ── The mascot in the header ──────────────────────────────────────────────────

/// The order book's Mostro: tap it and it reacts, and it picks up the mood of
/// the app around it.
///
/// v1 hid an easter egg in this same logo, so this is where v2 keeps its own.
/// The ambient moods are deliberately cheap: the book's loading state is
/// already watched by this screen, and the trade stream is already alive for
/// the bottom bar's badge, so neither costs a subscription of its own.
class _HeaderMascot extends ConsumerStatefulWidget {
  const _HeaderMascot();

  @override
  ConsumerState<_HeaderMascot> createState() => _HeaderMascotState();
}

class _HeaderMascotState extends ConsumerState<_HeaderMascot> {
  /// How long the book may take before Mostro starts shuffling.
  static const Duration _patienceRunsOut = Duration(seconds: 6);

  /// How long the party lasts after a trade completes.
  static const Duration _celebration = Duration(milliseconds: 1400);

  static const Set<OrderStatus> _completed = {
    OrderStatus.success,
    OrderStatus.settledByAdmin,
    OrderStatus.completedByAdmin,
  };

  Timer? _patience;
  Timer? _party;
  bool _impatient = false;
  bool _celebrating = false;

  @override
  void dispose() {
    _patience?.cancel();
    _party?.cancel();
    super.dispose();
  }

  /// Starts the clock while the book is loading and stops it when it lands.
  /// Never calls `setState` itself: it runs from `build`, and the timer's
  /// callback does not.
  void _syncPatience(bool loading) {
    if (loading) {
      _patience ??= Timer(_patienceRunsOut, () {
        if (mounted) setState(() => _impatient = true);
      });
      return;
    }
    _patience?.cancel();
    _patience = null;
    if (!_impatient) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _impatient = false);
    });
  }

  void _onTradeUpdate(
    AsyncValue<TradeUpdate>? _,
    AsyncValue<TradeUpdate> next,
  ) {
    final update = next.valueOrNull;
    if (update == null || !_completed.contains(update.status)) return;
    _party?.cancel();
    setState(() => _celebrating = true);
    _party = Timer(_celebration, () {
      if (mounted) setState(() => _celebrating = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    _syncPatience(ref.watch(orderBookProvider).isLoading);
    ref.listen(tradeUpdatesProvider, _onTradeUpdate);

    final mood = switch ((_celebrating, _impatient)) {
      (true, _) => MostroMood.celebrating,
      (_, true) => MostroMood.impatient,
      _ => MostroMood.neutral,
    };

    return MostroMascot(height: 26, mood: mood, interactive: true);
  }
}
