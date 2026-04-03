import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';

/// Order list item card with 5 rows per V1 spec.
class OrderListItem extends StatelessWidget {
  const OrderListItem({
    super.key,
    required this.order,
    this.onTap,
    this.currencyFlags = const {},
  });

  final OrderItem order;
  final VoidCallback? onTap;
  final Map<String, String> currencyFlags;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final inputBg = colors?.backgroundInput ?? const Color(0xFF252A3A);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final sellColor = colors?.sellColor ?? const Color(0xFFFF8A8A);

    final isSelling = order.kind == 'sell';
    final pillLabel = order.isMine
        ? (isSelling ? 'YOU ARE SELLING' : 'YOU ARE BUYING')
        : (isSelling ? 'SELLING' : 'BUYING');
    final pillColor = isSelling ? sellColor : green;
    final premiumPositive = order.premium >= 0;
    final premiumColor = premiumPositive ? green : sellColor;
    final flag = currencyFlags[order.fiatCode] ?? '';

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
            // Row 1: Status pill + relative timestamp
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: pillColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    pillLabel,
                    style: TextStyle(
                      color: pillColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _relativeTime(order.createdAt),
                  style: theme.textTheme.bodySmall!.copyWith(color: textSec),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),

            // Row 2: Fiat amount + currency code + flag
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
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
              ],
            ),
            const SizedBox(height: AppSpacing.xs),

            // Row 3: Price type label + premium
            Text(
              'Market Price (${premiumPositive ? '+' : ''}${order.premium.toStringAsFixed(1)}%)',
              style: TextStyle(color: premiumColor, fontSize: 13),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Row 4: Payment methods
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
            const SizedBox(height: AppSpacing.xs),

            // Row 5: Rating + trade count + days active
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
                  _StarRating(rating: order.rating, color: Colors.amber),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '${order.tradeCount} trades',
                    style: TextStyle(color: textSec, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    '${order.daysActive}d',
                    style: TextStyle(color: textSec, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Fractional star rating display (up to 5 stars).
class _StarRating extends StatelessWidget {
  const _StarRating({required this.rating, required this.color});

  final double rating;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final fill = (rating - i).clamp(0.0, 1.0);
        if (fill >= 0.75) {
          return Icon(Icons.star, size: 12, color: color);
        } else if (fill >= 0.25) {
          return Icon(Icons.star_half, size: 12, color: color);
        } else {
          return Icon(Icons.star_border, size: 12, color: color);
        }
      }),
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
              _shimmerBox(60, 18, shimmer),
              _shimmerBox(40, 14, shimmer),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _shimmerBox(180, 24, shimmer),
          const SizedBox(height: AppSpacing.xs),
          _shimmerBox(140, 14, shimmer),
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
            'No orders available',
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
