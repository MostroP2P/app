import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';

/// Whatever this run was given, so the end-to-end check knows to run.
const String _define = String.fromEnvironment('MOSTRO_FORCE_SEASON');

void main() {
  group('seasonOn', () {
    test('marks the three dates Bitcoin remembers, whatever the year', () {
      // Arrange / Act / Assert
      expect(seasonOn(DateTime(2026, 10, 31)), MostroSeason.whitepaper);
      expect(seasonOn(DateTime(2030, 1, 3)), MostroSeason.genesis);
      expect(seasonOn(DateTime(2008, 5, 22)), MostroSeason.pizzaDay);
    });

    test('leaves every other day alone', () {
      expect(seasonOn(DateTime(2026, 10, 30)), MostroSeason.none);
      expect(seasonOn(DateTime(2026, 11, 1)), MostroSeason.none);
      expect(seasonOn(DateTime(2026, 1, 4)), MostroSeason.none);
      expect(seasonOn(DateTime(2026, 5, 21)), MostroSeason.none);
    });

    test('reads the local date, not the hour', () {
      expect(seasonOn(DateTime(2026, 10, 31, 23, 59)), MostroSeason.whitepaper);
      expect(seasonOn(DateTime(2026, 10, 31, 0, 0)), MostroSeason.whitepaper);
    });
  });

  group('parseSeason', () {
    test('takes the names people reach for, not only the enum\'s', () {
      expect(parseSeason('whitepaper'), MostroSeason.whitepaper);
      expect(parseSeason('halloween'), MostroSeason.whitepaper);
      expect(parseSeason('genesis'), MostroSeason.genesis);
      expect(parseSeason('pizza'), MostroSeason.pizzaDay);
      expect(parseSeason('pizzaDay'), MostroSeason.pizzaDay);
      expect(parseSeason('pizza_day'), MostroSeason.pizzaDay);
      expect(parseSeason('pizza-day'), MostroSeason.pizzaDay);
    });

    test('names an ordinary day too, so a badge can be checked off', () {
      expect(parseSeason('none'), MostroSeason.none);
      expect(parseSeason('ordinary'), MostroSeason.none);
    });

    test('ignores case and surrounding space', () {
      expect(parseSeason('  HALLOWEEN  '), MostroSeason.whitepaper);
      expect(parseSeason('Genesis'), MostroSeason.genesis);
    });

    test('names nothing when it is not a season', () {
      expect(parseSeason(''), isNull);
      expect(parseSeason('   '), isNull);
      expect(parseSeason('easter'), isNull);
      expect(parseSeason('2026-10-31'), isNull);
    });
  });

  group('resolveSeason', () {
    final halloween = DateTime(2026, 10, 31);
    final plainDay = DateTime(2026, 6, 1);

    test('lets the date decide when nothing forces a season', () {
      expect(
        resolveSeason(forced: null, now: halloween),
        MostroSeason.whitepaper,
      );
      expect(resolveSeason(forced: null, now: plainDay), MostroSeason.none);
    });

    test('prefers a forced season over the date', () {
      expect(
        resolveSeason(forced: MostroSeason.pizzaDay, now: plainDay),
        MostroSeason.pizzaDay,
      );
    });

    test('lets a forced ordinary day win over a real anniversary', () {
      expect(
        resolveSeason(forced: MostroSeason.none, now: halloween),
        MostroSeason.none,
      );
    });
  });

  group('forcedSeason', () {
    test('forces nothing unless the build says so', () {
      // The anniversaries have to keep arriving on their own in an ordinary
      // build, which is every build that does not pass the define.
      expect(forcedSeason, _define.isEmpty ? isNull : isNotNull);
    });

    test(
      'reaches currentSeason when the build defines one',
      () {
        expect(forcedSeason, parseSeason(_define));
        // An ordinary day, so only the define can be answering.
        expect(currentSeason(DateTime(2026, 6, 1)), forcedSeason);
      },
      skip:
          _define.isEmpty
              ? 'pass --dart-define=MOSTRO_FORCE_SEASON=genesis to check '
                  'the wiring end to end'
              : false,
    );
  });

  group('seasonEmoji', () {
    test('gives each season its badge and the ordinary day none', () {
      expect(seasonEmoji(MostroSeason.whitepaper), '🎃');
      expect(seasonEmoji(MostroSeason.genesis), '📰');
      expect(seasonEmoji(MostroSeason.pizzaDay), '🍕');
      expect(seasonEmoji(MostroSeason.none), isNull);
    });
  });

  group('nextTapCount', () {
    final now = DateTime(2026, 6, 1, 12, 0, 0);

    test('starts the streak on the first tap', () {
      expect(nextTapCount(count: 0, lastTap: null, now: now), 1);
    });

    test('grows while the taps keep coming', () {
      expect(
        nextTapCount(
          count: 3,
          lastTap: now.subtract(const Duration(milliseconds: 300)),
          now: now,
        ),
        4,
      );
    });

    test('starts over once the streak goes cold', () {
      expect(
        nextTapCount(
          count: 5,
          lastTap: now.subtract(mostroTapWindow + const Duration(seconds: 1)),
          now: now,
        ),
        1,
      );
    });

    test('wraps after the dizzy tap so the streak can be earned again', () {
      expect(
        nextTapCount(
          count: mostroDizzyTaps,
          lastTap: now.subtract(const Duration(milliseconds: 100)),
          now: now,
        ),
        1,
      );
    });
  });

  group('moodForTaps', () {
    test('is pleased up to the dizzy tap, and dizzy on it', () {
      for (var taps = 1; taps < mostroDizzyTaps; taps++) {
        expect(moodForTaps(taps), MostroMood.happy, reason: 'tap $taps');
      }
      expect(moodForTaps(mostroDizzyTaps), MostroMood.dizzy);
    });
  });

  group('isLooping', () {
    test('separates the moods that never end from the one-shot reactions', () {
      expect(isLoopingMood(MostroMood.asleep), isTrue);
      expect(isLoopingMood(MostroMood.impatient), isTrue);
      expect(isLoopingMood(MostroMood.happy), isFalse);
      expect(isLoopingMood(MostroMood.dizzy), isFalse);
      expect(isLoopingMood(MostroMood.celebrating), isFalse);
      expect(isLoopingMood(MostroMood.neutral), isFalse);
    });
  });
}
