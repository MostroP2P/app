import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/shared/mascot/mostro_mascot.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';

/// An ordinary day: no anniversary, so nothing is on Mostro's head.
final DateTime _plainDay = DateTime(2026, 6, 1, 12);

Future<void> _pump(
  WidgetTester tester,
  Widget mascot, {
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
      home: Scaffold(body: Center(child: mascot)),
    ),
  );
  await tester.pump();
}

/// Whether the artwork is being moved at this instant. At rest the mascot
/// renders the bare image, so any [Transform] means it is reacting.
bool _isMoving(WidgetTester tester) =>
    find
        .descendant(
          of: find.byType(MostroMascot),
          matching: find.byType(Transform),
        )
        .evaluate()
        .isNotEmpty;

/// The opacities [glyph] is being drawn at right now.
///
/// Present is not the same as visible: the flourishes are built whatever the
/// animation is doing and fade in with it, so a mood that never starts leaves
/// them in the tree at zero. That gap is where the celebration bug hid.
Iterable<double> _glyphOpacities(WidgetTester tester, String glyph) => tester
    .widgetList<Opacity>(
      find.ancestor(of: find.text(glyph), matching: find.byType(Opacity)),
    )
    .map((opacity) => opacity.opacity);

/// The asset the mascot is drawn from right now.
String _artwork(WidgetTester tester) {
  final image = tester.widget<Image>(
    find.descendant(
      of: find.byType(MostroMascot),
      matching: find.byType(Image),
    ),
  );
  return (image.image as AssetImage).assetName;
}

Future<void> _tap(WidgetTester tester) async {
  await tester.tap(find.byType(MostroMascot));
  await tester.pump();
}

