import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations en;
  late AppLocalizations es;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    es = await AppLocalizations.delegate.load(const Locale('es'));
  });

  final at = DateTime.fromMillisecondsSinceEpoch(1757860000000);

  group('NotificationModel.tradeStatus', () {
    test('stores markers, not copy, and renders per locale', () {
      final n = NotificationModel.tradeStatus(
        orderId: 'order-1',
        status: 'active',
        at: at,
      );

      expect(n.title, isEmpty);
      expect(n.message, isEmpty);
      expect(n.resolvedTitle(en), en.tradeCardActiveTitle);
      expect(n.resolvedMessage(en), en.tradeCardActiveMessage);
      expect(n.resolvedTitle(es), es.tradeCardActiveTitle);
      expect(n.resolvedTitle(es), isNot(n.resolvedTitle(en)));
    });

    test('a cancel says why when the reason is known', () {
      NotificationModel canceled(String? reason) =>
          NotificationModel.tradeStatus(
            orderId: 'order-1',
            status: 'canceled',
            reason: reason,
            at: at,
          );

      expect(canceled(null).resolvedMessage(en), en.tradeCardCanceledMessage);
      expect(
        canceled('makerCanceled').resolvedMessage(en),
        en.tradeCardCanceledByMakerMessage,
      );
      expect(
        canceled('bondLostRace').resolvedMessage(en),
        en.tradeCardCanceledBondLostRaceMessage,
      );
      expect(
        canceled('bondExpired').resolvedMessage(en),
        en.tradeCardCanceledBondExpiredMessage,
      );
    });

    test('a cooperative-cancel request is its own card, not an active one', () {
      NotificationModel request(String status, String reason) =>
          NotificationModel.tradeStatus(
            orderId: 'order-1',
            status: status,
            reason: reason,
            at: at,
          );

      final mine = request('active', 'cooperativeCancelRequestedByMe');
      expect(mine.id, 'trade-order-1-active-cooperativeCancelRequestedByMe');
      expect(mine.resolvedTitle(en), en.tradeCardCancelRequestedByMeTitle);
      expect(mine.resolvedMessage(en), en.tradeCardCancelRequestedByMeMessage);
      expect(mine.resolvedTitle(es), es.tradeCardCancelRequestedByMeTitle);

      // The status carried is the trade's own: the same copy after fiat sent.
      final peer = request('fiatSent', 'cooperativeCancelRequestedByPeer');
      expect(peer.resolvedTitle(en), en.tradeCardCancelRequestedByPeerTitle);
      expect(
        peer.resolvedMessage(en),
        en.tradeCardCancelRequestedByPeerMessage,
      );
      expect(peer.resolvedTitle(en), isNot(mine.resolvedTitle(en)));
    });

    test('a status this build does not know still renders', () {
      final n = NotificationModel.tradeStatus(
        orderId: 'order-1',
        status: 'somethingNew',
        at: at,
      );

      expect(n.resolvedTitle(en), en.tradeCardUpdatedTitle);
      expect(n.resolvedMessage(en), en.tradeCardUpdatedMessage);
    });

    test('its markers never show up as detail rows', () {
      final n = NotificationModel.tradeStatus(
        orderId: 'order-1',
        status: 'canceled',
        reason: 'makerCanceled',
        at: at,
      );

      expect(n.resolvedDetail(en), isEmpty);
    });

    test('survives storage', () {
      final n = NotificationModel.tradeStatus(
        orderId: 'order-1',
        status: 'fiatSent',
        at: at,
      );

      final restored = NotificationModel.fromJson(n.toJson());
      expect(restored.id, n.id);
      expect(restored.timestamp, at);
      expect(restored.resolvedTitle(en), en.tradeCardFiatSentTitle);
    });
  });

  group('NotificationModel.chatMessages', () {
    test('counts in the copy, singular and plural', () {
      NotificationModel card(int count) => NotificationModel.chatMessages(
        tradeId: 'order-1',
        fromSolver: false,
        count: count,
        at: at,
      );

      expect(card(1).resolvedTitle(en), en.chatCardTitle);
      expect(
        card(1).resolvedMessage(en),
        '1 new message from your trade partner',
      );
      expect(
        card(3).resolvedMessage(en),
        '3 new messages from your trade partner',
      );
      expect(card(3).chatUnreadCount, 3);
      expect(card(3).resolvedDetail(en), isEmpty);
    });

    test('the solver\'s card says who wrote', () {
      final n = NotificationModel.chatMessages(
        tradeId: 'order-1',
        fromSolver: true,
        count: 2,
        at: at,
      );

      expect(n.id, 'chat-order-1-solver');
      expect(n.resolvedTitle(en), en.chatCardSolverTitle);
      expect(n.resolvedMessage(en), en.chatCardSolverMessage(2));
      expect(NotificationModel.fromJson(n.toJson()).isSolverChatCard, isTrue);
    });

    test('other notifications count no chat messages', () {
      final n = NotificationModel.tradeStatus(
        orderId: 'order-1',
        status: 'active',
        at: at,
      );

      expect(n.chatUnreadCount, 0);
      expect(n.isSolverChatCard, isFalse);
    });
  });
}
