import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Order list item card — "reason to pick" redesign.
///
/// Each card may carry one [OrderReason] pill (computed once per visible list
/// and passed in — never computed here), a color-coded premium pill, and a
/// numeric reputation row.
class OrderListItem extends StatelessWidget {
  const OrderListItem({
    super.key,
    required this.order,
    this.onTap,
    this.currencyFlags = const {},
    this.reason,
  });

  final OrderItem order;
  final VoidCallback? onTap;
  final Map<String, String> currencyFlags;

  /// "Reason to pick" badge awarded to this card, if any. Computed across the
  /// visible list (see [orderReasonsProvider]) and passed in by the screen.
  final OrderReason? reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final inputBg = colors?.backgroundInput ?? const Color(0xFF252A3A);
    final textPrimary = colors?.textPrimary ?? Colors.white;
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final sellColor = colors?.sellColor ?? const Color(0xFFFF8A8A);
    final amber = colors?.warningAmber ?? const Color(0xFFE89C3C);
    final blueFill = colors?.blueAccent ?? const Color(0xFF35485E);

    final l10n = AppLocalizations.of(context);
    final isSelling = order.kind == 'sell';
    final typeLabel = switch ((order.isMine, isSelling)) {
      (true, true) => l10n.orderPillYouAreSelling,
      (true, false) => l10n.orderPillYouAreBuying,
      (false, true) => l10n.orderPillSelling,
      (false, false) => l10n.orderPillBuying,
    };
    final typeColor = isSelling ? sellColor : green;
    final flag = currencyFlags[order.fiatCode] ?? '';

    // Premium pill: green < 2 (incl. negative), amber 2–5, sell-red > 5.
    final premiumColor = order.premium < 2
        ? green
        : order.premium > 5
            ? sellColor
            : amber;
    final premiumText =
        '${order.premium >= 0 ? '+' : ''}${order.premium.toStringAsFixed(1)}%';

    // Reason pill styling (gold per design ≈ #FFC940; blue per info-blue).
    final (reasonLabel, reasonColor, reasonBg) = switch (reason) {
      OrderReason.bestPremium => (
          l10n.reasonBestPremium,
          green,
          green.withValues(alpha: 0.15),
        ),
      OrderReason.mostReputable => (
          l10n.reasonMostReputable,
          Colors.amber,
          Colors.amber.withValues(alpha: 0.15),
        ),
      OrderReason.justPublished => (
          l10n.reasonJustPublished,
          const Color(0xFF7BB4F0),
          blueFill.withValues(alpha: 0.55),
        ),
      null => (null, null, null),
    };

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: reason pill + type pill + relative timestamp
            Row(
              children: [
                if (reasonLabel != null) ...[
                  _Pill(
                    label: reasonLabel,
                    color: reasonColor!,
                    background: reasonBg!,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Flexible(
                  child: _Pill(
                    label: typeLabel,
                    color: typeColor,
                    background: typeColor.withValues(alpha: 0.12),
                    fontSize: 10,
                  ),
                ),
                const Spacer(),
                Text(
                  _relativeTime(order.createdAt, l10n),
                  style: theme.textTheme.bodySmall!.copyWith(color: textSec),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // Row 2: fiat amount + currency + flag, premium pill right-aligned
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    order.displayAmount,
                    style: theme.textTheme.headlineMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '${order.fiatCode} $flag',
                  style: theme.textTheme.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                _Pill(
                  label: premiumText,
                  color: premiumColor,
                  background: premiumColor.withValues(alpha: 0.13),
                ),
              ],
            ),
            const SizedBox(height: 2),

            // Row 3: small secondary "Market price" caption
            Text(
              l10n.marketPriceCaption,
              style: TextStyle(color: textSec, fontSize: 11),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Row 4: numeric reputation — ★ 4.9 · 47 trades · 312 days
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: inputBg,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star, size: 14, color: Colors.amber),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    order.rating.toStringAsFixed(1),
                    style: TextStyle(
                      color: textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Flexible(
                    child: Text(
                      l10n.orderReputationStats(
                          order.tradeCount, order.daysActive),
                      style: TextStyle(color: textSec, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),

            // Row 5: payment methods
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: inputBg,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Row(
                children: [
                  Icon(Icons.payment_outlined, size: 14, color: textSec),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      order.paymentMethod,
                      style: TextStyle(color: textSec, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime dt, AppLocalizations l10n) {
    final diff = clock.now().difference(dt);
    if (diff.isNegative || diff.inMinutes < 1) return l10n.justNow;
    if (diff.inMinutes < 60) return l10n.minutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.hoursAgo(diff.inHours);
    return l10n.daysAgo(diff.inDays);
  }
}

/// Small rounded pill used for reason, type, and premium badges.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.background,
    this.fontSize = 11,
  });

  final String label;
  final Color color;
  final Color background;
  final double fontSize;

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
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Skeleton shimmer placeholder for loading state.
class OrderListItemSkeleton extends StatelessWidget {
  const OrderListItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final shimmer = colors?.backgroundInput ?? const Color(0xFF252A3A);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _shimmerBox(100, 18, shimmer),
              _shimmerBox(40, 14, shimmer),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _shimmerBox(140, 24, shimmer),
              _shimmerBox(48, 18, shimmer),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _shimmerBox(80, 12, shimmer),
          const SizedBox(height: AppSpacing.sm),
          _shimmerBox(double.infinity, 24, shimmer),
          const SizedBox(height: AppSpacing.xs),
          _shimmerBox(double.infinity, 24, shimmer),
        ],
      ),
    );
  }

  Widget _shimmerBox(double width, double height, Color color) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

/// Empty state when no orders match filters.
class OrderListEmpty extends StatelessWidget {
  const OrderListEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 48, color: Colors.white38),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppLocalizations.of(context).noOrdersAvailable,
            style: Theme.of(context)
                .textTheme
                .bodyMedium!
                .copyWith(color: Colors.white38),
          ),
        ],
      ),
    );
  }
}
