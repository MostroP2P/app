import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/notifications/services/push_background_handler.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;
import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/types.dart';

/// One hydration hook: re-read a feature's protocol state from the bridge.
///
/// **Streams are for live updates; queries are for hydration. Resume always
/// re-hydrates.** A notifier fed only by incremental events silently loses
/// everything that happened while the process was suspended, and a
/// hand-maintained list of per-feature refresh calls is exactly what let v1
/// ship the dispute-chat bug (MostroP2P/mobile#675). So a feature exposes the
/// same code path it uses at cold start, and resume runs all of them.
typedef Hydrator = Future<void> Function(ProviderContainer container);

/// The resume routine: `resync()` in Rust, then every hydrator, in order —
/// twice.
///
/// `resync()` returns once the subscriptions are re-issued, not once the
/// relays have replayed what was missed: the events the app was suspended
/// for arrive over the next seconds and are written to the database as they
/// land. So the hydrators run **immediately** (what is on disk is already
/// newer than what the notifiers hold) and **once more when the replay
/// settles**: after [settleQuiet] without a trade update following the last
/// one, or after [settleMax] whatever is still arriving. A trade update
/// already refreshes the trade list on its own; the second pass is for the
/// notifiers derived from it — chat rooms, disputes — which nothing else
/// re-reads.
///
/// Pure enough to test with fakes: the bridge call, the hook list and the
/// update stream are injected. Each step is isolated — a hydrator that throws
/// is logged and the next one still runs, and a failed resync still hydrates.
class ResumeResync {
  ResumeResync({
    required this.container,
    Future<ResyncOutcome> Function()? resync,
    List<Hydrator>? hydrators,
    Stream<Object?> Function()? updates,
    Future<bool> Function()? consumeWake,
    this.settleQuiet = const Duration(milliseconds: 1500),
    this.settleMax = const Duration(seconds: 10),
  }) : _resync = resync ?? nostr_api.resync,
       _hydrators = hydrators ?? defaultHydrators,
       _updates = updates ?? _bridgeTradeUpdates,
       _consumeWake = consumeWake ?? consumeWakePending;

  final ProviderContainer container;
  final Future<ResyncOutcome> Function() _resync;
  final List<Hydrator> _hydrators;
  final Stream<Object?> Function() _updates;
  final Future<bool> Function() _consumeWake;

  /// Replay is considered settled this long after its last trade update.
  final Duration settleQuiet;

  /// The second pass runs at the latest this long after the first, so a
  /// stream that never goes quiet (or never emits) still gets one.
  final Duration settleMax;

  /// Runs the routine to completion: resync, hydrate, wait for the replay to
  /// settle, hydrate again. Awaiting it is optional; the lifecycle service
  /// does not.
  Future<void> run() async {
    // Diagnostic only: the resync runs on every resume regardless. The flag
    // says whether a push rang while the app was away, which is the one
    // fact the display-only handler is allowed to leave behind.
    try {
      if (await _consumeWake()) debugPrint('[lifecycle] a push woke the app');
    } catch (e) {
      debugPrint('[lifecycle] wake flag unavailable: $e');
    }
    try {
      final outcome = await _resync();
      debugPrint(
        '[lifecycle] resync: online=${outcome.online} '
        'flushed=${outcome.flushed} coalesced=${outcome.coalesced}',
      );
    } catch (e) {
      debugPrint('[lifecycle] resync failed: $e');
    }
    await _hydrateAll();
    await _waitForReplayToSettle();
    await _hydrateAll();
  }

  Future<void> _hydrateAll() async {
    for (final hydrate in _hydrators) {
      try {
        await hydrate(container);
      } catch (e, st) {
        debugPrint('[lifecycle] hydration failed: $e\n$st');
      }
    }
  }

  /// Completes [settleQuiet] after the last update, or at [settleMax].
  Future<void> _waitForReplayToSettle() async {
    final settled = Completer<void>();
    void done() {
      if (!settled.isCompleted) settled.complete();
    }

    Timer quiet = Timer(settleQuiet, done);
    final cap = Timer(settleMax, done);
    StreamSubscription<Object?>? sub;
    try {
      sub = _updates().listen(
        (_) {
          quiet.cancel();
          quiet = Timer(settleQuiet, done);
        },
        onError: (Object e) {
          debugPrint('[lifecycle] trade update stream failed: $e');
          done();
        },
        onDone: done,
      );
    } catch (e) {
      debugPrint('[lifecycle] trade update stream unavailable: $e');
      done();
    }
    await settled.future;
    quiet.cancel();
    cap.cancel();
    await sub?.cancel();
  }
}

/// The bridge's trade updates, as a stream, for the settle window.
Stream<TradeUpdate> _bridgeTradeUpdates() async* {
  final stream = await orders_api.onTradeUpdated();
  while (true) {
    final update = await stream.next();
    if (update == null) break;
    yield update;
  }
}

/// Every notifier that holds protocol-derived state, in dependency order:
/// trades first, since chat rooms and disputes are read off the trade list.
final List<Hydrator> defaultHydrators = [
  hydrateTrades,
  hydrateChatRooms,
  hydrateDisputes,
  hydrateNotifications,
];
