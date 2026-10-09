/// Pure rules of the Mostro mascot's easter eggs. No Flutter here, so every
/// rule is unit-testable; the widgets only render what these return.
library;

/// How Mostro is feeling: how it moves, and which sticker it wears
/// ([moodSticker]).
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

  // ── Trade steps (#770 part 3), from `TradeUpdate` alone ──────────────────

  /// The seller's hold invoice is paid: the sats are in escrow. Settles in.
  escrowLocked,

  /// The buyer says the fiat is on its way. A hop.
  fiatSent,

  /// A dispute was opened. A stern shake, and it outranks every other step.
  disputed,

  /// The trade ended without one: canceled, by either side or an admin, or
  /// expired. Sinks a little.
  canceled,

  // ── The app around it ────────────────────────────────────────────────────

  /// No relay is reachable, and has not been for [mostroOfflineGrace].
  /// Shivers until one is, and outranks everything.
  offline,

  /// The node confirmed a new order. Lifts off.
  published,

  /// The user gave the counterparty five stars. A nod.
  loved,

  /// The user rated the counterparty, below five stars. A nod.
  thankful,

  /// The node refused an action (a `CantDo`). Shakes its head.
  refused,

  // ── Easter eggs (#770 part 4) ────────────────────────────────────────────

  /// The first look of a morning session ([isMorning]). Waves.
  greeting,

  /// The node confirmed a take. A hop.
  orderTaken,

  /// The counterparty asked to cancel. Jumps back.
  cancelAsked,

  /// The node accepted the buyer's invoice. A zap.
  invoiceAccepted,

  /// The user just verified their backup. A nod.
  backedUp,

  /// Tapped [mostroLaughTaps] times in a row. Shakes with laughter.
  laughing,

  /// Held. Leans back, shades on.
  cool,

  /// The [mostroFireStreak]th trade completed in a day, or later. Jumps.
  onFire,

  /// The counterparty agreed to the cancel this side asked for. A nod.
  agreed,
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

/// Taps in a row that make Mostro laugh: 21, for the 21 million. On the way
/// there it gets dizzy every [mostroDizzyTaps].
const int mostroLaughTaps = 21;

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

// ── Forcing a season, for a look ──────────────────────────────────────────────

/// Season forced by `--dart-define=MOSTRO_FORCE_SEASON=<name>`.
///
/// The anniversaries come round once a year, and moving the machine's clock
/// to meet them is a bad trade in this app: the events it signs would carry a
/// displaced timestamp and relays would start refusing them. This shows one on
/// demand instead, without touching the clock.
///
/// ```bash
/// flutter run -d linux --dart-define=MOSTRO_FORCE_SEASON=whitepaper
/// ```
const String _forceSeasonDefine = String.fromEnvironment('MOSTRO_FORCE_SEASON');

/// True in a release build. Read from the VM's own define rather than from
/// `kReleaseMode`, which would drag Flutter into these pure rules.
const bool _isReleaseBuild = bool.fromEnvironment('dart.vm.product');

/// The forced season, or null when nothing forces one.
///
/// A release build ignores the define outright, so a stray `--dart-define` on
/// a shipping build cannot leave Mostro in a pumpkin hat all year.
MostroSeason? get forcedSeason =>
    _isReleaseBuild ? null : parseSeason(_forceSeasonDefine);

/// The season named by [value], or null if it names none.
///
/// Trimmed and case-insensitive, and it takes the names people reach for
/// rather than only the enum's. An absent define is the empty string, which
/// names nothing and so changes nothing.
MostroSeason? parseSeason(String value) => switch (value.trim().toLowerCase()) {
  'whitepaper' || 'halloween' => MostroSeason.whitepaper,
  'genesis' => MostroSeason.genesis,
  'pizza' || 'pizzaday' || 'pizza_day' || 'pizza-day' => MostroSeason.pizzaDay,
  // Worth naming: it forces an ordinary day, so the badge can be checked off
  // on a date that would otherwise put one on.
  'none' || 'ordinary' => MostroSeason.none,
  _ => null,
};

/// Which season wins: a [forced] one when there is one, otherwise whichever
/// [now] falls on.
MostroSeason resolveSeason({
  required MostroSeason? forced,
  required DateTime now,
}) => forced ?? seasonOn(now);

/// The season to show right now. The one the widgets call.
MostroSeason currentSeason(DateTime now) =>
    resolveSeason(forced: forcedSeason, now: now);

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

/// The sticker [mood] wears, by name, or null for the plain artwork.
///
/// Until #770 a mood only moved the one artwork. Each one now also has its
/// face from the Mostro sticker set, and keeps its motion on top. The
/// stickers carry their own props (confetti, Zs, question marks), which
/// read even at the header's 26 dp. Swapping the artwork is not motion, so
/// it stays when the viewer has asked for less of it.
String? moodSticker(MostroMood mood) => switch (mood) {
  MostroMood.neutral => null,
  MostroMood.happy => 'waving',
  MostroMood.dizzy => 'confused',
  MostroMood.asleep => 'bored',
  MostroMood.impatient => 'thinking',
  MostroMood.celebrating => 'celebrate',
  MostroMood.escrowLocked => 'escrow',
  MostroMood.fiatSent => 'money',
  MostroMood.disputed => 'dispute',
  MostroMood.canceled => 'cry',
  MostroMood.offline => 'scared',
  MostroMood.published => 'rocket',
  MostroMood.loved => 'love',
  MostroMood.thankful => 'thanks',
  MostroMood.refused => 'facepalm',
  MostroMood.greeting => 'gm',
  MostroMood.orderTaken => 'p2p',
  MostroMood.cancelAsked => 'surprised',
  MostroMood.invoiceAccepted => 'lightning',
  MostroMood.backedUp => 'check',
  MostroMood.laughing => 'laugh',
  MostroMood.cool => 'cool',
  MostroMood.onFire => 'fire',
  MostroMood.agreed => 'thumbsup',
};

