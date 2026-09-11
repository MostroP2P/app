import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/order_detail_palette.dart';

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

/// Locks the order-detail legibility contract: every text role must meet
/// WCAG AA (4.5:1) on the actual composited surface it renders on. The
/// unavailable `Take order` ink is an inactive control (WCAG exempts those)
/// and is not checked.
void main() {
  for (final (mode, pal, book) in [
    ('dark', OrderDetailPalette.dark, OrderBookPalette.dark),
    ('light', OrderDetailPalette.light, OrderBookPalette.light),
  ]) {
    group('OrderDetailPalette.$mode contrast', () {
      test('side chips on the amount card', () {
        _expectAA(
          'sell ink',
          pal.sellInk,
          flatten(pal.sellChipBg, book.surface),
        );
        _expectAA('buy ink', pal.buyInk, flatten(pal.buyChipBg, book.surface));
      });

      for (final family in OrderStatusFamily.values) {
        test('status block, $family', () {
          final colors = statusColors(pal, family);
          final bg = flatten(colors.bg, book.bg);
          _expectAA('$family text', colors.text, bg);
          _expectAA('$family aside', colors.aside, bg);
          _expectAA('$family note', book.textSecondary, bg);
        });
      }

      test('cancel button on the action bar', () {
        _expectAA('danger', pal.danger, book.surfaceNav);
      });

      test('counterparty avatar', () {
        _expectAA('rating', book.limeInk, flatten(pal.avatarBg, book.surface));
        _expectAA('new', book.textNew, flatten(pal.avatarNewBg, book.surface));
      });

      test('Take order while loading', () {
        _expectAA(
          'loading ink',
          pal.ctaLoadingInk,
          flatten(pal.ctaLoadingBg, book.surfaceNav),
        );
      });

      test('captions on the cards and the action bar', () {
        _expectAA('tertiary on card', book.textTertiary, book.surface);
        _expectAA('secondary on bar', book.textSecondary, book.surfaceNav);
      });
    });
  }
}
