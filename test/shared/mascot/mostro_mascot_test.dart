import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
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

        // Three stars go round the head.
        expect(find.text('✨'), findsNWidgets(3));
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

        expect(find.text('📰'), findsOneWidget);

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

        expect(find.text('✨'), findsNWidgets(3));
      });
    });
  });
}
