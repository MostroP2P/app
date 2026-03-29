import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';

/// Notifications screen — Route `/notifications`.
///
/// Shows a scrollable list of notifications with a pinned backup reminder
/// card at the top when active. Supports Mark all as read and Clear all.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backupActive = ref.watch(backupReminderProvider);
    final notifications = ref.watch(notificationsProvider);
    final colors = Theme.of(context).extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          PopupMenuButton<_MenuAction>(
            onSelected: (action) {
              switch (action) {
                case _MenuAction.markAllRead:
                  ref.read(notificationsProvider.notifier).markAllAsRead();
                case _MenuAction.clearAll:
                  ref.read(notificationsProvider.notifier).deleteAll();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _MenuAction.markAllRead,
                child: Text('Mark all as read'),
              ),
              PopupMenuItem(
                value: _MenuAction.clearAll,
                child: Text('Clear all'),
              ),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          // Full refresh wired in Phase 5 with Sembast persistence.
        },
        child: _buildBody(
          context: context,
          ref: ref,
          backupActive: backupActive,
          notifications: notifications,
          green: green,
        ),
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required WidgetRef ref,
    required bool backupActive,
    required List<NotificationModel> notifications,
    required Color green,
  }) {
    final hasContent = backupActive || notifications.isNotEmpty;

    if (!hasContent) {
      return const _EmptyState();
    }

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      children: [
        if (backupActive) ...[
          _BackupReminderCard(green: green),
          const SizedBox(height: AppSpacing.sm),
        ],
        for (final n in notifications) ...[
          _NotificationCard(
            notification: n,
            onMarkRead: () =>
                ref.read(notificationsProvider.notifier).markAsRead(n.id),
            onDelete: () =>
                ref.read(notificationsProvider.notifier).delete(n.id),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

enum _MenuAction { markAllRead, clearAll }

// ── Backup reminder card ──────────────────────────────────────────────────────

class _BackupReminderCard extends StatelessWidget {
  const _BackupReminderCard({required this.green});

  final Color green;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);

    return GestureDetector(
      onTap: () => context.push(AppRoute.keyManagement),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: const Color(0xFFD84D4D), width: 1),
        ),
        child: Row(
          children: [
            const Icon(Icons.gavel, color: Color(0xFFD84D4D), size: 24),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You must back up your account',
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFD84D4D),
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap to view and save your secret words.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Notification card ─────────────────────────────────────────────────────────

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onMarkRead,
    required this.onDelete,
  });

  final NotificationModel notification;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);

    return GestureDetector(
      onTap: () {
        if (notification.orderId != null) {
          context.push(AppRoute.tradeDetailPath(notification.orderId!));
        } else if (notification.disputeId != null) {
          context.push(AppRoute.disputeDetailsPath(notification.disputeId!));
        }
      },
      onLongPress: () => _showContextMenu(context),
      child: Container(
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
            _TypeIcon(type: notification.type),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          fontWeight: notification.isRead
                              ? FontWeight.normal
                              : FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    notification.message,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall!
                        .copyWith(color: textSec),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _relativeTime(notification.timestamp),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall!
                            .copyWith(color: textSec),
                      ),
                      if (!notification.isRead)
                        GestureDetector(
                          onTap: onMarkRead,
                          child: Text(
                            'Mark as read',
                            style:
                                Theme.of(context).textTheme.labelSmall!.copyWith(
                                      color: colors?.mostroGreen,
                                    ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!notification.isRead)
              ListTile(
                leading: const Icon(Icons.mark_email_read_outlined),
                title: const Text('Mark as read'),
                onTap: () {
                  Navigator.pop(context);
                  onMarkRead();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(context);
                onDelete();
              },
            ),
          ],
        ),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.type});

  final NotificationType type;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (type) {
      NotificationType.orderUpdate => (Icons.shopping_bag_outlined, Colors.blue),
      NotificationType.tradeUpdate => (Icons.star_outline, Colors.amber),
      NotificationType.payment => (Icons.bolt_outlined, Colors.yellow),
      NotificationType.dispute => (Icons.gavel, Colors.red),
      NotificationType.cancellation => (Icons.cancel_outlined, Colors.orange),
      NotificationType.message => (Icons.chat_bubble_outline, Colors.teal),
      NotificationType.system => (Icons.info_outline, Colors.grey),
    };
    return Icon(icon, color: color, size: 22);
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.notifications_off_outlined, size: 48, color: Colors.white38),
          const SizedBox(height: AppSpacing.md),
          Text(
            'No notifications',
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
