import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/restore_palette.dart';

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

/// Every text role of the restore sheet (20a–20d) against the surface it
/// really renders on. Translucent fills are flattened over the sheet first.
void main() {
  for (final (mode, pal) in [
    ('dark', RestorePalette.dark),
    ('light', RestorePalette.light),
  ]) {
    group('RestorePalette.$mode contrast', () {
      final sheet = pal.sheet;

      test('header', () {
        _expectAA('title', pal.text, sheet);
        _expectAA('subtitle', pal.textSecondary, sheet);
        _expectAA('cancel', pal.textSecondary, sheet);
      });

      test('stages', () {
        final active = flatten(pal.activeFill, sheet);
        final failed = flatten(pal.errorFill, sheet);
        _expectAA('pending', pal.textPending, sheet);
        _expectAA('active', pal.text, active);
        _expectAA('counter', pal.limeSoft, active);
        _expectAA('done', pal.textSecondary, sheet);
        _expectAA('failed', pal.text, failed);
        _expectAA('no response', pal.errorDetail, failed);
      });

      test('failure (20c)', () {
        _expectAA('paragraph', pal.textSecondary, sheet);
        _expectAA('account', pal.emphasis, sheet);
        _expectAA('retry', pal.onLime, pal.lime);
        _expectAA('continue without', pal.emphasis, sheet);
      });

      test('summary (20d)', () {
        _expectAA('figure', pal.text, pal.card);
        _expectAA('figure label', pal.textSecondary, pal.card);
        _expectAA('action notice', pal.limeSoft, flatten(pal.noticeFill, sheet));
        _expectAA('partial notice', pal.amber, flatten(pal.amberFill, sheet));
        _expectAA('close', pal.onLime, pal.lime);
      });
    });
  }
}
