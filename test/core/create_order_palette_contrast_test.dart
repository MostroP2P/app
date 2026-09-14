import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/create_order_palette.dart';

import 'order_book_palette_contrast_test.dart' show contrastRatio, flatten;

const _aa = 4.5;

void _expectAA(String label, Color fg, Color bg) {
  final ratio = contrastRatio(fg, bg);
  expect(
    ratio,
    greaterThanOrEqualTo(_aa),
    reason: '$label must be ≥ $_aa:1 (got ${ratio.toStringAsFixed(2)}:1)',
  );
}

/// Locks the create-order legibility contract: every text role must meet
/// WCAG AA (4.5:1) on the actual composited surface it renders on. The
/// disabled "Publish order" ink is deliberately faint (WCAG exempts inactive
/// controls) and is not checked.
void main() {
  for (final (mode, pal, book) in [
    ('dark', CreateOrderPalette.dark, OrderBookPalette.dark),
    ('light', CreateOrderPalette.light, OrderBookPalette.light),
  ]) {
    group('CreateOrderPalette.$mode contrast', () {
      test('premium block, favourable', () {
        final bg = flatten(pal.premiumGoodBg, book.surface);
        _expectAA('good label', pal.premiumGoodLabel, bg);
        _expectAA('good value', pal.premiumGoodValue, bg);
      });

      test('premium block, unfavourable', () {
        final bg = flatten(pal.premiumBadBg, book.surface);
        _expectAA('bad label', pal.premiumBadLabel, bg);
        _expectAA('bad value', pal.premiumBadValue, bg);
      });

      test('premium block, zero', () {
        final bg = flatten(pal.premiumZeroBg, book.surface);
        _expectAA('zero label', pal.premiumZeroLabel, bg);
        _expectAA('zero value', pal.premiumZeroValue, bg);
      });

      test('field labels on the card', () {
        _expectAA('field label', pal.fieldLabel, book.surface);
        _expectAA('focused field label', pal.fieldLabelFocus, book.surface);
      });

      test('Sell tab on its tint', () {
        final track = flatten(book.tabTrack, book.bg);
        _expectAA('sell ink', pal.sellInk, flatten(pal.sellActiveBg, track));
      });

      test('validation message on the bottom bar', () {
        _expectAA('error', pal.error, book.surfaceNav);
      });
    });
  }
}
