import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/walkthrough/providers/first_run_provider.dart';
import 'package:mostro/features/walkthrough/providers/node_prefetch_provider.dart';
import 'package:mostro/features/walkthrough/screens/walkthrough_screen.dart';
import 'package:mostro/features/walkthrough/walkthrough_slides.dart';
import 'package:mostro/features/walkthrough/widgets/walkthrough_art.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/load_app_fonts.dart';

const _chooseNode = 'node choice screen';

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      firstRunProvider.overrideWith(
        (ref) => FirstRunNotifier(initialValue: false),
      ),
      // The prefetch asks the relays through the Rust bridge.
      firstRunNodePrefetchProvider.overrideWith((ref) {}),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Pumps the walkthrough under a router whose node choice is a plain marker,
/// so a finished walkthrough shows [_chooseNode].
Future<ProviderContainer> _pumpWalkthrough(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.dark,
  double textScale = 1,
}) async {
  final container = _container();
  final router = GoRouter(
    initialLocation: AppRoute.walkthrough,
    routes: [
      GoRoute(
        path: AppRoute.chooseNode,
        builder: (_, __) => const Scaffold(body: Text(_chooseNode)),
      ),
      GoRoute(
        path: AppRoute.walkthrough,
        builder: (_, __) => const WalkthroughScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme:
            brightness == Brightness.dark
                ? buildDarkTheme()
                : buildLightTheme(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        // Animations off: the ring's glint loops, so pumpAndSettle would
        // never return with them on.
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                disableAnimations: true,
                textScaler: TextScaler.linear(textScale),
              ),
              child: child!,
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

AppLocalizations _en() => lookupAppLocalizations(const Locale('en'));

void main() {
  setUpAll(loadAppFonts);

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('opens on the first slide, with no way back', (tester) async {
    await _pumpWalkthrough(tester);
    final l10n = _en();

    expect(find.text(l10n.walkthroughWelcomeTitle), findsOneWidget);
    expect(find.text(l10n.walkthroughStepCounter(1, 6)), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing);
    expect(find.text(l10n.skip).hitTestable(), findsOneWidget);
  });

  testWidgets(
    'Next walks every slide in order and Done leads to the node choice',
    (tester) async {
      final container = await _pumpWalkthrough(tester);
      final l10n = _en();
      final titles = walkthroughSlides(l10n).map((s) => s.title).toList();

      for (var i = 0; i < titles.length; i++) {
        expect(find.text(titles[i]), findsOneWidget, reason: 'slide ${i + 1}');
        expect(
          find.text(l10n.walkthroughStepCounter(i + 1, 6)),
          findsOneWidget,
        );
        if (i < titles.length - 1) {
          await tester.tap(find.text(l10n.walkthroughNext));
          await tester.pumpAndSettle();
        }
      }

      // The last slide answers Done, and there is nothing left to skip.
      expect(find.text(l10n.walkthroughNext), findsNothing);
      expect(find.text(l10n.skip).hitTestable(), findsNothing);

      await tester.tap(find.text(l10n.done));
      await tester.pumpAndSettle();

      // The node choice comes next and completes the first run, not this.
      expect(find.text(_chooseNode), findsOneWidget);
      expect(container.read(firstRunProvider), const AsyncData<bool>(false));
      expect(container.read(backupReminderProvider), isFalse);
    },
  );

  testWidgets('Back returns to the previous slide', (tester) async {
    await _pumpWalkthrough(tester);
    final l10n = _en();

    await tester.tap(find.text(l10n.walkthroughNext));
    await tester.pumpAndSettle();
    expect(find.text(l10n.walkthroughPrivacyTitle), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.walkthroughWelcomeTitle), findsOneWidget);
  });

  testWidgets('Skip leads to the node choice from a middle slide', (
    tester,
  ) async {
    final container = await _pumpWalkthrough(tester);
    final l10n = _en();

    await tester.tap(find.text(l10n.walkthroughNext));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.skip));
    await tester.pumpAndSettle();

    // The node choice comes next and completes the first run, not this.
    expect(find.text(_chooseNode), findsOneWidget);
    expect(container.read(firstRunProvider), const AsyncData<bool>(false));
    expect(container.read(backupReminderProvider), isFalse);
  });

  testWidgets('a swipe left goes forward and a swipe right goes back', (
    tester,
  ) async {
    await _pumpWalkthrough(tester);
    final l10n = _en();
    final page = find.byType(WalkthroughScreen);

    await tester.drag(page, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.text(l10n.walkthroughPrivacyTitle), findsOneWidget);

    await tester.drag(page, const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(find.text(l10n.walkthroughWelcomeTitle), findsOneWidget);

    // Nothing lies before the first slide.
    await tester.drag(page, const Offset(200, 0));
    await tester.pumpAndSettle();
    expect(find.text(l10n.walkthroughWelcomeTitle), findsOneWidget);
  });

  testWidgets('a short drag does not turn the slide', (tester) async {
    await _pumpWalkthrough(tester);

    await tester.drag(find.byType(WalkthroughScreen), const Offset(-30, 0));
    await tester.pumpAndSettle();

    expect(find.text(_en().walkthroughWelcomeTitle), findsOneWidget);
  });

  testWidgets('a double tap on Skip leaves once', (tester) async {
    await _pumpWalkthrough(tester);
    final skip = find.text(_en().skip);

    await tester.tap(skip);
    await tester.tap(skip, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.text(_chooseNode), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the arrow keys move between slides', (tester) async {
    await _pumpWalkthrough(tester);
    final l10n = _en();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text(l10n.walkthroughPrivacyTitle), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text(l10n.walkthroughWelcomeTitle), findsOneWidget);
  });

  testWidgets('the privacy slide shows both modes as cards and the footer', (
    tester,
  ) async {
    await _pumpWalkthrough(tester);
    final l10n = _en();

    await tester.tap(find.text(l10n.walkthroughNext));
    await tester.pumpAndSettle();

    for (final text in [
      l10n.walkthroughReputationModeName,
      l10n.walkthroughReputationModeBody,
      l10n.walkthroughFullPrivacyModeName,
      l10n.walkthroughFullPrivacyModeBody,
      l10n.walkthroughPrivacyFooter,
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  testWidgets('every slide shows its art at the handoff size', (tester) async {
    // The handoff's phone: a 340 x 720 screen with a 184 px illustration.
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pumpWalkthrough(tester);
    final l10n = _en();
    const expected = 740 * 184 / 720;

    for (var i = 0; i < 6; i++) {
      expect(
        tester.getSize(find.byType(WalkthroughArt)).width,
        moreOrLessEquals(expected, epsilon: 0.5),
        reason: 'slide ${i + 1}',
      );
      if (i < 5) {
        await tester.tap(find.text(l10n.walkthroughNext));
        await tester.pumpAndSettle();
      }
    }
  });

  testWidgets('only the welcome slide carries the flow between the peers', (
    tester,
  ) async {
    final slides = walkthroughSlides(_en());

    expect(slides.first.flow, isNotNull);
    expect(slides.skip(1).map((s) => s.flow), everyElement(isNull));
  });

  test('the welcome and security slides carry a flickering bolt', () {
    final bolts = walkthroughSlides(_en()).map((s) => s.bolt != null).toList();

    expect(bolts, [true, false, true, false, false, false]);
  });

  group('the bolt flickers on the handoff keyframes', () {
    test('steady before the glint ends its run', () {
      final zap = zapAt(0.2);
      expect(zap.opacity, 1);
      expect(zap.glow, 0);
    });

    test('dips at 36% and 40%, back to full at 38% and 43%', () {
      expect(zapAt(0.36).opacity, moreOrLessEquals(0.35));
      expect(zapAt(0.38).opacity, moreOrLessEquals(1));
      expect(zapAt(0.40).opacity, moreOrLessEquals(0.55));
      expect(zapAt(0.43).opacity, moreOrLessEquals(1));
    });

    test('glows 5 at 38%, 9 at 43%, 2 at 55%, then fades out', () {
      expect(zapAt(0.38).glow, moreOrLessEquals(5));
      expect(zapAt(0.43).glow, moreOrLessEquals(9));
      expect(zapAt(0.55).glow, moreOrLessEquals(2));
      expect(zapAt(0.99).glow, lessThan(0.5));
    });
  });

  testWidgets('the counter reads as a step to a screen reader', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpWalkthrough(tester);

    expect(
      find.bySemanticsLabel(_en().walkthroughStepSemantics(1, 6)),
      findsOneWidget,
    );
    handle.dispose();
  });

  group('motion', () {
    testWidgets('the ring glint loops while animations are on', (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: _container(),
          child: MaterialApp(
            theme: buildDarkTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const WalkthroughScreen(),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 3));

      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('the glint comes back when animations are turned on again', (
      tester,
    ) async {
      final still = ValueNotifier(true);
      addTearDown(still.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: _container(),
          child: MaterialApp(
            theme: buildDarkTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder:
                (context, child) => ValueListenableBuilder(
                  valueListenable: still,
                  builder:
                      (context, off, _) => MediaQuery(
                        data: MediaQuery.of(
                          context,
                        ).copyWith(disableAnimations: off),
                        child: child!,
                      ),
                ),
            home: const WalkthroughScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);

      still.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tester.hasRunningAnimations, isTrue);
    });

    testWidgets('nothing moves once animations are off', (tester) async {
      await _pumpWalkthrough(tester);

      expect(tester.hasRunningAnimations, isFalse);
      expect(find.byType(WalkthroughArt), findsOneWidget);
    });
  });

  test('every illustration and frame layer is a bundled asset', () async {
    final arts = [
      for (final s in walkthroughSlides(_en())) ...[
        s.art,
        if (s.flow case final flow?) flow.front,
        if (s.bolt case final bolt?) bolt,
      ],
    ];
    for (final path in [...arts, ...WalkthroughArt.frameAssets]) {
      final data = await rootBundle.loadString(path);
      expect(data, startsWith('<svg'), reason: path);
    }
  });

  // DS-A11Y-4: the longest locale, the narrowest screen, the largest text.
  for (final brightness in Brightness.values) {
    testWidgets(
      'every slide fits 320 x 640 in German at 2x text (${brightness.name})',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await _pumpWalkthrough(
          tester,
          locale: const Locale('de'),
          brightness: brightness,
          textScale: 2,
        );
        final de = lookupAppLocalizations(const Locale('de'));
        final slides = walkthroughSlides(de);

        for (var i = 0; i < slides.length; i++) {
          expect(tester.takeException(), isNull, reason: 'slide ${i + 1}');
          expect(find.text(slides[i].title), findsOneWidget);
          if (i < slides.length - 1) {
            await tester.tap(find.text(de.walkthroughNext));
            await tester.pumpAndSettle();
          }
        }
        expect(find.text(de.done), findsOneWidget);
      },
    );
  }
}
