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

double _contrastRatio(Color fg, Color bg) {
  final lf = _luminance(fg);
  final lb = _luminance(bg);
  final hi = math.max(lf, lb);
  final lo = math.min(lf, lb);
  return (hi + 0.05) / (lo + 0.05);
}

const _aa = 4.5;

void _expectAA(String label, Color fg, Color bg) {
  final ratio = _contrastRatio(fg, bg);
  expect(
    ratio,
    greaterThanOrEqualTo(_aa),
    reason: '$label must be ≥ $_aa:1 (got ${ratio.toStringAsFixed(2)}:1)',
  );
}

/// Every text role a modal renders, against the surface it really renders on.
///
/// The pair that started this (#534) is the confirm button: the theme filled
/// it with the accent and wrote white on it — 2.05:1, which is not readable.
/// Nothing here may fall below AA again.
void main() {
  for (final (mode, book, theme) in [
    ('dark', OrderBookPalette.dark, buildDarkTheme()),
    ('light', OrderBookPalette.light, buildLightTheme()),
  ]) {
    group('modal contrast · $mode', () {
      test('confirm button ink on its fill', () {
        _expectAA('primary', book.onLime, book.lime);
        _expectAA('destructive', book.onSell, book.sell);
      });

      test('the theme fills a FilledButton with a legible pair', () {
        final scheme = theme.colorScheme;
        _expectAA('colorScheme onPrimary', scheme.onPrimary, scheme.primary);
      });

      test('title and body on the modal surface', () {
        _expectAA('title', book.textPrimary, book.surface);
        _expectAA('body', book.textSecondary, book.surface);
      });

      test('secondary button label on the modal surface', () {
        _expectAA('label', book.textBody, book.surface);
      });

      test('link action on the modal surface', () {
        _expectAA('link', book.limeText, book.surface);
      });
    });
  }

  test('the app has exactly one accent', () {
    // AppColors and OrderBookPalette are two colour systems that met in the
    // modals as two nearly-equal greens. Holding them equal is what keeps
    // that from coming back.
    final dark = buildDarkTheme();
    final light = buildLightTheme();
    expect(dark.extension<AppColors>()!.mostroGreen, OrderBookPalette.dark.lime);
    expect(
      light.extension<AppColors>()!.mostroGreen,
      OrderBookPalette.light.lime,
    );
    expect(dark.colorScheme.primary, OrderBookPalette.dark.lime);
    expect(dark.colorScheme.onPrimary, OrderBookPalette.dark.onLime);
  });

  test('a modal inherits its surface, radius and scrim from the theme', () {
    for (final theme in [buildDarkTheme(), buildLightTheme()]) {
      final book =
          theme.brightness == Brightness.dark
              ? OrderBookPalette.dark
              : OrderBookPalette.light;
      expect(theme.dialogTheme.backgroundColor, book.surface);
      expect(theme.dialogTheme.barrierColor, book.scrim);
      expect(
        theme.dialogTheme.shape,
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.modal),
        ),
      );
      expect(theme.bottomSheetTheme.backgroundColor, book.surface);
      expect(theme.bottomSheetTheme.modalBarrierColor, book.scrim);
    }
  });
}
