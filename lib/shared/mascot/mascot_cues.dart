import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/daemon_errors.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/shared/mascot/mostro_mood.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart'
    show OrderStatus, TradeUpdate, TradeUpdateReason;

/// Something that happened, for the header mascot to react to.
class MascotCue {
  const MascotCue(this.mood, this.at);

  final MostroMood mood;

  /// When it happened: what decides whether it is still news when the
  /// mascot comes into view ([isFreshEvent]).
  final DateTime at;
}

/// Updates whose status is not a step.
const Set<TradeUpdateReason> _notASteps = {
  // A cooperative cancel request leaves the status as it was, and Rust emits
  // it with that status. The counterparty's is news all the same, by its
  // reason ([MostroMood.cancelAsked]).
  TradeUpdateReason.cooperativeCancelRequestedByMe,
  // A restore or a re-read, dated now: old news that only the reason gives
  // away.
  TradeUpdateReason.replayed,
};

/// The mood a trade step earns, or null when the step is not one Mostro
/// reacts to.
///
/// Read from `TradeUpdate` alone, which carries what the daemon said. Never
/// from the order book: its Kind 38383 `s` tag is not a trade's status
/// (#203).
MostroMood? moodForTradeUpdate(TradeUpdate update) {
  if (_notASteps.contains(update.reason)) return null;
  if (update.reason == TradeUpdateReason.cooperativeCancelRequestedByPeer) {
    return MostroMood.cancelAsked;
  }
  return switch (update.status) {
    OrderStatus.active => MostroMood.escrowLocked,
    OrderStatus.fiatSent => MostroMood.fiatSent,
    OrderStatus.dispute => MostroMood.disputed,
    OrderStatus.success ||
    OrderStatus.settledByAdmin ||
    OrderStatus.completedByAdmin => MostroMood.celebrating,
    OrderStatus.canceled ||
    OrderStatus.cooperativelyCanceled ||
    OrderStatus.canceledByAdmin ||
    OrderStatus.expired => MostroMood.canceled,
    _ => null,
  };
}

/// The next thing the header mascot should react to, held until a mascot is
/// on screen to show it (#770 part 3).
///
/// Every tab is its own route, and most of what Mostro reacts to happens
/// while one is not showing: a trade steps forward while its screen is open,
/// an order is published from the form. So a cue waits here, one at a time,
/// and the mascot takes it as it comes into view, if it is still news.
///
/// Kept alive for the trade stream it listens to, which a tab coming and
/// going would otherwise drop. Identity-scoped: `resetIdentityScopedState`
/// invalidates it, so the next user does not see the last one's trade.
class MascotCueNotifier extends Notifier<MascotCue?> {
  /// When each trade completed this session, by order: the third of a day
  /// sets Mostro on fire. A trade told twice is counted once.
  final Map<String, DateTime> _completed = {};

  /// The trades whose cooperative cancel this side asked for, until the
  /// counterparty agrees.
  final Set<String> _cancelAsked = {};

  /// Built when the first header mascot of the session mounts, which makes
  /// it the session's first look: in the morning, that waits as a gm. A new
  /// identity builds it again, and is greeted as a new session.
  @override
  MascotCue? build() {
    _completed.clear();
    _cancelAsked.clear();
    ref.listen(tradeUpdatesProvider, (_, next) {
      final update = next.valueOrNull;
      if (update != null) _onTradeUpdate(update);
    });
    // Not the backed-up flag: a seed import sets it too, and so does
    // loading it at startup. Only a verification is news.
    final verified = ref
        .watch(backupReminderProvider.notifier)
        .verifications
        .listen((_) => cue(MostroMood.backedUp));
    ref.onDispose(verified.cancel);
    final now = clock.now();
    return isMorning(now) ? MascotCue(MostroMood.greeting, now) : null;
  }

  void _onTradeUpdate(TradeUpdate update) {
    final at = DateTime.fromMillisecondsSinceEpoch(
      platformInt64ToInt(update.occurredAt) * 1000,
    );
    final orderId = update.orderId;
    // Who asked is not a cue: a confirmation that lands late (an offline
    // spell) still decides how the agreement looks.
    if (update.reason == TradeUpdateReason.cooperativeCancelRequestedByMe) {
      _cancelAsked.add(orderId);
    }
    // A restore replays trades that moved long ago (#474): that is not
    // news, and a pending cue of the present must not give way to it.
    if (!isFreshEvent(occurredAt: at, now: clock.now())) return;
    var mood = moodForTradeUpdate(update);
    if (mood == MostroMood.celebrating) {
      // A completion told twice (the buyer's message, then the book's
      // revision) was celebrated once already.
      if (_completed.containsKey(orderId)) return;
      _completed[orderId] = at;
      mood = moodForCompletion(_completedOnTheDayOf(at));
    } else if (mood == MostroMood.canceled &&
        update.status == OrderStatus.cooperativelyCanceled &&
        _cancelAsked.remove(orderId)) {
      mood = MostroMood.agreed;
    }
    if (mood != null) cue(mood, at: at);
  }

  /// The trades completed on the local day of [at].
  int _completedOnTheDayOf(DateTime at) {
    bool sameDay(DateTime d) =>
        d.year == at.year && d.month == at.month && d.day == at.day;
    return _completed.values.where(sameDay).length;
  }

  /// Queues [mood], which happened [at] (now when omitted). It replaces the
  /// cue already waiting unless that one is stronger and still news
  /// ([pickMood]).
  void cue(MostroMood mood, {DateTime? at}) {
    final waiting = _fresh();
    if (waiting != null && pickMood([waiting.mood, mood]) != mood) return;
    state = MascotCue(mood, at ?? clock.now());
  }

  /// The node confirmed a new order.
  void orderPublished() => cue(MostroMood.published);

  /// The node confirmed a take.
  void orderTaken() => cue(MostroMood.orderTaken);

  /// The node accepted the buyer's invoice.
  void invoiceAccepted() => cue(MostroMood.invoiceAccepted);

  /// The user rated the counterparty [score] stars.
  void rated(int score) => cue(moodForRating(score));

  /// An action failed with [error]; only the node saying no is a cue.
  void daemonRefused(Object error) {
    if (isDaemonRefusal(error)) cue(MostroMood.refused);
  }

  /// The waiting cue's mood, handed over once, or null when there is none
  /// or it is no longer news.
  MostroMood? take() {
    final waiting = _fresh();
    if (state != null) state = null;
    return waiting?.mood;
  }

  MascotCue? _fresh() {
    final waiting = state;
    if (waiting == null) return null;
    return isFreshEvent(occurredAt: waiting.at, now: clock.now())
        ? waiting
        : null;
  }
}

final mascotCueProvider = NotifierProvider<MascotCueNotifier, MascotCue?>(
  MascotCueNotifier.new,
);
