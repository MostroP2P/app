import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';

import 'trades_list_fixtures.dart';

int _ago(Duration d) => kTradesNow.subtract(d).millisecondsSinceEpoch ~/ 1000;

/// The handoff's 11b case, one room per trade of [kHandoffTrades] that has a
/// counterparty: the user's turn with two unread, a wait whose last message
/// is the user's, and a closed trade already read.
final kHandoffRooms = [
  ChatRoomState(
    orderId: 'release',
    peerPubkey: 'peer-jaguar',
    peerHandle: 'used-jaguar',
    peerIconIndex: 3,
    peerColorHue: 200,
    isSelling: true,
    lastMessage: 'Listo, ya te transferí. Avisame cuando llegue.',
    lastMessageAt: _ago(const Duration(minutes: 12)),
    unreadCount: 2,
  ),
  ChatRoomState(
    orderId: 'pay',
    peerPubkey: 'peer-otter',
    peerHandle: 'brave-otter',
    peerIconIndex: 5,
    peerColorHue: 120,
    isSelling: false,
    lastMessage: 'Te paso el comprobante en un rato',
    lastMessageIsOwn: true,
    lastMessageAt: _ago(const Duration(hours: 2)),
  ),
  ChatRoomState(
    orderId: 'done',
    peerPubkey: 'peer-heron',
    peerHandle: 'quiet-heron',
    peerIconIndex: 7,
    peerColorHue: 40,
    isSelling: false,
    lastMessage: 'Gracias, todo perfecto',
    lastMessageAt: _ago(const Duration(days: 1, hours: 3)),
  ),
];

/// One open dispute the user opened two hours ago.
final kHandoffDispute = DisputeItem(
  id: 'dispute-1',
  tradeId: 'pay',
  status: DisputeStatus.open,
  initiatedByMe: true,
  openedAt: _ago(const Duration(hours: 2)),
  peerHandle: 'brave-otter',
);

/// Everything the chat tab reads on top of [tradesListOverrides].
List<Override> chatListOverrides({
  List<ChatRoomState>? rooms,
  List<DisputeItem> disputes = const [],
}) => [
  ...tradesListOverrides(kHandoffTrades),
  chatRoomsFromTradesProvider.overrideWith(
    (ref) async => rooms ?? kHandoffRooms,
  ),
  disputeNotifierProvider.overrideWith((ref) {
    final notifier = DisputeNotifier();
    for (final d in disputes) {
      notifier.upsert(d);
    }
    return notifier;
  }),
];
