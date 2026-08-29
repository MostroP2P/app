import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Order list item card — pixel-exact port of the "Mostro UX Redesign" mock
/// (screen #3 · Order book with reasons to pick).
///
/// Layout, colors, and proportions mirror the mock's offer card:
/// reason pill + timestamp, 26px amount row with premium pill, "Market price"
/// caption, elevated numeric-reputation strip, and payment-method line.
/// Every card carries the palette's 9% hairline border; a [highlighted] card
/// swaps it for the green glow ring (at most one per screen — the selected /
/// action-required card).
/// Each card may carry one [OrderReason] pill (computed once per visible list
/// and passed in — never computed here).
class OrderListItem extends StatelessWidget {
  const OrderListItem({
    super.key,
    required this.order,
    this.onTap,
    this.currencyFlags = const {},
    this.reason,
    this.highlighted = false,
  });

  final OrderItem order;
  final VoidCallback? onTap;
  final Map<String, String> currencyFlags;

  /// "Reason to pick" badge awarded to this card, if any. Computed across the
  /// visible list (see [orderReasonsProvider]) and passed in by the screen.
  final OrderReason? reason;

  /// Marks this card as the screen's selected / action-required one:
  /// green [OrderBookPalette.glowBorder] + [OrderBookPalette.glowRing]
  /// instead of the plain hairline. Callers must set it on at most one
  /// card per screen — if all cards glow, none stands out.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final flag = currencyFlags[order.fiatCode] ?? '';

    // Premium pill: green < 2 (incl. negative), amber 2–5, red > 5.
    final premiumColor =
        order.premium < 2
            ? pal.green
            : order.premium > 5
            ? pal.red
            : pal.amber;
    final premiumText =
        '${NumberFormat('+0.0;-0.0', locale).format(order.premium)}%';

    final (reasonLabel, reasonColor, reasonBg) = switch (reason) {
      OrderReason.bestPremium => (
        l10n.reasonBestPremium,
        pal.green,
        pal.greenDim,
      ),
      OrderReason.mostReputable => (
        l10n.reasonMostReputable,
        pal.gold,
        pal.goldDim,
      ),
      OrderReason.justPublished => (
        l10n.reasonJustPublished,
        pal.blue,
        pal.blueFill,
      ),
      null => (null, null, null),
    };

    // The mock's cards carry no buy/sell pill (the tabs already scope the
    // side); the only functional signal kept is "yours" on own orders.
    final mineLabel =
        order.isMine
            ? (order.kind == 'sell'
                ? l10n.orderPillYouAreSelling
                : l10n.orderPillYouAreBuying)
            : null;

