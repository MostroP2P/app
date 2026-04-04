import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/logging.dart' as logging_api;
import 'package:mostro/src/rust/api/types.dart';

/// Live log entries from the Rust backend, newest first.
///
/// Caps at 500 entries to bound memory usage.  The stream is cancelled
/// when the provider is disposed (e.g. when LogReportScreen is popped).
final logEntriesProvider = StreamProvider.autoDispose<List<LogEntry>>((ref) async* {
  var cancelled = false;
  ref.onDispose(() => cancelled = true);

  final stream = await logging_api.onLogEntry();
  final entries = <LogEntry>[];
  while (!cancelled) {
    final entry = await stream.next();
    if (entry == null || cancelled) break;
    entries.insert(0, entry); // newest first
    if (entries.length > 500) entries.removeLast();
    yield List.unmodifiable(entries);
  }
});
