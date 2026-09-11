import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/startup_sequence.dart';

void main() {
  group('StartupSequence', () {
    test('optional swallows a failure so startup continues', () async {
      final seq = StartupSequence();
      var reached = false;

      await seq.optional('flaky', () async => throw StateError('boom'));
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

    test('a failing optional step still names itself', () async {
      final seq = StartupSequence();
      await seq.optional('connecting to the network', () async {
        throw StateError('offline');
      });
      expect(seq.currentStep, 'connecting to the network');
    });

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
