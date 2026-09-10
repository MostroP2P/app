import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/nostr.dart' as nostr_api;

/// Relay URLs the Rust core auto-added from the active Mostro node's kind
/// 10002 list, one emission per applied event.
///
/// **One subscription for the whole process, deliberately.** The Rust
/// broadcast sender is process-global and never closes, so a pending
/// `stream.next()` cannot be cancelled from Dart: a per-widget subscription
/// would strand one blocked bridge task and one receiver on every visit to
/// Settings. Keeping this provider alive means exactly one of each, ever.
///
/// The first emission is an **empty list**, sent as soon as the receiver
/// exists rather than when a relay is discovered. That is what lets a
/// listener take its relay snapshot with the receiver already installed, so
/// a list applied in between arrives as an emission instead of being lost.
final relayAutoSyncProvider = StreamProvider<List<String>>((ref) async* {
  final stream = await nostr_api.onRelayAutoSynced();
  yield const <String>[];
  while (true) {
    final added = await stream.next();
    if (added == null) break;
    yield added;
  }
});
