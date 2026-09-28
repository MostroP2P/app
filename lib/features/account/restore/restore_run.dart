import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:mostro/src/rust/api/orders.dart' as orders_api;
import 'package:mostro/src/rust/api/restore_progress.dart' as progress_api;
import 'package:mostro/src/rust/api/types.dart';

/// Where one of the restore's three stages stands (design 20a–20d).
enum RestoreStage { pending, active, done, failed }

/// How the restore ended, or that it has not yet.
enum RestoreOutcome { running, restored, failed }

/// Where the bar stands once the node took the request (20a).
const double kRestoreConnectedProgress = 0.34;

/// How much of the bar the details fill, on top of [kRestoreConnectedProgress].
const double kRestoreLoadingSpan = 0.44;

/// What the restore sheet shows: the three stages, the bar and the outcome.
@immutable
class RestoreRunState {
  const RestoreRunState({
    this.connected = false,
    this.found,
    this.toLoad,
    this.loaded = 0,
    this.outcome = RestoreOutcome.running,
    this.progress = 0,
  });

  /// The request reached a relay.
  final bool connected;

  /// Every order and dispute the node returned; null until it answers.
  final int? found;

  /// How many of them get their details loaded; null until the node answers.
  final int? toLoad;

  /// How many of [toLoad] have their details.
  final int loaded;

  final RestoreOutcome outcome;

  /// The bar, 0–1. Never moves back within a run.
  final double progress;

  /// Orders whose details never came, on a restore that answered: a partial
  /// restore when above zero.
  int get unloaded =>
      outcome == RestoreOutcome.restored ? (toLoad ?? 0) - loaded : 0;

  /// Connect, request, load — in that order.
  List<RestoreStage> get stages {
    if (outcome == RestoreOutcome.restored) {
      return const [RestoreStage.done, RestoreStage.done, RestoreStage.done];
    }
    final reached = [connected, found != null, _allLoaded];
    final running = reached.indexOf(false);
    return [
      for (var i = 0; i < reached.length; i++)
        if (reached[i])
          RestoreStage.done
        else if (i == running)
          outcome == RestoreOutcome.failed
              ? RestoreStage.failed
              : RestoreStage.active
        else
          RestoreStage.pending,
    ];
  }

  bool get _allLoaded => toLoad != null && loaded >= toLoad!;

  RestoreRunState copyWith({
    bool? connected,
    int? found,
    int? toLoad,
    int? loaded,
    RestoreOutcome? outcome,
    double? progress,
  }) => RestoreRunState(
    connected: connected ?? this.connected,
    found: found ?? this.found,
    toLoad: toLoad ?? this.toLoad,
    loaded: loaded ?? this.loaded,
    outcome: outcome ?? this.outcome,
    progress: progress ?? this.progress,
  );
}

/// One account restore, as the sheet follows it: the core's
/// `recover_trades`, with the steps it pushes on `on_restore_progress`.
///
/// The steps only move the stages and the bar; the outcome is the recovery's
/// own result. [start] again is a retry: it starts over from nothing.
class RestoreRun extends ChangeNotifier {
  RestoreRun({required this.progress, required this.recover});

  /// A run against the Rust core: `recover_trades`, followed on
  /// `on_restore_progress`.
  factory RestoreRun.core() => RestoreRun(
    progress: () async => _follow(await progress_api.onRestoreProgress()),
    recover: orders_api.recoverTrades,
  );

  static Stream<RestoreProgress> _follow(
    progress_api.RestoreProgressStream stream,
  ) async* {
    while (true) {
      final step = await stream.next();
      if (step == null) break;
      yield step;
    }
  }

  /// The core's step stream, subscribed before [recover] is called so the
  /// first steps are not missed.
  final Future<Stream<RestoreProgress>> Function() progress;

  /// The recovery itself; resolves with how many orders and disputes came
  /// back, throws when the node did not answer.
  final Future<int> Function() recover;

  RestoreRunState _state = const RestoreRunState();
  RestoreRunState get state => _state;

  StreamSubscription<RestoreProgress>? _steps;

  /// Which run the callbacks in flight belong to: a retry or a dispose makes
  /// the older ones stale.
  int _generation = 0;
  bool _disposed = false;

  Future<void> start() async {
    final generation = ++_generation;
    await _steps?.cancel();
    _set(const RestoreRunState());
    final Stream<RestoreProgress> stream;
    try {
      stream = await progress();
    } catch (e) {
      debugPrint('[restore] progress stream unavailable: $e');
      return _finish(generation, failed: true);
    }
    if (generation != _generation) return;
    _steps = stream.listen((step) {
      if (generation == _generation) _apply(step);
    });
    try {
      await recover();
      _finish(generation, failed: false);
    } catch (e) {
      debugPrint('[restore] recovery failed: $e');
      _finish(generation, failed: true);
    }
  }

  void _apply(RestoreProgress step) {
    final next = switch (step) {
      RestoreProgress_Connected() => _state.copyWith(connected: true),
      RestoreProgress_Found(:final found, :final toLoad) => _state.copyWith(
        connected: true,
        found: found,
        toLoad: toLoad,
      ),
      RestoreProgress_Loaded(:final done, :final toLoad) => _state.copyWith(
        connected: true,
        loaded: done,
        toLoad: toLoad,
      ),
    };
    _set(next.copyWith(progress: _atLeast(_barFor(next))));
  }

  void _finish(int generation, {required bool failed}) {
    if (generation != _generation) return;
    _steps?.cancel();
    _steps = null;
    _set(
      failed
          ? _state.copyWith(outcome: RestoreOutcome.failed)
          : _state.copyWith(outcome: RestoreOutcome.restored, progress: 1),
    );
  }

  static double _barFor(RestoreRunState s) {
    if (!s.connected) return 0;
    final toLoad = s.toLoad;
    if (toLoad == null) return kRestoreConnectedProgress;
    final share = toLoad == 0 ? 1.0 : (s.loaded / toLoad).clamp(0.0, 1.0);
    return kRestoreConnectedProgress + kRestoreLoadingSpan * share;
  }

  double _atLeast(double value) =>
      value > _state.progress ? value : _state.progress;

  void _set(RestoreRunState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _steps?.cancel();
    super.dispose();
  }
}
