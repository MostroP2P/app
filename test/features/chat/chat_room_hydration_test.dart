import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/chat/screens/chat_room_screen.dart';
import 'package:mostro/features/chat/widgets/trade_state_header.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

import '../../support/provider_harness.dart';

const _orderId = 'order-hydrate';
const _peerPubkey =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

/// A persisted trade as the identity-resolution path reads it. Without
/// `RustLib.init()` the nym lookup and message fetch inside
/// `tradeInfoToChatRoom` fail into their fallbacks ('Trader …' handle, empty
/// preview), which is exactly the shape these regressions need.
rust_types.TradeInfo _trade({required String counterpartyPubkey}) =>
    rust_types.TradeInfo(
      id: 'row-$_orderId',
      order: rust_types.OrderInfo(
        id: _orderId,
        kind: rust_types.OrderKind.sell,
        status: rust_types.OrderStatus.active,
        fiatAmount: 100,
        fiatCode: 'USD',
        paymentMethod: 'bank',
        premium: 0,
        creatorPubkey: 'maker',
        createdAt: intToPlatformInt64(1),
        isMine: true,
        rating: 0,
        totalReviews: 0,
        daysActive: 0,
      ),
      role: rust_types.TradeRole.seller,
      counterpartyPubkey: counterpartyPubkey,
      currentStep: const rust_types.TradeStep.seller(
        rust_types.SellerStep.takerFound,
      ),
      tradeKeyIndex: 1,
      startedAt: intToPlatformInt64(1),
    );

/// Pumps [ChatRoomScreen] bridge-free (see `chat_room_screen_test.dart`):
/// the screen's own bridge calls fail inside their try/catch, and the
/// providers the identity path depends on are overridden per test.
/// [warmUp] runs against the container before the widget mounts.
Future<ProviderContainer> _pumpChatRoom(
  WidgetTester tester, {
  required List<Override> overrides,
  Future<void> Function(ProviderContainer)? warmUp,
}) async {
  final container = createContainer(overrides: [
    incomingMessageProvider(_orderId)
        .overrideWith((ref) => const Stream.empty()),
    chatTradeOrderProvider(_orderId).overrideWith((ref) async => null),
    orderBookNotificationCountProvider.overrideWith((ref) => 0),
    ...overrides,
  ]);
  await warmUp?.call(container);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const ChatRoomScreen(orderId: _orderId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return container;
}

ChatRoomState _room(ProviderContainer container) => container
    .read(chatRoomsNotifierProvider)
    .firstWhere((r) => r.orderId == _orderId);

void main() {
  testWidgets('direct entry resolves the peer identity from the trade row',
      (tester) async {
    // The chat-list screen is the only other code that hydrates the rooms
    // notifier; before the fix, entering here directly left the header on
    // the empty-handle placeholder ("Unknown") even with a correct row.
    final container = await _pumpChatRoom(
      tester,
      overrides: [
        rawTradesProvider.overrideWith(
          (ref) async => [_trade(counterpartyPubkey: _peerPubkey)],
        ),
      ],
    );
    await tester.pump();

    final room = _room(container);
    expect(room.peerPubkey, _peerPubkey);
    expect(room.peerHandle, isNotEmpty, reason: 'no "Unknown" fallback');
  });

  testWidgets('hydration keeps the newer live preview', (tester) async {
    // A message beat identity resolution: _buildRoomPreview upserted a
    // placeholder with an empty pubkey but a live preview. The hydrated room
    // rebuilds its preview from the message store, which here (bridge-free)
    // is empty — upserting it wholesale would blank the preview and
    // resurrect an unread count _markRead had already zeroed.
    final container = await _pumpChatRoom(
      tester,
      overrides: [
        rawTradesProvider.overrideWith(
          (ref) async => [_trade(counterpartyPubkey: _peerPubkey)],
        ),
      ],
      warmUp: (container) async {
        container.read(chatRoomsNotifierProvider.notifier).upsertRoom(
              const ChatRoomState(
                orderId: _orderId,
                peerPubkey: '',
                peerHandle: '',
                peerIconIndex: 0,
                peerColorHue: 180,
                isSelling: false,
                lastMessage: 'hola',
                lastMessageAt: 2000,
                unreadCount: 3,
              ),
            );
      },
    );
    await tester.pump();

    final room = _room(container);
    expect(room.peerPubkey, _peerPubkey, reason: 'identity resolved');
    expect(room.lastMessage, 'hola', reason: 'live preview survives');
    expect(room.lastMessageAt, 2000);
    expect(room.unreadCount, 3, reason: 'unread count not resurrected');
  });

  testWidgets('a reveal landing while the screen is open flips the header',
      (tester) async {
    // The maker's row has no counterparty when the screen opens; the daemon
    // reveal fills it and rawTradesProvider refetches itself on the trade
    // update. The screen must pick up that emission — a one-shot read at
    // init would be left awaiting a future the update just invalidated.
    final responses = [
      [_trade(counterpartyPubkey: '')],
      [_trade(counterpartyPubkey: _peerPubkey)],
    ];
    final updates = StreamController<rust_types.TradeUpdate>();
    addTearDown(updates.close);

    final container = await _pumpChatRoom(
      tester,
      overrides: [
        rawTradesProvider.overrideWith((ref) async {
          // Mirror the production body: refetch on every trade update.
          ref.listen(tradeUpdatesProvider, (_, __) => ref.invalidateSelf());
          return responses.length > 1 ? responses.removeAt(0) : responses.first;
        }),
        tradeUpdatesProvider.overrideWith((ref) => updates.stream),
      ],
    );
    await tester.pump();
    expect(container.read(chatRoomsNotifierProvider), isEmpty,
        reason: 'pre-reveal: nothing to resolve, nothing upserted');

    updates.add(const rust_types.TradeUpdate(
      orderId: _orderId,
      status: rust_types.OrderStatus.active,
    ));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(_room(container).peerPubkey, _peerPubkey,
        reason: 'the reveal emission resolved the room while open');
  });
}