void main() {
  group('tapping the mascot', () {
    testWidgets('sits still until it is tapped', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(
          tester,
          const MostroMascot(height: 26, interactive: true),
        );

        expect(_isMoving(tester), isFalse);
      });
    });

    testWidgets('bounces on a single tap, without stars', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(
          tester,
          const MostroMascot(height: 26, interactive: true),
        );

        await _tap(tester);
        await tester.pump(const Duration(milliseconds: 200));

        expect(_isMoving(tester), isTrue);
        expect(find.text('✨'), findsNothing);
      });
    });

    testWidgets('goes dizzy, with stars, on the seventh tap in a row',
        (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(
          tester,
          const MostroMascot(height: 26, interactive: true),
        );

        for (var i = 0; i < mostroDizzyTaps - 1; i++) {
          await _tap(tester);
          expect(find.text('✨'), findsNothing, reason: 'after tap ${i + 1}');
        }
        await _tap(tester);
        await tester.pump(const Duration(milliseconds: 200));

        // Three stars go round the head, and are actually drawn.
        expect(find.text('✨'), findsNWidgets(3));
        expect(_glyphOpacities(tester, '✨'), everyElement(greaterThan(0)));
      });
    });

    testWidgets('laughs on the 21st tap in a row', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(
          tester,
          const MostroMascot(height: 26, interactive: true),
        );

        for (var i = 0; i < mostroLaughTaps - 1; i++) {
          await _tap(tester);
        }
        expect(_artwork(tester), isNot(MostroMascot.stickerAsset('laugh')));
        await _tap(tester);

        expect(_artwork(tester), MostroMascot.stickerAsset('laugh'));
        await tester.pumpAndSettle();
      });
    });

    testWidgets('puts its shades on when held', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(
          tester,
          const MostroMascot(height: 26, interactive: true),
        );

        await tester.longPress(find.byType(MostroMascot));
        await tester.pump();

        expect(_artwork(tester), MostroMascot.stickerAsset('cool'));
        await tester.pumpAndSettle();
        expect(_artwork(tester), MostroMascot.asset);
      });
    });

    testWidgets('forgets a streak that went cold', (tester) async {
      var now = _plainDay;
      await withClock(Clock(() => now), () async {
        await _pump(
          tester,
          const MostroMascot(height: 26, interactive: true),
        );

        for (var i = 0; i < mostroDizzyTaps - 1; i++) {
          await _tap(tester);
        }
        // Long enough that the next tap starts a new streak.
        now = now.add(mostroTapWindow + const Duration(seconds: 1));
        await _tap(tester);
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('✨'), findsNothing);
      });
    });

    testWidgets('ignores taps when it is not the interactive one',
        (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(tester, const MostroMascot(height: 26));

        await _tap(tester);
        await tester.pump(const Duration(milliseconds: 200));

        expect(_isMoving(tester), isFalse);
      });
    });
  });

  group('the dates Bitcoin remembers', () {
    final en = AppLocalizationsEn();

    testWidgets('wears nothing on an ordinary day', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(
          tester,
          const MostroMascot(height: 40, interactive: true),
        );

        expect(find.text('🎃'), findsNothing);
        expect(find.text('📰'), findsNothing);
        expect(find.text('🍕'), findsNothing);

        await _tap(tester);
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(SnackBar), findsNothing);
      });
    });

    testWidgets('wears a pumpkin on 31 October and quotes the whitepaper',
        (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 10, 31, 9)), () async {
        await _pump(
          tester,
          const MostroMascot(height: 40, interactive: true),
        );

        expect(find.text('🎃'), findsOneWidget);

        await _tap(tester);
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text(en.easterEggWhitepaper), findsOneWidget);
      });
    });

    testWidgets('quotes The Times on 3 January', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 1, 3, 9)), () async {
        await _pump(
          tester,
          const MostroMascot(height: 40, interactive: true),
        );

        // The day the genesis block was mined, Mostro hodls, in place of the
        // newspaper badge.
        expect(find.text('📰'), findsNothing);
        expect(_artwork(tester), MostroMascot.stickerAsset('hodl'));

        await _tap(tester);
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.textContaining('The Times 03/Jan/2009'), findsOneWidget);
      });
    });

    testWidgets('serves pizza on 22 May', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 5, 22, 9)), () async {
        await _pump(
          tester,
          const MostroMascot(height: 40, interactive: true),
        );

        expect(find.text('🍕'), findsOneWidget);

        await _tap(tester);
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text(en.easterEggPizzaDay), findsOneWidget);
      });
    });

    testWidgets('says it once per streak, not once per tap', (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 5, 22, 9)), () async {
        await _pump(
          tester,
          const MostroMascot(height: 40, interactive: true),
        );

        await _tap(tester);
        await _tap(tester);
        await _tap(tester);
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.text(en.easterEggPizzaDay), findsOneWidget);
      });
    });

    testWidgets('shows the badge even where tapping does nothing',
        (tester) async {
      await withClock(Clock.fixed(DateTime(2026, 10, 31, 9)), () async {
        await _pump(tester, const MostroMascot(height: 40));

        expect(find.text('🎃'), findsOneWidget);
      });
    });
  });

  group('accessibility', () {
    testWidgets('keeps the whole mascot out of the semantics tree',
        (tester) async {
      // A day with a badge on, and tapped into its noisiest state, so every
      // glyph the mascot can draw is on screen at once.
      await withClock(Clock.fixed(DateTime(2026, 10, 31, 9)), () async {
        final semantics = tester.ensureSemantics();
        await _pump(
          tester,
          const MostroMascot(height: 40, interactive: true),
        );
        for (var i = 0; i < mostroDizzyTaps; i++) {
          await _tap(tester);
        }
        await tester.pump(const Duration(milliseconds: 200));

        expect(find.text('✨'), findsNWidgets(3));
        expect(find.bySemanticsLabel('✨'), findsNothing);
        expect(find.bySemanticsLabel('🎃'), findsNothing);
        // An unlabelled tap target would be worse than no target at all.
        // With the mascot excluded this resolves to the node above it, which
        // offers nothing; were it exposing its own, that node would be it.
        expect(
          tester.getSemantics(find.byType(MostroMascot)),
          isNot(isSemantics(hasTapAction: true)),
        );

        semantics.dispose();
      });
    });

    testWidgets('pads the small header artwork out to a 48 dp target', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(
          tester,
          const MostroMascot(height: 26, interactive: true),
        );
        final mascot = find.byType(MostroMascot);
        expect(tester.getSize(mascot), const Size.square(48));

        // Beside the 18-dp-wide artwork, still inside the target (DS-CMP-6).
        await tester.tapAt(tester.getCenter(mascot) + const Offset(20, 0));
        await tester.pump(const Duration(milliseconds: 200));

        expect(_isMoving(tester), isTrue);
      });
    });

    testWidgets('takes only the artwork\'s room when nothing is to tap', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(tester, const MostroMascot(height: 26));

        expect(
          tester.getSize(find.byType(MostroMascot)),
          const Size(26 * MostroMascot.aspect, 26),
        );
      });
    });

    testWidgets('keeps the sleeping Z out of it too', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        final semantics = tester.ensureSemantics();
        await _pump(
          tester,
          const MostroMascot(height: 64, mood: MostroMood.asleep),
        );
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Z'), findsOneWidget);
        expect(find.bySemanticsLabel('Z'), findsNothing);

        semantics.dispose();
      });
    });
  });

  group('ambient moods', () {
    testWidgets('sleeps with a Z when there is nothing to trade',
        (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(
          tester,
          const MostroMascot(height: 64, mood: MostroMood.asleep),
        );
        // Never settled on purpose: sleeping is a loop.
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Z'), findsOneWidget);
        expect(_isMoving(tester), isTrue);
      });
    });

    testWidgets('holds still while the viewer asks for less motion',
        (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(
          tester,
          const MostroMascot(height: 64, mood: MostroMood.asleep),
          reduceMotion: true,
        );

        // The loop never starts, so the frame settles.
        await tester.pumpAndSettle();

        expect(find.text('Z'), findsOneWidget);
      });
    });

    testWidgets('shuffles while the book keeps it waiting', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(
          tester,
          const MostroMascot(height: 26, mood: MostroMood.impatient),
        );
        await tester.pump(const Duration(milliseconds: 200));

        expect(_isMoving(tester), isTrue);
      });
    });

    testWidgets('throws sparkles when a trade completes', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(
          tester,
          const MostroMascot(height: 26, mood: MostroMood.celebrating),
        );
        await tester.pump(const Duration(milliseconds: 300));

        // Nobody taps to celebrate: the mood arrives from the screen, so the
        // mascot has to start this one itself or it is never seen.
        expect(find.text('✨'), findsNWidgets(3));
        expect(_glyphOpacities(tester, '✨'), everyElement(greaterThan(0)));
      });
    });

    testWidgets('keeps the celebration still under reduce motion',
        (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(
          tester,
          const MostroMascot(height: 26, mood: MostroMood.celebrating),
          reduceMotion: true,
        );
        await tester.pumpAndSettle();

        // Motion nobody asked for answers to the setting; a tap reaction,
        // which the viewer caused, does not.
        expect(_glyphOpacities(tester, '✨'), everyElement(0));
      });
    });
  });

  group('artwork', () {
    /// The asset the mascot is drawn from right now.
    String artwork(WidgetTester tester) {
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byType(MostroMascot),
          matching: find.byType(Image),
        ),
      );
      return (image.image as AssetImage).assetName;
    }

    testWidgets('at rest it is the plain mascot', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(tester, const MostroMascot(height: 26));

        expect(artwork(tester), MostroMascot.asset);
      });
    });

    testWidgets('each ambient mood wears its sticker', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        for (final mood in [
          MostroMood.asleep,
          MostroMood.impatient,
          MostroMood.celebrating,
        ]) {
          await _pump(tester, MostroMascot(height: 26, mood: mood));

          expect(
            artwork(tester),
            MostroMascot.stickerAsset(moodSticker(mood)!),
            reason: mood.name,
          );
        }
      });
    });

    testWidgets('a tap waves, then rests again', (tester) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(tester, const MostroMascot(height: 26, interactive: true));

        await _tap(tester);
        expect(artwork(tester), MostroMascot.stickerAsset('waving'));

        await tester.pumpAndSettle();
        expect(artwork(tester), MostroMascot.asset);
      });
    });

    testWidgets('a sticker takes the same room as the plain mascot', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(tester, const MostroMascot(height: 26));
        final atRest = tester.getSize(find.byType(MostroMascot));

        await _pump(
          tester,
          const MostroMascot(height: 26, mood: MostroMood.celebrating),
        );

        expect(tester.getSize(find.byType(MostroMascot)), atRest);
      });
    });

    testWidgets('with reduce motion it keeps the sticker, standing still', (
      tester,
    ) async {
      await withClock(Clock.fixed(_plainDay), () async {
        await _pump(
          tester,
          const MostroMascot(height: 64, mood: MostroMood.asleep),
          reduceMotion: true,
        );

        // The loop never starts, so the frame settles, sticker on.
        await tester.pumpAndSettle();

        expect(artwork(tester), MostroMascot.stickerAsset('bored'));
      });
    });

    testWidgets('every sticker a mood names is bundled', (tester) async {
      for (final mood in MostroMood.values) {
        final sticker = moodSticker(mood);
        if (sticker == null) continue;
        final asset = MostroMascot.stickerAsset(sticker);
        final data = await tester.runAsync(() => rootBundle.load(asset));
        expect(data!.lengthInBytes, greaterThan(0), reason: asset);
      }
      for (final season in MostroSeason.values) {
        final sticker = seasonSticker(season);
        if (sticker == null) continue;
        final asset = MostroMascot.stickerAsset(sticker);
        final data = await tester.runAsync(() => rootBundle.load(asset));
        expect(data!.lengthInBytes, greaterThan(0), reason: asset);
      }
    });
  });
}
