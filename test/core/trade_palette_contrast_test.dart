import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/core/trade_palette.dart';

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

/// Locks the trade-screen legibility contract: every text role must meet
/// WCAG AA (4.5:1) on the actual composited surface it renders on.
void main() {
  for (final (mode, pal, book) in [
    ('dark', TradePalette.dark, OrderBookPalette.dark),
    ('light', TradePalette.light, OrderBookPalette.light),
  ]) {
    group('TradePalette.$mode contrast', () {
      test('status chips on their tints', () {
        _expectAA(
          'waiting chip',
          pal.chipWaitInk,
          flatten(pal.chipWaitBg, book.surface),
        );
        _expectAA(
          'active chip',
          pal.chipActiveInk,
          flatten(pal.chipActiveBg, book.surface),
        );
        _expectAA(
          'dispute chip',
          pal.chipDisputeInk,
          flatten(pal.chipDisputeBg, book.surface),
        );
      });

      test('release warning on its tint', () {
        _expectAA('warning', pal.warnInk, flatten(pal.warnBg, book.surface));
      });

      test('countdown figures on the card', () {
        _expectAA('active clock', pal.timerActive, book.surface);
        _expectAA('waiting clock', pal.timerWait, book.surface);
        _expectAA('urgent clock', pal.timerUrgent, book.surface);
      });

      test('secondary actions on the bottom bar', () {
        _expectAA('cancel', pal.cancelInk, book.surfaceNav);
        _expectAA('dispute', pal.neutralInk, book.surfaceNav);
      });

      test('reputation grade on the avatar', () {
        _expectAA('grade', book.limeInk, flatten(pal.avatarBg, book.surface));
        _expectAA('new', book.textNew, flatten(pal.avatarNewBg, book.surface));
      });

      test('the no-chat line on the page', () {
        _expectAA(
          'locked note',
          book.textSecondary,
          flatten(pal.lockedBg, book.bg),
        );
      });
    });
  }
}