/// The sticker Mostro wears at rest on [season], in place of its badge, or
/// null when the season keeps the plain artwork and its badge.
///
/// The genesis block's day is the day to hodl. Only the mascot that wears
/// stickers does: the drawer keeps its artwork and its 📰 badge.
String? seasonSticker(MostroSeason season) =>
    season == MostroSeason.genesis ? 'hodl' : null;

/// How long a reaction to something that happened stays on show: long
/// enough to read the sticker, short enough not to become the new rest.
const Duration mostroCueHold = Duration(milliseconds: 1800);

/// How long the relays may stay out of reach before Mostro is scared. A cold
/// start, a node switch or a network change drops them for a moment, and
/// that is not an outage worth a face.
const Duration mostroOfflineGrace = Duration(seconds: 8);

/// The top score a rating can give.
const int mostroTopRating = 5;

/// The mood a rating of [score] earns: love for the top score, thanks for
/// any other.
MostroMood moodForRating(int score) =>
    score >= mostroTopRating ? MostroMood.loved : MostroMood.thankful;

/// How strongly [mood] claims the mascot when several apply at once.
///
/// An outage hides everything else, because nothing that happens while it
/// lasts can be trusted to have reached the node. A dispute is the step the
/// user must not miss. Every other reaction outranks the moods that only
/// set the scene, and those outrank rest.
int _rank(MostroMood mood) => switch (mood) {
  MostroMood.offline => 4,
  MostroMood.disputed => 3,
  MostroMood.neutral => 0,
  _ when isLoopingMood(mood) => 1,
  _ => 2,
};

/// The one mood to show of [moods], listed oldest first: the strongest
/// ([_rank]), and the newest of equals. Rest when there is none.
MostroMood pickMood(Iterable<MostroMood> moods) {
  var shown = MostroMood.neutral;
  for (final mood in moods) {
    if (_rank(mood) >= _rank(shown)) shown = mood;
  }
  return shown;
}

/// How old a trade event may be and still count as news.
///
/// A daemon message carries its own `created_at`, which a relay slow to
/// deliver, or a sender's clock a little off ours, can push back by a minute
/// or so. A history replay after a restore is days or months old (#474):
/// celebrating that would be celebrating the past.
const Duration mostroFreshEvent = Duration(minutes: 2);

/// Whether something that happened at [occurredAt] is still news at [now].
/// A time slightly ahead of ours is a sender clock, not the future, so it
/// counts.
bool isFreshEvent({required DateTime occurredAt, required DateTime now}) =>
    now.difference(occurredAt) <= mostroFreshEvent;

/// The streak length after a tap at [now], given the previous [count] and the
/// time of the [lastTap].
///
/// Starts over both when the streak has gone cold and right after the laugh,
/// so the easter eggs can be earned again.
int nextTapCount({
  required int count,
  required DateTime? lastTap,
  required DateTime now,
}) {
  if (lastTap == null || now.difference(lastTap) > mostroTapWindow) return 1;
  final next = count + 1;
  return next > mostroLaughTaps ? 1 : next;
}

/// The mood a streak of [count] taps earns: a laugh on the 21st, dizzy on
/// every seventh before it, pleased otherwise.
MostroMood moodForTaps(int count) {
  if (count >= mostroLaughTaps) return MostroMood.laughing;
  if (count % mostroDizzyTaps == 0) return MostroMood.dizzy;
  return MostroMood.happy;
}

/// Trades completed in one day that set Mostro on fire.
const int mostroFireStreak = 3;

/// The mood a completed trade earns, the [completedToday]th of its day.
MostroMood moodForCompletion(int completedToday) =>
    completedToday >= mostroFireStreak
        ? MostroMood.onFire
        : MostroMood.celebrating;

/// The morning, in local hours: from [_morningStarts] until [_morningEnds].
const int _morningStarts = 5;
const int _morningEnds = 11;

/// Whether [local] is morning, when a session opens with a gm.
bool isMorning(DateTime local) =>
    local.hour >= _morningStarts && local.hour < _morningEnds;

/// Whether [mood] is an ambient state that runs until it is replaced, as
/// opposed to a reaction that plays once and is over.
///
/// Load-bearing beyond style: a looping animation never lets a widget test
/// settle, so the looping moods are the ones the mascot gates behind the
/// viewer's reduce-motion setting.
bool isLoopingMood(MostroMood mood) =>
    mood == MostroMood.asleep ||
    mood == MostroMood.impatient ||
    mood == MostroMood.offline;
