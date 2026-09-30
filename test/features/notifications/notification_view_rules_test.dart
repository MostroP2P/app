import 'package:flutter/material.dart' show Icons;
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/models/notification_view_rules.dart';

NotificationModel _status(
  String status, {
  String orderId = 'o',
  String? reason,
  int hour = 1,
}) => NotificationModel.tradeStatus(
  orderId: orderId,
  status: status,
  reason: reason,
  at: DateTime.utc(2026, 1, 1, hour),
);

NotificationModel _system(int hour) => NotificationModel(
  id: 'system-$hour',
  type: NotificationType.system,
  title: 't',
  message: 'm',
  timestamp: DateTime.utc(2026, 1, 1, hour),
);

void main() {
  group('noticeTone', () {
    test('an active trade is the buyer\'s step and the seller\'s wait', () {
      expect(noticeTone(_status('active'), isBuyer: true), NoticeTone.action);
      expect(noticeTone(_status('active'), isBuyer: false), NoticeTone.waiting);
    });

    test('fiat sent is the seller\'s step: release', () {
      expect(
        noticeTone(_status('fiatSent'), isBuyer: false),
        NoticeTone.action,
      );
      expect(
        noticeTone(_status('fiatSent'), isBuyer: true),
        NoticeTone.waiting,
      );
    });

    test('an invoice step is the buyer\'s, a hold invoice the seller\'s', () {
      expect(
        noticeTone(_status('waitingBuyerInvoice'), isBuyer: true),
        NoticeTone.action,
      );
      expect(
        noticeTone(_status('waitingPayment'), isBuyer: false),
        NoticeTone.action,
      );
      expect(
        noticeTone(_status('waitingPayment'), isBuyer: true),
        NoticeTone.waiting,
      );
    });

    test('a finished trade is done, never an invitation to rate', () {
      expect(noticeTone(_status('success'), isBuyer: true), NoticeTone.done);
      expect(noticeTone(_status('canceled'), isBuyer: false), NoticeTone.done);
      expect(noticeTone(_status('expired'), isBuyer: true), NoticeTone.done);
    });

    test('a dispute is red', () {
      expect(noticeTone(_status('dispute'), isBuyer: true), NoticeTone.dispute);
      expect(noticeTone(_status('dispute')), NoticeTone.dispute);
    });

    test('without the trade row a live status reads as waiting', () {
      expect(noticeTone(_status('active')), NoticeTone.waiting);
      expect(noticeTone(_status('success')), NoticeTone.done);
    });

    test('a cancel request is the user\'s call only when the peer asked', () {
      expect(
        noticeTone(
          _status('active', reason: 'cooperativeCancelRequestedByPeer'),
          isBuyer: false,
        ),
        NoticeTone.action,
      );
      expect(
        noticeTone(
          _status('active', reason: 'cooperativeCancelRequestedByMe'),
          isBuyer: true,
        ),
        NoticeTone.waiting,
      );
    });

    test('chat, resolver, bonds and system notices', () {
      final chat = NotificationModel.chatMessages(
        tradeId: 'o',
        fromSolver: false,
        count: 1,
        at: DateTime.utc(2026),
      );
      final solver = NotificationModel.chatMessages(
        tradeId: 'o',
        fromSolver: true,
        count: 1,
        at: DateTime.utc(2026),
      );
      NotificationModel claim({required bool completed}) =>
          NotificationModel.bondClaim(
            orderId: 'o',
            nodePubkey: 'n',
            slashedAt: 1,
            amountSats: 10,
            completed: completed,
            updatedAt: 1,
          );
      expect(noticeTone(chat), NoticeTone.chat);
      expect(noticeTone(solver), NoticeTone.dispute);
      expect(noticeTone(claim(completed: false)), NoticeTone.action);
      expect(noticeTone(claim(completed: true)), NoticeTone.done);
      expect(noticeTone(_system(1)), NoticeTone.info);
    });
  });

  test('noticeIcon names what happened', () {
    expect(noticeIcon(_status('active')), Icons.lock_outline);
    expect(noticeIcon(_status('fiatSent')), Icons.payments_outlined);
    expect(noticeIcon(_status('success')), Icons.check_circle_outline);
    expect(noticeIcon(_status('dispute')), Icons.gavel_rounded);
    expect(noticeIcon(_system(1)), Icons.info_outline);
  });

  group('sectionNotices', () {
    test('pins trades that need the user now, the rest in one timeline', () {
      // Arrange
      final notices = [
        _status('active', orderId: 'mine', hour: 1),
        _status('success', orderId: 'done', hour: 5),
        _status('waitingPayment', orderId: 'done', hour: 2),
        _system(3),
      ];

      // Act
      final sections = sectionNotices(
        notices,
        needsAction: (id) => id == 'mine',
      );

      // Assert
      expect(sections.needsAction.single.orderId, 'mine');
      expect(sections.recent, hasLength(2));
      final first = sections.recent.first as NoticeGroupEntry;
      expect(first.orderId, 'done');
      expect(
        first.events.map((n) => n.tradeStatus),
        ['success', 'waitingPayment'],
        reason: 'a group lists its events newest first',
      );
      expect(sections.recent.last, isA<NoticeSystemEntry>());
    });

    test('a dispute keyed without an order is never pinned', () {
      final dispute = NotificationModel(
        id: 'd',
        type: NotificationType.dispute,
        title: 't',
        message: 'm',
        timestamp: DateTime.utc(2026),
        disputeId: 'dispute-1',
      );

      final sections = sectionNotices([dispute], needsAction: (_) => true);

      expect(sections.needsAction, isEmpty);
      expect(sections.recent.single, isA<NoticeGroupEntry>());
    });
  });
}
