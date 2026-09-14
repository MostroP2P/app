import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/invoice_palette.dart';
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

/// Every text role of the invoice redesign against the surface it really
/// renders on. Translucent fills are flattened over their parent surface.
void main() {
  for (final (mode, pal, book) in [
    ('dark', InvoicePalette.dark, OrderBookPalette.dark),
    ('light', InvoicePalette.light, OrderBookPalette.light),
  ]) {
    group('InvoicePalette.$mode contrast', () {
      final card = book.surface;
      final page = book.bg;

      test('app bar and hero card', () {
        _expectAA('title', book.textPrimary, page);
        _expectAA('order id', book.textSecondary, page);
        _expectAA('figure', book.textPrimary, card);
        _expectAA('hero label', book.textSecondary, card);
      });

      test('time band', () {
        final band = flatten(pal.timeFill, page);
        _expectAA('sentence', pal.timeInk, band);
        _expectAA('figure', pal.timeFigure, band);
        _expectAA('urgent', pal.errorInk, flatten(pal.errorFill, page));
      });

      test('invoice field and validation', () {
        _expectAA('field label', book.textSecondary, card);
        _expectAA('field value', book.textPrimary, card);
        _expectAA('paste / scan', book.limeText, card);
        _expectAA('valid', pal.validInk, flatten(pal.validFill, page));
        _expectAA('error', pal.errorInk, flatten(pal.errorFill, page));
      });

      test('counterpart card and hold note', () {
        final subtle = flatten(pal.subtleFill, page);
        _expectAA('label', book.textSecondary, subtle);
        _expectAA('value', book.textStrong, subtle);
      });

      test('actions', () {
        _expectAA('primary', book.onLime, book.lime);
        _expectAA(
          'secondary',
          pal.secondaryInk,
          flatten(pal.secondaryFill, page),
        );
        _expectAA('cancel 13a', book.textSecondary, page);
        _expectAA('cancel 13b', pal.cancelDanger, page);
      });
    });
  }
}
