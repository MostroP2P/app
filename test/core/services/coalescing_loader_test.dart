import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/services/coalescing_loader.dart';

void main() {
  group('CoalescingLoader', () {
    test('runs the load once when nothing overlaps', () async {
      // Arrange
      var runs = 0;
      final loader = CoalescingLoader(() async => runs++);

      // Act
      await loader.run();

      // Assert
      expect(runs, 1);
    });

    test('runs one extra pass when a request arrives mid-load', () async {
      // Arrange — this is the auto-sync-during-initial-load case: the first
      // read has already captured its snapshot when the new relay lands.
      final gate = Completer<void>();
      var runs = 0;
      late CoalescingLoader loader;
      loader = CoalescingLoader(() async {
        runs++;
        if (runs == 1) await gate.future;
      });

      // Act
      final first = loader.run();
      final duringLoad = loader.run();
      expect(runs, 1, reason: 'the second request must not start a second load');
      gate.complete();
      await Future.wait([first, duringLoad]);

      // Assert
      expect(runs, 2);
    });

    test('coalesces many overlapping requests into a single extra pass',
        () async {
      // Arrange
      final gate = Completer<void>();
      var runs = 0;
      final loader = CoalescingLoader(() async {
        runs++;
        if (runs == 1) await gate.future;
      });

      // Act
      final first = loader.run();
      final overlapping = [loader.run(), loader.run(), loader.run()];
      gate.complete();
      await Future.wait([first, ...overlapping]);

      // Assert
      expect(runs, 2);
    });

    test('clears the in-flight flag when the load throws', () async {
      // Arrange
      var runs = 0;
      final loader = CoalescingLoader(() async {
        runs++;
        throw StateError('boom');
      });

      // Act / Assert
      await expectLater(loader.run(), throwsStateError);
      expect(loader.isRunning, isFalse);
      await expectLater(loader.run(), throwsStateError);
      expect(runs, 2, reason: 'a failed load must not wedge the loader');
    });
  });
}
