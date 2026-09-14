import 'package:flutter/material.dart';

import 'package:mostro/core/order_book_palette.dart';

/// Tokens of the node-selector redesign (`design_handoff_selector_nodo`,
/// variants 9a · the sheet and 9b · the custom-node dialog and availability
/// states), added on top of [OrderBookPalette], which it shares for surfaces
/// and text roles.
///
/// Dark values are the handoff's. The handoff is dark-only, so [light] maps
/// each role onto the light surfaces the order book already uses, adjusted
/// where a text role would fail WCAG AA (4.5:1) on the surface it renders on.
/// `test/core/node_selector_palette_contrast_test.dart` locks every pair.
@immutable
class NodeSelectorPalette {
  const NodeSelectorPalette({
    required this.border,
    required this.borderSelected,
    required this.inset,
    required this.colDivider,
    required this.stripText,
    required this.rowDivider,
    required this.chipMineBg,
    required this.chipMineBorder,
    required this.chipMineInk,
    required this.chipNeutralBg,
    required this.chipNeutralInk,
    required this.trustedBg,
    required this.trustedBorder,
    required this.trustedInk,
    required this.warnBg,
    required this.warnBorder,
    required this.warnInk,
    required this.dashedBorder,
    required this.dashedFill,
    required this.figureLime,
    required this.dotOnline,
    required this.dotWarn,
    required this.dotOffline,
    required this.danger,
    required this.radioBorder,
    required this.avatarLimeBg,
    required this.avatarYellowBg,
    required this.avatarLimeInk,
    required this.avatarYellowInk,
    required this.fieldUnderline,
    required this.fieldUnderlineFocus,
    required this.fieldLabel,
    required this.fieldLabelFocus,
    required this.buttonBorder,
    required this.ctaDisabledBg,
    required this.ctaDisabledInk,
    required this.dialogShadow,
  });

  /// Resting card border.
  final Color border;

  /// Border of the selected card.
  final Color borderSelected;

  /// Metrics strip fill.
  final Color inset;

  /// Vertical separators between the three metric columns.
  final Color colDivider;

  /// Units, labels and the fiat line on the metrics strip. The handoff's
  /// `#7E899E` / `#6B7589` fall under AA on the tinted strip, so dark lifts
  /// them just enough.
  final Color stripText;

  /// Top border of the trust row.
  final Color rowDivider;

  /// Currency chip of the user's own fiat.
  final Color chipMineBg;
  final Color chipMineBorder;
  final Color chipMineInk;

  /// Every other currency chip, and the `+N` overflow chip.
  final Color chipNeutralBg;
  final Color chipNeutralInk;

  /// `DE CONFIANZA` chip.
  final Color trustedBg;
  final Color trustedBorder;
  final Color trustedInk;

  /// Amber `SIN ARS` chip, the dialog's warning box, and `Bond: no compatible`
  /// / `· 0 en ARS` figures.
  final Color warnBg;
  final Color warnBorder;
  final Color warnInk;

  /// `Agregar nodo propio` dashed border and fill.
  final Color dashedBorder;
  final Color dashedFill;

  /// The liquidity figure — the only lime number on the card.
  final Color figureLime;

  /// Availability dots.
  final Color dotOnline;
  final Color dotWarn;
  final Color dotOffline;

  /// Invalid-pubkey underline and error line.
  final Color danger;

  /// Unselected radio ring.
  final Color radioBorder;

  /// Fallback avatar (initial on a tinted disc), tint derived from the name.
  final Color avatarLimeBg;
  final Color avatarYellowBg;
  final Color avatarLimeInk;
  final Color avatarYellowInk;

  /// Dialog fields: underline and uppercase label, at rest and focused.
  final Color fieldUnderline;
  final Color fieldUnderlineFocus;
  final Color fieldLabel;
  final Color fieldLabelFocus;

  /// `Cancelar` outline.
  final Color buttonBorder;

  /// `Agregar` while the key is empty or invalid.
  final Color ctaDisabledBg;
  final Color ctaDisabledInk;

  final List<BoxShadow> dialogShadow;

