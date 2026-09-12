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
