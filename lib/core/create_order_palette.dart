import 'package:flutter/material.dart';

import 'package:mostro/core/order_book_palette.dart';

/// Tokens the create-order redesign (variants 5a · range at market price,
/// 5b · single amount at fixed price, 5c · component details) adds on top of
/// [OrderBookPalette], which it shares for surfaces, text roles and the
/// Buy tab.
///
/// Dark values are the handoff's. The handoff is dark-only, so [light] maps
/// each role onto the light surfaces the order book already uses, adjusted
/// where a text role would fail WCAG AA (4.5:1) on the surface it renders on.
/// `test/core/create_order_palette_contrast_test.dart` locks every pair.
@immutable
class CreateOrderPalette {
  const CreateOrderPalette({
    required this.fieldUnderline,
    required this.fieldUnderlineFocus,
    required this.fieldLabel,
    required this.fieldLabelFocus,
    required this.inset,
    required this.premiumGoodBg,
    required this.premiumGoodBorder,
    required this.premiumGoodLabel,
    required this.premiumGoodValue,
    required this.premiumBadBg,
    required this.premiumBadBorder,
    required this.premiumBadLabel,
    required this.premiumBadValue,
    required this.premiumZeroBg,
    required this.premiumZeroBorder,
    required this.premiumZeroLabel,
    required this.premiumZeroValue,
    required this.sliderTrack,
    required this.sliderZeroMark,
    required this.sellActiveBg,
    required this.sellActiveBorder,
    required this.sellInk,
    required this.ctaDisabledBg,
    required this.ctaDisabledInk,
    required this.dashedBorder,
    required this.error,
    required this.ctaShadow,
  });

  /// Resting underline of an amount field.
  final Color fieldUnderline;

  /// Focused underline (1.5px) and cursor.
  final Color fieldUnderlineFocus;

  /// Uppercase field label (`MÍNIMO` / `MÁXIMO`) at rest.
  final Color fieldLabel;

  /// The same label while its field has focus.
  final Color fieldLabelFocus;

  /// Currency selector row.
  final Color inset;

  /// Premium block when the premium plays in the maker's favour.
  final Color premiumGoodBg;
  final Color premiumGoodBorder;
  final Color premiumGoodLabel;
  final Color premiumGoodValue;

  /// Premium block when the premium plays against the maker.
  final Color premiumBadBg;
  final Color premiumBadBorder;
  final Color premiumBadLabel;
  final Color premiumBadValue;

  /// Premium block at exactly 0%.
  final Color premiumZeroBg;
  final Color premiumZeroBorder;
  final Color premiumZeroLabel;
  final Color premiumZeroValue;

  /// Unfilled part of the premium rail.
  final Color sliderTrack;

  /// The 0% tick on the rail.
  final Color sliderZeroMark;

  /// Active "Sell BTC" tab.
  final Color sellActiveBg;
  final Color sellActiveBorder;
  final Color sellInk;

  /// "Publish order" while the form is incomplete.
  final Color ctaDisabledBg;
  final Color ctaDisabledInk;

  /// Dashed border of the "Add" payment-method chip.
  final Color dashedBorder;

  /// Validation message and the underline of the field it names.
  final Color error;

  final List<BoxShadow> ctaShadow;

  static const dark = CreateOrderPalette(
    fieldUnderline: Color(0x24FFFFFF), // white 14%
    fieldUnderlineFocus: Color(0xFF92D64F),
    // Handoff #7E899E is 4.3:1 on the card — lightened to pass AA.
    fieldLabel: Color(0xFF8792A7),
    fieldLabelFocus: Color(0xFFB7E38A),
    inset: Color(0x0AFFFFFF), // white 4%
    premiumGoodBg: Color(0x1492D64F), // rgba(146,214,79,0.08)
    premiumGoodBorder: Color(0x3392D64F), // rgba(146,214,79,0.20)
    premiumGoodLabel: Color(0xFFB7E38A),
    premiumGoodValue: Color(0xFF92D64F),
    premiumBadBg: Color(0x12F2D14B), // rgba(242,209,75,0.07)
    premiumBadBorder: Color(0x2EF2D14B), // rgba(242,209,75,0.18)
    premiumBadLabel: Color(0xFFF7DE72),
    premiumBadValue: Color(0xFFF7DE72),
    premiumZeroBg: Color(0x0AFFFFFF), // white 4%
    premiumZeroBorder: Color(0x12FFFFFF), // white 7%
    premiumZeroLabel: Color(0xFF8B97AD),
    premiumZeroValue: Color(0xFFD6DCE8),
    sliderTrack: Color(0x1AFFFFFF), // white 10%
    sliderZeroMark: Color(0x38FFFFFF), // white 22%
    sellActiveBg: Color(0x24FF8B8B), // rgba(255,139,139,0.14)
    sellActiveBorder: Color(0x4DFF8B8B), // rgba(255,139,139,0.30)
    sellInk: Color(0xFFFFB4B4),
    ctaDisabledBg: Color(0x2992D64F), // rgba(146,214,79,0.16)
    ctaDisabledInk: Color(0x8CC6F09A), // rgba(198,240,154,0.55)
    dashedBorder: Color(0x29FFFFFF), // white 16%
    error: Color(0xFFFF8B8B),
    ctaShadow: [
      BoxShadow(
        color: Color(0xA692D64F), // rgba(146,214,79,0.65)
        offset: Offset(0, 10),
        blurRadius: 24,
        spreadRadius: -10,
      ),
    ],
  );

  static const light = CreateOrderPalette(
    fieldUnderline: Color(0x2E12161F), // ink 18%
    fieldUnderlineFocus: Color(0xFF5C9130),
    fieldLabel: Color(0xFF5A6474),
    fieldLabelFocus: Color(0xFF3E6B1C),
    inset: Color(0x0A12161F), // ink 4%
    premiumGoodBg: Color(0x1F92D64F), // lime 12%
    premiumGoodBorder: Color(0x5C5C9130), // rgba(92,145,48,0.36)
    premiumGoodLabel: Color(0xFF3E6B1C),
    premiumGoodValue: Color(0xFF3E6B1C),
    premiumBadBg: Color(0x24F2D14B), // yellow 14%
    premiumBadBorder: Color(0x59D8AF19), // rgba(216,175,25,0.35)
    premiumBadLabel: Color(0xFF7A5D00),
    premiumBadValue: Color(0xFF7A5D00),
    premiumZeroBg: Color(0x0A12161F),
    premiumZeroBorder: Color(0x1412161F),
    premiumZeroLabel: Color(0xFF5A6474),
    premiumZeroValue: Color(0xFF2A303C),
    sliderTrack: Color(0x1F12161F), // ink 12%
    sliderZeroMark: Color(0x4712161F), // ink 28%
    sellActiveBg: Color(0x2EFF8B8B), // rgba(255,139,139,0.18)
    sellActiveBorder: Color(0x66C2453F), // rgba(194,69,63,0.40)
    sellInk: Color(0xFF9A2F2A),
    ctaDisabledBg: Color(0x3892D64F), // lime 22%
    ctaDisabledInk: Color(0xB33E6B1C), // rgba(62,107,28,0.70)
    dashedBorder: Color(0x3312161F), // ink 20%
    error: Color(0xFFC2403A),
    ctaShadow: [
      BoxShadow(
        color: Color(0x6692D64F), // lime 40%
        offset: Offset(0, 10),
        blurRadius: 24,
        spreadRadius: -10,
      ),
    ],
  );

  static CreateOrderPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
