import 'package:flutter/material.dart';

import 'package:mostro/core/activity_palette.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/models/notification_view_rules.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/features/trades/widgets/trade_card.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Collapsible card grouping all notifications that reference the same
/// trade (order id) or dispute (issue #610).
///
/// The header says which trade it is — the user's side, the amount and the
/// payment method, from [tradeRow] — and, when the next step is the user's,
/// the step itself. The latest event shows in full: icon, whole title and
/// message. Earlier events expand below it as a one-line timeline. A footer
/// action navigates to the trade (or dispute) detail screen. The card has no
/// per-event menu: the screen deletes it with a swipe.
class NotificationGroupCard extends StatefulWidget {
  const NotificationGroupCard({
    super.key,
    required this.notifications,
    required this.onTapNotification,
    required this.onGoToTrade,
    this.tradeRow,
    this.isDisputeGroup = false,
  });

  /// Events for this trade, sorted newest first. Must not be empty.
  final List<NotificationModel> notifications;
  final ValueChanged<NotificationModel> onTapNotification;
  final VoidCallback onGoToTrade;

  /// The trade as My Trades shows it; null while the trades load, or once
  /// the row is gone (wiped or deleted), when the header falls back to the
  /// short id.
  final TradeRow? tradeRow;

  /// True when the group is keyed by a dispute id (no order id available).
  final bool isDisputeGroup;

  @override
  State<NotificationGroupCard> createState() => _NotificationGroupCardState();
}

class _NotificationGroupCardState extends State<NotificationGroupCard> {
  bool _expanded = false;

  NotificationModel get _latest => widget.notifications.first;

  List<NotificationModel> get _earlier => widget.notifications.skip(1).toList();

  int get _unreadCount => widget.notifications.where((n) => !n.isRead).length;

  /// The user's side, which decides whose turn a status is; unknown without
  /// a trade row.
  bool? get _isBuyer {
    final row = widget.tradeRow;
    return row == null || row.claimOnly ? null : !row.isSelling;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final pal = ActivityPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final row = widget.tradeRow;
    final needsAction = row?.state.needsAction ?? false;
    final isDispute =
        widget.isDisputeGroup ||
        widget.notifications.any(
          (n) => noticeTone(n, isBuyer: _isBuyer) == NoticeTone.dispute,
        );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color:
              isDispute
                  ? pal.chipDisputeBorder
                  : needsAction
                  ? pal.borderAction
                  : _unreadCount > 0
                  ? Colors.white12
                  : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            row: row,
            fallbackId: _latest.orderId ?? _latest.disputeId ?? '',
            isDisputeGroup: widget.isDisputeGroup,
            isDispute: isDispute,
            unreadCount: _unreadCount,
          ),
          if (needsAction && row!.state.verb != TradeRowVerb.none) ...[
            const SizedBox(height: AppSpacing.sm),
            _ActionTag(label: TradeCard.verbText(row.state.verb, l10n)),
          ],
          const SizedBox(height: AppSpacing.md),
          _LatestEvent(
            notification: _latest,
            isBuyer: _isBuyer,
            onTap: () => widget.onTapNotification(_latest),
          ),
          if (_expanded && _earlier.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            for (final n in _earlier)
              _TimelineEvent(
                notification: n,
                isBuyer: _isBuyer,
                isLast: identical(n, _earlier.last),
                onTap: () => widget.onTapNotification(n),
              ),
          ],
          const SizedBox(height: AppSpacing.sm),
          _Footer(
            earlierCount: _earlier.length,
            expanded: _expanded,
            isDisputeGroup: widget.isDisputeGroup,
            onToggle: () => setState(() => _expanded = !_expanded),
            onGoToTrade: widget.onGoToTrade,
          ),
        ],
      ),
    );
  }
}

