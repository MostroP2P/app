import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';

/// Collapsible card grouping all notifications that reference the same
/// trade (order id) or dispute.
///
/// Collapsed it shows the latest event only; "View N earlier events"
/// expands the remaining events inline. A footer action navigates to the
/// trade (or dispute) detail screen.
class NotificationGroupCard extends StatefulWidget {
  const NotificationGroupCard({
    super.key,
    required this.notifications,
    required this.onMarkRead,
    required this.onDelete,
    required this.onTapNotification,
    required this.onGoToTrade,
    this.isDisputeGroup = false,
  });

  /// Events for this trade, sorted newest first. Must not be empty.
  final List<NotificationModel> notifications;
  final ValueChanged<NotificationModel> onMarkRead;
  final ValueChanged<NotificationModel> onDelete;
  final ValueChanged<NotificationModel> onTapNotification;
  final VoidCallback onGoToTrade;

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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final hasDispute = widget.notifications.any(
      (n) => n.type == NotificationType.dispute,
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border:
            _unreadCount > 0
                ? Border.all(color: Colors.white12, width: 1)
                : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: dot + trade label + unread badge ──
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: hasDispute ? const Color(0xFFD84D4D) : green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  _groupTitle(AppLocalizations.of(context)),
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_unreadCount > 0)
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: green,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$_unreadCount',
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Latest event ──
          _EventRow(
            notification: _latest,
            highlight: true,
            onMarkRead: () => widget.onMarkRead(_latest),
            onDelete: () => widget.onDelete(_latest),
            onTap: () => widget.onTapNotification(_latest),
          ),

          // ── Earlier events (expandable) ──
          if (_expanded && _earlier.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            for (final n in _earlier)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: _EventRow(
                  notification: n,
                  highlight: false,
                  onMarkRead: () => widget.onMarkRead(n),
                  onDelete: () => widget.onDelete(n),
                  onTap: () => widget.onTapNotification(n),
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.sm),

          // ── Footer: expand toggle + go to trade ──
          Row(
            children: [
              Expanded(
                child:
                    _earlier.isEmpty
                        ? const SizedBox.shrink()
                        : InkWell(
                          onTap: () => setState(() => _expanded = !_expanded),
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _expanded
                                      ? Icons.keyboard_arrow_up
                                      : Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: textSec,
                                ),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    _expanded
                                        ? AppLocalizations.of(context)
                                            .hideEarlierEvents
                                        : AppLocalizations.of(context)
                                            .viewEarlierEvents(_earlier.length),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall!
                                        .copyWith(color: textSec, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
              ),
              InkWell(
                onTap: widget.onGoToTrade,
                borderRadius: BorderRadius.circular(AppRadius.chip),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.isDisputeGroup
                            ? AppLocalizations.of(context).viewDisputeButton
                            : AppLocalizations.of(context).goToTrade,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
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
          ),
        ],
      ),
    );
  }

  /// "Trade · 5,400 sats" when an amount is derivable from any event's
  /// detail map, otherwise "Trade #a1b2c3d4" (short order id).
  String _groupTitle(AppLocalizations l10n) {
    final label = widget.isDisputeGroup ? l10n.disputeWord : l10n.tradeWord;
    final sats = _deriveSats();
    if (sats != null) {
      return '$label · $sats sats';
    }
    final id = _latest.orderId ?? _latest.disputeId ?? '';
    final shortId = id.length > 8 ? id.substring(0, 8) : id;
    return '$label #$shortId';
  }

  /// Looks for an "N sats" amount in any event's detail values.
  String? _deriveSats() {
    final re = RegExp(r'([\d,.]+)\s*sats?\b');
    for (final n in widget.notifications) {
      final detail = n.detail;
      if (detail == null) continue;
      for (final value in detail.values) {
        final match = re.firstMatch(value);
        if (match != null) return match.group(1);
      }
    }
    return null;
  }
}

// ── Single event row inside a group ──────────────────────────────────────────

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.notification,
    required this.highlight,
    required this.onMarkRead,
    required this.onDelete,
    required this.onTap,
  });

  final NotificationModel notification;

  /// Latest event gets a tinted pill; earlier events render muted.
  final bool highlight;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);
    final isDispute = notification.type == NotificationType.dispute;
    final pillColor = isDispute ? const Color(0xFFD84D4D) : green;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Row(
        children: [
          Flexible(
            child:
                highlight
                    ? Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: pillColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        notification.resolvedTitle(AppLocalizations.of(context)),
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: pillColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                    : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!notification.isRead)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: green,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Flexible(
                          child: Text(
                            notification.resolvedTitle(AppLocalizations.of(context)),
                            style: Theme.of(context).textTheme.bodySmall!
                                .copyWith(color: textSec, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '· ${relativeTime(notification.timestamp, AppLocalizations.of(context))}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall!.copyWith(color: textSec, fontSize: 11),
          ),
          const Spacer(),
          _EventOverflowMenu(
            isRead: notification.isRead,
            onMarkRead: onMarkRead,
            onDelete: onDelete,
          ),
        ],
      ),
    );
  }
}

// ── Overflow menu (per event) ─────────────────────────────────────────────────

enum _EventMenuAction { markRead, delete }

class _EventOverflowMenu extends StatelessWidget {
  const _EventOverflowMenu({
    required this.isRead,
    required this.onMarkRead,
    required this.onDelete,
  });

  final bool isRead;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_EventMenuAction>(
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onSelected: (action) {
        switch (action) {
          case _EventMenuAction.markRead:
            onMarkRead();
          case _EventMenuAction.delete:
            onDelete();
        }
      },
      itemBuilder:
          (context) => [
            if (!isRead)
              PopupMenuItem(
                value: _EventMenuAction.markRead,
                child: Text(AppLocalizations.of(context).markAsRead),
              ),
            PopupMenuItem(
              value: _EventMenuAction.delete,
              child: Text(AppLocalizations.of(context).deleteNotificationLabel),
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
