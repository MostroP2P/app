import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/chat/widgets/message_actions_menu.dart';
import 'package:mostro/features/chat/widgets/message_bubble.dart';
import 'package:mostro/l10n/app_localizations.dart';

const _text = 'CBU 0000003100010000000001';

/// The menu of a P2P chat message: tapped or held, a text message offers
/// Copy, and the counterpart's the reactions.
void main() {
  ChatMessage textMessage({
    bool isMine = false,
    String? reaction,
    String content = _text,
  }) =>
      ChatMessage(
        id: 'm1',
        tradeId: 'order-chat',
        content: content,
        isMine: isMine,
        isRead: true,
        hasAttachment: false,
        createdAt: 1000,
        reaction: reaction,
      );

  /// What the bubble asked to send, in order.
  late List<String> reacted;

  setUp(() => reacted = []);

  Future<void> pump(
    WidgetTester tester,
    ChatMessage message, {
    Locale locale = const Locale('en'),
    bool atBottom = false,
    bool midScreen = false,
    bool inLongList = false,
  }) async {
    // As the chat screen does: only the counterpart's messages take one.
    final bubble = MessageBubble(
      message: message,
      peerColorHue: 200,
      onReact: message.isMine ? null : (emoji) async => reacted.add(emoji),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          // A chat lists its newest message at the bottom.
          body: switch ((atBottom, midScreen, inLongList)) {
            (true, _, _) => ListView(reverse: true, children: [bubble]),
            (_, true, _) => ListView(
                children: [const SizedBox(height: 300), bubble],
              ),
            // 300 dp down a list that scrolls far past it.
            (_, _, true) => ListView.builder(
                itemCount: 40,
                itemBuilder: (_, i) =>
                    i == 1 ? bubble : const SizedBox(height: 300),
              ),
            // The bubble's column takes the whole height: the message
            // sits at the top.
            _ => Center(child: bubble),
          },
        ),
      ),
    );
  }

  /// Presses the message's text for [hold], then lifts the finger.
  Future<void> press(WidgetTester tester, Duration hold) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(_text).first),
    );
    await tester.pump(hold);
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('tapping a counterpart message opens the menu', (tester) async {
    await pump(tester, textMessage());

    await tester.tap(find.text(_text));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('❤️'), findsOneWidget);
  });

  testWidgets('holding a message opens the menu as well', (tester) async {
    await pump(tester, textMessage());

    await press(tester, const Duration(milliseconds: 500));

    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('scrolling over a message opens nothing', (tester) async {
    await pump(tester, textMessage(), inLongList: true);

    await tester.drag(find.text(_text), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsNothing);
  });

  group('feedback', () {
    /// The platform calls the bubble makes, by method name.
    List<String> spyOnPlatform(WidgetTester tester) {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      return calls;
    }

    testWidgets(
      'a tap gives the tap feedback, not the long-press vibration',
      (tester) async {
        final calls = spyOnPlatform(tester);
        await pump(tester, textMessage());

        await tester.tap(find.text(_text));
        await tester.pumpAndSettle();

        expect(calls, contains('SystemSound.play'));
        expect(calls, isNot(contains('HapticFeedback.vibrate')));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'a hold keeps the long-press vibration',
      (tester) async {
        final calls = spyOnPlatform(tester);
        await pump(tester, textMessage());

        await press(tester, const Duration(milliseconds: 500));

        expect(calls, contains('HapticFeedback.vibrate'));
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });

  testWidgets('a message at the bottom gets the menu above it, on screen', (
    tester,
  ) async {
    await pump(tester, textMessage(), atBottom: true);
    final bubble = tester.getRect(find.text(_text).first);

    await press(tester, const Duration(seconds: 1));
    final menu = tester.getRect(
      find
          .ancestor(of: find.text('Copy'), matching: find.byType(Material))
          .first,
    );

    expect(menu.bottom, lessThanOrEqualTo(bubble.top));
    expect(menu.top, greaterThanOrEqualTo(0));
    expect(menu.left, greaterThanOrEqualTo(0));
  });

  ScrollPosition listPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position;

  testWidgets('the menu follows its message when the chat scrolls', (
    tester,
  ) async {
    await pump(tester, textMessage(), inLongList: true);
    await press(tester, const Duration(seconds: 1));
    final before = tester.getRect(find.text('Copy'));

    // As a new message arriving at the bottom would.
    listPosition(tester).jumpTo(100);
    await tester.pump();
    await tester.pump();

    expect(tester.getRect(find.text('Copy')).top, before.top - 100);
    // The lit copy of the message stays on the message.
    expect(
      tester.getRect(find.text(_text).last),
      tester.getRect(find.text(_text).first),
    );
  });

  testWidgets('the menu closes once its message is gone', (tester) async {
    await pump(tester, textMessage(), inLongList: true);
    await press(tester, const Duration(seconds: 1));

    listPosition(tester).jumpTo(5000);
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('the menu closes once its message scrolls out of sight', (
    tester,
  ) async {
    await pump(tester, textMessage(), inLongList: true);
    await press(tester, const Duration(seconds: 1));
    final bubble = tester.getRect(find.text(_text).first);

    // Just above the top: out of sight, still built in the list's cache.
    listPosition(tester).jumpTo(bubble.bottom + 50);
    await tester.pump();
    expect(find.text(_text, skipOffstage: false), findsWidgets);
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a message partly scrolled away stays cut at the list', (
    tester,
  ) async {
    await pump(tester, textMessage(), inLongList: true);
    await press(tester, const Duration(seconds: 1));
    final bubble = tester.getRect(find.text(_text).first);

    // Half of it above the list's top edge.
    listPosition(tester).jumpTo(bubble.top + bubble.height / 2);
    await tester.pump();
    await tester.pump();

    expect(find.text('Copy'), findsOneWidget);
    final lit = find.text(_text).last;
    expect(tester.getRect(lit).top, lessThan(0));
    final cut = find.ancestor(of: lit, matching: find.byType(ClipRect)).first;
    expect(tester.getRect(cut).top, 0);
  });

  testWidgets('the menu stays clear of an open keyboard', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await pump(tester, textMessage(), atBottom: true);

    await press(tester, const Duration(seconds: 1));

    expect(
      tester.getRect(find.text('Copy')).bottom,
      lessThanOrEqualTo(800 - 300),
    );
  });

  testWidgets('a change of screen size keeps the menu on its message', (
    tester,
  ) async {
    addTearDown(tester.view.reset);
    await pump(tester, textMessage());

    await press(tester, const Duration(seconds: 1));
    tester.view.physicalSize = tester.view.physicalSize.flipped;
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    expect(
      tester.getRect(find.text(_text).last),
      tester.getRect(find.text(_text).first),
    );
  });

  testWidgets('the menu keeps clear of a cutout on the side', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.padding = const FakeViewPadding(left: 120);
    await pump(tester, textMessage());

    await press(tester, const Duration(seconds: 1));

    final cutout = 120 / tester.view.devicePixelRatio;
    expect(
      tester.getRect(find.text('Copy')).left,
      greaterThanOrEqualTo(cutout + 16),
    );
  });

  testWidgets('a screen reader learns what tapping a message opens', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await pump(tester, textMessage());

    expect(
      tester.getSemantics(find.text(_text)),
      isSemantics(
        isButton: true,
        hasTapAction: true,
        onTapHint: 'Open the message menu',
      ),
    );
    semantics.dispose();
  });

  // DS-CMP-6: a one-line bubble is ~36 dp tall, and a one-letter one
  // narrower than 48 dp; the finger still gets a 48 × 48 target.
  group('a short message is still a 48 dp target', () {
    Rect bubbleOf(WidgetTester tester, String text) => tester.getRect(
          find
              .ancestor(of: find.text(text), matching: find.byType(Container))
              .first,
        );

    testWidgets('a tap just under it opens its menu', (tester) async {
      await pump(tester, textMessage(content: 'OK'), midScreen: true);
      final bubble = bubbleOf(tester, 'OK');
      expect(bubble.height, lessThan(48));

      await tester.tapAt(bubble.bottomLeft + const Offset(8, 4));
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsOneWidget);
    });

    testWidgets('a tap just beside it opens its menu', (tester) async {
      await pump(tester, textMessage(content: 'k'), midScreen: true);
      final bubble = bubbleOf(tester, 'k');
      expect(bubble.width, lessThan(48));

      await tester.tapAt(bubble.centerRight + const Offset(4, 0));
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsOneWidget);
    });
  });

  testWidgets('own messages open the menu without reactions', (
    tester,
  ) async {
    await pump(tester, textMessage(isMine: true));

    await press(tester, const Duration(seconds: 1));

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('❤️'), findsNothing);
  });

  group('reactions', () {
    testWidgets('the counterpart\'s message offers six and «…»', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, textMessage());

      await press(tester, const Duration(seconds: 1));

      for (final emoji in quickReactions) {
        expect(find.text(emoji), findsOneWidget);
      }
      expect(find.bySemanticsLabel('More reactions'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('picking one sends it and closes the menu', (tester) async {
      await pump(tester, textMessage());

      await press(tester, const Duration(seconds: 1));
      await tester.tap(find.text('👍'));
      await tester.pumpAndSettle();

      expect(reacted, ['👍']);
      expect(find.text('Copy'), findsNothing);
    });

    testWidgets('the current one is marked, and picking it withdraws it', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, textMessage(reaction: '😂'));

      await press(tester, const Duration(seconds: 1));
      // The last one is the menu's; the first, the chip under the message.
      final current = find.text('😂').last;
      expect(
        tester.getSemantics(current),
        isSemantics(isButton: true, isSelected: true),
      );
      await tester.tap(current);
      await tester.pumpAndSettle();

      expect(reacted, ['']);
      semantics.dispose();
    });

    testWidgets('❤ from the full list marks the quick ❤️', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(tester, textMessage(reaction: '❤'));

      await press(tester, const Duration(seconds: 1));

      expect(
        tester.getSemantics(find.text('❤️')),
        isSemantics(isButton: true, isSelected: true),
      );
      semantics.dispose();
    });

    testWidgets('they sit above the message and the actions under it', (
      tester,
    ) async {
      await pump(tester, textMessage(), midScreen: true);
      final bubble = tester.getRect(find.text(_text).first);

      await press(tester, const Duration(seconds: 1));

      expect(tester.getRect(find.text('❤️')).bottom, lessThan(bubble.top));
      expect(tester.getRect(find.text('Copy')).top, greaterThan(bubble.bottom));
    });

    testWidgets('a message at the top gets both under it', (tester) async {
      await pump(tester, textMessage());
      final bubble = tester.getRect(find.text(_text).first);

      await press(tester, const Duration(seconds: 1));
      final reactions = tester.getRect(find.text('❤️'));

      expect(reactions.top, greaterThan(bubble.bottom));
      expect(tester.getRect(find.text('Copy')).top, greaterThan(reactions.bottom));
    });

    testWidgets('a message at the bottom gets both above it, on screen', (
      tester,
    ) async {
      await pump(tester, textMessage(), atBottom: true);
      final bubble = tester.getRect(find.text(_text).first);

      await press(tester, const Duration(seconds: 1));
      final reactions = tester.getRect(find.text('❤️'));
      final copy = tester.getRect(find.text('Copy'));

      expect(reactions.bottom, lessThan(copy.top));
      expect(copy.bottom, lessThan(bubble.top));
      expect(reactions.top, greaterThanOrEqualTo(0));
    });

    testWidgets('«…» opens every emoji and sends the one picked', (
      tester,
    ) async {
      await pump(tester, textMessage());

      await press(tester, const Duration(seconds: 1));
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      expect(find.text('More reactions'), findsOneWidget);
      await tester.tap(find.text('😀').first);
      await tester.pumpAndSettle();

      expect(reacted, ['😀']);
      expect(find.text('More reactions'), findsNothing);
    });

    testWidgets('a tall message keeps the reactions clear of the actions', (
      tester,
    ) async {
      // Nearly the whole screen: no room above it or below it.
      final long = List.filled(26, 'line').join('\n');
      await pump(tester, textMessage(content: long));
      final bubble = tester.getRect(find.text(long).first);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text(long).first),
      );
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pumpAndSettle();

      final reactions = tester.getRect(find.text('❤️'));
      final copy = tester.getRect(find.text('Copy'));
      expect(copy.top, lessThan(bubble.bottom), reason: 'over the message');
      expect(reactions.bottom, lessThan(copy.top));
      expect(reactions.top, greaterThanOrEqualTo(0));
      expect(copy.bottom, lessThanOrEqualTo(600));
      await tester.tap(find.text('❤️'));
      expect(reacted, ['❤️'], reason: 'the reactions stay tappable');
    });

    testWidgets('picking the current one from «…» withdraws it too', (
      tester,
    ) async {
      await pump(tester, textMessage(reaction: '😀'));

      await press(tester, const Duration(seconds: 1));
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('😀').last);
      await tester.pumpAndSettle();

      expect(reacted, ['']);
    });

    testWidgets('every emoji fits 320 dp at 2x text in German', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(tester, textMessage(), locale: const Locale('de'));

      await press(tester, const Duration(seconds: 1));
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      expect(find.text('Weitere Reaktionen'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final cell = tester.getSize(
        find.ancestor(of: find.text('😀').last, matching: find.byType(InkWell)).first,
      );
      expect(cell.width, greaterThanOrEqualTo(48));
    });

    testWidgets('a reaction shows under its message', (tester) async {
      await pump(tester, textMessage(reaction: '👍'));

      expect(
        tester.getRect(find.text('👍')).top,
        greaterThan(tester.getRect(find.text(_text)).bottom),
      );
    });
  });

  group('clipboard', () {
    late List<String?> copied;

    setUp(() => copied = []);

    void spyOnClipboard(WidgetTester tester) {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    testWidgets('Copy puts the text on the clipboard, closes and confirms', (
      tester,
    ) async {
      spyOnClipboard(tester);
      await pump(tester, textMessage());

      await press(tester, const Duration(seconds: 1));
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copied, [_text]);
      expect(find.text('Copy'), findsNothing);
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('tapping outside the menu closes it without copying', (
      tester,
    ) async {
      spyOnClipboard(tester);
      await pump(tester, textMessage());

      await press(tester, const Duration(seconds: 1));
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsNothing);
      expect(find.text('Copied'), findsNothing);
      expect(copied, isEmpty);
    });
  });

  testWidgets('the open menu fits 320 dp at 2x text in German', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pump(tester, textMessage(), locale: const Locale('de'));

    await press(tester, const Duration(seconds: 1));

    expect(find.text('Kopieren'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Too narrow for seven 48-dp targets: the last quick reaction gives way
    // to «…», which still offers it.
    expect(find.text('❤️'), findsOneWidget);
    expect(find.text('😢'), findsNothing);
    final more = find.ancestor(
      of: find.byIcon(Icons.more_horiz_rounded),
      matching: find.byType(InkResponse),
    );
    expect(tester.getSize(more.first), const Size(48, 48));
    expect(tester.getRect(more.first).right, lessThanOrEqualTo(320));
  });
}
