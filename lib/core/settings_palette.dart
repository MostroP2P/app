import 'package:flutter/material.dart';

import 'package:mostro/core/order_book_palette.dart';

/// Tokens of the settings redesign (`design_handoff_configuracion`, variants
/// 10a · the grouped list, 10b · relays, 10c · the NWC wallet, 10d · push
/// notifications and 10e · the log report), added on top of
/// [OrderBookPalette], which it shares for surfaces and text roles.
///
/// Dark values are the handoff's. The handoff is dark-only, so [light] maps
/// each role onto the light surfaces the order book already uses, adjusted
/// where a text role would fail WCAG AA (4.5:1) on the surface it renders on.
/// `test/core/settings_palette_contrast_test.dart` locks every pair.
@immutable
class SettingsPalette {
  const SettingsPalette({
    required this.rowDivider,
    required this.groupHeader,
    required this.textMono,
    required this.placeholder,
    required this.dashedBorder,
    required this.dashedFill,
    required this.toggleOnBg,
    required this.toggleOnBorder,
    required this.toggleOnThumb,
    required this.toggleOffBg,
    required this.toggleOffBorder,
    required this.toggleOffThumb,
    required this.chipActiveBg,
    required this.chipActiveBorder,
    required this.chipActiveInk,
    required this.chipIdleBg,
    required this.chipIdleBorder,
    required this.chipIdleInk,
    required this.logDebugBg,
    required this.logDebugInk,
    required this.logInfoBg,
    required this.logInfoInk,
    required this.logWarnBg,
    required this.logWarnInk,
    required this.logErrBg,
    required this.logErrInk,
    required this.warnBg,
    required this.warnBorder,
    required this.warnInk,
    required this.summaryOkBorder,
    required this.summaryWarnBorder,
    required this.discBg,
    required this.discBorder,
    required this.dotOnline,
    required this.dotSlow,
    required this.dotOffline,
    required this.danger,
    required this.dangerBorder,
    required this.fieldUnderline,
    required this.fieldUnderlineFocus,
    required this.fieldLabel,
    required this.fieldLabelFocus,
    required this.buttonFill,
    required this.buttonBorder,
    required this.scanFill,
    required this.scanBorder,
    required this.ctaDisabledBg,
    required this.ctaDisabledInk,
    required this.ctaShadow,
  });

  /// Hairline between two rows of the same group card. The last row of a card
  /// has none — the card edge already separates it from the next group.
  final Color rowDivider;

  /// `APLICACIÓN` / `PAGOS` / `RED` / `AYUDA` above each card. The handoff's
  /// `#6B7589` is 3.9:1 on the page and 3.5:1 on a card, so both themes lift
  /// it to the nearest tone that passes AA.
  final Color groupHeader;

  /// Manrope runs that are data rather than prose: relay URLs, the NWC URI,
  /// log messages.
  final Color textMono;

  /// Field placeholder (`nostr+walletconnect://…`) and log timestamps.
  final Color placeholder;

  /// `Agregar relay` dashed border and fill.
  final Color dashedBorder;
  final Color dashedFill;

  /// Toggle, on. Replaces the Material switch: the old olive-on-green pair
  /// read the same in both states at a glance.
  final Color toggleOnBg;
  final Color toggleOnBorder;
  final Color toggleOnThumb;

  /// Toggle, off.
  final Color toggleOffBg;
  final Color toggleOffBorder;
  final Color toggleOffThumb;

  /// Log subsystem filter chip, selected.
  final Color chipActiveBg;
  final Color chipActiveBorder;
  final Color chipActiveInk;

  /// Log subsystem filter chip, unselected.
  final Color chipIdleBg;
  final Color chipIdleBorder;
  final Color chipIdleInk;

  /// Log level chips. `DEBUG` is not in the handoff's three-level table — it
  /// takes a neutral tint so the three levels that matter keep the colour.
  final Color logDebugBg;
  final Color logDebugInk;
  final Color logInfoBg;
  final Color logInfoInk;
  final Color logWarnBg;
  final Color logWarnInk;
  final Color logErrBg;
  final Color logErrInk;

