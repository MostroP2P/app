import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/backup_palette.dart';
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

/// Every text role of the Account and backup redesign against the surface it
/// really renders on. Translucent fills are flattened over their parent first.
void main() {
  for (final (mode, pal, book) in [
    ('dark', BackupPalette.dark, OrderBookPalette.dark),
    ('light', BackupPalette.light, OrderBookPalette.light),
  ]) {
    group('BackupPalette.$mode contrast', () {
      final card = book.surface;
      final page = book.bg;

      test('amber banner (15a) and warning (16a)', () {
        final banner = flatten(pal.amberFill, page);
        _expectAA('banner title', pal.amberTitle, banner);
        _expectAA('banner subtitle', book.textMuted, banner);
        _expectAA('warning body', pal.amberText, banner);
      });

      test('words card (15b)', () {
        final cell = flatten(pal.cell, card);
        _expectAA('title', book.textStrong, card);
        _expectAA('chip', book.limeInk, flatten(pal.chipFill, card));
        _expectAA('word number', pal.wordIndex, cell);
        _expectAA('revealed word', book.textStrong, cell);
        _expectAA('show words', book.limeText, flatten(pal.revealFill, card));
        _expectAA('hide / copy', book.textMuted, card);
      });

      test('privacy card and buttons', () {
        _expectAA('option title', book.textStrong, card);
        _expectAA('option subtitle', book.textSecondary, card);
        _expectAA('generate', book.onLime, book.lime);
        _expectAA('import', book.limeText, page);
      });

      test('sheet (15c)', () {
        final steps = flatten(pal.stepsFill, card);
        _expectAA('title', book.textPrimary, card);
        _expectAA('body', book.textMuted, card);
        _expectAA('highlight', book.limeInk, card);
        _expectAA('step', book.textMuted, steps);
        _expectAA(
          'step number',
          book.limeInk,
          flatten(pal.stepNumberFill, steps),
        );
        _expectAA('later', book.textSecondary, card);
      });

      test('write down (16a)', () {
        _expectAA('note', book.textSecondary, flatten(pal.noteFill, card));
      });

      test('verify (16b/16c)', () {
        _expectAA('heading', book.textPrimary, page);
        _expectAA('instructions', book.textSecondary, page);
        _expectAA(
          'slot label',
          book.textSecondary,
          flatten(pal.slotFill, card),
        );
        _expectAA('solved word', book.limeInk, flatten(pal.slotDoneFill, card));
        _expectAA('options label', book.textTertiary, page);
        _expectAA('option', book.textStrong, flatten(pal.optionFill, page));
        _expectAA('all correct', book.limeInk, page);
        _expectAA('wrong pick', pal.wrong, page);
        _expectAA('view words', book.textMuted, page);
      });

      test('done (16d)', () {
        _expectAA('title', book.textPrimary, page);
        _expectAA('body', book.textSecondary, page);
      });
    });
  }
}
