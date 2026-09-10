import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/logging.dart' as logging_api;
import 'package:mostro/src/rust/api/types.dart';

/// Entries held in the provider. Matches `BUFFER_CAPACITY` in
/// `rust/src/api/logging.rs`, so the screen shows and shares every entry Rust
/// still holds.
const logEntriesLimit = 1000;

/// Pulls the next live entry, or null once the stream closes.
typedef LogEntryReader = Future<LogEntry?> Function();

/// The two bridge calls behind function seams, so the merge below can be
/// driven in tests without a live bridge.
final logHistoryProvider =
    Provider<Future<List<LogEntry>> Function()>((ref) => logging_api.recentLogs);

final logStreamProvider = Provider<Future<LogEntryReader> Function()>(
  (ref) => () async => (await logging_api.onLogEntry()).next,
);

/// Log entries from the Rust backend, newest first.
///
/// Seeded from the Rust ring buffer so the screen opens on the history that led
/// to whatever the user is reporting, then followed live. Cancelled when the
/// provider is disposed (e.g. when LogReportScreen is popped).
final logEntriesProvider =
    StreamProvider.autoDispose<List<LogEntry>>((ref) async* {
  var cancelled = false;
  ref.onDispose(() => cancelled = true);

  // Subscribe before snapshotting: an entry emitted between the two calls
  // arrives on the stream and is dropped below, whereas the reverse order
  // would lose it entirely.
  final nextEntry = await ref.read(logStreamProvider)();
  final entries =
      (await ref.read(logHistoryProvider)()).take(logEntriesLimit).toList();
  final seededUpTo = entries.isEmpty ? -1 : entries.first.id;
  yield List.unmodifiable(entries);

  while (!cancelled) {
    final entry = await nextEntry();
    if (entry == null || cancelled) break;
    if (entry.id <= seededUpTo) continue; // already in the seed
    entries.insert(0, entry);
    if (entries.length > logEntriesLimit) entries.removeLast();
    yield List.unmodifiable(entries);
  }
});
