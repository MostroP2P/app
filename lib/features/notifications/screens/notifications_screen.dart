import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/notifications/widgets/notification_card.dart';

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
          NotificationCard(
            notification: n,
            onMarkRead: () =>
                ref.read(notificationsProvider.notifier).markAsRead(n.id),
            onDelete: () =>
                ref.read(notificationsProvider.notifier).delete(n.id),
            onTap: () => _handleTap(context, n),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  void _handleTap(BuildContext context, NotificationModel n) {
    void noId() {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open notification details.'),
          duration: Duration(seconds: 2),
        ),
      );
    }

    switch (n.type) {
      case NotificationType.ratingReceived:
      case NotificationType.tradeUpdate:
        n.orderId != null
            ? context.push(AppRoute.rateUserPath(n.orderId!))
            : noId();
      case NotificationType.paymentReceived:
      case NotificationType.payment:
        n.orderId != null
            ? context.push(AppRoute.payInvoicePath(n.orderId!))
            : noId();
      case NotificationType.invoiceRequest:
      case NotificationType.orderUpdate:
      case NotificationType.orderTaken:
        n.orderId != null
            ? context.push(AppRoute.addInvoicePath(n.orderId!))
            : noId();
      case NotificationType.dispute:
        n.disputeId != null
            ? context.push(AppRoute.disputeDetailsPath(n.disputeId!))
            : noId();
      default:
        n.orderId != null
            ? context.push(AppRoute.tradeDetailPath(n.orderId!))
            : noId();
    }
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

// ── Type icon (kept per spec — referenced by future phases) ──────────────────

// ignore: unused_element
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
      NotificationType.ratingReceived => (Icons.star, Colors.amber),
      NotificationType.paymentReceived => (Icons.attach_money, Colors.blue),
      NotificationType.invoiceRequest => (Icons.description, Colors.green),
      NotificationType.orderTaken => (Icons.add_circle_outline, Colors.green),
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
          const Icon(
            Icons.notifications_off_outlined,
            size: 48,
            color: Colors.white38,
          ),
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
