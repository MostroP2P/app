/// In-app cards for trade status changes and chat messages (issue #474).
///
/// A push carries no payload (docs/PUSH_NOTIFICATIONS.md §2.3), so a tap
/// opens Notifications and these cards say what the wake was about. They are
/// built from the same Rust streams the screens read, whether the event is
/// live or part of a replay: trade cards go through
/// [NotificationsNotifier.addIfNew] keyed on order + status, and chat cards
/// fold every message of a trade into one card, each message counted once.
///
/// Three filters keep the list about news:
/// - the event predates the current identity (a restore replays history
///   the user already lived through elsewhere);
/// - its toggle in Settings → Notifications is off;
/// - it is the user's own doing (their own messages, their own cancel, the
///   maker bond of their own order) or not a trade state at all (the public
///   book's `pending` / `in-progress`).
library;

import 'package:flutter/foundation.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/settings/providers/notification_prefs_provider.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart';

/// The toggle that gates a status's card, or null when the status raises none.
NotificationEvent? tradeCardEvent(OrderStatus status) => switch (status) {
  // The public book's buckets and the maker's own bond: not news.
  OrderStatus.pending ||
  OrderStatus.inProgress ||
  OrderStatus.waitingMakerBond => null,
  OrderStatus.waitingBuyerInvoice ||
  OrderStatus.waitingPayment ||
  OrderStatus.waitingTakerBond ||
  OrderStatus.settledHoldInvoice ||
  OrderStatus.success => NotificationEvent.paymentAlerts,
  OrderStatus.dispute ||
  OrderStatus.canceledByAdmin ||
  OrderStatus.settledByAdmin ||
  OrderStatus.completedByAdmin => NotificationEvent.disputeUpdates,
  OrderStatus.active ||
  OrderStatus.fiatSent ||
  OrderStatus.canceled ||
  OrderStatus.expired ||
  OrderStatus.cooperativelyCanceled => NotificationEvent.tradeUpdates,
};

/// Turns bridge events into notification cards. Every dependency is a
/// function, so the rules are tested without Rust, a router or storage.
class EventCards {
  EventCards({
    required this.notifications,
    required this.isEnabled,
    required this.identityCreatedAt,
    required this.currentLocation,
  });

  final NotificationsNotifier Function() notifications;

  /// Whether a Settings toggle is on.
  final bool Function(NotificationEvent event) isEnabled;

  /// When the current identity was created or imported; null when unknown,
  /// which filters nothing.
  final Future<DateTime?> Function() identityCreatedAt;

  /// The route on screen, to skip a card for the chat the user is reading.
  final String? Function() currentLocation;

  Future<void> onTradeUpdate(TradeUpdate update) async {
    final event = tradeCardEvent(update.status);
    if (event == null) return;
    if (update.reason == TradeUpdateReason.userCanceled) return;
    if (!isEnabled(event)) return;
    final at = _secondsToDate(update.occurredAt);
    if (await _predatesIdentity(at)) return;
    await notifications().addIfNew(
      NotificationModel.tradeStatus(
        orderId: update.orderId,
        status: update.status.name,
        reason: update.reason?.name,
        at: at,
      ),
    );
  }

  Future<void> onChatMessage(ChatMessage message) async {
    if (message.isMine || message.messageType == MessageType.system) return;
    final notifier = notifications();
    if (notifier.hasProcessedChatMessage(message.id)) return;
    final fromSolver = message.messageType == MessageType.admin;
    final cardId = NotificationModel.chatCardId(
      message.tradeId,
      fromSolver: fromSolver,
    );
    final readRevision = notifier.readRevision(cardId);
    final at = _secondsToDate(message.createdAt);
    final predatesIdentity = await _predatesIdentity(at);
    await notifier.addChatMessage(
      messageId: message.id,
      cardId: cardId,
      fold: (existing) {
        // Evaluate at commit time, after identity lookup and queued writes.
        // Even if the room has since closed, a read during those awaits wins.
        if (message.isRead ||
            predatesIdentity ||
            !isEnabled(NotificationEvent.newMessages) ||
            notifier.readRevision(cardId) != readRevision ||
            (!fromSolver &&
                currentLocation() == AppRoute.chatRoomPath(message.tradeId))) {
          return null;
        }
        return NotificationModel.chatMessages(
          tradeId: message.tradeId,
          fromSolver: fromSolver,
          count:
              existing == null || existing.isRead
                  ? 1
                  : existing.chatUnreadCount + 1,
          at:
              existing != null && existing.timestamp.isAfter(at)
                  ? existing.timestamp
                  : at,
        );
      },
    );
  }

  Future<bool> _predatesIdentity(DateTime at) async {
    final since = await identityCreatedAt();
    return since != null && at.isBefore(since);
  }

  static DateTime _secondsToDate(Object seconds) =>
      DateTime.fromMillisecondsSinceEpoch(platformInt64ToInt(seconds) * 1000);
}

/// Feeds [next] into [handle] for the process lifetime, the way the bond
/// consumers in `app_bootstrap.dart` do: a failure on one event is logged and
/// the loop goes on; only a closed stream (null) or a throwing [next] ends it.
void pumpEvents<T>(
  String label,
  Future<T?> Function() next,
  Future<void> Function(T event) handle,
) {
  Future.microtask(() async {
    while (true) {
      final T? event;
      try {
        event = await next();
      } catch (e, st) {
        debugPrint('[$label] stream closed: $e\n$st');
        return;
      }
      if (event == null) return;
      try {
        await handle(event);
      } catch (e, st) {
        debugPrint('[$label] failed to record card: $e\n$st');
      }
    }
  });
}
