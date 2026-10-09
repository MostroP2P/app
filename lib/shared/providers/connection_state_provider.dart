import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;
import 'package:mostro/src/rust/api/types.dart' show ConnectionState;

/// Whether the relay pool can reach a relay: its state now, then every
/// change Rust reports.
///
/// Subscribes before reading, so a change between the two is not lost. Before
/// the pool exists both calls throw, and the provider stays in error: read
/// that as "unknown", never as offline.
///
/// One stream for the app's life, not one per mascot: the header remounts on
/// every tab change, and a Rust stream given up mid-`next()` stays parked
/// until the state next changes. Device state, not identity state.
final connectionStateProvider = StreamProvider<ConnectionState>((ref) async* {
  final changes = await nostr_api.onConnectionStateChanged();
  yield await nostr_api.getConnectionState();
  while (true) {
    final state = await changes.next();
    if (state == null) break;
    yield state;
  }
});

/// Whether [state] means no relay is connected. `reconnecting` counts: it is
/// what an outage looks like while the pool keeps trying.
bool isDisconnected(ConnectionState state) => state != ConnectionState.online;
