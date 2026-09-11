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
      await tester.tap(find.text('Copy details'));
      await tester.pump();

      expect(copied, hasLength(1));
      expect(copied.single, contains('loading the engine'));
      expect(copied.single, contains('wasm module missing'));
      expect(find.text('Copied'), findsOneWidget);
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
