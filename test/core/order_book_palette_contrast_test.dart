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

/// Flattens a possibly-translucent [fill] over opaque [surface] — how the
/// translucent chips, tabs and scrim actually render on screen.
Color flatten(Color fill, Color surface) {
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
  final ratio = contrastRatio(fg, bg);
  expect(
    ratio,
    greaterThanOrEqualTo(_aa),
    reason: '$label must be ≥ $_aa:1 (got ${ratio.toStringAsFixed(2)}:1)',
  );
}

/// Locks the order-book legibility contract: every text role must meet WCAG
/// AA (4.5:1) on the actual composited surface it renders on.
void main() {
  for (final (mode, pal) in [
    ('dark', OrderBookPalette.dark),
    ('light', OrderBookPalette.light),
  ]) {
    group('OrderBookPalette.$mode contrast', () {
      final tabTrack = flatten(pal.tabTrack, pal.bg);
      final inset = flatten(pal.inset, pal.surface);

      test('tabs, filter row and bottom bar', () {
        _expectAA(
          '$mode active tab',
          pal.limeInk,
          flatten(pal.tabActiveFill, tabTrack),
        );
        _expectAA('$mode inactive tab', pal.textSecondary, tabTrack);
        _expectAA(
          '$mode filter chip',
          pal.textStrong,
          flatten(pal.chipFill, pal.bg),
        );
        _expectAA('$mode order count', pal.textTertiary, pal.bg);
        _expectAA('$mode sort caption', pal.sortLabel, pal.bg);
        _expectAA('$mode active destination', pal.limeText, pal.surfaceNav);
        _expectAA(
          '$mode inactive destination',
          pal.textTertiary,
          pal.surfaceNav,
        );
      });

      test('card text on the card', () {
        for (final (name, color) in [
          ('amount', pal.textPrimary),
          ('amount caption', pal.textTertiary),
          ('sats figure', pal.limeInk),
          ('time and premium caption', pal.textFaint),
          ('payment methods', pal.textMuted),
          ('premium in the taker favour', pal.limeText),
          ('premium up to 3 points against', pal.premiumMid),
          ('premium beyond 3 points against', pal.premiumHigh),
        ]) {
          _expectAA('$mode $name', color, pal.surface);
        }
        _expectAA(
          '$mode currency chip',
          pal.textStrong,
          flatten(pal.currencyChipFill, pal.surface),
        );
      });

      test('chips on their fills', () {
        _expectAA(
          '$mode best-premium chip',
          pal.limeInk,
          flatten(pal.bestChipFill, pal.surface),
        );
        _expectAA(
          '$mode most-reputable chip',
          pal.yellowInk,
          flatten(pal.reputableChipFill, pal.surface),
        );
        _expectAA(
          '$mode own-order chip',
          pal.textSecondary,
          flatten(pal.currencyChipFill, pal.surface),
        );
      });

      test('reputation strip on its inset', () {
        for (final (name, color) in [
          ('base text', pal.textSecondary),
          ('rating', pal.textStrong),
          ('figures', pal.textBody),
          ('"New"', pal.textNew),
        ]) {
          _expectAA('$mode reputation $name', color, inset);
        }
      });

      test('create-order menu', () {
        _expectAA('$mode Buy label', pal.onLime, pal.lime);
        _expectAA('$mode Sell label', pal.onSell, pal.sell);
        for (final (name, under) in [('page', pal.bg), ('card', pal.surface)]) {
          _expectAA(
            '$mode dismiss hint over the $name',
            pal.scrimText,
            flatten(pal.scrim, under),
          );
        }
      });

      test('empty and error states on the page', () {
        _expectAA('$mode empty title', pal.textBody, pal.bg);
        _expectAA('$mode empty line', pal.textSecondary, pal.bg);
        _expectAA('$mode clear filters', pal.limeText, pal.bg);
      });
    });
  }
}
