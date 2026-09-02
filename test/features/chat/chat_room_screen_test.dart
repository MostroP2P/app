import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/chat/screens/chat_room_screen.dart';
import 'package:mostro/features/chat/widgets/message_bubble.dart';
import 'package:mostro/features/chat/widgets/trade_state_header.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart' as rust_types;

import '../../support/provider_harness.dart';

const _orderId = 'order-chat';

/// Tall enough that one bubble exceeds [kFollowThresholdPixels], so a list
/// that has not finished animating to a new bubble reads as "not at the
/// bottom" by position alone — the case a follow animation must not lose.
const _tallContent = 'line one\nline two\nline three\nline four\nline five';

rust_types.ChatMessage _peerMessage(int n, {String? id}) =>
    rust_types.ChatMessage(
      id: id ?? 'msg-$n',
      tradeId: _orderId,
      senderPubkey: 'peer',
      content: '$_tallContent #$n',
      messageType: rust_types.MessageType.peer,
      isMine: false,
      isRead: false,
      hasAttachment: false,
      createdAt: intToPlatformInt64(1000 + n),
    );

/// Pumps [ChatRoomScreen] without `RustLib.init()`, following the
/// convention of `trade_detail_screen_test.dart`: the screen's own bridge
/// calls (`getMessages`, `markAsRead`) fail inside their `try/catch`, and the
/// incoming stream is driven from [incoming].
///
/// A phone-sized viewport keeps the list scrollable with a few dozen
/// bubbles and hides the tablet side panel.
Future<void> _pumpChatRoom(
  WidgetTester tester,
  StreamController<rust_types.ChatMessage> incoming,
) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = createContainer(overrides: [
    incomingMessageProvider(_orderId).overrideWith((ref) => incoming.stream),
    // The sticky header and the nav badge would otherwise reach the bridge.
    chatTradeOrderProvider(_orderId).overrideWith((ref) async => null),
    orderBookNotificationCountProvider.overrideWith((ref) => 0),
  ]);

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
  // Initial build, then a frame to flush the failed history load.
  await tester.pump();
  await tester.pump();
}

/// Delivers [messages] through the stream and lays them out.
Future<void> _receive(
  WidgetTester tester,
  StreamController<rust_types.ChatMessage> incoming,
  Iterable<rust_types.ChatMessage> messages,
) async {
  messages.forEach(incoming.add);
  await tester.pump(); // stream delivery + setState
  await tester.pump(); // layout + post-frame follow
}

/// Unmounts the screen and lets any flushed bridge call settle.
Future<void> _leaveRoom(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

ScrollController _listController(WidgetTester tester) =>
    tester.widget<ListView>(find.byType(ListView)).controller!;

/// Counts `markAsRead` bridge calls by their failure log line: without
/// `RustLib.init()` every call fails, so the line count *is* the call count.
///
/// `debugPrint` is a foundation debug variable, and the test binding checks
/// it is back to its original value before the test body returns, so
/// [run] restores it itself rather than leaving that to a tear-down.
class _MarkReadCounter {
  _MarkReadCounter._();

  int calls = 0;

  static Future<void> run(
    Future<void> Function(_MarkReadCounter counter) body,
  ) async {
    final counter = _MarkReadCounter._();
    final previous = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null && message.contains('markAsRead failed')) {
        counter.calls++;
      }
    };
    try {
      await body(counter);
    } finally {
      debugPrint = previous;
    }
  }
}

void main() {
  late StreamController<rust_types.ChatMessage> incoming;

  setUp(() => incoming = StreamController<rust_types.ChatMessage>());
  tearDown(() => incoming.close());

  group('ChatRoomScreen incoming messages', () {
    testWidgets('renders a replayed id once', (tester) async {
      await _pumpChatRoom(tester, incoming);

      await _receive(tester, incoming, [
        _peerMessage(1, id: 'same'),
        _peerMessage(2, id: 'same'),
      ]);

      expect(find.byType(MessageBubble), findsOneWidget);
      await _leaveRoom(tester);
    });

    testWidgets('leaves a reader who scrolled up where they were',
        (tester) async {
      await _pumpChatRoom(tester, incoming);
      await _receive(
          tester, incoming, List.generate(30, (i) => _peerMessage(i)));
      await tester.pump(const Duration(milliseconds: 300));
      final list = _listController(tester);
      expect(list.position.maxScrollExtent, greaterThan(0),
          reason: 'the list must be scrollable for the test to mean anything');
      list.jumpTo(100);
      await tester.pump();

      await _receive(tester, incoming, [_peerMessage(99)]);
      await tester.pump(const Duration(milliseconds: 300));

      expect(list.offset, 100,
          reason: 'an arriving message must not yank the reader away');
      await _leaveRoom(tester);
    });

    testWidgets('follows the conversation for a reader at the bottom',
        (tester) async {
      await _pumpChatRoom(tester, incoming);
      await _receive(
          tester, incoming, List.generate(30, (i) => _peerMessage(i)));
      await tester.pump(const Duration(milliseconds: 300));
      final list = _listController(tester);
      list.jumpTo(list.position.maxScrollExtent);
      await tester.pump();

      await _receive(tester, incoming, [_peerMessage(99)]);
      await tester.pump(const Duration(milliseconds: 300));

      expect(list.offset, list.position.maxScrollExtent);
      await _leaveRoom(tester);
    });

    testWidgets('keeps following when a message lands mid-animation',
        (tester) async {
      await _pumpChatRoom(tester, incoming);
      await _receive(
          tester, incoming, List.generate(30, (i) => _peerMessage(i)));
      await tester.pump(const Duration(milliseconds: 300));
      final list = _listController(tester);
      list.jumpTo(list.position.maxScrollExtent);
      await tester.pump();

      // First message starts a 200 ms follow animation; the second arrives
      // while the list is still short of the end it is heading for.
      await _receive(tester, incoming, [_peerMessage(98)]);
      await tester.pump(const Duration(milliseconds: 40));
      expect(list.offset, lessThan(list.position.maxScrollExtent),
          reason: 'the follow animation must still be in flight');
      await _receive(tester, incoming, [_peerMessage(99)]);
      await tester.pump(const Duration(milliseconds: 400));

      expect(list.offset, list.position.maxScrollExtent,
          reason: 'a reader who never scrolled up must not be left behind');
      await _leaveRoom(tester);
    });
  });

  group('ChatRoomScreen mark-read', () {
    testWidgets('marks a burst read once, after it settles', (tester) async {
      await _MarkReadCounter.run((counter) async {
        await _pumpChatRoom(tester, incoming);
        expect(counter.calls, 1, reason: 'entering the room marks it read');

        await _receive(
            tester, incoming, List.generate(40, (i) => _peerMessage(i)));
        expect(counter.calls, 1, reason: 'nothing fires mid-burst');

        await tester.pump(kMarkReadDebounce);
        await tester.pump();
        expect(counter.calls, 2, reason: 'one call for the whole burst');
        await _leaveRoom(tester);
      });
    });

    testWidgets('flushes a pending mark-read when leaving the room',
        (tester) async {
      await _MarkReadCounter.run((counter) async {
        await _pumpChatRoom(tester, incoming);
        await _receive(tester, incoming, [_peerMessage(1)]);
        expect(counter.calls, 1);

        await _leaveRoom(tester);

        expect(counter.calls, 2,
            reason: 'the reader saw the message; leaving early must not '
                'leave the room flagged unread');
      });
    });
  });
}
