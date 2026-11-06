import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/notifications/services/event_cards.dart';
import 'package:mostro/features/settings/providers/notification_prefs_provider.dart';
import 'package:mostro/src/rust/api/types.dart';

void main() {
  late DatabaseFactory factory;
  late NotificationsNotifier notifier;
  late Set<NotificationEvent> disabled;
  DateTime? identityCreatedAt;
  String? location;
  late EventCards cards;

  // Reads current notifier state without the deprecated debugState getter.
  List<NotificationModel> stateOf(NotificationsNotifier n) {
    late List<NotificationModel> snapshot;
    n.addListener((s) => snapshot = s)();
    return snapshot;
  }

  EventCards cardsFor(NotificationsNotifier n) => EventCards(
    notifications: () => n,
    isEnabled: (event) => !disabled.contains(event),
    identityCreatedAt: () async => identityCreatedAt,
    currentLocation: () => location,
    disputeIdForTrade: (tradeId) => tradeId == 'order-1' ? 'dispute-1' : null,
  );

  Future<NotificationsNotifier> openNotifier() async {
    final n = NotificationsNotifier(
      store: SembastNotificationsStore(factory: factory, path: 'n.db'),
    );
    await n.loadInitialData();
    return n;
  }

  setUp(() async {
    factory = newDatabaseFactoryMemory();
    notifier = await openNotifier();
    disabled = {};
    identityCreatedAt = null;
    location = null;
    cards = cardsFor(notifier);
  });

  TradeUpdate update(
    OrderStatus status, {
    TradeUpdateReason? reason,
    int at = 1000,
  }) => TradeUpdate(
    orderId: 'order-1',
    status: status,
    reason: reason,
    occurredAt: at,
  );

  ChatMessage message(
    String id, {
    bool isMine = false,
    MessageType type = MessageType.peer,
    int at = 1000,
  }) => ChatMessage(
    id: id,
    tradeId: 'order-1',
    senderPubkey: 'peer',
    content: 'hi',
    messageType: type,
    isMine: isMine,
    isRead: false,
    hasAttachment: false,
    createdAt: at,
    reactions: const [],
  );

  group('tradeCardEvent', () {
    test('the public book buckets and the maker bond raise no card', () {
      expect(tradeCardEvent(OrderStatus.pending), isNull);
      expect(tradeCardEvent(OrderStatus.inProgress), isNull);
      expect(tradeCardEvent(OrderStatus.waitingMakerBond), isNull);
    });

    test('each status answers to its Settings toggle', () {
      expect(
        tradeCardEvent(OrderStatus.waitingPayment),
        NotificationEvent.paymentAlerts,
      );
      expect(
        tradeCardEvent(OrderStatus.success),
        NotificationEvent.paymentAlerts,
      );
      expect(
        tradeCardEvent(OrderStatus.dispute),
        NotificationEvent.disputeUpdates,
      );
      expect(
        tradeCardEvent(OrderStatus.settledByAdmin),
        NotificationEvent.disputeUpdates,
      );
      expect(
        tradeCardEvent(OrderStatus.fiatSent),
        NotificationEvent.tradeUpdates,
      );
      expect(
        tradeCardEvent(OrderStatus.canceled),
        NotificationEvent.tradeUpdates,
      );
    });
  });

  group('trade cards', () {
    test('a status change adds one card dated by the daemon message', () async {
      await cards.onTradeUpdate(update(OrderStatus.active, at: 1757860000));

      final card = stateOf(notifier).single;
      expect(card.id, 'trade-order-1-active');
      expect(card.type, NotificationType.tradeUpdate);
      expect(card.orderId, 'order-1');
      expect(
        card.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1757860000 * 1000),
      );
    });

    test('a replay of the same transition adds nothing', () async {
      await cards.onTradeUpdate(update(OrderStatus.active));
      await cards.onTradeUpdate(update(OrderStatus.active));

      expect(stateOf(notifier), hasLength(1));
    });

    test('the node publishing the order raises a card', () async {
      // The book's `pending` is no news; the node's `new-order` once the
      // maker's bond locked is, and it is what woke the maker: a tap on
      // that push opens Notifications, which must say what it was about.
      await cards.onTradeUpdate(update(OrderStatus.pending));
      expect(stateOf(notifier), isEmpty);

      await cards.onTradeUpdate(
        update(
          OrderStatus.pending,
          reason: TradeUpdateReason.orderPublished,
          at: 1757860000,
        ),
      );

      final card = stateOf(notifier).single;
      expect(card.id, 'trade-order-1-pending-orderPublished');
      expect(card.tradeStatus, 'pending');
      expect(card.tradeReason, 'orderPublished');
      expect(
        card.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1757860000 * 1000),
      );
    });

    test('a taker walking away raises a card', () async {
      // The maker's last card said the order was in a trade. The taker
      // cancelled or let the window lapse, and the node put the order back
      // in the book (#917): the `pending` is news this time.
      await cards.onTradeUpdate(
        update(
          OrderStatus.pending,
          reason: TradeUpdateReason.takerLeft,
          at: 1757860000,
        ),
      );

      final card = stateOf(notifier).single;
      expect(card.id, 'trade-order-1-pending-takerLeft');
      expect(card.tradeStatus, 'pending');
      expect(card.tradeReason, 'takerLeft');
    });

    test('a taker walking away answers to the trade updates toggle', () async {
      disabled = {NotificationEvent.tradeUpdates};

      await cards.onTradeUpdate(
        update(OrderStatus.pending, reason: TradeUpdateReason.takerLeft),
      );

      expect(stateOf(notifier), isEmpty);
    });

    test('the publication answers to the trade updates toggle', () async {
      disabled = {NotificationEvent.tradeUpdates};

      await cards.onTradeUpdate(
        update(OrderStatus.pending, reason: TradeUpdateReason.orderPublished),
      );

      expect(stateOf(notifier), isEmpty);
    });

    test('a re-stated status raises nothing, even with no card yet', () async {
      // A restore and a reputation re-read re-state a status as `replayed`,
      // dated now (#770): on a fresh install no card exists to dedupe it
      // against, and the identity's date cannot tell it from news.
      await cards.onTradeUpdate(
        update(OrderStatus.success, reason: TradeUpdateReason.replayed),
      );
      await cards.onTradeUpdate(update(OrderStatus.active));
      await cards.onTradeUpdate(
        update(OrderStatus.active, reason: TradeUpdateReason.replayed),
      );

      expect(stateOf(notifier).map((n) => n.id), ['trade-order-1-active']);
    });

    // #811: cards of a trade on another node.
    const nodeA = 'aa11';
    const nodeB = 'bb22';
    final cutoff = DateTime.fromMillisecondsSinceEpoch(5000 * 1000);
    EventCards onNode(String active, {bool rowKept = false}) => EventCards(
      notifications: () => notifier,
      isEnabled: (_) => true,
      identityCreatedAt: () async => null,
      currentLocation: () => null,
      tradeNodeOf: (orderId) async => nodeA,
      activeNode: () => active,
      otherNodeCardsSince: () => cutoff,
      tradeExists: (orderId) async => rowKept,
    );

    test('a card records the node of its trade', () async {
      await onNode(nodeA).onTradeUpdate(update(OrderStatus.active, at: 6000));

      expect(stateOf(notifier).single.nodePubkey, nodeA);
    });

    test(
      'another node raises a card, with its node, after the cutoff',
      () async {
        await onNode(
          nodeB,
        ).onTradeUpdate(update(OrderStatus.waitingPayment, at: 6000));

        final card = stateOf(notifier).single;
        expect(card.id, 'trade-order-1-waitingPayment');
        expect(card.nodePubkey, nodeA);
      },
    );

    test('what another node did before the cutoff raises no card', () async {
      // Its history replays whichever node is active: the first run with
      // other nodes heard must not turn it into cards.
      await onNode(
        nodeB,
      ).onTradeUpdate(update(OrderStatus.waitingPayment, at: 4000));

      expect(stateOf(notifier), isEmpty);
    });

    test('the active node is not held to the cutoff', () async {
      await onNode(nodeA).onTradeUpdate(update(OrderStatus.active, at: 4000));

      expect(stateOf(notifier), hasLength(1));
    });

    test('a trade on another node that never started raises no card', () async {
      // canceled without a row / expired: an order nobody took, a bond left
      // unpaid, a take not completed in time.
      final elsewhere = onNode(nodeB);
      await elsewhere.onTradeUpdate(update(OrderStatus.canceled, at: 6000));
      await elsewhere.onTradeUpdate(update(OrderStatus.expired, at: 6000));
      expect(stateOf(notifier), isEmpty);

      await elsewhere.onTradeUpdate(
        update(OrderStatus.cooperativelyCanceled, at: 6000),
      );
      expect(
        stateOf(notifier).single.id,
        'trade-order-1-cooperativelyCanceled',
      );
    });

    test('a started trade canceled on another node raises its card', () async {
      // The escrow deadline or a hold invoice canceled while active: the
      // trade went active, so it kept its row.
      await onNode(
        nodeB,
        rowKept: true,
      ).onTradeUpdate(update(OrderStatus.canceled, at: 6000));

      final card = stateOf(notifier).single;
      expect(card.id, 'trade-order-1-canceled');
      expect(card.nodePubkey, nodeA);
    });

    test('on its own node a canceled trade still raises its card', () async {
      await onNode(nodeA).onTradeUpdate(update(OrderStatus.canceled, at: 6000));

      expect(stateOf(notifier), hasLength(1));
    });

    test(
      'a chat card records its node, and another node waits for the cutoff',
      () async {
        final elsewhere = onNode(nodeB);
        await elsewhere.onChatMessage(message('m1', at: 4000));
        expect(stateOf(notifier), isEmpty, reason: 'before the cutoff');

        await elsewhere.onChatMessage(message('m2', at: 6000));
        final card = stateOf(notifier).single;
        expect(card.id, 'chat-order-1');
        expect(card.nodePubkey, nodeA);
      },
    );

    test('a later status on the same order adds its own card', () async {
      await cards.onTradeUpdate(update(OrderStatus.active));
      await cards.onTradeUpdate(update(OrderStatus.fiatSent, at: 2000));

      expect(stateOf(notifier).map((n) => n.id), [
        'trade-order-1-fiatSent',
        'trade-order-1-active',
      ]);
    });

    test('a toggle that is off silences only its statuses', () async {
      disabled = {NotificationEvent.tradeUpdates};

      await cards.onTradeUpdate(update(OrderStatus.active));
      await cards.onTradeUpdate(update(OrderStatus.waitingPayment));

      expect(stateOf(notifier).single.id, 'trade-order-1-waitingPayment');
    });

    test('history from before the identity raises nothing', () async {
      identityCreatedAt = DateTime.fromMillisecondsSinceEpoch(2000 * 1000);

      await cards.onTradeUpdate(update(OrderStatus.active, at: 1000));
      await cards.onTradeUpdate(update(OrderStatus.fiatSent, at: 3000));

      expect(stateOf(notifier).single.id, 'trade-order-1-fiatSent');
    });

    test('the user\'s own cancel raises nothing; the maker\'s does', () async {
      await cards.onTradeUpdate(
        update(OrderStatus.canceled, reason: TradeUpdateReason.userCanceled),
      );
      expect(stateOf(notifier), isEmpty);

      await cards.onTradeUpdate(
        update(OrderStatus.canceled, reason: TradeUpdateReason.makerCanceled),
      );
      expect(
        stateOf(notifier).single.id,
        'trade-order-1-canceled-makerCanceled',
      );
    });

    test(
      'a cooperative-cancel request raises a card for either side',
      () async {
        // The requester's confirmation: their own doing, but it says the
        // trade now waits on the counterparty, which they need to know.
        await cards.onTradeUpdate(
          update(
            OrderStatus.active,
            reason: TradeUpdateReason.cooperativeCancelRequestedByMe,
          ),
        );
        // The counterparty's request, after the fiat was sent.
        await cards.onTradeUpdate(
          update(
            OrderStatus.fiatSent,
            reason: TradeUpdateReason.cooperativeCancelRequestedByPeer,
          ),
        );
        // A replay of the same request adds nothing.
        await cards.onTradeUpdate(
          update(
            OrderStatus.fiatSent,
            reason: TradeUpdateReason.cooperativeCancelRequestedByPeer,
          ),
        );

        expect(stateOf(notifier).map((n) => n.id), [
          'trade-order-1-fiatSent-cooperativeCancelRequestedByPeer',
          'trade-order-1-active-cooperativeCancelRequestedByMe',
        ]);
      },
    );

    test('a book-only status raises nothing', () async {
      await cards.onTradeUpdate(update(OrderStatus.pending));
      await cards.onTradeUpdate(update(OrderStatus.inProgress));

      expect(stateOf(notifier), isEmpty);
    });
  });

  group('chat cards', () {
    test('incoming messages fold into one card per trade', () async {
      await cards.onChatMessage(message('m1'));
      await cards.onChatMessage(message('m2', at: 2000));

      final card = stateOf(notifier).single;
      expect(card.id, 'chat-order-1');
      expect(card.type, NotificationType.message);
      expect(card.orderId, 'order-1');
      expect(card.chatUnreadCount, 2);
      expect(card.isRead, isFalse);
      expect(card.timestamp, DateTime.fromMillisecondsSinceEpoch(2000 * 1000));
    });

    test('a message delivered twice counts once', () async {
      await cards.onChatMessage(message('m1'));
      await cards.onChatMessage(message('m1'));

      expect(stateOf(notifier).single.chatUnreadCount, 1);
    });

    test('the user\'s own messages raise nothing', () async {
      await cards.onChatMessage(message('m1', isMine: true));

      expect(stateOf(notifier), isEmpty);
    });

    test('nothing while that chat is on screen', () async {
      location = AppRoute.chatRoomPath('order-1');

      await cards.onChatMessage(message('m1'));

      expect(stateOf(notifier), isEmpty);
    });

    test('no solver card while the dispute chat is on screen', () async {
      for (final path in [
        AppRoute.disputeDetailsPath('dispute-1'),
        AppRoute.disputeChatPath('dispute-1'),
      ]) {
        location = path;
        await cards.onChatMessage(message('s-$path', type: MessageType.admin));
      }
      expect(stateOf(notifier), isEmpty);

      // The P2P chat on screen hides the peer's messages, not the solver's.
      location = AppRoute.chatRoomPath('order-1');
      await cards.onChatMessage(message('s2', type: MessageType.admin));
      expect(stateOf(notifier).single.id, 'chat-order-1-solver');
    });

    test(
      'a message suppressed in an open chat stays suppressed after restart',
      () async {
        location = AppRoute.chatRoomPath('order-1');
        await cards.onChatMessage(message('seen'));
        location = null;
        final restarted = await openNotifier();
        await cardsFor(restarted).onChatMessage(message('seen'));
        expect(stateOf(restarted), isEmpty);
        await cardsFor(restarted).onChatMessage(message('new'));
        expect(stateOf(restarted).single.chatUnreadCount, 1);
      },
    );

    test('a card the user read starts counting again', () async {
      await cards.onChatMessage(message('m1'));
      await notifier.markAsRead('chat-order-1');
      await cards.onChatMessage(message('m2'));

      final card = stateOf(notifier).single;
      expect(card.chatUnreadCount, 1);
      expect(card.isRead, isFalse);
    });

    test(
      'a deleted card returns with the next message, not a replay',
      () async {
        await cards.onChatMessage(message('m1'));
        await notifier.delete('chat-order-1');

        await cards.onChatMessage(message('m1'));
        expect(stateOf(notifier), isEmpty);

        await cards.onChatMessage(message('m2'));
        expect(stateOf(notifier).single.chatUnreadCount, 1);
      },
    );

    test('the solver keeps a card of their own', () async {
      await cards.onChatMessage(message('m1'));
      await cards.onChatMessage(message('s1', type: MessageType.admin));

      final byId = {for (final n in stateOf(notifier)) n.id: n};
      expect(
        byId.keys,
        unorderedEquals(['chat-order-1', 'chat-order-1-solver']),
      );
      expect(byId['chat-order-1-solver']!.isSolverChatCard, isTrue);
      expect(byId['chat-order-1']!.isSolverChatCard, isFalse);
    });

    test('a toggle that is off, or history before the identity, raises '
        'nothing', () async {
      disabled = {NotificationEvent.newMessages};
      await cards.onChatMessage(message('m1'));
      expect(stateOf(notifier), isEmpty);

      disabled = {};
      identityCreatedAt = DateTime.fromMillisecondsSinceEpoch(2000 * 1000);
      await cards.onChatMessage(message('m2', at: 1000));
      expect(stateOf(notifier), isEmpty);
    });

    test('a restart neither recounts nor loses the card', () async {
      await cards.onChatMessage(message('m1'));

      final restarted = await openNotifier();
      final restartedCards = cardsFor(restarted);
      await restartedCards.onChatMessage(message('m1')); // replay
      expect(stateOf(restarted).single.chatUnreadCount, 1);

      await restartedCards.onChatMessage(message('m2'));
      expect(stateOf(restarted).single.chatUnreadCount, 2);
    });
  });

  group('pumpEvents', () {
    test('a failing event does not stop the loop; null ends it', () async {
      final queue = <int?>[1, 2, 3, null];
      final handled = <int>[];
      final ended = Completer<void>();

      pumpEvents<int>(
        'test',
        () async {
          final next = queue.removeAt(0);
          if (next == null) ended.complete();
          return next;
        },
        (event) async {
          handled.add(event);
          if (event == 2) throw StateError('boom');
        },
      );

      await ended.future;
      expect(handled, [1, 2, 3]);
    });
  });
}
