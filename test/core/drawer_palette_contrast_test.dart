import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';

/// WCAG 2.x relative luminance of an opaque color.
double _luminance(Color c) {
  double linear(double channel) {
    return channel <= 0.03928
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b);
}

double _contrastRatio(Color fg, Color bg) {
  final lf = _luminance(fg);
  final lb = _luminance(bg);
  return (math.max(lf, lb) + 0.05) / (math.min(lf, lb) + 0.05);
}

/// Flattens a possibly-translucent [fill] over opaque [surface].
Color _flatten(Color fill, Color surface) {
  double mix(double f, double b) => f * fill.a + b * (1 - fill.a);
  return Color.from(
    alpha: 1,
    red: mix(fill.r, surface.r),
    green: mix(fill.g, surface.g),
    blue: mix(fill.b, surface.b),
  );
}

const _aa = 4.5;

void _expectAA(String label, Color fg, Color bg) {
  final ratio = _contrastRatio(fg, bg);
  expect(
    ratio,
    greaterThanOrEqualTo(_aa),
    reason: '$label must be ≥ $_aa:1 (got ${ratio.toStringAsFixed(2)}:1)',
  );
}

/// Locks the drawer legibility contract: every text role meets WCAG AA on the
/// surface it actually renders on, halos included where they sit under text.
void main() {
  for (final (mode, pal) in [
    ('dark', DrawerPalette.dark),
    ('light', DrawerPalette.light),
  ]) {
    group('DrawerPalette.$mode contrast', () {
      // The wordmark and tagline sit at the centre of the green halo, where
      // it is at full strength.
      final header = _flatten(pal.haloGreen, pal.panelGradient.first);

      test('header text over the green halo', () {
        _expectAA('$mode wordmark', pal.wordmark, header);
        _expectAA('$mode tagline', pal.tagline, header);
      });

      test('stage chip text on its fill', () {
        _expectAA(
          '$mode chipText',
          pal.chipText,
          _flatten(pal.chipFill, pal.panelGradient.first),
        );
      });

      test('item label on the row fill', () {
        _expectAA(
          '$mode itemLabel',
          pal.itemLabel,
          _flatten(pal.itemFill, pal.panelGradient[1]),
        );
      });

      test('footer version on the panel bottom', () {
        _expectAA('$mode footerText', pal.footerText, pal.panelGradient.last);
      });
    });
  }
}
