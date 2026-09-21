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
    required this.promptFill,
    required this.promptBorder,
    required this.promptBorderPeak,
    required this.promptHalo,
    required this.filledBorder,
    required this.textareaFill,
    required this.textareaBorder,
    required this.placeholder,
    required this.pasteFill,
    required this.pasteBorder,
    required this.fieldActionFill,
    required this.fieldActionBorder,
    required this.fieldActionInk,
    required this.fieldActionIcon,
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

  /// The empty invoice field asking to be filled
  /// (`design_handoff_campo_factura`, 17a): fill, border at rest and at the
  /// peak of its pulse, and the halo around it at the peak.
  final Color promptFill;
  final Color promptBorder;
  final Color promptBorderPeak;
  final Color promptHalo;

  /// The field once it holds an invoice (17b).
  final Color filledBorder;

  /// The three-line text area inside the field, and its placeholder.
  final Color textareaFill;
  final Color textareaBorder;
  final Color placeholder;

  /// `Paste`, the expected action while the field is empty.
  final Color pasteFill;
  final Color pasteBorder;

  /// `Scan` / `Replace` under the field.
  final Color fieldActionFill;
  final Color fieldActionBorder;
  final Color fieldActionInk;
  final Color fieldActionIcon;

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
    disabledFill: Color(0x2992D64F), // rgba(146,214,79,0.16)
    disabledInk: Color(0xFF6E8F4B),
    cancelDanger: Color(0xFFE4685D),
    promptFill: Color(0x0F92D64F), // rgba(146,214,79,0.06)
    promptBorder: Color(0x7392D64F), // rgba(146,214,79,0.45)
    promptBorderPeak: Color(0xF292D64F), // rgba(146,214,79,0.95)
    promptHalo: Color(0x1A92D64F), // rgba(146,214,79,0.10)
    filledBorder: Color(0x9992D64F), // rgba(146,214,79,0.60)
    textareaFill: Color(0xFF0F131C),
    textareaBorder: Color(0x4092D64F), // rgba(146,214,79,0.25)
    // The handoff's #6C7789 reads 4.1:1 on the text area; textTertiary
    // clears AA.
    placeholder: Color(0xFF7E899E),
    pasteFill: Color(0x2492D64F), // rgba(146,214,79,0.14)
    pasteBorder: Color(0x5992D64F), // rgba(146,214,79,0.35)
    fieldActionFill: Color(0x0AFFFFFF), // rgba(255,255,255,0.04)
    fieldActionBorder: Color(0x1AFFFFFF), // rgba(255,255,255,0.10)
    fieldActionInk: Color(0xFFC3CBD9),
    fieldActionIcon: Color(0xFFA6B0C2),
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
    promptFill: Color(0x1492D64F), // lime 8%
    promptBorder: Color(0x735C9130), // rgba(92,145,48,0.45)
    promptBorderPeak: Color(0xF25C9130), // rgba(92,145,48,0.95)
    promptHalo: Color(0x265C9130), // rgba(92,145,48,0.15)
    filledBorder: Color(0x995C9130), // rgba(92,145,48,0.60)
    textareaFill: Color(0xFFFFFFFF),
    textareaBorder: Color(0x595C9130), // rgba(92,145,48,0.35)
    placeholder: Color(0xFF5F6979),
    pasteFill: Color(0x2E92D64F), // lime 18%
    pasteBorder: Color(0x735C9130), // rgba(92,145,48,0.45)
    fieldActionFill: Color(0x0A12161F), // ink 4%
    fieldActionBorder: Color(0x2412161F), // ink 14%
    fieldActionInk: Color(0xFF3F4756),
    fieldActionIcon: Color(0xFF5F6979),
  );

  static InvoicePalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
