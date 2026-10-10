import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/trades/widgets/trade_chat_card.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/tab_app_bar.dart' show CountBadge;

import '../../../support/load_app_fonts.dart';

const _orderId = 'order-chat';

/// The card alone, under a router whose chat route says which room opened.
Future<void> _pump(
  WidgetTester tester, {
  required bool closed,
  int unread = 0,
  bool isSelling = false,
  bool withRoom = true,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder:
            (_, __) => Scaffold(
              body: TradeChatCard(
                orderId: _orderId,
                closed: closed,
                isSelling: isSelling,
              ),
            ),
      ),
      GoRoute(
        path: AppRoute.chatRoom,
        builder:
            (_, state) =>
                Scaffold(body: Text('room ${state.pathParameters['orderId']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        chatRoomsNotifierProvider.overrideWith(
          (ref) =>
              ChatRoomsNotifier()..setRooms([
                if (withRoom)
                  ChatRoomState(
                    orderId: _orderId,
                    peerPubkey: 'peer',
                    peerHandle: 'bright-fox-41',
                    peerIconIndex: 3,
                    peerColorHue: 120,
                    isSelling: isSelling,
                    unreadCount: unread,
                  ),
              ]),
        ),
      ],
      child: MaterialApp.router(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  // The badge's width is the digit's: measured in the app's own figures.
  setUpAll(loadAppFonts);

  for (final closed in [false, true]) {
    testWidgets('a tap opens the room (closed: $closed)', (tester) async {
      await _pump(tester, closed: closed);
      await tester.tap(find.byType(TradeChatCard));
      await tester.pumpAndSettle();
      expect(find.text('room $_orderId'), findsOneWidget);
    });
  }

  // 21a: the card names who the user writes to, by role, and says it opens.
  testWidgets('a seller chats with the buyer', (tester) async {
    await _pump(tester, closed: false, isSelling: true);
    expect(find.text('Chat with the buyer'), findsOneWidget);
    expect(find.text('End-to-end encrypted'), findsOneWidget);
    // The role says who is on the other side; the room shows the alias.
    expect(find.textContaining('bright-fox-41'), findsNothing);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('a buyer chats with the seller', (tester) async {
    await _pump(tester, closed: false);
    expect(find.text('Chat with the seller'), findsOneWidget);
  });

  testWidgets('unread messages take the second line', (tester) async {
    await _pump(tester, closed: false, unread: 2);
    expect(find.text('Chat with the seller'), findsOneWidget);
    expect(find.text('2 new messages'), findsOneWidget);
    expect(find.text('End-to-end encrypted'), findsNothing);
  });

  testWidgets('a closed card keeps its role and drops "Open"', (tester) async {
    await _pump(tester, closed: true, unread: 2);
    expect(find.text('Chat with the seller'), findsOneWidget);
    expect(find.text('Conversation closed · view messages'), findsOneWidget);
    expect(find.text('Open'), findsNothing);
  });

  // The rooms are only built on hydration, from the Chat tab or the room
  // itself: a trade that turns active on screen has none yet. The card
  // still names the role, from the screen's side, and never "Unknown".
  testWidgets('without a room the card reads the trade side', (tester) async {
    await _pump(tester, closed: false, isSelling: true, withRoom: false);
    expect(find.text('Chat with the buyer'), findsOneWidget);
    expect(find.text('End-to-end encrypted'), findsOneWidget);
    expect(find.textContaining('Unknown'), findsNothing);
  });

  // DS-A11Y-1: one button that says who the chat is with and opens it.
  testWidgets('the card is one button with the role and the line', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, closed: false, isSelling: true);
    expect(
      tester.getSemantics(find.byType(TradeChatCard)),
      matchesSemantics(
        isButton: true,
        hasEnabledState: true,
        isEnabled: true,
        hasTapAction: true,
        label: 'Chat with the buyer. End-to-end encrypted',
        hint: 'Open',
      ),
    );
    handle.dispose();
  });

  testWidgets('the unread count reads as it is up to 99', (tester) async {
    await _pump(tester, closed: false, unread: 7);
    expect(find.text('7'), findsOneWidget);
    // One digit keeps the round 16 dp badge the hand-drawn one was.
    final badge = find.ancestor(
      of: find.byType(CountBadge),
      matching: find.byType(Container),
    );
    expect(tester.getSize(badge.first), const Size(16, 16));
  });

  // The chat list and the Chat tab still count a closed room's unread
  // messages: the card says the same.
  testWidgets('a closed card keeps the unread count', (tester) async {
    await _pump(tester, closed: true, unread: 3);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('past 99 unread messages the count reads 99+', (tester) async {
    await _pump(tester, closed: false, unread: 150);
    expect(find.text('99+'), findsOneWidget);
    expect(find.text('150'), findsNothing);
  });
}
