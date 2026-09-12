/// Pure rules of the Mostro mascot's easter eggs. No Flutter here, so every
/// rule is unit-testable; the widgets only render what these return.
library;

/// How Mostro is feeling. Everything else about the mascot is the same
/// artwork: the mood only decides how it moves.
enum MostroMood {
  /// Resting. No motion at all.
  neutral,

  /// Tapped. A short, springy bounce.
  happy,

  /// Tapped [mostroDizzyTaps] times in a row. Wobbles, with stars.
  dizzy,

  /// Nothing to trade. Breathes slowly, with a rising Z.
  asleep,

  /// The book is taking its time. Shuffles from foot to foot.
  impatient,

  /// A trade just completed. Jumps, with sparkles.
  celebrating,
}

/// A date Bitcoin remembers, and Mostro with it.
enum MostroSeason {
  none,

  /// 31 October. The whitepaper, and — Mostro being a monster — Halloween.
  whitepaper,

  /// 3 January. The genesis block, and the headline inside it.
  genesis,

  /// 22 May. Two pizzas, ten thousand bitcoin.
  pizzaDay,
}

/// Taps in a row that make Mostro dizzy. One tap is a greeting; this many is
/// someone who kept going, which is the point of an easter egg.
const int mostroDizzyTaps = 7;

/// How long a tap streak survives without another tap. Short enough that a
/// stray tap tomorrow does not count towards today's.
const Duration mostroTapWindow = Duration(seconds: 2);

/// The season [date] falls on, by day and month: the anniversaries repeat
/// every year, so the year is deliberately ignored.
MostroSeason seasonOn(DateTime date) => switch ((date.month, date.day)) {
  (10, 31) => MostroSeason.whitepaper,
  (1, 3) => MostroSeason.genesis,
  (5, 22) => MostroSeason.pizzaDay,
  _ => MostroSeason.none,
};

/// The badge Mostro wears on [season], or null on an ordinary day.
///
/// System emoji, like the currency flags elsewhere in the app: it renders on
/// every platform without shipping an asset per season.
String? seasonEmoji(MostroSeason season) => switch (season) {
  MostroSeason.whitepaper => '🎃',
  MostroSeason.genesis => '📰',
  MostroSeason.pizzaDay => '🍕',
  MostroSeason.none => null,
};

/// The streak length after a tap at [now], given the previous [count] and the
/// time of the [lastTap].
///
/// Starts over both when the streak has gone cold and right after the dizzy
/// tap, so the easter egg can be earned again rather than staying dizzy.
int nextTapCount({
  required int count,
  required DateTime? lastTap,
  required DateTime now,
}) {
  if (lastTap == null || now.difference(lastTap) > mostroTapWindow) return 1;
  final next = count + 1;
  return next > mostroDizzyTaps ? 1 : next;
}

/// The mood a streak of [count] taps earns.
MostroMood moodForTaps(int count) =>
    count >= mostroDizzyTaps ? MostroMood.dizzy : MostroMood.happy;

/// Whether [mood] is an ambient state that runs until it is replaced, as
/// opposed to a reaction that plays once and is over.
///
/// Load-bearing beyond style: a looping animation never lets a widget test
/// settle, so the looping moods are the ones the mascot gates behind the
/// viewer's reduce-motion setting.
bool isLoopingMood(MostroMood mood) =>
    mood == MostroMood.asleep || mood == MostroMood.impatient;
