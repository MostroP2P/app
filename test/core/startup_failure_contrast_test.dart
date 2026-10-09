import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/startup_failure.dart';

import 'order_book_palette_contrast_test.dart' show contrastRatio;

/// The startup failure screen hard-codes its colors, so no palette test
/// covers them (`.specify/DESIGN_SYSTEM.md` §13). Each text color is asserted
/// at 4.5:1 against the screen's one background, and the measured ratios are
/// pinned so a changed value shows up here and not as a faded screen.
void main() {
  group('StartupFailureApp contrast', () {
    const aa = 4.5;
    final roles = <(String, Color, double)>[
      ('title', StartupFailureApp.title, 16.08),
      ('body', StartupFailureApp.body, 7.91),
      ('detail', StartupFailureApp.detail, 5.30),
    ];

    for (final (name, color, measured) in roles) {
      test('$name is at least $aa:1 on the background', () {
        final ratio = contrastRatio(color, StartupFailureApp.background);
        expect(ratio, greaterThanOrEqualTo(aa));
        expect(ratio, closeTo(measured, 0.01));
      });
    }
  });
}
