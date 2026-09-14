import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/lifecycle/resume_resync.dart';
import 'package:mostro/src/rust/api/types.dart';

void main() {
  const ok = ResyncOutcome(online: true, flushed: 0, coalesced: false);

  late ProviderContainer container;
  late List<String> calls;

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    calls = [];
  });

  Hydrator hook(String name, {bool throws = false}) => (c) async {
    expect(identical(c, container), isTrue);
    calls.add(name);
    if (throws) throw StateError('$name failed');
  };

  /// No replay to wait for: the settle window closes at once.
  Stream<Object?> noUpdates() => const Stream.empty();

  test('resync runs first, then every hydrator in order, twice', () async {
    // Arrange
    final routine = ResumeResync(
      container: container,
      resync: () async {
        calls.add('resync');
        return ok;
      },
      hydrators: [hook('trades'), hook('chat'), hook('disputes')],
      updates: noUpdates,
    );

    // Act
    await routine.run();

    // Assert — once for what is on disk, once more when the replay settled.
    expect(calls, [
      'resync',
      'trades',
      'chat',
      'disputes',
      'trades',
      'chat',
      'disputes',
    ]);
  });

  test('a hydrator that throws does not stop the ones after it', () async {
    final routine = ResumeResync(
      container: container,
      resync: () async => ok,
      hydrators: [hook('trades'), hook('chat', throws: true), hook('disputes')],
      updates: noUpdates,
    );

    await routine.run();

    expect(calls.take(3), ['trades', 'chat', 'disputes']);
  });

  test('a failed resync still hydrates — disk is newer than memory', () async {
    final routine = ResumeResync(
      container: container,
      resync: () async => throw StateError('no bridge'),
      hydrators: [hook('trades')],
      updates: noUpdates,
    );

    await expectLater(routine.run(), completes);

    expect(calls, ['trades', 'trades']);
  });

  group('the second pass waits for the replay to settle', () {
    const quiet = Duration(milliseconds: 40);
    const max = Duration(milliseconds: 300);

    test('it runs after a quiet window following the last update', () async {
      final updates = StreamController<Object?>();
      addTearDown(updates.close);
      final passes = <DateTime>[];
      final routine = ResumeResync(
        container: container,
        resync: () async => ok,
        hydrators: [(c) async => passes.add(DateTime.now())],
        updates: () => updates.stream,
        settleQuiet: quiet,
        settleMax: max,
      );

      final run = routine.run();
      // Replay: three updates 15 ms apart keep the window open.
      for (var i = 0; i < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 15));
        updates.add(i);
      }
      final lastUpdate = DateTime.now();
      await run;

      expect(passes, hasLength(2));
      expect(
        passes[1].difference(lastUpdate),
        greaterThanOrEqualTo(quiet - const Duration(milliseconds: 5)),
        reason: 'the second pass came only once the replay went quiet',
      );
    });

    test(
      'a replay that never goes quiet still gets its pass at the cap',
      () async {
        final updates = StreamController<Object?>();
        addTearDown(updates.close);
        final routine = ResumeResync(
          container: container,
          resync: () async => ok,
          hydrators: [hook('h')],
          updates: () => updates.stream,
          settleQuiet: quiet,
          settleMax: max,
        );
        final chatter = Timer.periodic(
          const Duration(milliseconds: 10),
          (_) => updates.add(null),
        );
        addTearDown(chatter.cancel);

        final started = DateTime.now();
        await routine.run();

        expect(calls, ['h', 'h']);
        expect(DateTime.now().difference(started), lessThan(max * 3));
      },
    );

    test(
      'an update stream that fails does not block the second pass',
      () async {
        final routine = ResumeResync(
          container: container,
          resync: () async => ok,
          hydrators: [hook('h')],
          updates: () => Stream.error(StateError('no bridge')),
          settleQuiet: quiet,
          settleMax: max,
        );

        await routine.run();

        expect(calls, ['h', 'h']);
      },
    );
  });

  test('the default hook list covers every protocol-state notifier', () {
    // Trades first: chat rooms and disputes are read off the trade list.
    expect(defaultHydrators, hasLength(4));
  });
}
