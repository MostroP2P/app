import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/notifications/widgets/notification_group_card.dart';
import 'package:mostro/features/notifications/widgets/system_notification_banner.dart';

/// Notifications screen — Route `/notifications`.
///
/// Trade-related notifications are grouped by order id into collapsible
/// group cards (latest event shown, earlier events expandable). System
/// notifications (backup reminder, announcements) render in a separate
/// banner section at the top. Filter chips narrow the list to dispute
/// groups or system items.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

enum _NotificationFilter { all, disputes, system }

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  _NotificationFilter _filter = _NotificationFilter.all;

  @override
  Widget build(BuildContext context) {
    final backupActive = ref.watch(backupReminderProvider);
    final notifications = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context).notificationsScreenTitle),
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
            itemBuilder:
                (context) => [
                  PopupMenuItem(
                    value: _MenuAction.markAllRead,
                    child:
                        Text(AppLocalizations.of(context).markAllAsReadMenuItem),
                  ),
                  PopupMenuItem(
                    value: _MenuAction.clearAll,
                    child: Text(AppLocalizations.of(context).clearAllMenuItem),
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
          backupActive: backupActive,
          notifications: notifications,
        ),
      ),
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required bool backupActive,
    required List<NotificationModel> notifications,
  }) {
    final hasContent = backupActive || notifications.isNotEmpty;

    if (!hasContent) {
      return const _EmptyState();
    }

    // ── Partition: system items vs trade/dispute groups ──
    final systemItems = <NotificationModel>[];
    final groups = <String, List<NotificationModel>>{};
    for (final n in notifications) {
      final key = n.orderId ?? n.disputeId;
      if (key == null) {
        systemItems.add(n);
      } else {
        groups.putIfAbsent(key, () => []).add(n);
      }
    }
    systemItems.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    for (final events in groups.values) {
      events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    }
    final sortedGroups =
        groups.values.toList()
          ..sort((a, b) => b.first.timestamp.compareTo(a.first.timestamp));

    final disputeGroups =
        sortedGroups
            .where((g) => g.any((n) => n.type == NotificationType.dispute))
            .toList();
    final systemCount = systemItems.length + (backupActive ? 1 : 0);

    final showSystem =
        _filter == _NotificationFilter.all ||
        _filter == _NotificationFilter.system;
    final visibleGroups = switch (_filter) {
      _NotificationFilter.all => sortedGroups,
      _NotificationFilter.disputes => disputeGroups,
      _NotificationFilter.system => <List<NotificationModel>>[],
    };

    final notifier = ref.read(notificationsProvider.notifier);

    return Column(
      children: [
        _FilterChipsRow(
          selected: _filter,
          disputeCount: disputeGroups.length,
          systemCount: systemCount,
          onSelected: (f) => setState(() => _filter = f),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            children: [
              // ── System section (banners) ──
              if (showSystem) ...[
                if (backupActive) ...[
                  const _BackupReminderBanner(),
                  const SizedBox(height: AppSpacing.sm),
                ],
                for (final n in systemItems) ...[
                  SystemNotificationBanner(
                    notification: n,
                    onMarkRead: () => notifier.markAsRead(n.id),
                    onDelete: () => notifier.delete(n.id),
                    onTap: () => _handleTap(context, n),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
              // ── Trade groups ──
              for (final group in visibleGroups) ...[
                NotificationGroupCard(
                  notifications: group,
                  isDisputeGroup: group.first.orderId == null,
                  onMarkRead: (n) => notifier.markAsRead(n.id),
                  onDelete: (n) => notifier.delete(n.id),
                  onTapNotification: (n) => _handleTap(context, n),
                  onGoToTrade: () => _goToTrade(context, group.first),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              if ((!showSystem && visibleGroups.isEmpty) ||
                  (_filter == _NotificationFilter.system && systemCount == 0))
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.xxl),
                  child: _EmptyState(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Footer action of a group card — open the trade (or dispute) detail.
  void _goToTrade(BuildContext context, NotificationModel n) {
    if (n.orderId != null) {
      context.push(AppRoute.tradeDetailPath(n.orderId!));
    } else if (n.disputeId != null) {
      context.push(AppRoute.disputeDetailsPath(n.disputeId!));
    }
  }

  void _handleTap(BuildContext context, NotificationModel n) {
    void noId() {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).unableToOpenNotification),
          duration: const Duration(seconds: 2),
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

// ── Filter chips row ──────────────────────────────────────────────────────────

class _FilterChipsRow extends StatelessWidget {
  const _FilterChipsRow({
    required this.selected,
    required this.disputeCount,
    required this.systemCount,
    required this.onSelected,
  });

  final _NotificationFilter selected;
  final int disputeCount;
  final int systemCount;
  final ValueChanged<_NotificationFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chips = <(_NotificationFilter, String)>[
      (_NotificationFilter.all, l10n.notifFilterAll),
      (
        _NotificationFilter.disputes,
        disputeCount > 0
            ? l10n.notifFilterDisputesCount(disputeCount)
            : l10n.notifFilterDisputes,
      ),
      (
        _NotificationFilter.system,
        systemCount > 0
            ? l10n.notifFilterSystemCount(systemCount)
            : l10n.notifFilterSystem,
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: [
          for (final (filter, label) in chips) ...[
            _FilterChip(
              label: label,
              isSelected: selected == filter,
              onTap: () => onSelected(filter),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final textSec = colors?.textSecondary ?? const Color(0xFFB0B3C6);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: isSelected ? green.withValues(alpha: 0.15) : cardBg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color:
                isSelected ? green.withValues(alpha: 0.4) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            color: isSelected ? green : textSec,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── Backup reminder banner ────────────────────────────────────────────────────

class _BackupReminderBanner extends StatelessWidget {
  const _BackupReminderBanner();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);
    final amber = colors?.warningAmber ?? const Color(0xFFE89C3C);

    return GestureDetector(
      onTap: () => context.push(AppRoute.keyManagement),
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
              child: Icon(Icons.warning_amber_rounded, color: amber, size: 18),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context).youMustBackUpYourAccount,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context).tapToViewAndSaveSecretWords,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall!.copyWith(fontSize: 11),
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
      NotificationType.orderUpdate => (
        Icons.shopping_bag_outlined,
        Colors.blue,
      ),
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
      NotificationType.bondSlashed => (Icons.money_off, Colors.red),
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
            AppLocalizations.of(context).noNotifications,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(color: Colors.white38),
          ),
        ],
      ),
    );
  }
}
