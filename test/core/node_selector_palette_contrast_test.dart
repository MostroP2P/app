import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/node_selector_palette.dart';
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

/// Every text role of the node-selector redesign against the surface it
/// really renders on. Translucent chip fills are flattened over the card
/// surface first. Disabled controls (the dead `Agregar` ink) are exempt, as
/// WCAG exempts inactive components.
void main() {
  for (final (mode, pal, book) in [
    ('dark', NodeSelectorPalette.dark, OrderBookPalette.dark),
    ('light', NodeSelectorPalette.light, OrderBookPalette.light),
  ]) {
    group('NodeSelectorPalette.$mode contrast', () {
      final card = book.surface;
      final sheet = book.bg;

      test('currency chips', () {
        _expectAA('mine', pal.chipMineInk, flatten(pal.chipMineBg, card));
        _expectAA(
          'neutral',
          pal.chipNeutralInk,
          flatten(pal.chipNeutralBg, card),
        );
        _expectAA('missing', pal.warnInk, flatten(pal.warnBg, card));
      });

      test('trusted chip', () {
        _expectAA('trusted', pal.trustedInk, flatten(pal.trustedBg, card));
      });

      test('metric figures on the inset strip', () {
        final strip = flatten(pal.inset, card);
        _expectAA('liquidity', pal.figureLime, strip);
        _expectAA('figure', book.textStrong, strip);
        _expectAA('unit', pal.stripText, strip);
        _expectAA('missing figure', pal.stripText, strip);
        _expectAA('zero in mine', pal.warnInk, strip);
      });

      test('trust row and availability', () {
        _expectAA('custody', book.textSecondary, card);
        _expectAA('bond incompatible', pal.warnInk, card);
        _expectAA('availability', book.textSecondary, card);
      });

      test('sheet chrome', () {
        _expectAA('title', book.textPrimary, sheet);
        _expectAA('subtitle', book.textTertiary, sheet);
        _expectAA('subtitle currency', book.limeIcon, sheet);
        _expectAA('disclaimer', book.textFaint, sheet);
        _expectAA('add node', book.textBody, flatten(pal.dashedFill, sheet));
      });

      test('dialog', () {
        _expectAA('label focus', pal.fieldLabelFocus, card);
        _expectAA('label rest', pal.fieldLabel, card);
        _expectAA('value', book.textPrimary, card);
        _expectAA('warning', pal.warnInk, flatten(pal.warnBg, card));
        _expectAA('error', pal.danger, card);
        _expectAA('cancel', book.textBody, card);
        _expectAA('add', book.onLime, book.lime);
      });

      test('fallback avatar initial', () {
        _expectAA('lime', pal.avatarLimeInk, flatten(pal.avatarLimeBg, card));
        _expectAA(
          'yellow',
          pal.avatarYellowInk,
          flatten(pal.avatarYellowBg, card),
        );
      });
    });
  }
}
