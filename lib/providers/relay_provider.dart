/// Relay provider stub.
///
/// Phase 3 T036 replaces this with a real implementation backed by
/// rust/src/api/nostr.rs relay methods.
library relay_provider;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Relay connection state.
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

/// Placeholder relay info.
class RelayInfo {
  const RelayInfo({required this.url, required this.state});

  final String url;
  final ConnectionState state;
}

class RelayNotifier extends AsyncNotifier<List<RelayInfo>> {
  @override
  Future<List<RelayInfo>> build() async {
    // Phase 3: connect to default relays and stream status updates.
    return [];
  }
}

final relayProvider =
    AsyncNotifierProvider<RelayNotifier, List<RelayInfo>>(
  RelayNotifier.new,
);

/// Convenience provider returning overall connection state.
final connectionStateProvider = Provider<ConnectionState>((ref) {
  final relays = ref.watch(relayProvider).valueOrNull ?? [];
  if (relays.any((r) => r.state == ConnectionState.connected)) {
    return ConnectionState.connected;
  }
  if (relays.any((r) => r.state == ConnectionState.connecting)) {
    return ConnectionState.connecting;
  }
  if (relays.any((r) => r.state == ConnectionState.error)) {
    return ConnectionState.error;
  }
  return ConnectionState.disconnected;
});