  /// Amber: a setting that is unset or degraded (`Sin conectar`,
  /// `3 de 4 conectados`), and the system-permission banner of 10d.
  final Color warnBg;
  final Color warnBorder;
  final Color warnInk;

  /// Border of the relay summary card: lime when every relay is connected,
  /// amber as soon as one is not.
  final Color summaryOkBorder;
  final Color summaryWarnBorder;

  /// Tinted disc behind the relay and wallet glyphs.
  final Color discBg;
  final Color discBorder;

  /// Per-relay dots. [dotSlow] is only reachable once the connection manager
  /// publishes latency (see `relayRows`).
  final Color dotOnline;
  final Color dotSlow;
  final Color dotOffline;

  /// `Desconectar` ink and outline.
  final Color danger;
  final Color dangerBorder;

  /// The NWC URI field: underline and uppercase label, at rest and focused.
  final Color fieldUnderline;
  final Color fieldUnderlineFocus;
  final Color fieldLabel;
  final Color fieldLabelFocus;

  /// `Pegar` — the exception path, so it stays neutral.
  final Color buttonFill;
  final Color buttonBorder;

  /// `Escanear QR` — the real path, so it carries the lime tint.
  final Color scanFill;
  final Color scanBorder;

  /// `Conectar` with an empty or invalid URI.
  final Color ctaDisabledBg;
  final Color ctaDisabledInk;

  final List<BoxShadow> ctaShadow;

  static const dark = SettingsPalette(
    rowDivider: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    groupHeader: Color(0xFF808A9E), // #6B7589 lifted for AA
    textMono: Color(0xFFC3CBD9),
    placeholder: Color(0xFF808A9E), // #5D6879 lifted for AA
    dashedBorder: Color(0x29FFFFFF), // rgba(255,255,255,0.16)
    dashedFill: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    toggleOnBg: Color(0x3892D64F), // rgba(146,214,79,0.22)
    toggleOnBorder: Color(0x5992D64F), // rgba(146,214,79,0.35)
    toggleOnThumb: Color(0xFF92D64F),
    toggleOffBg: Color(0x17FFFFFF), // rgba(255,255,255,0.09)
    toggleOffBorder: Color(0x1FFFFFFF), // rgba(255,255,255,0.12)
    toggleOffThumb: Color(0xFF5D6879),
    chipActiveBg: Color(0x2492D64F), // rgba(146,214,79,0.14)
    chipActiveBorder: Color(0x4D92D64F), // rgba(146,214,79,0.30)
    chipActiveInk: Color(0xFFC6F09A),
    chipIdleBg: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    chipIdleBorder: Color(0x17FFFFFF), // rgba(255,255,255,0.09)
    chipIdleInk: Color(0xFFA6B0C2),
    logDebugBg: Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
    logDebugInk: Color(0xFFA6B0C2),
    logInfoBg: Color(0x2492D64F), // rgba(146,214,79,0.14)
    logInfoInk: Color(0xFFC6F09A),
    logWarnBg: Color(0x24F2D14B), // rgba(242,209,75,0.14)
    logWarnInk: Color(0xFFF7DE72),
    logErrBg: Color(0x24FF8B8B), // rgba(255,139,139,0.14)
    logErrInk: Color(0xFFFF8B8B),
    warnBg: Color(0x12F2D14B), // rgba(242,209,75,0.07)
    warnBorder: Color(0x2EF2D14B), // rgba(242,209,75,0.18)
    warnInk: Color(0xFFF7DE72),
    summaryOkBorder: Color(0x3892D64F), // rgba(146,214,79,0.22)
    summaryWarnBorder: Color(0x33F2D14B), // rgba(242,209,75,0.20)
    discBg: Color(0x1F92D64F), // rgba(146,214,79,0.12)
    discBorder: Color(0x3892D64F), // rgba(146,214,79,0.22)
    dotOnline: Color(0xFF92D64F),
    dotSlow: Color(0xFFF2D14B),
    dotOffline: Color(0xFF5D6879),
    danger: Color(0xFFFF8B8B),
    dangerBorder: Color(0x4DFF8B8B), // rgba(255,139,139,0.30)
    fieldUnderline: Color(0x1FFFFFFF), // rgba(255,255,255,0.12)
    fieldUnderlineFocus: Color(0xFF92D64F),
    fieldLabel: Color(0xFF808A9E), // #6B7589 lifted for AA
    fieldLabelFocus: Color(0xFFB7E38A),
    buttonFill: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    buttonBorder: Color(0x1AFFFFFF), // rgba(255,255,255,0.10)
    scanFill: Color(0x1F92D64F), // rgba(146,214,79,0.12)
    scanBorder: Color(0x4792D64F), // rgba(146,214,79,0.28)
    ctaDisabledBg: Color(0x2992D64F), // rgba(146,214,79,0.16)
    ctaDisabledInk: Color(0x8CC6F09A), // rgba(198,240,154,0.55)
    ctaShadow: [
      BoxShadow(
        color: Color(0xA692D64F), // rgba(146,214,79,0.65)
        offset: Offset(0, 10),
        blurRadius: 24,
        spreadRadius: -10,
      ),
    ],
  );

