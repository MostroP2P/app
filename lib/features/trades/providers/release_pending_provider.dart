import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a release published from this device stands, per order.
///
/// `release_order` only publishes: the daemon answers much later, once it has
/// settled the hold invoice (`HoldInvoicePaymentSettled`), which can take tens
/// of seconds. Until then the trade stays at `fiatSent` and the screen used to
/// offer Release again — a seller who pressed it twice more got two
/// `NotAllowedByStatus` refusals, and the confirmation of the first press
/// arriving right after the third looked like the third one worked.
enum ReleaseWait {
  /// Published; the order has not moved yet. Release is not offered.
  waiting,

  /// [kReleaseConfirmationTimeout] passed with no move: Release is offered
  /// again. Safe — a daemon that already released refuses the retry.
  unconfirmed,
}

/// How long a published release waits for the order to move before Release
/// is offered again.
const kReleaseConfirmationTimeout = Duration(seconds: 90);

class ReleasePendingNotifier extends Notifier<Map<String, ReleaseWait>> {
  final _timers = <String, Timer>{};
  int _generation = 0;

  /// Bumped by every rebuild — an identity reset invalidates this provider,
  /// and Riverpod re-runs [build] on the same instance. A caller that spans
  /// an await captures it first and hands it to [start], so a release the
  /// previous identity published is not recorded into the next one's state.
  int get generation => _generation;

  @override
  Map<String, ReleaseWait> build() {
    _generation++;
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    return const {};
  }

  /// A release of [orderId] was published. With [since], only if no rebuild
  /// (identity reset) happened after that [generation] was read.
  void start(String orderId, {int? since}) {
    if (since != null && since != _generation) return;
    _timers.remove(orderId)?.cancel();
    _timers[orderId] = Timer(kReleaseConfirmationTimeout, () {
      _timers.remove(orderId);
      if (state[orderId] == ReleaseWait.waiting) {
        state = {...state, orderId: ReleaseWait.unconfirmed};
      }
    });
    state = {...state, orderId: ReleaseWait.waiting};
  }

  /// The order moved: whatever the release was waiting for is over.
  void settle(String orderId) {
    _timers.remove(orderId)?.cancel();
    if (!state.containsKey(orderId)) return;
    state = Map.fromEntries(state.entries.where((e) => e.key != orderId));
  }
}

/// Identity-scoped: `resetIdentityScopedState` invalidates it.
final releasePendingProvider =
    NotifierProvider<ReleasePendingNotifier, Map<String, ReleaseWait>>(
      ReleasePendingNotifier.new,
    );
