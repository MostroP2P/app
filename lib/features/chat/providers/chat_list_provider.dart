import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/chat/models/chat_list_rules.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';

/// One conversation of the chat list: the room and the trade it belongs to.
@immutable
class ChatListRow {
  const ChatListRow({
    required this.room,
    required this.trade,
    required this.state,
  });

  final ChatRoomState room;

  /// Null while the trades have not loaded. The context line is composed
  /// from this model — direction, amount, currency, status — never from a
  /// text stored with the chat.
  final TradeRow? trade;
  final ChatRowState state;
}

Map<String, TradeRow> _tradesById(Ref ref) => {
  for (final t
      in ref.watch(tradeRowsProvider).valueOrNull ?? const <TradeRow>[])
    t.orderId: t,
};

/// The conversations as grouped for the Messages segment.
final groupedChatRowsProvider = Provider<List<ChatRowGroup<ChatListRow>>>((
  ref,
) {
  final trades = _tradesById(ref);
  final rows = [
    for (final room in ref.watch(chatRoomsNotifierProvider))
      ChatListRow(
        room: room,
        trade: trades[room.orderId],
        state: ChatRowState.of(trades[room.orderId]?.state),
      ),
  ];
  return groupChatRows(
    rows,
    groupOf: (r) => r.state.group,
    lastMessageAt: (r) => r.room.lastMessageAt,
  );
});

/// The state of one conversation, for the chat room: whether it is read-only.
final chatRowStateProvider = Provider.family<ChatRowState, String>(
  (ref, orderId) => ChatRowState.of(_tradesById(ref)[orderId]?.state),
);
