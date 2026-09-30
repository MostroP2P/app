import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/models/notification_view_rules.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/notifications/widgets/bond_slashed_dialog.dart';
import 'package:mostro/features/notifications/widgets/notification_group_card.dart';
import 'package:mostro/features/notifications/widgets/system_notification_banner.dart';
import 'package:mostro/features/cashu/seller_funding_route.dart';
import 'package:mostro/features/settings/providers/escrow_mode_provider.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';

/// Notifications screen — Route `/notifications`.
///
/// One list (issue #610): trade-related notifications are grouped by order
/// id into collapsible group cards (latest event in full, earlier events
/// expandable), and notices that belong to no trade sit among them by time.
/// Trades whose next step is the user's right now are pinned above the rest,
/// under their own header.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Notices swiped away whose snack bar is still open: hidden at once, so
  /// the dismissed card leaves the tree, and deleted only if not undone.
  final Set<String> _hidden = {};

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
                    child: Text(
                      AppLocalizations.of(context).markAllAsReadMenuItem,
                    ),
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
    final visible = [
      for (final n in notifications)
        if (!_hidden.contains(n.id)) n,
    ];
    final hasContent = backupActive || visible.isNotEmpty;

    if (!hasContent) {
      return const _EmptyState();
    }

    // The trades as My Trades sees them: the header of each group, and
    // whether its next step is the user's. Until they load, every group
    // shows its short id and nothing is pinned.
    final rows = ref.watch(tradeRowsProvider).valueOrNull ?? const <TradeRow>[];
    final rowsById = {for (final r in rows) r.orderId: r};
    final sections = sectionNotices(
      visible,
      needsAction: (id) => rowsById[id]?.state.needsAction ?? false,
    );
    final pinned = sections.needsAction.isNotEmpty;

    Widget entryCard(NoticeEntry entry) => switch (entry) {
      // Keyed by trade so an expanded card stays expanded when it moves.
      NoticeGroupEntry(:final events) => _Swipeable(
        key: ValueKey(
          'group-${events.first.orderId ?? events.first.disputeId}',
        ),
        onDismissed: () => _dismiss(events),
        child: NotificationGroupCard(
          notifications: events,
          tradeRow: rowsById[events.first.orderId],
          isDisputeGroup: events.first.orderId == null,
          onTapNotification: (n) => _handleTap(context, n),
          onGoToTrade: () => _goToTrade(context, events),
        ),
      ),
      NoticeSystemEntry(:final notification) => _Swipeable(
        key: ValueKey('notice-${notification.id}'),
        onDismissed: () => _dismiss([notification]),
        child: SystemNotificationBanner(
          notification: notification,
          onTap: () => _handleTap(context, notification),
        ),
      ),
    };

    final l10n = AppLocalizations.of(context);
    return ListView(
      // #267: add the bottom system-bar inset so the last item isn't
      // hidden behind the gesture / 3-button navigation bar.
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md + MediaQuery.of(context).viewPadding.bottom,
      ),
      children: [
        if (backupActive) ...[
          const _BackupReminderBanner(),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (pinned) _SectionHeader(l10n.tradesGroupNeedsAction),
        for (final entry in sections.needsAction) ...[
          entryCard(entry),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (pinned && sections.recent.isNotEmpty)
          _SectionHeader(l10n.notifSectionRecent),
        for (final entry in sections.recent) ...[
          entryCard(entry),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  /// A card swiped away (issue #610): hidden now, with an Undo; deleted once
  /// the snack bar closes any other way — timeout, another swipe, leaving
  /// the screen. The notifier outlives the screen, so the delete still runs.
  void _dismiss(List<NotificationModel> events) {
    final ids = {for (final n in events) n.id};
    setState(() => _hidden.addAll(ids));
    final notifier = ref.read(notificationsProvider.notifier);
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    // A second swipe settles the first card's snack bar: it is deleted.
    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: Text(l10n.notificationDeletedSnack(ids.length)),
            // With an action a snack bar would stay until dismissed, and
            // the notices would stay hidden without being deleted.
            persist: false,
            action: SnackBarAction(
              label: l10n.notificationDeletedUndo,
              onPressed: () {},
            ),
          ),
        )
        .closed
        .then((reason) async {
          if (reason != SnackBarClosedReason.action) {
            await Future.wait([for (final id in ids) notifier.delete(id)]);
          }
          // Ids can come back (a chat card is re-created by the next
          // message), so none stays hidden once settled.
          if (mounted) setState(() => _hidden.removeAll(ids));
        });
  }

  /// Footer action of a group card — open the trade (or dispute) detail.
  /// The user is going to see where the trade stands, so its notices are
  /// read (issue #610); a dispute group, keyed without an order, by its ids.
  void _goToTrade(BuildContext context, List<NotificationModel> group) {
    final n = group.first;
    final notifier = ref.read(notificationsProvider.notifier);
    if (n.orderId != null) {
      notifier.markOrderAsRead(n.orderId!);
    } else {
      for (final e in group) {
        if (!e.isRead) notifier.markAsRead(e.id);
      }
    }
    if (n.orderId != null) {
      context.push(AppRoute.tradeDetailPath(n.orderId!));
    } else if (n.disputeId != null) {
      context.push(AppRoute.disputeDetailsPath(n.disputeId!));
    }
  }

  void _handleTap(BuildContext context, NotificationModel n) {
    // Opening a notice reads it (issue #610). Not awaited: the write must
    // never hold up the navigation. The resolver's chat card is the
    // exception: it opens the trade, not the dispute chat that owns its read
    // state, so the user has not seen those messages yet.
    if (!n.isRead && !n.isSolverChatCard) {
      ref.read(notificationsProvider.notifier).markAsRead(n.id);
    }
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
        n.orderId != null
            ? context.push(AppRoute.rateUserPath(n.orderId!))
            : noId();
      // A peer chat card opens that chat; the solver's opens the trade,
      // like a trade status card (the default below).
      case NotificationType.message
          when n.orderId != null && !n.isSolverChatCard:
        context.push(AppRoute.chatRoomPath(n.orderId!));
      case NotificationType.paymentReceived:
      case NotificationType.payment:
        n.orderId != null
            ? context.push(
              sellerFundingPath(
                n.orderId!,
                cashu: ref.read(isCashuModeProvider),
              ),
            )
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
      case NotificationType.bondClaim:
        n.orderId != null
            ? context.push(AppRoute.bondPayoutPath(n.orderId!))
            : noId();
      case NotificationType.bondSlashed:
        BondSlashedDialog.show(context, n);
      default:
        n.orderId != null
            ? context.push(AppRoute.tradeDetailPath(n.orderId!))
            : noId();
    }
  }
}

enum _MenuAction { markAllRead, clearAll }

// ── Swipe to delete ───────────────────────────────────────────────────────────

/// A card the user can swipe away, either way, to delete it. Screen readers
/// get the same through a custom action, since a swipe is not one they make.
class _Swipeable extends StatelessWidget {
  const _Swipeable({
    required super.key,
    required this.onDismissed,
    required this.child,
  });

  final VoidCallback onDismissed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final red = colors?.destructiveRed ?? const Color(0xFFD84D4D);
    Widget background(Alignment alignment) => Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Icon(Icons.delete_outline_rounded, color: red),
    );
    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(
              label: AppLocalizations.of(context).deleteNotificationLabel,
            ):
            onDismissed,
      },
      child: Dismissible(
        key: key!,
        onDismissed: (_) => onDismissed(),
        background: background(Alignment.centerLeft),
        secondaryBackground: background(Alignment.centerRight),
        child: child,
      ),
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        bottom: AppSpacing.sm,
        left: AppSpacing.xs,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.bodySmall!.copyWith(
          color: colors?.textSecondary ?? const Color(0xFFB0B3C6),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
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
