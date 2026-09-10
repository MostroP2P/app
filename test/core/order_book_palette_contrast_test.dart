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

double contrastRatio(Color fg, Color bg) {
  final lf = _luminance(fg);
  final lb = _luminance(bg);
  final hi = math.max(lf, lb);
  final lo = math.min(lf, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// Composites [fg] at [alpha] over opaque [bg] — how translucent pill fills
/// actually render on screen.
Color composite(Color fg, double alpha, Color bg) {
  double mix(double f, double b) => f * alpha + b * (1 - alpha);
  return Color.from(
    alpha: 1,
    red: mix(fg.r, bg.r),
    green: mix(fg.g, bg.g),
    blue: mix(fg.b, bg.b),
  );
}

/// Flattens a possibly-translucent fill color over [surface].
Color flatten(Color fill, Color surface) => composite(fill, fill.a, surface);

const _aa = 4.5;

void _expectAA(String label, Color fg, Color bg) {
  final ratio = contrastRatio(fg, bg);
  expect(
    ratio,
    greaterThanOrEqualTo(_aa),
    reason: '$label must be ≥ $_aa:1 (got ${ratio.toStringAsFixed(2)}:1)',
  );
}

/// Locks the Order Book legibility contract: every text role must meet
/// WCAG AA (4.5:1) on the actual composited surface it renders on.
void main() {
  for (final (mode, pal) in [
    ('dark', OrderBookPalette.dark),
    ('light', OrderBookPalette.light),
  ]) {
    group('OrderBookPalette.$mode contrast', () {
      test('body text roles on their surfaces', () {
        _expectAA('$mode textPrimary/bgCard', pal.textPrimary, pal.bgCard);
        _expectAA(
            '$mode textPrimary/bgElevated', pal.textPrimary, pal.bgElevated);
        _expectAA('$mode textSecondary/bgCard', pal.textSecondary, pal.bgCard);
        _expectAA(
            '$mode textSecondary/bgElevated', pal.textSecondary, pal.bgElevated);
        _expectAA('$mode textSecondary/bg', pal.textSecondary, pal.bg);
        // Empty/error state copy renders on the list well behind the cards.
        _expectAA('$mode textSecondary/bgWell', pal.textSecondary, pal.bgWell);
        // Timestamps, "Market price", the sort caption, and separators.
        _expectAA('$mode textTertiary/bgCard', pal.textTertiary, pal.bgCard);
        _expectAA('$mode textTertiary/bg', pal.textTertiary, pal.bg);
        _expectAA('$mode textTertiary/bgWell', pal.textTertiary, pal.bgWell);
      });

      test('reason pills on their fills', () {
        _expectAA(
            '$mode green/greenDim', pal.green, flatten(pal.greenDim, pal.bgCard));
        _expectAA(
            '$mode gold/goldDim', pal.gold, flatten(pal.goldDim, pal.bgCard));
        _expectAA(
            '$mode blue/blueFill', pal.blue, flatten(pal.blueFill, pal.bgCard));
      });

      test('premium pills on their 13% fills over the card', () {
        for (final (name, color) in [
          ('green', pal.green),
          ('amber', pal.amber),
          ('red', pal.red),
        ]) {
          _expectAA('$mode premium $name pill', color,
              composite(color, 0.13, pal.bgCard));
        }
      });

      test('active tab label on the page background', () {
        _expectAA('$mode green tab/bg', pal.green, pal.bg);
      });
    });
  }

  test('light inactive tab label meets AA (interactive control)', () {
    _expectAA('light tabInactive/bg', OrderBookPalette.light.tabInactive,
        OrderBookPalette.light.bg);
  });
}
