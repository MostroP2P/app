import 'package:flutter/material.dart';

import 'package:mostro/core/order_book_palette.dart';

/// Tokens of the Lightning invoice redesign (`design_handoff_factura_lightning`,
/// variants 13a · receive your sats and 13b · lock your sats), added on top of
/// [OrderBookPalette], which it shares for the page, the card surface, lime
/// and the text roles.
///
/// Dark values are the handoff's. The handoff is dark-only, so [light] maps
/// each role onto the light surfaces the order book already uses, adjusted
/// where a text role would fail WCAG AA (4.5:1) on the surface it renders on.
/// `test/core/invoice_palette_contrast_test.dart` locks every pair.
@immutable
class InvoicePalette {
  const InvoicePalette({
    required this.cardBorder,
    required this.subtleFill,
    required this.subtleBorder,
    required this.fieldFocusBorder,
    required this.icon,
    required this.validFill,
    required this.validBorder,
    required this.validInk,
    required this.validIcon,
    required this.errorFill,
    required this.errorBorder,
    required this.errorInk,
    required this.timeFill,
    required this.timeBorder,
    required this.timeInk,
    required this.timeFigure,
    required this.secondaryFill,
    required this.secondaryBorder,
    required this.secondaryInk,
    required this.disabledFill,
    required this.disabledInk,
    required this.cancelDanger,
  });

  /// Hero amount card and the invoice field at rest.
  final Color cardBorder;

  /// Counterpart card and hold note.
  final Color subtleFill;
  final Color subtleBorder;

  /// The invoice field while it has focus.
  final Color fieldFocusBorder;

  /// Lock of the hold note.
  final Color icon;

  /// Validation row of a usable invoice or address.
  final Color validFill;
  final Color validBorder;
  final Color validInk;
  final Color validIcon;

  /// Validation row with a concrete reason, the daemon's refusal, and the
  /// time band under a minute.
  final Color errorFill;
  final Color errorBorder;
  final Color errorInk;

  /// Time band: fill, border, sentence, and the figure inside it.
  final Color timeFill;
  final Color timeBorder;
  final Color timeInk;
  final Color timeFigure;

  /// `Copy` / `Share` (and `Open in my wallet` once no wallet answered).
  final Color secondaryFill;
  final Color secondaryBorder;
  final Color secondaryInk;

  /// Primary action while the field does not validate.
  final Color disabledFill;
  final Color disabledInk;

  /// `Cancel trade` in 13b, where cancelling has a consequence.
  final Color cancelDanger;

  static const dark = InvoicePalette(
    cardBorder: Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
    subtleFill: Color(0x08FFFFFF), // rgba(255,255,255,0.03)
    subtleBorder: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    fieldFocusBorder: Color(0x4792D64F), // rgba(146,214,79,0.28)
    icon: Color(0xFF7E899E),
    validFill: Color(0x1A92D64F), // rgba(146,214,79,0.10)
    validBorder: Color(0x3892D64F), // rgba(146,214,79,0.22)
    validInk: Color(0xFFC6F09A),
    validIcon: Color(0xFF92D64F),
    errorFill: Color(0x1AE4685D), // rgba(228,104,93,0.10)
    errorBorder: Color(0x47E4685D), // rgba(228,104,93,0.28)
    errorInk: Color(0xFFE4685D),
    timeFill: Color(0x14F7DE72), // rgba(247,222,114,0.08)
    timeBorder: Color(0x38F7DE72), // rgba(247,222,114,0.22)
    timeInk: Color(0xFFE8D89A),
    timeFigure: Color(0xFFF7DE72),
    secondaryFill: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    secondaryBorder: Color(0x17FFFFFF), // rgba(255,255,255,0.09)
    secondaryInk: Color(0xFFA6B0C2),
    disabledFill: Color(0x4092D64F), // rgba(146,214,79,0.25)
    disabledInk: Color(0x8C12161F), // rgba(18,22,31,0.55)
    cancelDanger: Color(0xFFE4685D),
  );

  static const light = InvoicePalette(
    cardBorder: Color(0x1412161F), // ink 8%
    subtleFill: Color(0x0A12161F), // ink 4%
    subtleBorder: Color(0x1412161F), // ink 8%
    fieldFocusBorder: Color(0x995C9130), // rgba(92,145,48,0.60)
    icon: Color(0xFF5F6979),
    validFill: Color(0x2692D64F), // lime 15%
    validBorder: Color(0x665C9130), // rgba(92,145,48,0.40)
    validInk: Color(0xFF3E6B1C),
    validIcon: Color(0xFF4E8526),
    errorFill: Color(0x1FC2403A), // rgba(194,64,58,0.12)
    errorBorder: Color(0x66C2403A), // rgba(194,64,58,0.40)
    errorInk: Color(0xFFB0352F),
    timeFill: Color(0x24F2D14B), // yellow 14%
    timeBorder: Color(0x59D8AF19), // rgba(216,175,25,0.35)
    timeInk: Color(0xFF6B5200),
    timeFigure: Color(0xFF6B5200),
    secondaryFill: Color(0x0A12161F), // ink 4%
    secondaryBorder: Color(0x2412161F), // ink 14%
    secondaryInk: Color(0xFF3F4756),
    disabledFill: Color(0x4092D64F), // lime 25%
    disabledInk: Color(0x8C12161F), // ink 55%
    cancelDanger: Color(0xFFB0352F),
  );

  static InvoicePalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
