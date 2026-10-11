import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/trades/widgets/trade_chat_card.dart';

import '../../../support/golden_harness.dart';
import '../../../support/load_app_fonts.dart';

ChatRoomState _room(String orderId, {required int unread}) => ChatRoomState(
  orderId: orderId,
  peerPubkey: 'peer-$orderId',
  peerHandle: 'cool-turkey',
  peerIconIndex: 3,
  peerColorHue: 120,
  isSelling: true,
  unreadCount: unread,
);

/// The card open, open with unread messages and closed (21a), stacked and
/// keyed so the golden captures just the cards.
Widget _gallery() => ProviderScope(
  overrides: [
    chatRoomsNotifierProvider.overrideWith(
      (ref) =>
          ChatRoomsNotifier()..setRooms([
            _room('open', unread: 0),
            _room('unread', unread: 2),
            _room('closed', unread: 0),
          ]),
    ),
  ],
  child: const Padding(
    key: ValueKey('chat-card-gallery'),
    padding: EdgeInsets.all(12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TradeChatCard(orderId: 'open'),
        SizedBox(height: 8),
        TradeChatCard(orderId: 'unread'),
        SizedBox(height: 8),
        TradeChatCard(orderId: 'closed', closed: true),
      ],
    ),
  ),
);

void main() {
  setUpAll(loadAppFonts);

  for (final (name, brightness) in [
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    testWidgets('TradeChatCard · $name', (tester) async {
      await pumpForGolden(
        tester,
        _gallery(),
        brightness: brightness,
        width: 360,
      );
      await expectLater(
        find.byKey(const ValueKey('chat-card-gallery')),
        matchesGoldenFile('goldens/trade_chat_card_$name.png'),
      );
    });
  }
}
