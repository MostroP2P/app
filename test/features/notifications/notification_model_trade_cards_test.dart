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

    // #823: a new request for an invoice after a failed payout rides on the
    // first request's status; the reason gives it its own card and copy.
    test('a request after a failed payout says the payment failed', () {
      final first = NotificationModel.tradeStatus(
        orderId: 'order-1',
        status: 'waitingBuyerInvoice',
        at: at,
      );
      final again = NotificationModel.tradeStatus(
        orderId: 'order-1',
        status: 'waitingBuyerInvoice',
        reason: 'payoutFailed',
        at: at,
      );

      expect(again.id, isNot(first.id));
      expect(again.resolvedTitle(en), en.tradeCardPayoutFailedTitle);
      expect(again.resolvedMessage(en), en.tradeCardPayoutFailedMessage);
      expect(again.resolvedTitle(es), es.tradeCardPayoutFailedTitle);
      expect(first.resolvedTitle(en), en.tradeCardWaitingBuyerInvoiceTitle);
    });

    test('a publication says the order is in the book', () {
      final n = NotificationModel.tradeStatus(
        orderId: 'order-1',
        status: 'pending',
        reason: 'orderPublished',
        at: at,
      );

      expect(n.resolvedTitle(en), 'Order published');
      expect(
        n.resolvedMessage(en),
        'Your order is in the order book now, and other users can take it.',
      );
      expect(n.resolvedTitle(es), 'Orden publicada');
    });

    test('a taker walking away says the order is back in the book', () {
      final n = NotificationModel.tradeStatus(
        orderId: 'order-1',
        status: 'pending',
        reason: 'takerLeft',
        at: at,
      );

      expect(n.resolvedTitle(en), 'Order back in the book');
      expect(
        n.resolvedMessage(en),
        'The other party did not continue the trade. Your order is back in '
        'the order book, and other users can take it.',
      );
      expect(n.resolvedTitle(es), 'Orden de nuevo en el libro');
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

    test('keeps the node of its trade through storage and a read (#811)', () {
      final n = NotificationModel.tradeStatus(
        orderId: 'order-1',
        status: 'fiatSent',
        at: at,
        nodePubkey: 'aa11',
      );

      final restored = NotificationModel.fromJson(n.toJson());
      expect(restored.nodePubkey, 'aa11');
      expect(restored.copyWith(isRead: true).nodePubkey, 'aa11');
    });

    test('a card stored before nodes were recorded has none', () {
      final json =
          NotificationModel.tradeStatus(
              orderId: 'order-1',
              status: 'fiatSent',
              at: at,
            ).toJson()
            ..remove('nodePubkey');

      expect(NotificationModel.fromJson(json).nodePubkey, isNull);
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
        '1 new message from your counterpart',
      );
      expect(
        card(3).resolvedMessage(en),
        '3 new messages from your counterpart',
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

  group('NotificationModel.tradeStatus speaks to the user by role (#845)', () {
    NotificationModel card(String status) => NotificationModel.tradeStatus(
      orderId: 'order-1',
      status: status,
      at: at,
    );

    test('the seller owes the sats while the order waits for payment', () {
      final n = card('waitingPayment');

      expect(
        n.resolvedTitle(en, isBuyer: false),
        en.tradeCardWaitingPaymentSellerTitle,
      );
      expect(
        n.resolvedMessage(en, isBuyer: false),
        en.tradeCardWaitingPaymentSellerMessage,
      );
      expect(
        n.resolvedTitle(es, isBuyer: false),
        isNot(es.tradeCardWaitingPaymentTitle),
      );
      // The buyer does wait for the seller.
      expect(
        n.resolvedTitle(en, isBuyer: true),
        en.tradeCardWaitingPaymentTitle,
      );
    });

    test('the buyer owes the invoice while the order waits for it', () {
      final n = card('waitingBuyerInvoice');

      expect(
        n.resolvedTitle(en, isBuyer: true),
        en.tradeCardWaitingBuyerInvoiceBuyerTitle,
      );
      expect(
        n.resolvedMessage(en, isBuyer: true),
        en.tradeCardWaitingBuyerInvoiceBuyerMessage,
      );
      expect(
        n.resolvedTitle(en, isBuyer: false),
        en.tradeCardWaitingBuyerInvoiceTitle,
      );
    });

    test('later statuses name the counterpart and say "you" for the user', () {
      expect(
        card('active').resolvedMessage(en, isBuyer: true),
        en.tradeCardActiveBuyerMessage,
      );
      expect(
        card('active').resolvedMessage(en, isBuyer: false),
        en.tradeCardActiveSellerMessage,
      );
      expect(
        card('fiatSent').resolvedMessage(en, isBuyer: true),
        en.tradeCardFiatSentBuyerMessage,
      );
      expect(
        card('fiatSent').resolvedMessage(en, isBuyer: false),
        en.tradeCardFiatSentSellerMessage,
      );
      expect(
        card('settledHoldInvoice').resolvedMessage(en, isBuyer: true),
        en.tradeCardSettledHoldInvoiceBuyerMessage,
      );
      expect(
        card('settledHoldInvoice').resolvedMessage(en, isBuyer: false),
        en.tradeCardSettledHoldInvoiceSellerMessage,
      );
      expect(
        card('settledByAdmin').resolvedMessage(en, isBuyer: true),
        en.tradeCardSettledByAdminBuyerMessage,
      );
      expect(
        card('settledByAdmin').resolvedMessage(en, isBuyer: false),
        en.tradeCardSettledByAdminMessage,
      );
    });

    test('without a known side the neutral copy stays', () {
      for (final status in [
        'waitingBuyerInvoice',
        'waitingPayment',
        'active',
        'fiatSent',
        'settledHoldInvoice',
        'settledByAdmin',
      ]) {
        final n = card(status);
        expect(n.resolvedTitle(en, isBuyer: null), n.resolvedTitle(en));
        expect(n.resolvedMessage(en, isBuyer: null), n.resolvedMessage(en));
      }
      expect(
        card('waitingPayment').resolvedTitle(en),
        en.tradeCardWaitingPaymentTitle,
      );
    });

    test('the taker is told to pay their own deposit', () {
      expect(
        card('waitingTakerBond').resolvedMessage(en),
        isNot(contains("taker's")),
      );
    });
  });
}
