/// Relay provider — Phase 3 T036.
///
/// Polls the Rust relay pool every 5 seconds for connection status.
/// The nostr pool itself is initialised by the identity provider after
/// identity creation/import (or by main.dart on a warm start).
library relay_provider;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../src/rust/api/nostr.dart' as rust_nostr;
import '../src/rust/api/types.dart';

// Re-export types used by screens.
export '../src/rust/api/types.dart'
    show ConnectionState, RelayInfo, RelayStatus;

class RelayNotifier extends AsyncNotifier<List<RelayInfo>> {
  Timer? _timer;
  bool _polling = false;

  @override
  Future<List<RelayInfo>> build() async {
    ref.onDispose(() => _timer?.cancel());

    final infos = await rust_nostr.getRelayInfos();

    _timer = Timer.periodic(const Duration(seconds: 5), (_) async {
      // Guard against overlapping invocations if getRelayInfos takes > 5 s.
      if (_polling) return;
      _polling = true;
      try {
        final updated = await rust_nostr.getRelayInfos();
        state = AsyncValue.data(updated);
      } catch (_) {
        // Silently swallow — pool may not be ready yet.
      } finally {
        _polling = false;
      }
    });

    return infos;
  }
}

final relayProvider =
    AsyncNotifierProvider<RelayNotifier, List<RelayInfo>>(RelayNotifier.new);

/// Derived connection state from relay list statuses.
final connectionStateProvider = Provider<ConnectionState>((ref) {
  final relays = ref.watch(relayProvider).valueOrNull ?? [];
  if (relays.any((r) => r.status == RelayStatus.connected)) {
    return ConnectionState.online;
  }
  if (relays.any((r) => r.status == RelayStatus.connecting)) {
    return ConnectionState.reconnecting;
  }
  return ConnectionState.offline;
});
