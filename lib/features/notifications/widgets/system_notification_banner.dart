import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/widgets/notification_group_card.dart'
    show relativeTime;

/// Banner-style card for notifications that don't reference a trade
/// (system items: backup reminders, announcements, etc.).
///
/// Amber-bordered per the redesign mock; keeps the standard mark-as-read /
/// delete overflow actions.
class SystemNotificationBanner extends StatelessWidget {
  const SystemNotificationBanner({
    super.key,
    required this.notification,
    required this.onMarkRead,
    required this.onDelete,
    this.onTap,
  });

  final NotificationModel notification;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final amber = colors?.warningAmber ?? const Color(0xFFE89C3C);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: amber.withValues(alpha: 0.3), width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: amber,
                  size: 18,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (!notification.isRead)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: AppSpacing.sm),
                            decoration: BoxDecoration(
                              color:
                                  colors?.mostroGreen ??
                                  const Color(0xFF8CC63F),
                              shape: BoxShape.circle,
                            ),
                          ),
                        Flexible(
                          child: Text(
                            notification.title,
                            style: Theme.of(
                              context,
                            ).textTheme.bodyMedium!.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${notification.message} '
                      '· ${relativeTime(notification.timestamp, AppLocalizations.of(context))}',
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        color: textSec,
                        fontSize: 11,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              _BannerOverflowMenu(
                isRead: notification.isRead,
                onMarkRead: onMarkRead,
                onDelete: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Overflow menu ──────────────────────────────────────────────────────────────

enum _BannerMenuAction { markRead, delete }

class _BannerOverflowMenu extends StatelessWidget {
  const _BannerOverflowMenu({
    required this.isRead,
    required this.onMarkRead,
    required this.onDelete,
  });

  final bool isRead;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_BannerMenuAction>(
      iconSize: 16,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onSelected: (action) {
        switch (action) {
          case _BannerMenuAction.markRead:
            onMarkRead();
          case _BannerMenuAction.delete:
            onDelete();
        }
      },
      itemBuilder:
          (context) => [
            if (!isRead)
              PopupMenuItem(
                value: _BannerMenuAction.markRead,
                child: Text(AppLocalizations.of(context).markAsRead),
              ),
            PopupMenuItem(
              value: _BannerMenuAction.delete,
              child: Text(AppLocalizations.of(context).deleteNotificationLabel),
            ),
          ],
    );
  }
}
