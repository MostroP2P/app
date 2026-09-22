import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/startup_failure.dart';

void main() {
  group('StartupFailureApp', () {
    testWidgets('names the step that failed', (tester) async {
      await tester.pumpWidget(
        const StartupFailureApp(step: 'loading the engine'),
      );

      // The step name is the reason this screen exists: "Mostro won't open" is
      // unactionable, "it failed loading the engine" is where to look. A
      // refactor that drops it leaves a screen no more useful than the blank
      // page it replaced (#389).
      expect(find.textContaining('loading the engine'), findsOneWidget);
      expect(find.text('Mostro could not start'), findsOneWidget);
    });

    testWidgets('says which step, not just that one failed', (tester) async {
      await tester.pumpWidget(
        const StartupFailureApp(step: 'reading your settings'),
      );
      expect(find.textContaining('reading your settings'), findsOneWidget);
      expect(find.textContaining('loading the engine'), findsNothing);
    });

    testWidgets('a deep initial route yields one page, not one per segment', (
      tester,
    ) async {
      // On the web the initial route is the browser's URL. Flutter's default
      // handling splits a deep path and pushes a route per segment, so without
      // onGenerateInitialRoutes this screen is stacked once per segment and
      // back pops to an identical copy (#405 review).
      //
      // defaultRouteNameTestValue is the only way to set that route in a test:
      // there is no browser here to ask for one.
      tester.binding.platformDispatcher.defaultRouteNameTestValue =
          '/orders/abc/detail';
      addTearDown(
        tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
      );

      await tester.pumpWidget(
        const StartupFailureApp(step: 'loading the engine'),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Mostro could not start'), findsOneWidget);
      expect(
        tester.state<NavigatorState>(find.byType(Navigator)).canPop(),
        isFalse,
        reason:
            'a deep URL must not stack one copy of this screen per path '
            'segment — back would then land on a clone of it',
      );
    });

    testWidgets('shows the cause when given one', (tester) async {
      // On Android, iOS and Linux there is no console for the person hitting
      // this to read, so without it the step name is all they could report.
      await tester.pumpWidget(
        const StartupFailureApp(
          step: 'loading the engine',
          error: 'Bad state: wasm module missing',
        ),
      );

      expect(
        find.textContaining('wasm module missing'),
        findsOneWidget,
        reason: 'the cause must be readable without a console',
      );
    });

    testWidgets('shows no second line when there is no cause to show', (
      tester,
    ) async {
      await tester.pumpWidget(
        const StartupFailureApp(step: 'loading the engine'),
      );
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('truncates a long error rather than pushing the sentence off '
        'the screen', (tester) async {
      await tester.pumpWidget(
        StartupFailureApp(step: 'loading the engine', error: 'x' * 5000),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Mostro could not start'), findsOneWidget);
      final shown = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(shown.data!.length, lessThan(400));
    });

    testWidgets('truncates by character, never inside an emoji', (
      tester,
    ) async {
      // 299 single-unit chars then emoji: a cut by UTF-16 unit at 300 lands
      // between the two halves of the first emoji.
      await tester.pumpWidget(
        StartupFailureApp(
          step: 'loading the engine',
          error: '${'x' * 299}${'😀' * 10}',
        ),
      );
      final shown =
          tester.widget<SelectableText>(find.byType(SelectableText)).data!;
      expect(
        shown,
        '${'x' * 299}😀…',
        reason: 'half an emoji renders as a replacement glyph',
      );
    });

    testWidgets('stays readable on a short screen instead of overflowing', (
      tester,
    ) async {
      // The screen that exists to make a failure legible must not be covered
      // by Flutter's striped overflow warning. 320x400 with a cause at the
      // truncation limit is the worst case that can reach it.
      tester.view.physicalSize = const Size(320, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        StartupFailureApp(
          step: 'opening the local database',
          error: 'x' * 5000,
        ),
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'a long cause on a short screen must scroll, not overflow',
      );
      expect(find.text('Mostro could not start'), findsOneWidget);
    });

    testWidgets('the copied cause is not the one trimmed for the screen', (
      tester,
    ) async {
      // The 300-character cap protects the layout, and the clipboard has no
      // layout. A long cause — a bridge panic, a wrapped PlatformException —
      // must reach the issue tracker whole (#405, coderabbit).
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
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

      final long = 'panic: ${'x' * 400} at the end';
      await tester.pumpWidget(
        StartupFailureApp(step: 'loading the engine', error: long),
      );
      await tester.tap(find.byTooltip('Copy details'));
      await tester.pump();

      expect(copied.single, contains('at the end'));
      expect(copied.single, isNot(contains('…')));
    });

    testWidgets('a tap puts the step and the cause on the clipboard', (
      tester,
    ) async {
      // A tap, not a text selection: on a phone there is no console, and
      // dragging to select inside a scrolling view is fiddly. What lands on the
      // clipboard has to carry the step too — the cause alone loses half of
      // what makes a report actionable.
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
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

      await tester.pumpWidget(
        const StartupFailureApp(
          step: 'loading the engine',
          error: 'Bad state: wasm module missing',
        ),
      );
      await tester.tap(find.byTooltip('Copy details'));
      await tester.pump();

      expect(copied, hasLength(1));
      expect(copied.single, contains('loading the engine'));
      expect(copied.single, contains('wasm module missing'));
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('says so when the copy fails instead of claiming it worked', (
      tester,
    ) async {
      // On the web the clipboard write can be refused. "Copied" over an empty
      // clipboard sends someone off to paste nothing.
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            throw PlatformException(code: 'denied');
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

      await tester.pumpWidget(
        const StartupFailureApp(step: 'loading the engine', error: 'x'),
      );
      await tester.tap(find.byTooltip('Copy details'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('Copied'), findsNothing);
      expect(find.textContaining('Could not copy'), findsOneWidget);
    });

    testWidgets('points to where to report and warns before clearing data', (
      tester,
    ) async {
      // A copy with nowhere to paste it is a dead end, and clearing app data
      // without the secret words loses the account (#405 review).
      await tester.pumpWidget(const StartupFailureApp(step: 'starting up'));
      expect(
        find.textContaining('github.com/MostroP2P/app/issues'),
        findsOneWidget,
      );
      expect(find.textContaining('secret words'), findsOneWidget);
    });

    testWidgets('a second button copies where to report', (tester) async {
      // Typing a URL off a failure screen, often on a phone, is where a report
      // gets abandoned.
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
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

      await tester.pumpWidget(const StartupFailureApp(step: 'starting up'));
      await tester.ensureVisible(find.byTooltip('Copy link'));
      await tester.tap(find.byTooltip('Copy link'));
      await tester.pump();

      expect(copied, ['https://github.com/MostroP2P/app/issues']);
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('each copy button sits to the right of what it copies, and '
        'the warning is a footer', (tester) async {
      tester.view.physicalSize = const Size(800, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        const StartupFailureApp(step: 'loading the engine', error: 'boom'),
      );

      final cause = tester.getRect(find.text('boom'));
      final copyDetails = tester.getRect(find.byTooltip('Copy details'));
      expect(copyDetails.left, greaterThanOrEqualTo(cause.right));
      expect(copyDetails.center.dy, closeTo(cause.center.dy, 24));

      final link = tester.getRect(find.textContaining('github.com'));
      final copyLink = tester.getRect(find.byTooltip('Copy link'));
      expect(copyLink.left, greaterThanOrEqualTo(link.right));
      expect(copyLink.center.dy, closeTo(link.center.dy, 24));

      expect(
        copyLink.left,
        copyDetails.left,
        reason: 'the copy buttons line up vertically',
      );
      expect(
        cause.center.dx,
        closeTo(400, 1),
        reason: 'the text is centred on the screen, not text plus button',
      );
      expect(link.center.dx, closeTo(400, 1));
      expect(
        copyLink.left - link.right,
        lessThan(8),
        reason: 'the button sits beside the widest text, not at the edge',
      );

      // Checked on the style and the gap rather than the rendered title
      // height: the test font is wider than the real one, so the title wraps
      // here and its height says nothing about the size.
      final titleText = tester.widget<Text>(
        find.text('Mostro could not start'),
      );
      expect(
        titleText.style!.fontSize,
        26,
        reason: 'the title is 30% larger than the base 20',
      );
      final title = tester.getRect(find.text('Mostro could not start'));
      final sentence = tester.getRect(find.textContaining('It failed'));
      expect(
        sentence.top - title.bottom,
        closeTo(12 + 26 * titleText.style!.height!, 0.5),
        reason: 'one title line of air under the title, on top of the gap',
      );

      final footer = tester.getRect(find.textContaining('secret words'));
      expect(
        footer.top,
        greaterThan(copyLink.bottom + 100),
        reason: 'with room to spare the warning sits at the bottom',
      );
      expect(
        footer.bottom,
        greaterThan(1000 - 120),
        reason: 'it is a footer, not the next paragraph',
      );
    });

    testWidgets('renders without any app dependency', (tester) async {
      // No ProviderScope, no AppLocalizations, no theme, no Rust bridge — this
      // pump is the assertion. Any of those could be what failed, so a rescue
      // surface that needs one is a second blank page.
      await tester.pumpWidget(const StartupFailureApp(step: 'starting up'));

      expect(tester.takeException(), isNull);
      expect(find.byType(MaterialApp), findsOneWidget);
    });
  });
}