// ── Header: which trade this is ───────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.row,
    required this.fallbackId,
    required this.isDisputeGroup,
    required this.isDispute,
    required this.unreadCount,
  });

  final TradeRow? row;
  final String fallbackId;
  final bool isDisputeGroup;
  final bool isDispute;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final pal = ActivityPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final shortId =
        fallbackId.length > 8 ? fallbackId.substring(0, 8) : fallbackId;
    final row = this.row;
    final hasTrade = row != null && !row.claimOnly;

    final String title;
    final String subtitle;
    if (!hasTrade) {
      title = '${isDisputeGroup ? l10n.disputeWord : l10n.tradeWord} #$shortId';
      subtitle = row == null ? '' : paymentMethodLabel(row.paymentMethod);
    } else {
      title = tradeAmountSummary(
        l10n,
        isSelling: row.isSelling,
        fiatAmount: row.fiatAmount,
        fiatAmountMin: row.fiatAmountMin,
        fiatAmountMax: row.fiatAmountMax,
        fiatCode: row.fiatCode,
        sats: row.amountSats,
        locale: locale,
      );
      subtitle = [
        paymentMethodLabel(row.paymentMethod),
        '#$shortId',
      ].where((s) => s.isNotEmpty).join(' · ');
    }
    final (icon, iconColor) =
        isDispute
            ? (Icons.gavel_rounded, pal.chipDisputeInk)
            : !hasTrade
            ? (Icons.swap_horiz_rounded, textSec)
            : row.isSelling
            ? (Icons.arrow_upward_rounded, pal.sellArrow)
            : (Icons.arrow_downward_rounded, pal.buyArrow);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle.isNotEmpty)
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: textSec, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        if (unreadCount > 0) ...[
          const SizedBox(width: AppSpacing.sm),
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: green, shape: BoxShape.circle),
            child: Text(
              '$unreadCount',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The step the user owes, as My Trades names it (`Add invoice`, `Release`).
class _ActionTag extends StatelessWidget {
  const _ActionTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final pal = ActivityPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: pal.chipActionBg,
        border: Border.all(color: pal.chipActionBorder),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bolt_rounded, size: 13, color: pal.chipActionInk),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              color: pal.chipActionInk,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Events ────────────────────────────────────────────────────────────────────

/// Ink and background of a notice's icon, by what it means to the user.
({Color ink, Color bg}) _toneColors(BuildContext context, NoticeTone tone) {
  final pal = ActivityPalette.of(context);
  final colors = Theme.of(context).extension<AppColors>();
  final blue = colors?.blueAccent ?? const Color(0xFF5B9BD5);
  final grey = colors?.textSecondary ?? const Color(0xFFB0B3C6);
  return switch (tone) {
    NoticeTone.action => (ink: pal.chipActionInk, bg: pal.chipActionBg),
    NoticeTone.waiting => (ink: pal.chipWaitInk, bg: pal.chipWaitBg),
    NoticeTone.chat => (ink: blue, bg: blue.withValues(alpha: 0.15)),
    NoticeTone.dispute => (ink: pal.chipDisputeInk, bg: pal.chipDisputeBg),
    NoticeTone.done => (ink: pal.chipDoneInk, bg: pal.chipDoneBg),
    NoticeTone.info => (ink: grey, bg: grey.withValues(alpha: 0.12)),
  };
}

/// The newest event in full: icon, whole title, message, time.
class _LatestEvent extends StatelessWidget {
  const _LatestEvent({
    required this.notification,
    required this.isBuyer,
    required this.onTap,
  });

  final NotificationModel notification;
  final bool? isBuyer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final l10n = AppLocalizations.of(context);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final tone = _toneColors(
      context,
      noticeTone(notification, isBuyer: isBuyer),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: tone.bg, shape: BoxShape.circle),
            child: Icon(noticeIcon(notification), size: 17, color: tone.ink),
          ),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        notification.resolvedTitle(l10n),
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: Colors.white,
                          fontWeight:
                              notification.isRead
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        relativeTime(notification.timestamp, l10n),
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: textSec,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  notification.resolvedMessage(l10n),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: textSec, fontSize: 13),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One line of the expanded history: icon on the rail, whole title, time.
class _TimelineEvent extends StatelessWidget {
  const _TimelineEvent({
    required this.notification,
    required this.isBuyer,
    required this.isLast,
    required this.onTap,
  });

  final NotificationModel notification;
  final bool? isBuyer;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final l10n = AppLocalizations.of(context);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final rail = VerticalDivider(
      color: textSec.withValues(alpha: 0.3),
      width: 1,
    );
    final tone = _toneColors(
      context,
      noticeTone(notification, isBuyer: isBuyer),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // The rail joining the events, under the latest event's icon.
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  Expanded(child: rail),
                  Icon(noticeIcon(notification), size: 15, color: tone.ink),
                  Expanded(child: isLast ? const SizedBox.shrink() : rail),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
            if (!notification.isRead)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: AppSpacing.xs + 2),
                decoration: BoxDecoration(color: green, shape: BoxShape.circle),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  notification.resolvedTitle(l10n),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: textSec, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              relativeTime(notification.timestamp, l10n),
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: textSec, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Footer: expand toggle + go to trade ───────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({
    required this.earlierCount,
    required this.expanded,
    required this.isDisputeGroup,
    required this.onToggle,
    required this.onGoToTrade,
  });

  final int earlierCount;
  final bool expanded;
  final bool isDisputeGroup;
  final VoidCallback onToggle;
  final VoidCallback onGoToTrade;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final l10n = AppLocalizations.of(context);
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final small = Theme.of(context).textTheme.bodySmall!;

    return Row(
      children: [
        Expanded(
          child:
              earlierCount == 0
                  ? const SizedBox.shrink()
                  : Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: onToggle,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              expanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              size: 16,
                              color: textSec,
                            ),
                            const SizedBox(width: 2),
                            Flexible(
                              child: Text(
                                expanded
                                    ? l10n.hideEarlierEvents
                                    : l10n.viewEarlierEvents(earlierCount),
                                style: small.copyWith(
                                  color: textSec,
                                  fontSize: 12,
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
        InkWell(
          onTap: onGoToTrade,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isDisputeGroup ? l10n.viewDisputeButton : l10n.goToTrade,
                  style: small.copyWith(
                    color: green,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.arrow_forward, size: 14, color: green),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shared relative-time formatter for notification widgets.
String relativeTime(DateTime dt, AppLocalizations l10n) {
  final diff = DateTime.now().difference(dt);
  if (diff.isNegative || diff.inMinutes < 1) return l10n.justNow;
  if (diff.inMinutes < 60) return l10n.minutesAgo(diff.inMinutes);
  if (diff.inHours < 24) return l10n.hoursAgo(diff.inHours);
  return l10n.daysAgo(diff.inDays);
}
