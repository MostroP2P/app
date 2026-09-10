import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/providers/log_provider.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../support/provider_harness.dart';

/// Tests for the seed-then-follow merge in [logEntriesProvider]: the Rust ring
/// buffer and the live stream overlap by design, and the ordering between the
/// two calls is what keeps that overlap from turning into a lost or duplicated
/// entry.
void main() {
  LogEntry entry(int id) => LogEntry(
        id: id,
        level: LogLevel.info,
        tag: 'probe',
        message: 'entry $id',
        timestamp: intToPlatformInt64(0),
      );

  /// Records the call order of both seams and hands out [live] one entry per
  /// pull, then parks — a live stream with nothing more to deliver yet.
  ({List<String> calls, List<Override> overrides}) seams({
    required List<LogEntry> history,
    List<LogEntry> live = const [],
  }) {
    final calls = <String>[];
    final pending = [...live];
    return (
      calls: calls,
      overrides: [
        logHistoryProvider.overrideWithValue(() async {
          calls.add('history');
          return history;
        }),
        logStreamProvider.overrideWithValue(() async {
          calls.add('stream');
          Future<LogEntry?> next() async {
            if (pending.isEmpty) return Completer<LogEntry?>().future;
            return pending.removeAt(0);
          }

          return next;
        }),
      ],
    );
  }

  /// Resolves with the first emitted value satisfying [matches].
  Future<List<LogEntry>> valueWhere(
    ProviderContainer container,
    bool Function(List<LogEntry>) matches,
  ) {
    final completer = Completer<List<LogEntry>>();
    final sub = container.listen<AsyncValue<List<LogEntry>>>(
      logEntriesProvider,
      (_, next) {
        final value = next.value;
        if (value != null && matches(value) && !completer.isCompleted) {
          completer.complete(value);
        }
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);
    return completer.future.timeout(const Duration(seconds: 2));
  }

  test('subscribes to the live stream before snapshotting the history', () async {
    final s = seams(history: [entry(1)]);
    final container = createContainer(overrides: s.overrides);

    await valueWhere(container, (v) => v.isNotEmpty);

    expect(s.calls, ['stream', 'history']);
  });

  test('drops streamed entries the seed already holds', () async {
    final s = seams(
      history: [entry(3), entry(2), entry(1)],
      live: [entry(2), entry(3), entry(4)],
    );
    final container = createContainer(overrides: s.overrides);

    final entries = await valueWhere(container, (v) => v.length == 4);

    expect(entries.map((e) => e.id), [4, 3, 2, 1]);
  });

  test('caps the list and evicts the oldest entry', () async {
    const newest = logEntriesLimit + 100;
    final history = [
      for (var id = newest; id >= 1; id--) entry(id),
    ];
    final s = seams(history: history, live: [entry(newest + 1)]);
    final container = createContainer(overrides: s.overrides);

    final seeded = await valueWhere(container, (v) => v.first.id == newest);
    expect(seeded, hasLength(logEntriesLimit));
    expect(seeded.last.id, newest - logEntriesLimit + 1);

    final entries = await valueWhere(container, (v) => v.first.id == newest + 1);
    expect(entries, hasLength(logEntriesLimit));
    expect(entries.last.id, newest - logEntriesLimit + 2);
  });
}
