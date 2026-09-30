import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;

import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;

/// Pure rules of the Notifications screen (issue #610): what a notice means
/// to the user, its icon, and where it sits in the list. Kept free of widgets
/// so every mapping is unit-tested.

/// What a notice means to the user, which picks its color.
enum NoticeTone {
  /// The next step is the user's.
  action,

  /// The other side, or the node, has to move.
  waiting,

  /// Messages from the trade partner.
  chat,

  /// A dispute, the resolver, or a lost bond.
  dispute,

  /// The trade is over.
  done,

  /// Anything else: node notices and older records.
  info,
}

/// [isBuyer] is the user's side of the trade, null when its row is gone:
/// whose turn a status is depends on it (`active` is the buyer's step and
/// the seller's wait), so without it a live status reads as waiting.
///
/// Derived from [TradeRowState.of], the mapping My Trades uses, so both
/// screens agree on whose turn a status is. A past event is never an
/// invitation to rate, hence `canRate: false`.
NoticeTone noticeTone(NotificationModel n, {bool? isBuyer}) {
  if (n.isChatCard) {
    return n.isSolverChatCard ? NoticeTone.dispute : NoticeTone.chat;
  }
  switch (n.type) {
    case NotificationType.bondSlashed:
    case NotificationType.dispute:
      return NoticeTone.dispute;
    case NotificationType.bondClaim:
      return n.isBondClaimPaid ? NoticeTone.done : NoticeTone.action;
    default:
      break;
  }
  switch (n.tradeReason) {
    case 'cooperativeCancelRequestedByPeer':
      return NoticeTone.action;
    case 'cooperativeCancelRequestedByMe':
      return NoticeTone.waiting;
  }
  final status = _orderStatus(n.tradeStatus);
  if (status == null) return NoticeTone.info;
  if (isBuyer == null) {
    if (status == OrderStatus.dispute) return NoticeTone.dispute;
    return _isOver(status) ? NoticeTone.done : NoticeTone.waiting;
  }
  final row = TradeRowState.of(
    status: status,
    isBuyer: isBuyer,
    ratedByMe: true,
    canRate: false,
  );
  return switch (row.chipKind) {
    TradeChipKind.action => NoticeTone.action,
    TradeChipKind.waiting => NoticeTone.waiting,
    TradeChipKind.dispute => NoticeTone.dispute,
    TradeChipKind.done => NoticeTone.done,
  };
}

/// The icon of a notice: what happened, not how it is stored.
IconData noticeIcon(NotificationModel n) {
  if (n.isChatCard) {
    return n.isSolverChatCard ? Icons.gavel_rounded : Icons.chat_bubble_outline;
  }
  switch (n.type) {
    case NotificationType.bondSlashed:
      return Icons.warning_amber_rounded;
    case NotificationType.bondClaim:
      return Icons.savings_outlined;
    case NotificationType.dispute:
      return Icons.gavel_rounded;
    case NotificationType.system:
      return Icons.info_outline;
    default:
      break;
  }
  if (n.tradeReason?.startsWith('cooperativeCancelRequested') ?? false) {
    return Icons.undo_rounded;
  }
  return switch (n.tradeStatus) {
    'waitingBuyerInvoice' => Icons.receipt_long_outlined,
    'waitingPayment' => Icons.hourglass_top_rounded,
    'waitingTakerBond' => Icons.shield_outlined,
    'active' => Icons.lock_outline,
    'fiatSent' => Icons.payments_outlined,
    'settledHoldInvoice' || 'settledByAdmin' => Icons.lock_open_rounded,
    'success' || 'completedByAdmin' => Icons.check_circle_outline,
    'canceled' ||
    'cooperativelyCanceled' ||
    'canceledByAdmin' => Icons.cancel_outlined,
    'expired' => Icons.timer_off_outlined,
    'dispute' => Icons.gavel_rounded,
    null => Icons.notifications_none_rounded,
    _ => Icons.sync_rounded,
  };
}

OrderStatus? _orderStatus(String? name) =>
    name == null
        ? null
        : OrderStatus.values.where((s) => s.name == name).firstOrNull;

bool _isOver(OrderStatus s) => switch (s) {
  OrderStatus.success ||
  OrderStatus.canceled ||
  OrderStatus.expired ||
  OrderStatus.cooperativelyCanceled ||
  OrderStatus.canceledByAdmin ||
  OrderStatus.settledByAdmin ||
  OrderStatus.completedByAdmin => true,
  _ => false,
};

// ── Sections ──────────────────────────────────────────────────────────────────

/// One card of the list: a trade's (or dispute's) notices, newest first, or
/// a notice that belongs to no trade.
@immutable
sealed class NoticeEntry {
  const NoticeEntry();

  /// The time the entry sorts by: its newest notice.
  DateTime get latestAt;
}

final class NoticeGroupEntry extends NoticeEntry {
  const NoticeGroupEntry(this.events);

  /// Newest first; never empty.
  final List<NotificationModel> events;

  String? get orderId => events.first.orderId;

  @override
  DateTime get latestAt => events.first.timestamp;
}

final class NoticeSystemEntry extends NoticeEntry {
  const NoticeSystemEntry(this.notification);

  final NotificationModel notification;

  @override
  DateTime get latestAt => notification.timestamp;
}

@immutable
class NoticeSections {
  const NoticeSections({required this.needsAction, required this.recent});

  /// Trades whose next step is the user's right now, newest first.
  final List<NoticeGroupEntry> needsAction;

  /// Everything else in one timeline, newest first.
  final List<NoticeEntry> recent;
}

/// Groups [notices] by trade (or dispute) and splits them into the two
/// sections. [needsAction] answers from the trade's **current** state, not
/// from its notices: an old "add your invoice" whose invoice was sent long
/// ago must not pin its trade.
NoticeSections sectionNotices(
  List<NotificationModel> notices, {
  required bool Function(String orderId) needsAction,
}) {
  final groups = <String, List<NotificationModel>>{};
  final recent = <NoticeEntry>[];
  for (final n in notices) {
    final key = n.orderId ?? n.disputeId;
    if (key == null) {
      recent.add(NoticeSystemEntry(n));
    } else {
      groups.putIfAbsent(key, () => []).add(n);
    }
  }
  final pinned = <NoticeGroupEntry>[];
  for (final events in groups.values) {
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final entry = NoticeGroupEntry(events);
    final orderId = entry.orderId;
    if (orderId != null && needsAction(orderId)) {
      pinned.add(entry);
    } else {
      recent.add(entry);
    }
  }
  int newestFirst(NoticeEntry a, NoticeEntry b) =>
      b.latestAt.compareTo(a.latestAt);
  pinned.sort(newestFirst);
  recent.sort(newestFirst);
  return NoticeSections(needsAction: pinned, recent: recent);
}
