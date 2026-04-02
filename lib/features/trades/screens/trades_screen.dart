import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/features/trades/widgets/trades_list_item.dart';
import 'package:mostro/shared/widgets/bottom_nav_bar.dart';
import 'package:mostro/shared/widgets/notification_bell.dart';

/// My Trades screen — Route [AppRoute.orderBook] (`/order_book`, bottom nav tab 1).
///
/// Shows all user trades sorted newest-first with a status filter dropdown.
/// Tapping a card navigates to `/trade_detail/:orderId`.
class TradesScreen extends ConsumerWidget {
  const TradesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) throw StateError('AppColors theme extension must be registered');

    final tradesAsync = ref.watch(filteredTradesWithOrderStateProvider);
    final selectedFilter = ref.watch(selectedStatusFilterProvider);

    // Reset badge and snapshot statuses whenever this screen is shown.
    ref.listen(filteredTradesWithOrderStateProvider, (_, next) {
      next.whenData((_) => resetTradeNotifications(ref));
    });

    // Also wire the bottom nav badge to orderBookNotificationCountProvider.
    ref.listen(orderBookNotificationCountProvider, (_, count) {
      ref.read(tradesNotificationCountProvider.notifier).state = count;
    });

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
            tooltip: 'Menu',
          ),
        ),
        title: Image.asset(
          'assets/images/mostro_logo.png',
          height: 28,
          errorBuilder: (_, __, ___) => Text(
            'Mostro',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
        centerTitle: true,
        actions: const [NotificationBell()],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Sub-header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'My Trades',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),

                // ── Status filter dropdown ──────────────────────────────
                _StatusFilterButton(
                  selected: selectedFilter,
                  colors: colors,
                  onChanged: (filter) {
                    if (filter != null) {
                      ref.read(selectedStatusFilterProvider.notifier).state =
                          filter;
                    }
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Trade list / loading / empty / error ─────────────────────
          Expanded(
            child: tradesAsync.when(
              data: (trades) => trades.isEmpty
                  ? _EmptyState(colors: colors)
                  : RefreshIndicator(
                      onRefresh: () {
                        refreshTrades(ref);
                        return ref.refresh(filteredTradesWithOrderStateProvider.future);
                      },
                      child: ListView.builder(
                        padding: const EdgeInsets.only(
                          top: AppSpacing.xs,
                          bottom: AppSpacing.lg,
                        ),
                        itemCount: trades.length,
                        itemBuilder: (context, index) =>
                            TradesListItem(trade: trades[index]),
                      ),
                    ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                colors: colors,
                onRetry: () =>
                    ref.invalidate(filteredTradesWithOrderStateProvider),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const BottomNavBar(),
    );
  }
}

// ── Status filter button ──────────────────────────────────────────────────────

class _StatusFilterButton extends StatelessWidget {
  const _StatusFilterButton({
    required this.selected,
    required this.colors,
    required this.onChanged,
  });

  final TradeStatusFilter selected;
  final AppColors colors;
  final ValueChanged<TradeStatusFilter?> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<TradeStatusFilter>(
      initialValue: selected,
      onSelected: onChanged,
      itemBuilder: (_) => TradeStatusFilter.values
          .map(
            (f) => PopupMenuItem(
              value: f,
              child: Text(f.label),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colors.backgroundInput,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.filter_list, size: 14, color: colors.textSecondary),
            const SizedBox(width: 4),
            Text(
              'Status | ${selected.label}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 16, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.colors});

  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_outlined, size: 64, color: colors.textSubtle),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'No trades',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Your active and completed trades will appear here.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSubtle,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.colors, required this.onRetry});

  final AppColors colors;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 48, color: colors.textSubtle),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Could not load trades',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
