import 'package:flutter/foundation.dart';

/// The startup steps, and which one is running.
///
/// Exists so a failure before `runApp` can say *where* it happened: the guard
/// that catches it is at the end of the sequence and has no other way to know.
///
/// Both helpers set [currentStep] on entry, so every stretch of startup runs
/// under its own name. That is the point of having two of them rather than one:
/// with only [optional], the mandatory stretches in between would keep running
/// under the label of whichever optional step finished last, and a failure
/// there would name a step that succeeded (#405 review).
class StartupSequence {
  /// The step in progress. Read by the failure surface.
  String currentStep = 'starting up';

  /// A step the app can open without: a failure is recorded and startup
  /// continues, degraded.
  ///
  /// Every degradation prints the same `[startup]` prefix, so grepping it lists
  /// what a run gave up on, in order — which matters when one failure causes
  /// the next.
  Future<void> optional(String name, Future<void> Function() body) async {
    currentStep = name;
    try {
      await body();
    } catch (e, st) {
      debugPrint('[startup] $name failed — continuing without it: $e\n$st');
    }
  }

  /// A step the app cannot open without: the failure propagates to the guard,
  /// which shows the failure surface naming [name].
  Future<T> required<T>(String name, Future<T> Function() body) {
    currentStep = name;
    return body();
  }
}
