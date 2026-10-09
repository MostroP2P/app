import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';

/// Whatever this run was given, so the end-to-end check knows to run.
const String _define = String.fromEnvironment('MOSTRO_FORCE_SEASON');

/// The season this run's define actually names, which is the thing to key on.
/// A define that is absent and one that names no season both name nothing,
/// and "non-empty" is not the same as "forces a season".
final MostroSeason? _named = parseSeason(_define);

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
    test('is exactly what this build\'s define names', () {
      // Holds in every build, including one whose define names no season.
      expect(forcedSeason, _named);
    });

    test(
      'forces nothing when nothing names a season',
      () {
        // The ordinary case, and the one CI runs: the anniversaries have to
        // keep arriving on their own.
        expect(forcedSeason, isNull);
        expect(currentSeason(DateTime(2026, 10, 31)), MostroSeason.whitepaper);
      },
      skip:
          _named == null
              ? false
              : 'this build forces $_named, so it cannot make this claim',
    );

    test(
      'reaches currentSeason when the build defines one',
      () {
        // An ordinary day, so only the define can be answering.
        expect(currentSeason(DateTime(2026, 6, 1)), _named);
      },
      skip:
          _named == null
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

    test('keeps counting past the dizzy tap, up to the laugh', () {
      expect(
        nextTapCount(
          count: mostroDizzyTaps,
          lastTap: now.subtract(const Duration(milliseconds: 100)),
          now: now,
        ),
        mostroDizzyTaps + 1,
      );
    });

    test('wraps after the laugh so the streak can be earned again', () {
      expect(
        nextTapCount(
          count: mostroLaughTaps,
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

    test('gets dizzy again every seven, and laughs on the 21st', () {
      expect(moodForTaps(mostroDizzyTaps + 1), MostroMood.happy);
      expect(moodForTaps(2 * mostroDizzyTaps), MostroMood.dizzy);
      expect(moodForTaps(mostroLaughTaps - 1), MostroMood.happy);
      expect(moodForTaps(mostroLaughTaps), MostroMood.laughing);
    });
  });

  group('moodForCompletion', () {
    test('celebrates a trade, and is on fire from the third of the day', () {
      expect(moodForCompletion(1), MostroMood.celebrating);
      expect(moodForCompletion(2), MostroMood.celebrating);
      expect(moodForCompletion(mostroFireStreak), MostroMood.onFire);
      expect(moodForCompletion(mostroFireStreak + 2), MostroMood.onFire);
    });
  });

  group('isMorning', () {
    test('is from five to eleven, local time', () {
      expect(isMorning(DateTime(2026, 6, 1, 5)), isTrue);
      expect(isMorning(DateTime(2026, 6, 1, 10, 59)), isTrue);
      expect(isMorning(DateTime(2026, 6, 1, 4, 59)), isFalse);
      expect(isMorning(DateTime(2026, 6, 1, 11)), isFalse);
      expect(isMorning(DateTime(2026, 6, 1, 23)), isFalse);
    });
  });

  group('seasonSticker', () {
    test('the genesis block is a day to hodl; the others keep their badge', () {
      expect(seasonSticker(MostroSeason.genesis), 'hodl');
      expect(seasonSticker(MostroSeason.whitepaper), isNull);
      expect(seasonSticker(MostroSeason.pizzaDay), isNull);
      expect(seasonSticker(MostroSeason.none), isNull);
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

    test('offline lasts as long as the outage, a trade step plays once', () {
      expect(isLoopingMood(MostroMood.offline), isTrue);
      for (final mood in const [
        MostroMood.escrowLocked,
        MostroMood.fiatSent,
        MostroMood.disputed,
        MostroMood.canceled,
        MostroMood.published,
        MostroMood.loved,
        MostroMood.thankful,
        MostroMood.refused,
      ]) {
        expect(isLoopingMood(mood), isFalse, reason: mood.name);
      }
    });
  });

  group('moodSticker', () {
    test('each mood wears its sticker, and rest wears the plain mascot', () {
      expect(moodSticker(MostroMood.neutral), isNull);
      expect(moodSticker(MostroMood.happy), 'waving');
      expect(moodSticker(MostroMood.dizzy), 'confused');
      expect(moodSticker(MostroMood.asleep), 'bored');
      expect(moodSticker(MostroMood.impatient), 'thinking');
      expect(moodSticker(MostroMood.celebrating), 'celebrate');
    });

    test('each trade step and app event wears its own', () {
      expect(moodSticker(MostroMood.escrowLocked), 'escrow');
      expect(moodSticker(MostroMood.fiatSent), 'money');
      expect(moodSticker(MostroMood.disputed), 'dispute');
      expect(moodSticker(MostroMood.canceled), 'cry');
      expect(moodSticker(MostroMood.offline), 'scared');
      expect(moodSticker(MostroMood.published), 'rocket');
      expect(moodSticker(MostroMood.loved), 'love');
      expect(moodSticker(MostroMood.thankful), 'thanks');
      expect(moodSticker(MostroMood.refused), 'facepalm');
    });

    test('the easter eggs wear the rest of the set', () {
      expect(moodSticker(MostroMood.greeting), 'gm');
      expect(moodSticker(MostroMood.orderTaken), 'p2p');
      expect(moodSticker(MostroMood.cancelAsked), 'surprised');
      expect(moodSticker(MostroMood.invoiceAccepted), 'lightning');
      expect(moodSticker(MostroMood.backedUp), 'check');
      expect(moodSticker(MostroMood.laughing), 'laugh');
      expect(moodSticker(MostroMood.cool), 'cool');
      expect(moodSticker(MostroMood.onFire), 'fire');
      expect(moodSticker(MostroMood.agreed), 'thumbsup');
    });

    test('every mood but rest has one', () {
      for (final mood in MostroMood.values) {
        if (mood == MostroMood.neutral) continue;
        expect(moodSticker(mood), isNotNull, reason: mood.name);
      }
    });
  });

  group('pickMood', () {
    test('rests when nothing asks for a mood', () {
      expect(pickMood(const []), MostroMood.neutral);
    });

    test('offline beats everything, a dispute everything else', () {
      expect(
        pickMood(const [
          MostroMood.disputed,
          MostroMood.offline,
          MostroMood.celebrating,
        ]),
        MostroMood.offline,
      );
      expect(
        pickMood(const [MostroMood.disputed, MostroMood.fiatSent]),
        MostroMood.disputed,
      );
      expect(
        pickMood(const [MostroMood.fiatSent, MostroMood.disputed]),
        MostroMood.disputed,
      );
    });

    test('a reaction beats a mood that only sets the scene', () {
      expect(
        pickMood(const [MostroMood.impatient, MostroMood.escrowLocked]),
        MostroMood.escrowLocked,
      );
      expect(
        pickMood(const [MostroMood.celebrating, MostroMood.asleep]),
        MostroMood.celebrating,
      );
      expect(pickMood(const [MostroMood.impatient]), MostroMood.impatient);
    });

    test('between equals, the newer one wins', () {
      expect(
        pickMood(const [MostroMood.escrowLocked, MostroMood.fiatSent]),
        MostroMood.fiatSent,
      );
      expect(
        pickMood(const [MostroMood.fiatSent, MostroMood.escrowLocked]),
        MostroMood.escrowLocked,
      );
    });
  });

  group('moodForRating', () {
    test('five stars is love, any other score a thank-you', () {
      expect(moodForRating(5), MostroMood.loved);
      for (final score in const [1, 2, 3, 4]) {
        expect(moodForRating(score), MostroMood.thankful, reason: '$score');
      }
    });
  });

  group('isFreshEvent', () {
    final now = DateTime.utc(2026, 6, 1, 12);

    test('something that just happened is news', () {
      expect(isFreshEvent(occurredAt: now, now: now), isTrue);
      expect(
        isFreshEvent(
          occurredAt: now.subtract(const Duration(seconds: 30)),
          now: now,
        ),
        isTrue,
      );
    });

    test('a relay slow by up to two minutes still counts', () {
      expect(
        isFreshEvent(occurredAt: now.subtract(mostroFreshEvent), now: now),
        isTrue,
      );
    });

    test('a replayed past is not news', () {
      expect(
        isFreshEvent(
          occurredAt: now.subtract(const Duration(minutes: 3)),
          now: now,
        ),
        isFalse,
      );
      expect(
        isFreshEvent(
          occurredAt: now.subtract(const Duration(days: 40)),
          now: now,
        ),
        isFalse,
      );
    });

    test('a sender clock a little ahead of ours is still news', () {
      expect(
        isFreshEvent(
          occurredAt: now.add(const Duration(seconds: 20)),
          now: now,
        ),
        isTrue,
      );
    });
  });
}
