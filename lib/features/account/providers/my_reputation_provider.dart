import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/account/providers/privacy_mode_provider.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/src/rust/api/my_reputation.dart' as my_reputation_api;
import 'package:mostro/src/rust/api/my_reputation.dart' show MyReputation;

/// What the Account screen knows of the user's own reputation on the active
/// node (issue #755).
@immutable
class MyReputationState {
  const MyReputationState({this.reputation, this.loading = false});

  /// The active node's last answer, `null` until it first answers.
  final MyReputation? reputation;

  /// A request to the node is in flight.
  final bool loading;
}

/// The core calls behind [MyReputationNotifier], a seam for tests.
class MyReputationCore {
  const MyReputationCore({
    required this.readCache,
    required this.refresh,
    required this.changes,
  });

  /// The Rust core: the cache is per identity and node, the refresh sends
  /// `user-info`, and every stored answer comes back on [changes].
  factory MyReputationCore.bridge() => const MyReputationCore(
    readCache: my_reputation_api.cachedMyReputation,
    refresh: my_reputation_api.refreshMyReputation,
    changes: _bridgeChanges,
  );

  final Future<MyReputation?> Function() readCache;
  final Future<MyReputation?> Function() refresh;

  /// Opens a new stream of stored answers. Each notifier opens its own: an
  /// identity swap rebuilds the notifier, and the bridge's stream takes a
  /// single listener.
  final Stream<MyReputation> Function() changes;

  static Stream<MyReputation> _bridgeChanges() async* {
    final stream = await my_reputation_api.onMyReputationChanged();
    while (true) {
      yield await stream.next();
    }
  }
}

final myReputationCoreProvider = Provider<MyReputationCore>(
  (ref) => MyReputationCore.bridge(),
);

/// The user's own reputation on the active node.
///
/// Rust asks the node at startup, on a node switch and once the user rates a
/// counterpart; this follows the answers it stores and asks again when the
/// Account screen opens or the user leaves full privacy mode.
final myReputationProvider =
    StateNotifierProvider<MyReputationNotifier, MyReputationState>((ref) {
      final core = ref.watch(myReputationCoreProvider);
      final notifier = MyReputationNotifier(
        readCache: core.readCache,
        refresh: core.refresh,
        changes: core.changes,
      );
      // The cache is per node: show the new node's answer, if any, while
      // Rust asks it.
      ref.listen(mostroPubkeyProvider, (_, __) => notifier.switchNode());
      ref.listen(privacyModeProvider, (previous, next) {
        if (previous == true && !next) unawaited(notifier.refresh());
      });
      return notifier;
    });

class MyReputationNotifier extends StateNotifier<MyReputationState> {
  MyReputationNotifier({
    required Future<MyReputation?> Function() readCache,
    required Future<MyReputation?> Function() refresh,
    required Stream<MyReputation> Function() changes,
  }) : _readCache = readCache,
       _refresh = refresh,
       super(const MyReputationState()) {
    // Any stored answer, for any node: re-read the active node's.
    _changes = changes().listen(
      (_) => unawaited(reload()),
      onError: (Object e) => debugPrint('[my_reputation] changes: $e'),
    );
    unawaited(reload());
  }

  final Future<MyReputation?> Function() _readCache;
  final Future<MyReputation?> Function() _refresh;
  late final StreamSubscription<MyReputation> _changes;

  /// Orders overlapping [reload]s: only the latest one is shown.
  int _reads = 0;

  /// Show the active node's cached answer — the single source of what is
  /// shown, keyed by identity and node in Rust.
  Future<void> reload() async {
    final read = ++_reads;
    try {
      final cached = await _readCache();
      if (mounted && read == _reads) {
        state = MyReputationState(reputation: cached, loading: state.loading);
      }
    } catch (e) {
      debugPrint('[my_reputation] cache read failed: $e');
    }
  }

  /// The active node changed: drop the previous node's answer at once, so it
  /// never sits beside the new node's name, then show the new one's cache.
  Future<void> switchNode() {
    state = MyReputationState(loading: state.loading);
    return reload();
  }

  /// Ask the active node, then show what the cache holds for it. The answer
  /// itself is not shown: the user may have switched node meanwhile. No
  /// answer leaves the cached one on screen.
  Future<void> refresh() async {
    if (state.loading) return;
    state = MyReputationState(reputation: state.reputation, loading: true);
    try {
      await _refresh();
    } catch (e) {
      debugPrint('[my_reputation] refresh failed: $e');
    }
    if (!mounted) return;
    state = MyReputationState(reputation: state.reputation);
    await reload();
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    super.dispose();
  }
}