  static const light = SettingsPalette(
    rowDivider: Color(0x1412161F), // ink 8%
    groupHeader: Color(0xFF5F6979),
    textMono: Color(0xFF2A303C),
    placeholder: Color(0xFF5F6979),
    dashedBorder: Color(0x3312161F), // ink 20%
    dashedFill: Color(0x0A12161F), // ink 4%
    toggleOnBg: Color(0x4792D64F), // lime 28%
    toggleOnBorder: Color(0x8C5C9130), // rgba(92,145,48,0.55)
    toggleOnThumb: Color(0xFF5C9130),
    toggleOffBg: Color(0x1412161F), // ink 8%
    toggleOffBorder: Color(0x2412161F), // ink 14%
    toggleOffThumb: Color(0xFF8A94A6),
    chipActiveBg: Color(0x3392D64F), // lime 20%
    chipActiveBorder: Color(0x665C9130), // rgba(92,145,48,0.40)
    chipActiveInk: Color(0xFF3E6B1C),
    chipIdleBg: Color(0x0F12161F), // ink 6%
    chipIdleBorder: Color(0x1412161F), // ink 8%
    chipIdleInk: Color(0xFF3F4756),
    logDebugBg: Color(0x0F12161F), // ink 6%
    logDebugInk: Color(0xFF3F4756),
    logInfoBg: Color(0x3392D64F),
    logInfoInk: Color(0xFF3E6B1C),
    logWarnBg: Color(0x40F2D14B), // yellow 25%
    logWarnInk: Color(0xFF7A5D00),
    logErrBg: Color(0x33FF8B8B), // rgba(255,139,139,0.20)
    logErrInk: Color(0xFF9E2B26),
    warnBg: Color(0x40F2D14B),
    warnBorder: Color(0x73D8AF19), // rgba(216,175,25,0.45)
    warnInk: Color(0xFF7A5D00),
    summaryOkBorder: Color(0x665C9130),
    summaryWarnBorder: Color(0x73D8AF19),
    discBg: Color(0x3392D64F),
    discBorder: Color(0x665C9130),
    dotOnline: Color(0xFF5C9130),
    dotSlow: Color(0xFFD8AF19),
    dotOffline: Color(0xFF8A94A6),
    danger: Color(0xFFC2403A),
    dangerBorder: Color(0x66C2403A), // rgba(194,64,58,0.40)
    fieldUnderline: Color(0x2412161F), // ink 14%
    fieldUnderlineFocus: Color(0xFF5C9130),
    fieldLabel: Color(0xFF5F6979),
    fieldLabelFocus: Color(0xFF3E6B1C),
    buttonFill: Color(0x0A12161F), // ink 4%
    buttonBorder: Color(0x2412161F), // ink 14%
    scanFill: Color(0x3392D64F),
    scanBorder: Color(0x665C9130),
    ctaDisabledBg: Color(0x2992D64F),
    ctaDisabledInk: Color(0x8C3E6B1C),
    ctaShadow: [
      BoxShadow(
        color: Color(0x5992D64F), // lime 35%
        offset: Offset(0, 10),
        blurRadius: 24,
        spreadRadius: -10,
      ),
    ],
  );

  static SettingsPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
