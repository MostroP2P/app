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
///   the user already lived through elsewhere), or Rust only re-states a
///   status, dated now ([TradeUpdateReason.replayed]: a restore filing an
///   old trade, a re-read after the peer's reputation);
/// - its toggle in Settings → Notifications is off;
/// - it is the user's own doing (their own messages, their own cancel, the
///   maker bond of their own order) or not a trade state at all (the public
///   book's `pending` / `in-progress`). A `pending` that says the node
///   published the user's order ([TradeUpdateReason.orderPublished]) is
///   news: it comes once the maker's bond locked, often while the app was
///   closed, and its push opens Notifications. So is one that says the
///   taker walked away and the order is back in the book
///   ([TradeUpdateReason.takerLeft], #917): the maker's last card said the
///   order was in a trade.
///
/// A card records the node of its trade (#811), whichever node is active,
/// so the card can say later that it is another node's. A trade on another
/// node is heard whichever node is active, and two more rules keep its
/// cards about news:
/// - only what happened after [otherNodeCardsSince] raises one: the kind-14
///   feed replays every history, and the first run with other nodes heard
///   would turn weeks of it into cards;
/// - a trade that never started raises nothing for its end: `expired`
///   (an order nobody took), and `canceled` once its row is gone — a trade
///   canceled before it went active loses its row before its update is
///   emitted (an order nobody took, a bond left unpaid, a take not
///   completed in time). A trade that started keeps its row, and its cancel
///   (the escrow deadline, a hold invoice canceled while active) raises its
///   card.
library;

import 'package:flutter/foundation.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/trade_node.dart';
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

/// Where the first run with other nodes heard stored its cutoff (#811).
const kOtherNodeCardsSinceKey = 'otherNodeCardsSince';

/// Turns bridge events into notification cards. Every dependency is a
/// function, so the rules are tested without Rust, a router or storage.
class EventCards {
  EventCards({
    required this.notifications,
    required this.isEnabled,
    required this.identityCreatedAt,
    required this.currentLocation,
    this.disputeIdForTrade = _noDispute,
    this.tradeNodeOf = _unknownNode,
    this.activeNode = _noActiveNode,
    this.otherNodeCardsSince = _noCutoff,
    this.tradeExists = _noRow,
  });

  final NotificationsNotifier Function() notifications;

  /// Whether a Settings toggle is on.
  final bool Function(NotificationEvent event) isEnabled;

  /// When the current identity was created or imported; null when unknown,
  /// which filters nothing.
  final Future<DateTime?> Function() identityCreatedAt;

  /// The route on screen, to skip a card for the chat the user is reading.
  final String? Function() currentLocation;

  /// The id of a trade's dispute, which names the dispute chat's route: a
  /// solver message is skipped while that chat is on screen (PR #596).
  final String? Function(String tradeId) disputeIdForTrade;

  static String? _noDispute(String tradeId) => null;

  /// The node a trade lives on; empty when unknown (#811).
  final Future<String> Function(String orderId) tradeNodeOf;

  static Future<String> _unknownNode(String orderId) async => '';

  /// The active node, read when an event arrives.
  final String Function() activeNode;

  static String _noActiveNode() => '';

  /// The first run with other nodes heard: what another node did before it
  /// raises no card. Null filters nothing.
  final DateTime? Function() otherNodeCardsSince;

  static DateTime? _noCutoff() => null;

  /// Whether the trade still has its row: a trade that went active keeps it
  /// once canceled, one that never did loses it (#811).
  final Future<bool> Function(String orderId) tradeExists;

  static Future<bool> _noRow(String orderId) async => false;

  /// Whether [node] is another node than the active one.
  bool _otherNode(String node) =>
      isOnOtherNode(tradeNode: node, activeNode: activeNode());

  /// Whether [at] is from before other nodes' cards began.
  bool _predatesCutoff(DateTime at) {
    final since = otherNodeCardsSince();
    return since != null && at.isBefore(since);
  }

  Future<void> onTradeUpdate(TradeUpdate update) async {
    final event = switch (update.reason) {
      TradeUpdateReason.orderPublished ||
      TradeUpdateReason.takerLeft => NotificationEvent.tradeUpdates,
      _ => tradeCardEvent(update.status),
    };
    if (event == null) return;
    if (update.reason == TradeUpdateReason.userCanceled) return;
    // Dated now, so the identity's date cannot filter it, and on a fresh
    // install no card exists to dedupe it against (#770).
    if (update.reason == TradeUpdateReason.replayed) return;
    if (!isEnabled(event)) return;
    final at = _secondsToDate(update.occurredAt);
    if (await _predatesIdentity(at)) return;
    final node = await tradeNodeOf(update.orderId);
    if (_otherNode(node)) {
      if (update.status == OrderStatus.expired) return;
      if (update.status == OrderStatus.canceled &&
          !await tradeExists(update.orderId)) {
        return;
      }
      if (_predatesCutoff(at)) return;
    }
    await notifications().addIfNew(
      NotificationModel.tradeStatus(
        orderId: update.orderId,
        status: update.status.name,
        reason: update.reason?.name,
        at: at,
        nodePubkey: node.isEmpty ? null : node,
      ),
    );
  }

  /// Whether the room a message belongs to is on screen: the P2P chat, or
  /// the dispute chat (under either of its routes) for the solver's.
  bool _isOnScreen(String tradeId, bool fromSolver) {
    final location = currentLocation();
    if (!fromSolver) return location == AppRoute.chatRoomPath(tradeId);
    final disputeId = disputeIdForTrade(tradeId);
    return disputeId != null &&
        (location == AppRoute.disputeDetailsPath(disputeId) ||
            location == AppRoute.disputeChatPath(disputeId));
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
    final node = await tradeNodeOf(message.tradeId);
    final beforeOtherNodeCards = _otherNode(node) && _predatesCutoff(at);
    await notifier.addChatMessage(
      messageId: message.id,
      cardId: cardId,
      fold: (existing) {
        // Evaluate at commit time, after identity lookup and queued writes.
        // Even if the room has since closed, a read during those awaits wins.
        if (message.isRead ||
            predatesIdentity ||
            beforeOtherNodeCards ||
            !isEnabled(NotificationEvent.newMessages) ||
            notifier.readRevision(cardId) != readRevision ||
            _isOnScreen(message.tradeId, fromSolver)) {
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
          nodePubkey: node.isEmpty ? null : node,
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
