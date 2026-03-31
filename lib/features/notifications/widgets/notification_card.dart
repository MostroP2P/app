import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';

class NotificationCard extends StatelessWidget {
  const NotificationCard({
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
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: notification.isRead
                    ? null
                    : Border.all(color: Colors.white12, width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TypeIconCircle(type: notification.type),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                notification.title,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge!
                                    .copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                              ),
                            ),
                            _OverflowMenu(
                              isRead: notification.isRead,
                              onMarkRead: onMarkRead,
                              onDelete: onDelete,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          notification.message,
                          style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                                color: textSec,
                                fontSize: 14,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (notification.detail != null &&
                            notification.detail!.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.sm),
                          _DetailSection(detail: notification.detail!),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          _relativeTime(notification.timestamp),
                          style: Theme.of(context).textTheme.bodySmall!.copyWith(
                                color: textSec,
                                fontSize: 12,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Unread dot — top-right of the card
            if (!notification.isRead)
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF8CC63F),
                    shape: BoxShape.circle,
                  ),
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

// ── Detail section ─────────────────────────────────────────────────────────────

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.detail});

  final Map<String, String> detail;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final bg = colors?.backgroundInput ?? const Color(0xFF252A3A);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        border: const Border(
          left: BorderSide(color: Colors.blue, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: detail.entries
            .map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Text(
                      '${e.key}: ',
                      style: Theme.of(context).textTheme.bodySmall!.copyWith(
                            fontSize: 12,
                            color: Colors.white70,
                          ),
                    ),
                    Flexible(
                      child: Text(
                        e.value,
                        style:
                            Theme.of(context).textTheme.bodySmall!.copyWith(
                                  fontSize: 12,
                                  color: Colors.white,
                                ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ── Overflow menu ──────────────────────────────────────────────────────────────

enum _CardMenuAction { markRead, delete }

class _OverflowMenu extends StatelessWidget {
  const _OverflowMenu({
    required this.isRead,
    required this.onMarkRead,
    required this.onDelete,
  });

  final bool isRead;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_CardMenuAction>(
      iconSize: 18,
      padding: EdgeInsets.zero,
      onSelected: (action) {
        switch (action) {
          case _CardMenuAction.markRead:
            onMarkRead();
          case _CardMenuAction.delete:
            onDelete();
        }
      },
      itemBuilder: (_) => [
        if (!isRead)
          const PopupMenuItem(
            value: _CardMenuAction.markRead,
            child: Text('Mark as read'),
          ),
        const PopupMenuItem(
          value: _CardMenuAction.delete,
          child: Text('Delete'),
        ),
      ],
    );
  }
}

// ── Type icon circle ───────────────────────────────────────────────────────────

class _TypeIconCircle extends StatelessWidget {
  const _TypeIconCircle({required this.type});

  final NotificationType type;

  @override
  Widget build(BuildContext context) {
    final (icon, bg) = switch (type) {
      NotificationType.ratingReceived ||
      NotificationType.tradeUpdate =>
        (Icons.star, Colors.amber),
      NotificationType.paymentReceived ||
      NotificationType.payment =>
        (Icons.attach_money, Colors.blue),
      NotificationType.invoiceRequest ||
      NotificationType.orderUpdate =>
        (Icons.description, Colors.green),
      NotificationType.orderTaken =>
        (Icons.add_circle, Colors.green),
      NotificationType.dispute => (Icons.gavel, Colors.red),
      NotificationType.cancellation => (Icons.cancel, Colors.orange),
      NotificationType.message => (Icons.chat_bubble, Colors.teal),
      NotificationType.system => (Icons.info, Colors.grey),
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.2),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: bg, size: 20),
    );
  }
}