  static const dark = NodeSelectorPalette(
    border: Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
    borderSelected: Color(0x4D92D64F), // rgba(146,214,79,0.30)
    inset: Color(0x0AFFFFFF), // rgba(255,255,255,0.04)
    colDivider: Color(0x12FFFFFF), // rgba(255,255,255,0.07)
    stripText: Color(0xFF8590A4), // #7E899E lifted for AA on the strip
    rowDivider: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    chipMineBg: Color(0x2492D64F), // rgba(146,214,79,0.14)
    chipMineBorder: Color(0x4D92D64F), // rgba(146,214,79,0.30)
    chipMineInk: Color(0xFFC6F09A),
    chipNeutralBg: Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
    chipNeutralInk: Color(0xFFA6B0C2),
    trustedBg: Color(0x1F92D64F), // rgba(146,214,79,0.12)
    trustedBorder: Color(0x4292D64F), // rgba(146,214,79,0.26)
    trustedInk: Color(0xFFC6F09A),
    warnBg: Color(0x12F2D14B), // rgba(242,209,75,0.07)
    warnBorder: Color(0x2EF2D14B), // rgba(242,209,75,0.18)
    warnInk: Color(0xFFF7DE72),
    dashedBorder: Color(0x29FFFFFF), // rgba(255,255,255,0.16)
    dashedFill: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    figureLime: Color(0xFF92D64F),
    dotOnline: Color(0xFF92D64F),
    dotWarn: Color(0xFFF2D14B),
    dotOffline: Color(0xFF5D6879),
    danger: Color(0xFFFF8B8B),
    radioBorder: Color(0x29FFFFFF), // rgba(255,255,255,0.16)
    avatarLimeBg: Color(0x2492D64F), // rgba(146,214,79,0.14)
    avatarYellowBg: Color(0x24F2D14B), // rgba(242,209,75,0.14)
    avatarLimeInk: Color(0xFFC6F09A),
    avatarYellowInk: Color(0xFFF7DE72),
    fieldUnderline: Color(0x24FFFFFF), // rgba(255,255,255,0.14)
    fieldUnderlineFocus: Color(0xFF92D64F),
    fieldLabel: Color(0xFF808A9E), // #6B7589 lifted for AA on the card
    fieldLabelFocus: Color(0xFFB7E38A),
    buttonBorder: Color(0x24FFFFFF), // rgba(255,255,255,0.14)
    ctaDisabledBg: Color(0x2992D64F), // rgba(146,214,79,0.16)
    ctaDisabledInk: Color(0x8CC6F09A), // rgba(198,240,154,0.55)
    dialogShadow: [
      BoxShadow(
        color: Color(0xBF000000), // rgba(0,0,0,0.75)
        offset: Offset(0, 24),
        blurRadius: 60,
        spreadRadius: -20,
      ),
    ],
  );

  static const light = NodeSelectorPalette(
    border: Color(0x1412161F), // ink 8%
    borderSelected: Color(0x735C9130), // rgba(92,145,48,0.45)
    inset: Color(0x0A12161F), // ink 4%
    colDivider: Color(0x1F12161F), // ink 12%
    stripText: Color(0xFF636D7D),
    rowDivider: Color(0x1412161F), // ink 8%
    chipMineBg: Color(0x3392D64F), // lime 20%
    chipMineBorder: Color(0x665C9130), // rgba(92,145,48,0.40)
    chipMineInk: Color(0xFF3E6B1C),
    chipNeutralBg: Color(0x0F12161F), // ink 6%
    chipNeutralInk: Color(0xFF3F4756),
    trustedBg: Color(0x3392D64F),
    trustedBorder: Color(0x665C9130),
    trustedInk: Color(0xFF3E6B1C),
    warnBg: Color(0x40F2D14B), // yellow 25%
    warnBorder: Color(0x73D8AF19), // rgba(216,175,25,0.45)
    warnInk: Color(0xFF7A5D00),
    dashedBorder: Color(0x3312161F), // ink 20%
    dashedFill: Color(0x0A12161F), // ink 4%
    figureLime: Color(0xFF3E6B1C),
    dotOnline: Color(0xFF5C9130),
    dotWarn: Color(0xFFD8AF19),
    dotOffline: Color(0xFF8A94A6),
    danger: Color(0xFFC2403A),
    radioBorder: Color(0x3312161F), // ink 20%
    avatarLimeBg: Color(0x3392D64F),
    avatarYellowBg: Color(0x40F2D14B),
    avatarLimeInk: Color(0xFF3E6B1C),
    avatarYellowInk: Color(0xFF7A5D00),
    fieldUnderline: Color(0x2412161F), // ink 14%
    fieldUnderlineFocus: Color(0xFF5C9130),
    fieldLabel: Color(0xFF636D7D),
    fieldLabelFocus: Color(0xFF3E6B1C),
    buttonBorder: Color(0x2412161F),
    ctaDisabledBg: Color(0x2992D64F),
    ctaDisabledInk: Color(0x8C3E6B1C),
    dialogShadow: [
      BoxShadow(
        color: Color(0x4D000000), // rgba(0,0,0,0.30)
        offset: Offset(0, 24),
        blurRadius: 60,
        spreadRadius: -20,
      ),
    ],
  );

  static NodeSelectorPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
