import 'package:flutter/material.dart';

import 'package:mostro/core/activity_palette.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/widgets/notification_group_card.dart'
    show relativeTime;
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart' show AnnouncementSeverity;

/// Banner-style card for notifications that don't reference a trade:
/// system items and project announcements (specs/006 §6.2).
///
/// Tapping it reads it; the screen deletes it with a swipe (issue #610). An
/// announcement is painted by its level (§3.4): `info` in the lime the
/// action chips use, `warning` in the amber a plain system notice always
/// had, `critical` in the dispute red — each with its own icon and label, so
/// the distinction survives without colour. The publisher never chooses any
/// of this. When the announcement carries a link, [onOpenLink] shows the one
/// tappable thing beyond the card itself; the body is never a link.
class SystemNotificationBanner extends StatelessWidget {
  const SystemNotificationBanner({
    super.key,
    required this.notification,
    this.onTap,
    this.onOpenLink,
  });

  final NotificationModel notification;
  final VoidCallback? onTap;

  /// Opens the announcement's link; null when there is none.
  final VoidCallback? onOpenLink;

  /// A card's corners (DS-CMP-8) and the tile inside it (guide §4).
  static const _cardRadius = 18.0;
  static const _tileRadius = 12.0;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = ActivityPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final tone = _tone(pal, notification.announcementSeverity);
    final label = notification.announcementLevelLabel(l10n);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_cardRadius),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: book.surface,
            borderRadius: BorderRadius.circular(_cardRadius),
            border: Border.all(color: tone.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: tone.bg,
                  borderRadius: BorderRadius.circular(_tileRadius),
                ),
                child: Icon(tone.icon, color: tone.ink, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (label != null) ...[
                      Text(
                        label.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: tone.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Row(
                      children: [
                        if (!notification.isRead)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: pal.chipActionDot,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Flexible(
                          child: Text(
                            notification.resolvedTitle(l10n),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: book.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${notification.resolvedMessage(l10n)} '
                      '· ${relativeTime(notification.timestamp, l10n)}',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: book.textSecondary,
                      ),
                      // An announcement body runs to 500 characters (§3.2):
                      // the card shows it whole rather than hiding the one
                      // sentence that mattered.
                      maxLines: notification.isAnnouncement ? null : 2,
                      overflow:
                          notification.isAnnouncement
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                    ),
                    if (onOpenLink != null) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: onOpenLink,
                        borderRadius: BorderRadius.circular(_tileRadius),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 4,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.open_in_new_rounded,
                                size: 14,
                                color: tone.ink,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                l10n.announcementOpenLink,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: tone.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The level's paint (§3.4), from the Activity chips so the card agrees
  /// with the trade cards next to it. A plain system notice keeps the amber
  /// it always had.
  static ({Color bg, Color border, Color ink, IconData icon}) _tone(
    ActivityPalette pal,
    AnnouncementSeverity? severity,
  ) => switch (severity) {
    AnnouncementSeverity.info => (
      bg: pal.chipActionBg,
      border: pal.chipActionBorder,
      ink: pal.chipActionInk,
      icon: Icons.info_outline_rounded,
    ),
    AnnouncementSeverity.critical => (
      bg: pal.chipDisputeBg,
      border: pal.chipDisputeBorder,
      ink: pal.chipDisputeInk,
      icon: Icons.shield_outlined,
    ),
    AnnouncementSeverity.warning || null => (
      bg: pal.chipWaitBg,
      border: pal.chipWaitBorder,
      ink: pal.chipWaitInk,
      icon: Icons.warning_amber_rounded,
    ),
  };
}
