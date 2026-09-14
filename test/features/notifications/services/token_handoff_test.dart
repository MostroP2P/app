import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/notifications/services/token_handoff.dart';
import 'package:mostro/src/rust/api/types.dart';

/// A scheduler the test fires by hand, recording the delays asked for.
class _Scheduler {
  final delays = <Duration>[];
  final _callbacks = <void Function()>[];

  Timer schedule(Duration delay, void Function() run) {
    delays.add(delay);
    _callbacks.add(run);
    return Timer(const Duration(days: 1), () {});
  }

  Future<void> fireNext() async {
    final run = _callbacks.removeAt(0);
    run();
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  const delays = [Duration(seconds: 1), Duration(seconds: 5)];

  late List<String> handed;
  late List<Object> failures;
  late _Scheduler scheduler;

  setUp(() {
    handed = [];
    failures = [];
    scheduler = _Scheduler();
  });

  TokenHandoff handoff() => TokenHandoff(
    setToken: (token, platform) async {
      if (failures.isNotEmpty) throw failures.removeAt(0);
      handed.add('$token ${platform.name}');
    },
    delays: delays,
    schedule: scheduler.schedule,
  );

  test(
    'a token Rust accepts is handed over once and nothing is pending',
    () async {
      final h = handoff();

      await h.offer('t1', PushPlatform.android);

      expect(handed, ['t1 android']);
      expect(h.pending, isNull);
      expect(scheduler.delays, isEmpty);
    },
  );

  test(
    'StorageUnavailable keeps the token and retries on the backoff',
    () async {
      failures = [
        Exception('StorageUnavailable'),
        Exception('StorageUnavailable'),
      ];
      final h = handoff();

      await h.offer('t1', PushPlatform.android);
      expect(h.pending, 't1');
      expect(scheduler.delays, [delays[0]]);

      await scheduler.fireNext();
      expect(scheduler.delays, delays, reason: 'second failure, second delay');

      await scheduler.fireNext();
      expect(handed, ['t1 android']);
      expect(h.pending, isNull);
    },
  );

  test('the retries are bounded by the delay list', () async {
    failures = List.generate(5, (_) => Exception('StorageUnavailable'));
    final h = handoff();

    await h.offer('t1', PushPlatform.android);
    await scheduler.fireNext();
    await scheduler.fireNext();

    expect(scheduler.delays, hasLength(delays.length));
    expect(
      h.pending,
      't1',
      reason: 'kept for retryPending, not retried on its own',
    );
    expect(handed, isEmpty);
  });

  test('retryPending hands a kept token over ahead of its backoff', () async {
    failures = [Exception('StorageUnavailable')];
    final h = handoff();
    await h.offer('t1', PushPlatform.ios);

    await h.retryPending();

    expect(handed, ['t1 ios']);
    expect(h.pending, isNull);
  });

  test('InvalidToken is dropped, not retried', () async {
    failures = [Exception('InvalidToken')];
    final h = handoff();

    await h.offer('', PushPlatform.android);

    expect(h.pending, isNull);
    expect(scheduler.delays, isEmpty);
  });

  test('a newer token supersedes a pending one', () async {
    failures = [Exception('StorageUnavailable')];
    final h = handoff();
    await h.offer('old', PushPlatform.android);
    expect(h.pending, 'old');

    await h.offer('new', PushPlatform.android);

    expect(handed, ['new android']);
    expect(h.pending, isNull);
    // The old token's timer was cancelled; firing it would be a no-op.
  });
}
