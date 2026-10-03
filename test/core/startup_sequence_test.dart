import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/startup_sequence.dart';

void main() {
  group('StartupSequence', () {
    test('optional swallows a failure so startup continues', () async {
      final seq = StartupSequence();
      var reached = false;

      await seq.optional('flaky', () async => throw Exception('boom'));
      await seq.optional('next', () async => reached = true);

      expect(reached, isTrue, reason: 'a degraded step must not end startup');
    });

    test('required lets a failure through to the guard', () async {
      final seq = StartupSequence();

      await expectLater(
        seq.required('essential', () async => throw StateError('boom')),
        throwsStateError,
      );
    });

    test('required returns what the body produced', () async {
      final seq = StartupSequence();
      expect(await seq.required('reading', () async => 42), 42);
    });

    test('the step reported is the one that failed, not the last that '
        'succeeded', () async {
      // The regression this class exists for. With a single helper that set
      // the label and never restored it, everything between two optional
      // steps ran under the earlier one's name, and a failure there named a
      // step that had finished fine (#405 review).
      final seq = StartupSequence();

      await seq.optional('opening the local database', () async {});
      await expectLater(
        seq.required(
          'building the interface',
          () async => throw StateError('x'),
        ),
        throwsStateError,
      );

      expect(seq.currentStep, 'building the interface');
    });

    test('optional reports a programming error loudly in debug, and '
        'startup still continues', () async {
      // An Error (TypeError, StateError, a failed assert) is a bug, not a
      // missing environment: it must not pass as one more log line. But it
      // must not stop startup either — a step that already fails this way on
      // some platform would then block every debug run there (#405 review).
      // Tests run in debug mode.
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);

      final seq = StartupSequence();
      var reached = false;
      await seq.optional('flaky', () async => throw StateError('bug'));
      await seq.optional('next', () async => reached = true);

      expect(reported, hasLength(1), reason: 'the bug must be reported');
      expect(reported.single.exception, isStateError);
      expect(reached, isTrue, reason: 'startup must carry on past it');
    });

    test('optional does not report an environment failure as a bug', () async {
      final reported = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = reported.add;
      addTearDown(() => FlutterError.onError = previous);

      await StartupSequence().optional(
        'offline',
        () async => throw Exception('no network'),
      );
      expect(reported, isEmpty);
    });

    test('a failing optional step still names itself', () async {
      final seq = StartupSequence();
      await seq.optional('connecting to the network', () async {
        throw Exception('offline');
      });
      expect(seq.currentStep, 'connecting to the network');
    });

    test(
      'work started before the step still fails under its own name',
      () async {
        // Startup launches its three platform round trips together and awaits
        // each inside its own step (#494 merged the parallel start into the
        // sequence this guard names). `currentStep` is one field, so the name
        // must come from where the failure is awaited, not from where the work
        // began.
        final engine = Future<void>.error(StateError('bridge panic'))..ignore();
        final seq = StartupSequence();

        await seq.optional('setting up notifications', () async {});
        await expectLater(
          seq.required('loading the engine', () => engine),
          throwsStateError,
        );

        expect(seq.currentStep, 'loading the engine');
      },
    );

    test('the label is in place while the body runs, not only after', () async {
      final seq = StartupSequence();
      late String seen;
      await seq.required('loading the engine', () async {
        seen = seq.currentStep;
      });
      expect(seen, 'loading the engine');
    });
  });
}
