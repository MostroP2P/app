import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';

/// A single card row in the My Trades list.
///
/// Layout:
/// ┌──────────────────────────────────────────────────────── ❯ ─┐
/// │ Selling / Buying Bitcoin                                    │
/// │ [Status chip]  [Role chip]                                  │
/// │ 🏦 966 ARS · 2 hours ago    Mercado Pago                   │
/// └─────────────────────────────────────────────────────────────┘
///
/// Watches [tradeStatusProvider] to keep the status chip current without
/// requiring a full list reload.
///
/// Tap → navigates to `/my_order/:orderId`.
class TradesListItem extends ConsumerWidget {
  const TradesListItem({
    super.key,
    required this.trade,
  });

  final TradeListItem trade;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = Theme.of(context).extension<AppColors>();
    if (colors == null) throw StateError('AppColors theme extension must be registered');
    final textTheme = Theme.of(context).textTheme;

    // Live status from the polling provider; falls back to the DB snapshot.
    final liveStatusAsync = ref.watch(tradeStatusProvider(trade.orderId));
    final effectiveStatus = liveStatusAsync.whenOrNull(
          data: orderStatusToFilter,
        ) ??
        trade.status;

    final titleText = trade.isSelling ? 'Selling Bitcoin' : 'Buying Bitcoin';
    final (statusBg, statusFg) = _statusColors(effectiveStatus);
    final statusLabel = effectiveStatus.label;
    final roleLabel =
        trade.role == TradeRole.creator ? 'Created by you' : 'Taken by you';
    final timeAgo = _timeAgo(trade.createdAt);

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.card),
        onTap: () => context.push(AppRoute.myOrderPath(trade.orderId)),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Main content ───────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: Title
                    Text(
                      titleText,
                      style: textTheme.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),

                    // Row 2: Status + role chips
                    Wrap(
                      spacing: AppSpacing.xs,
                      children: [
                        _Chip(
                          label: statusLabel,
                          background: statusBg,
                          foreground: statusFg,
                        ),
                        _Chip(
                          label: roleLabel,
                          background: AppColors.statusActive.$1,
                          foreground: AppColors.statusActive.$2,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),

                    // Row 3: Amount + time + payment method
                    Row(
                      children: [
                        Icon(
                          Icons.account_balance_outlined,
                          size: 14,
                          color: colors.textSubtle,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${trade.fiatAmount} ${trade.fiatCurrency}',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '· $timeAgo',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textSubtle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      trade.paymentMethod,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSubtle,
                      ),
                    ),
                  ],
                ),
              ),

              // ── Chevron ────────────────────────────────────────
              Icon(
                Icons.chevron_right,
                color: colors.textSubtle,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Maps a [TradeStatusFilter] to (background, foreground) colors.
  static (Color, Color) _statusColors(TradeStatusFilter status) {
    return switch (status) {
      TradeStatusFilter.pending => AppColors.statusPending,
      TradeStatusFilter.active => AppColors.statusActive,
      TradeStatusFilter.fiatSent => AppColors.statusActive,
      TradeStatusFilter.success => AppColors.statusSuccess,
      TradeStatusFilter.canceled => AppColors.statusInactive,
      TradeStatusFilter.dispute => AppColors.statusDispute,
      // `all` is a filter sentinel, not a real trade status.
      TradeStatusFilter.all => AppColors.statusInactive,
    };
  }

  /// Returns a compact "time ago" string from a unix timestamp (e.g. "4m", "2h", "3d").
  static String _timeAgo(int unixSeconds) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000);
    final diff = DateTime.now().difference(dt);

    if (diff.isNegative || diff.inSeconds < 60) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }
}

// ── Small chip widget ─────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w500,
              fontSize: 11,
            ),
      ),
    );
  }
}
