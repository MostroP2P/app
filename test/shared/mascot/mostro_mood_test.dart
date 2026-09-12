import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';

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