    // Material + InkWell (not GestureDetector) so each offer card is
    // focusable, keyboard-activatable, and announced as a button. The depth
    // shadow (and the glow ring) live on an outer DecoratedBox because
    // Material shapes clip shadows; the border rides the Material shape so
    // InkWell clips to it. With bgCard == bg the shadow is what separates
    // the card from the page.
    // The card wraps exactly one tap target, so merging is what keeps the tap
    // action on the node that carries the identifier.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: highlighted
            ? [...pal.glowRing, ...pal.cardShadow]
            : pal.cardShadow,
      ),
      child: Material(
        color: pal.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: highlighted ? pal.glowBorder : pal.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: reason pill (+ "yours" pill) · relative timestamp.
                // Pills keep their intrinsic width and wrap to a second run
                // when they don't fit beside the timestamp — shrinking them
                // ellipsized the labels on small phones ("ESTÁS COMP…").
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          // Own-order pill first: on an own order it must
                          // always be readable, so the reason badge is the
                          // one that drops to the next run when they don't
                          // fit together.
                          if (mineLabel != null)
                            _Pill(
                              label: mineLabel,
                              color: pal.textSecondary,
                              background: pal.bgElevated,
                            ),
                          if (reasonLabel != null)
                            _Pill(
                              label: reasonLabel,
                              color: reasonColor!,
                              background: reasonBg!,
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _relativeTime(order.createdAt, l10n),
                      style: TextStyle(fontSize: 11, color: pal.textTertiary),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Row 2: amount + currency + flag · premium pill
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        order.displayAmount,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: pal.textPrimary,
                          height: 1.2,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      order.fiatCode,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: pal.textSecondary,
                      ),
                    ),
                    if (flag.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(flag, style: const TextStyle(fontSize: 18)),
                    ],
                    const Spacer(),
                    _Pill(
                      label: premiumText,
                      color: premiumColor,
                      background: premiumColor.withValues(alpha: 0.13),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Row 3: "Market price" caption
                Text(
                  l10n.marketPriceCaption,
                  style: TextStyle(fontSize: 11, color: pal.textTertiary),
                ),
                const SizedBox(height: 10),

                // Row 4: numeric reputation — ★ 4.9 · 47 trades · 312 days
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: pal.bgElevated,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.star, size: 16, color: pal.gold),
                      const SizedBox(width: 4),
                      Text(
                        _formatRating(order.rating, locale),
                        style: TextStyle(
                          color: pal.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text(
                        '·',
                        style: TextStyle(fontSize: 12, color: pal.textTertiary),
                      ),
                      const SizedBox(width: 14),
                      _StatText(
                        value: NumberFormat.decimalPattern(
                          locale,
                        ).format(order.tradeCount),
                        label: l10n.reputationTradesLabel(order.tradeCount),
                        palette: pal,
                      ),
                      const SizedBox(width: 14),
                      Text(
                        '·',
                        style: TextStyle(fontSize: 12, color: pal.textTertiary),
                      ),
                      const SizedBox(width: 14),
                      Flexible(
                        child: _StatText(
                          value: NumberFormat.decimalPattern(
                            locale,
                          ).format(order.daysActive),
                          label: l10n.reputationDaysLabel(order.daysActive),
                          palette: pal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Row 5: payment methods
                Text(
                  order.paymentMethod,
                  style: TextStyle(fontSize: 12, color: pal.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    ).withAutomationId(AutomationIds.orderBookItem(order.id));
  }

  /// Mock renders raw ratings (4.9, 4.95): up to 2 decimals, no trailing
  /// zeros, localized decimal separator.
  String _formatRating(double rating, String locale) {
    return NumberFormat('0.##', locale).format(rating);
  }

  String _relativeTime(DateTime dt, AppLocalizations l10n) {
    final diff = clock.now().difference(dt);
    if (diff.isNegative || diff.inMinutes < 1) return l10n.justNow;
    if (diff.inMinutes < 60) return l10n.minutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.hoursAgo(diff.inHours);
    return l10n.daysAgo(diff.inDays);
  }
}

/// Bold-number + secondary-label stat ("47 trades") from the reputation strip.
class _StatText extends StatelessWidget {
  const _StatText({
    required this.value,
    required this.label,
    required this.palette,
  });

  final String value;
  final String label;
  final OrderBookPalette palette;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              color: palette.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(text: ' $label'),
        ],
      ),
      style: TextStyle(fontSize: 12, color: palette.textSecondary),
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Small rounded pill — mock's `sm` variant (3×8 padding, radius 8, 11px/600).
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.color,
    required this.background,
  });

  final String label;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
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
    final pal = OrderBookPalette.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: pal.bgCard,
        border: Border.all(color: pal.border),
        borderRadius: BorderRadius.circular(20),
        boxShadow: pal.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _shimmerBox(100, 18, pal.bgElevated),
              _shimmerBox(40, 14, pal.bgElevated),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _shimmerBox(140, 26, pal.bgElevated),
              _shimmerBox(48, 18, pal.bgElevated),
            ],
          ),
          const SizedBox(height: 4),
          _shimmerBox(80, 12, pal.bgElevated),
          const SizedBox(height: 10),
          _shimmerBox(double.infinity, 36, pal.bgElevated),
          const SizedBox(height: 8),
          _shimmerBox(double.infinity, 14, pal.bgElevated),
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
    final pal = OrderBookPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48, color: pal.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppLocalizations.of(context).noOrdersAvailable,
            style: TextStyle(fontSize: 14, color: pal.textSecondary),
          ),
        ],
      ),
    );
  }
}
