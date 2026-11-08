import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_trades.dart';
import '../../../support/trade_rows_harness.dart';

/// The node the user switches to in these tests.
const _otherNode =
    'bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22bb22';

BondClaim _claim(String orderId, String node) => BondClaim(
  orderId: orderId,
  nodePubkey: node,
  tradeIndex: 1,
  amountSats: BigInt.from(1500),
  slashedAt: intToPlatformInt64(500),
  // Far in the future: the clock never expires it in a test.
  deadlineAt: intToPlatformInt64(4102444800),
  phase: BondClaimPhase.pending,
  submittedInvoice: null,
  fiatCode: 'VES',
  fiatAmount: 100,
  paymentMethod: 'PagoMovil',
  updatedAt: intToPlatformInt64(600),
);

ChatRoomState _room(String orderId, {int unread = 0}) => ChatRoomState(
  orderId: orderId,
  peerPubkey: 'peer-$orderId',
  peerHandle: 'peer',
  peerIconIndex: 0,
  peerColorHue: 0,
  isSelling: false,
  unreadCount: unread,
);

/// A trade the user has to act on next: a buyer's active trade.
TradeInfo _needsAction(String id, String node) =>
    fakeTrade(id: id, status: OrderStatus.active, nodePubkey: node);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('My Trades shows the active node\'s trades (#813)', () {
    test('only the active node\'s rows, in either case, and none without a '
        'node; every row stays in tradeRowsProvider', () async {
      final c = tradeRowsContainer([
        _needsAction('own', defaultMostroPubkey.toUpperCase()),
        _needsAction('other', _otherNode),
        _needsAction('unknown', ''),
      ]);
      await loadTradeRows(c);

      expect(c.read(activeNodeTradeRowsProvider).value!.map((r) => r.orderId), [
        'order-own',
      ]);
      // Notifications reads these: another node's card keeps its row (#811).
      expect(c.read(tradeRowsProvider).value!.map((r) => r.orderId), [
        'order-own',
        'order-other',
        'order-unknown',
      ]);
    });

    test('a claim shows on the node that issued it', () async {
      final c = tradeRowsContainer(
        const [],
        claims: [
          _claim('claim-own', defaultMostroPubkey),
          _claim('claim-other', _otherNode),
        ],
      );
      await loadTradeRows(c);

      expect(c.read(activeNodeTradeRowsProvider).value!.map((r) => r.orderId), [
        'claim-own',
      ]);
    });

    test('a switch shows the new node\'s trades and their count', () async {
      final c = tradeRowsContainer([
        _needsAction('own', defaultMostroPubkey),
        _needsAction('other-1', _otherNode),
        _needsAction('other-2', _otherNode),
      ]);
      await loadTradeRows(c);
      expect(c.read(needsActionCountProvider), 1);

      c.read(mostroPubkeyProvider.notifier).state = _otherNode;

      expect(c.read(activeNodeTradeRowsProvider).value!.map((r) => r.orderId), [
        'order-other-1',
        'order-other-2',
      ]);
      expect(c.read(needsActionCountProvider), 2);
    });
  });

  group('the node switch warning', () {
    test('counts only the active node\'s trades in progress', () async {
      final c = tradeRowsContainer([
        _needsAction('other', _otherNode),
        fakeTrade(id: 'done', status: OrderStatus.success, completedAt: 2000),
      ]);
      final lookup = c.read(tradeInProgressLookupProvider);

      expect(await lookup(), isFalse);

      c.read(mostroPubkeyProvider.notifier).state = _otherNode;
      expect(await lookup(), isTrue);
    });

    test(
      'counts a trade in progress whose row does not know its node',
      () async {
        // Its actions go to whichever node is active (#810).
        final c = tradeRowsContainer([_needsAction('unknown', '')]);

        expect(await c.read(tradeInProgressLookupProvider)(), isTrue);
      },
    );
  });

  group('the Chats list shows the active node\'s rooms (#813)', () {
    test('a room of another node\'s trade waits for a switch; one whose '
        'trade is gone stays, and so does its unread count', () async {
      final c = tradeRowsContainer([
        _needsAction('own', defaultMostroPubkey),
        _needsAction('other', _otherNode),
      ]);
      c.read(chatRoomsNotifierProvider.notifier)
        ..upsertRoom(_room('order-own', unread: 1))
        ..upsertRoom(_room('order-other', unread: 2))
        ..upsertRoom(_room('order-gone', unread: 4));
      await loadTradeRows(c);

      expect(
        c.read(activeNodeChatRoomsProvider).map((r) => r.orderId),
        unorderedEquals(['order-own', 'order-gone']),
      );
      expect(c.read(chatCountProvider), 5);

      c.read(mostroPubkeyProvider.notifier).state = _otherNode;
      expect(
        c.read(activeNodeChatRoomsProvider).map((r) => r.orderId),
        unorderedEquals(['order-other', 'order-gone']),
      );
      expect(c.read(chatCountProvider), 6);
    });

    test('the room of a row without a node stays out once the row is '
        'gone', () async {
      // A wiped legacy row: its room was hidden with it, and must not turn
      // into a room whose trade is gone.
      final trades = [
        _needsAction('own', defaultMostroPubkey),
        _needsAction('legacy', ''),
      ];
      final c = tradeRowsContainer(trades);
      c.read(chatRoomsNotifierProvider.notifier)
        ..upsertRoom(_room('order-own'))
        ..upsertRoom(_room('order-legacy', unread: 3));
      c.listen(activeNodeChatRoomsProvider, (_, _) {});
      await loadTradeRows(c);
      expect(c.read(activeNodeChatRoomsProvider).map((r) => r.orderId), [
        'order-own',
      ]);

      trades.removeWhere((t) => t.order.id == 'order-legacy');
      c.invalidate(rawTradesProvider);
      await c.read(rawTradesProvider.future);
      await pumpEventQueue();

      expect(c.read(activeNodeChatRoomsProvider).map((r) => r.orderId), [
        'order-own',
      ]);
      expect(c.read(chatCountProvider), 0);
    });

    test('the room of a row without a node stays out once the row is '
        'gone, even when the Chats list was not open', () async {
      // The rooms were filled (a resume's hydration) while no screen watched
      // the trades nor the Chats list, and the row went before it was opened:
      // only what the notifier itself listens to may notice.
      final trades = [
        _needsAction('own', defaultMostroPubkey),
        _needsAction('legacy', ''),
      ];
      final c = tradeRowsContainer(trades);
      c.read(chatRoomsNotifierProvider.notifier)
        ..upsertRoom(_room('order-own'))
        ..upsertRoom(_room('order-legacy', unread: 3));
      await c.read(rawTradesProvider.future);

      trades.removeWhere((t) => t.order.id == 'order-legacy');
      c.invalidate(rawTradesProvider);
      await c.read(rawTradesProvider.future);
      await pumpEventQueue();

      expect(c.read(chatRoomsNotifierProvider).map((r) => r.orderId), [
        'order-own',
      ]);
      expect(c.read(activeNodeChatRoomsProvider).map((r) => r.orderId), [
        'order-own',
      ]);
      expect(c.read(chatCountProvider), 0);
    });

    test('no room shows before the trades load', () {
      final c = tradeRowsContainer([_needsAction('other', _otherNode)]);
      c
          .read(chatRoomsNotifierProvider.notifier)
          .upsertRoom(_room('order-other'));

      expect(c.read(activeNodeChatRoomsProvider), isEmpty);
    });
  });
}
