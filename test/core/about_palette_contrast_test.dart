import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/about_palette.dart';
import 'package:mostro/core/order_book_palette.dart';

import 'order_book_palette_contrast_test.dart' show contrastRatio, flatten;

const _aa = 4.5;

void _expectAA(String label, Color fg, Color bg) {
  final ratio = contrastRatio(fg, bg);
  expect(
    ratio,
    greaterThanOrEqualTo(_aa),
    reason: '$label: ${ratio.toStringAsFixed(2)}:1 < $_aa:1',
  );
}

/// Every text role of the About redesign against the surface it really renders
/// on. Translucent fills are flattened over their parent surface first.
void main() {
  for (final (mode, pal, book) in [
    ('dark', AboutPalette.dark, OrderBookPalette.dark),
    ('light', AboutPalette.light, OrderBookPalette.light),
  ]) {
    group('AboutPalette.$mode contrast', () {
      final card = book.surface;
      final page = book.bg;

      test('page chrome', () {
        _expectAA('title', book.textPrimary, page);
        _expectAA('group header', pal.groupHeader, page);
      });

      test('brand card', () {
        _expectAA('name', book.textPrimary, card);
        _expectAA('tagline', book.textSecondary, card);
        _expectAA('version pill', pal.accent, flatten(pal.pillFill, card));
      });

      test('rows', () {
        _expectAA('12a label', book.textStrong, card);
        _expectAA('12a value', book.textMuted, card);
        _expectAA('12b label', book.textMuted, card);
        _expectAA('12b key label', book.textSecondary, card);
        _expectAA('12b value', book.textStrong, card);
      });

      test('connected node card', () {
        final cell = flatten(pal.cell, card);
        _expectAA('pubkey', book.textSecondary, card);
        _expectAA('cell label', book.textSecondary, cell);
        _expectAA('cell figure', book.textStrong, cell);
        _expectAA('limits footnote', pal.groupHeader, card);
      });

      test('12b footnote and copy all', () {
        _expectAA('footnote', book.textSecondary, flatten(pal.noteFill, page));
        _expectAA('copy all', pal.accent, flatten(pal.actionFill, page));
        _expectAA('header copy action', pal.accent, page);
      });
    });
  }
}
