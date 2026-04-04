import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/logging.dart' as logging_api;
import 'package:mostro/src/rust/api/types.dart';

/// Live log entries from the Rust backend, newest first.
///
/// Caps at 500 entries to bound memory usage.
final logEntriesProvider = StreamProvider.autoDispose<List<LogEntry>>((ref) async* {
  final stream = await logging_api.onLogEntry();
  final entries = <LogEntry>[];
  while (true) {
    final entry = await stream.next();
    if (entry == null) break;
    entries.insert(0, entry); // newest first
    if (entries.length > 500) entries.removeLast();
    yield List.unmodifiable(entries);
  }
});
