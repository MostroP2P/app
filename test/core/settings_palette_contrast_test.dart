import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/core/settings_palette.dart';

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

/// Every text role of the settings redesign against the surface it really
/// renders on. Translucent chip and banner fills are flattened over that
/// surface first. Disabled controls are exempt, as WCAG exempts inactive
/// components — which is why the dead `Conectar` ink is not asserted here.
void main() {
  for (final (mode, pal, book) in [
    ('dark', SettingsPalette.dark, OrderBookPalette.dark),
    ('light', SettingsPalette.light, OrderBookPalette.light),
  ]) {
    group('SettingsPalette.$mode contrast', () {
      final page = book.bg;
      final card = book.surface;
      final nav = book.surfaceNav;

      test('group header sits on the page, not a card', () {
        _expectAA('group header', pal.groupHeader, page);
      });

      test('setting row', () {
        _expectAA('label', book.textStrong, card);
        _expectAA('value neutral', book.textMuted, card);
        _expectAA('value good', book.limeInk, card);
        _expectAA('value warning', pal.warnInk, card);
        _expectAA('value data', pal.textMono, card);
      });

      test('footnotes and the notification intro', () {
        _expectAA('footnote', book.textTertiary, page);
        _expectAA('intro', book.textSecondary, page);
      });

      test('relay summary and rows', () {
        _expectAA('tally', book.textPrimary, card);
        _expectAA('healthy', book.textSecondary, card);
        _expectAA('at risk', pal.warnInk, card);
        _expectAA('url connected', book.textStrong, card);
        _expectAA('url down', book.textSecondary, card);
        _expectAA('status down', book.textTertiary, card);
      });

      test('add relay', () {
        _expectAA('label', book.textBody, flatten(pal.dashedFill, page));
      });

      test('denied-permission banner', () {
        _expectAA('text', pal.warnInk, flatten(pal.warnBg, page));
      });

      test('NWC card and field', () {
        _expectAA('title', book.textPrimary, card);
        _expectAA('body', book.textSecondary, card);
        _expectAA('label rest', pal.fieldLabel, card);
        _expectAA('label focus', pal.fieldLabelFocus, card);
        _expectAA('value', book.textPrimary, card);
        _expectAA('placeholder', pal.placeholder, card);
        _expectAA('paste', book.textBody, flatten(pal.buttonFill, card));
        _expectAA('scan', book.limeInk, flatten(pal.scanFill, card));
        _expectAA('balance', book.limeInk, card);
        _expectAA('connect', book.onLime, book.lime);
        _expectAA('disconnect', pal.danger, nav);
      });

      test('log filter chips', () {
        _expectAA('active', pal.chipActiveInk, flatten(pal.chipActiveBg, page));
        _expectAA('idle', pal.chipIdleInk, flatten(pal.chipIdleBg, page));
      });

      test('log entry', () {
        _expectAA('debug', pal.logDebugInk, flatten(pal.logDebugBg, card));
        _expectAA('info', pal.logInfoInk, flatten(pal.logInfoBg, card));
        _expectAA('warn', pal.logWarnInk, flatten(pal.logWarnBg, card));
        _expectAA('error', pal.logErrInk, flatten(pal.logErrBg, card));
        _expectAA('subsystem', book.textSecondary, card);
        _expectAA('time', pal.placeholder, card);
        _expectAA('message', pal.textMono, card);
      });

      test('verbose bar', () {
        _expectAA('label', book.textStrong, nav);
        _expectAA('consequence', book.textTertiary, nav);
      });
    });
  }
}
