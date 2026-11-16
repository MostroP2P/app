import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/chat/models/chat_list_rules.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;

ChatRowState _chat(
  OrderStatus status, {
  bool isBuyer = true,
  bool ratedByMe = true,
}) => ChatRowState.of(
  status: status,
  trade: TradeRowState.of(
    status: status,
    isBuyer: isBuyer,
    ratedByMe: ratedByMe,
    canRate: true,
  ),
);

void main() {
  group('ChatRowState', () {
    test('an active trade whose next step is the user\'s', () {
      final row = _chat(OrderStatus.active);
      expect(row.group, ChatGroup.active);
      expect(row.tone, ChatAvatarTone.yourTurn);
      expect(row.showsActiveDot, isTrue);
    });

    test('an active trade waiting on the counterpart', () {
      final row = _chat(OrderStatus.active, isBuyer: false);
      expect(row.group, ChatGroup.active);
      expect(row.tone, ChatAvatarTone.waiting);
      expect(row.showsActiveDot, isTrue);
    });

    test('a closed trade steps back, with no active dot', () {
      for (final status in [OrderStatus.success, OrderStatus.canceled]) {
        final row = _chat(status);
        expect(row.group, ChatGroup.closed, reason: '$status');
        expect(row.tone, ChatAvatarTone.closed);
        expect(row.showsActiveDot, isFalse);
      }
    });

    test('a completed trade not rated yet is closed for chat', () {
      // The trades list keeps it in `Requieren tu acción` (rating), but the
      // conversation is over: a send would never reach the counterpart.
      final row = _chat(OrderStatus.success, ratedByMe: false);
      expect(row.group, ChatGroup.closed);
      expect(row.isReadOnly, isTrue);
    });

    test('a dispute keeps its conversation open', () {
      expect(_chat(OrderStatus.dispute).group, ChatGroup.active);
    });

    test('a room whose trade is not loaded yet reads as active, waiting', () {
      // Never as closed: that would disable the composer of a live trade.
      final row = ChatRowState.of();
      expect(row.group, ChatGroup.active);
      expect(row.tone, ChatAvatarTone.waiting);
      expect(row.isReadOnly, isFalse);
    });

    test('while the trades load, nothing can be composed yet', () {
      expect(ChatRowState.resolving.canCompose, isFalse);
      expect(ChatRowState.resolving.isReadOnly, isFalse);
      expect(ChatRowState.resolving.group, ChatGroup.active);
      expect(_chat(OrderStatus.active).canCompose, isTrue);
      expect(_chat(OrderStatus.success).canCompose, isFalse);
    });

    group('the grace window after a completed trade (#642)', () {
      const doneAt = 1700000000;
      ChatRowState completed(
        OrderStatus status, {
        int? completedAt,
        int? now,
      }) => ChatRowState.of(
        status: status,
        trade: TradeRowState.of(
          status: status,
          isBuyer: true,
          ratedByMe: false,
          canRate: true,
        ),
        completedAt: completedAt,
        now: now ?? doneAt,
      );

      test('a completed trade keeps its conversation open for an hour', () {
        final row = completed(
          OrderStatus.success,
          completedAt: doneAt,
          now: doneAt + kPeerChatGraceSeconds - 1,
        );
        expect(row.group, ChatGroup.active);
        expect(row.canCompose, isTrue);
        expect(row.isReadOnly, isFalse);
      });

      test('and closes once the hour is over', () {
        final row = completed(
          OrderStatus.success,
          completedAt: doneAt,
          now: doneAt + kPeerChatGraceSeconds,
        );
        expect(row.group, ChatGroup.closed);
        expect(row.isReadOnly, isTrue);
      });

      test('a completion with no recorded time stays closed', () {
        expect(completed(OrderStatus.success).isReadOnly, isTrue);
      });

      test('a cancelled trade keeps its conversation open for an hour', () {
        for (final status in [
          OrderStatus.canceled,
          OrderStatus.cooperativelyCanceled,
        ]) {
          final open = completed(
            status,
            completedAt: doneAt,
            now: doneAt + kPeerChatGraceSeconds - 1,
          );
          expect(open.canCompose, isTrue, reason: '$status');
          final over = completed(
            status,
            completedAt: doneAt,
            now: doneAt + kPeerChatGraceSeconds,
          );
          expect(over.isReadOnly, isTrue, reason: '$status');
          expect(completed(status).isReadOnly, isTrue, reason: '$status');
        }
      });

      test('no other ending opens a window', () {
        for (final status in [
          OrderStatus.expired,
          OrderStatus.canceledByAdmin,
          OrderStatus.settledByAdmin,
          OrderStatus.completedByAdmin,
        ]) {
          expect(
            completed(status, completedAt: doneAt).isReadOnly,
            isTrue,
            reason: '$status',
          );
        }
      });

      test('chatGraceEndsAt dates the end of the window', () {
        expect(
          chatGraceEndsAt(status: OrderStatus.success, completedAt: doneAt),
          doneAt + kPeerChatGraceSeconds,
        );
        expect(chatGraceEndsAt(status: OrderStatus.success), isNull);
        expect(
          chatGraceEndsAt(status: OrderStatus.canceled, completedAt: doneAt),
          doneAt + kPeerChatGraceSeconds,
        );
        expect(
          chatGraceEndsAt(status: OrderStatus.expired, completedAt: doneAt),
          isNull,
        );
      });
    });

    test('only a closed conversation is read-only', () {
      expect(_chat(OrderStatus.success).isReadOnly, isTrue);
      expect(_chat(OrderStatus.active).isReadOnly, isFalse);
    });
  });

  group('groupChatRows', () {
    test('active first, closed after, newest message first in each', () {
      final rows = [
        (id: 'closed', group: ChatGroup.closed, at: 50),
        (id: 'old', group: ChatGroup.active, at: 10),
        (id: 'new', group: ChatGroup.active, at: 40),
      ];

      final grouped = groupChatRows(
        rows,
        groupOf: (r) => r.group,
        lastMessageAt: (r) => r.at,
      );

      expect(grouped.map((g) => g.group), [ChatGroup.active, ChatGroup.closed]);
      expect(grouped.first.rows.map((r) => r.id), ['new', 'old']);
    });

    test('an empty group is left out', () {
      final grouped = groupChatRows(
        [(id: 'a', group: ChatGroup.active, at: 1)],
        groupOf: (r) => r.group,
        lastMessageAt: (r) => r.at,
      );
      expect(grouped.map((g) => g.group), [ChatGroup.active]);
    });
  });
}
