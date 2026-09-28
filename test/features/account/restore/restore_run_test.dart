import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/account/restore/restore_run.dart';
import 'package:mostro/src/rust/api/types.dart';

void main() {
  late StreamController<RestoreProgress> steps;
  late Completer<int> answer;
  late int recoveries;
  late RestoreRun run;

  setUp(() {
    steps = StreamController<RestoreProgress>.broadcast();
    answer = Completer<int>();
    recoveries = 0;
    run = RestoreRun(
      progress: () async => steps.stream,
      recover: () {
        recoveries++;
        return answer.future;
      },
    );
  });

  tearDown(() async {
    run.dispose();
    await steps.close();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  /// Start a run and let it subscribe, as the core's stream is subscribed
  /// before the recovery is asked for.
  Future<void> begin() async {
    unawaited(run.start());
    await settle();
  }

  group('while the node is asked', () {
    test('the first stage runs until a relay took the request', () async {
      unawaited(run.start());
      await settle();

      expect(run.state.stages, [
        RestoreStage.active,
        RestoreStage.pending,
        RestoreStage.pending,
      ]);
      expect(run.state.progress, 0);
    });

    test('20a: connected, asking for the orders, bar at 34 %', () async {
      await begin();
      steps.add(const RestoreProgress.connected());
      await settle();

      expect(run.state.stages, [
        RestoreStage.done,
        RestoreStage.active,
        RestoreStage.pending,
      ]);
      expect(run.state.found, isNull, reason: 'no total before the answer');
      expect(run.state.progress, closeTo(0.34, 1e-9));
    });

    test('20b: the answer names the orders and each one loads', () async {
      await begin();
      steps
        ..add(const RestoreProgress.connected())
        ..add(const RestoreProgress.found(found: 3, toLoad: 3))
        ..add(const RestoreProgress.loaded(done: 2, toLoad: 3));
      await settle();

      expect(run.state.stages, [
        RestoreStage.done,
        RestoreStage.done,
        RestoreStage.active,
      ]);
      expect(run.state.found, 3);
      expect(run.state.loaded, 2);
      expect(run.state.toLoad, 3);
      expect(run.state.progress, closeTo(0.34 + 0.44 * 2 / 3, 1e-9));
    });

    test('the bar never moves back', () async {
      await begin();
      steps
        ..add(const RestoreProgress.connected())
        ..add(const RestoreProgress.found(found: 3, toLoad: 3))
        ..add(const RestoreProgress.loaded(done: 2, toLoad: 3))
        // A retry of the request inside the core reports it again.
        ..add(const RestoreProgress.connected());
      await settle();

      expect(run.state.progress, closeTo(0.34 + 0.44 * 2 / 3, 1e-9));
    });
  });

  group('20d, when the restore answers', () {
    test('every order loaded is a full restore', () async {
      await begin();
      steps
        ..add(const RestoreProgress.connected())
        ..add(const RestoreProgress.found(found: 3, toLoad: 3))
        ..add(const RestoreProgress.loaded(done: 3, toLoad: 3));
      await settle();
      answer.complete(3);
      await settle();

      expect(run.state.outcome, RestoreOutcome.restored);
      expect(run.state.stages, everyElement(RestoreStage.done));
      expect(run.state.progress, 1);
      expect(run.state.unloaded, 0);
    });

    test('orders whose details never came are a partial restore', () async {
      await begin();
      steps
        ..add(const RestoreProgress.connected())
        ..add(const RestoreProgress.found(found: 3, toLoad: 3))
        ..add(const RestoreProgress.loaded(done: 1, toLoad: 3));
      await settle();
      answer.complete(3);
      await settle();

      expect(run.state.outcome, RestoreOutcome.restored);
      expect(run.state.unloaded, 2);
    });

    test('an account with no orders is restored, not failed', () async {
      await begin();
      steps
        ..add(const RestoreProgress.connected())
        ..add(const RestoreProgress.found(found: 0, toLoad: 0));
      await settle();
      answer.complete(0);
      await settle();

      expect(run.state.outcome, RestoreOutcome.restored);
      expect(run.state.found, 0);
      expect(run.state.unloaded, 0);
    });
  });

  group('20c, when the restore fails', () {
    test('marks the stage that was running and keeps the ones done', () async {
      await begin();
      steps.add(const RestoreProgress.connected());
      await settle();
      answer.completeError(Exception('NoDaemonResponse'));
      await settle();

      expect(run.state.outcome, RestoreOutcome.failed);
      expect(run.state.stages, [
        RestoreStage.done,
        RestoreStage.failed,
        RestoreStage.pending,
      ]);
    });

    test('a retry starts over and asks the node again', () async {
      await begin();
      answer.completeError(Exception('offline'));
      await settle();
      expect(run.state.stages.first, RestoreStage.failed);

      answer = Completer<int>();
      unawaited(run.start());
      await settle();

      expect(recoveries, 2);
      expect(run.state.outcome, RestoreOutcome.running);
      expect(run.state.stages.first, RestoreStage.active);
    });
  });

  test('steps from a run that was left are not applied', () async {
    await begin();
    run.dispose();
    steps.add(const RestoreProgress.connected());
    await settle();

    expect(run.state.stages.first, RestoreStage.active);
  });
}
