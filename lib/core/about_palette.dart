import 'package:flutter/material.dart';

import 'package:mostro/core/order_book_palette.dart';

/// Tokens of the About redesign (`design_handoff_acerca_de`, variants 12a ·
/// About and 12b · Technical data), added on top of [OrderBookPalette], which
/// it shares for the page, the card surface and the text roles.
///
/// Dark values are the handoff's. The handoff is dark-only, so [light] maps
/// each role onto the light surfaces the order book already uses, adjusted
/// where a text role would fail WCAG AA (4.5:1) on the surface it renders on.
/// `test/core/about_palette_contrast_test.dart` locks every pair.
@immutable
class AboutPalette {
  const AboutPalette({
    required this.rowDivider,
    required this.cell,
    required this.groupHeader,
    required this.icon,
    required this.chevron,
    required this.accent,
    required this.logoFill,
    required this.pillFill,
    required this.pillBorder,
    required this.actionFill,
    required this.actionBorder,
    required this.noteFill,
    required this.noteBorder,
    required this.dotOnline,
    required this.dotPending,
    required this.dotOffline,
  });

  /// Hairline between the rows of a card.
  final Color rowDivider;

  /// The three limit cells of the connected-node card.
  final Color cell;

  /// `APPLICATION`, `MOSTRO`… above each card, and the limits footnote. The
  /// handoff's `#6B7589` is 3.5:1 on the card, so dark lifts it to AA.
  final Color groupHeader;

  /// Copy, server and info icons.
  final Color icon;

  /// Chevron and external-link icon at the end of a row.
  final Color chevron;

  /// Lime ink: version pill, the header copy action, `Copy all data`, and the
  /// check a copy icon turns into.
  final Color accent;

  /// Behind the logo.
  final Color logoFill;

  /// Version pill.
  final Color pillFill;
  final Color pillBorder;

  /// `Copy all data`.
  final Color actionFill;
  final Color actionBorder;

  /// The footnote box of 12b.
  final Color noteFill;
  final Color noteBorder;

  /// Connected-node dot: answered, still waiting, not responding.
  final Color dotOnline;
  final Color dotPending;
  final Color dotOffline;

  static const dark = AboutPalette(
    rowDivider: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    cell: Color(0x09FFFFFF), // rgba(255,255,255,0.035)
    groupHeader: Color(0xFF808A9E), // #6B7589 lifted for AA on the card
    icon: Color(0xFF7E899E),
    chevron: Color(0xFF5D6879),
    accent: Color(0xFF92D64F),
    logoFill: Color(0x1A92D64F), // rgba(146,214,79,0.10)
    pillFill: Color(0x1F92D64F), // rgba(146,214,79,0.12)
    pillBorder: Color(0x3892D64F), // rgba(146,214,79,0.22)
    actionFill: Color(0x1A92D64F), // rgba(146,214,79,0.10)
    actionBorder: Color(0x4092D64F), // rgba(146,214,79,0.25)
    noteFill: Color(0x08FFFFFF), // rgba(255,255,255,0.03)
    noteBorder: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    dotOnline: Color(0xFF92D64F),
    dotPending: Color(0xFFF7DE72),
    dotOffline: Color(0xFFE4685D),
  );

  static const light = AboutPalette(
    rowDivider: Color(0x1412161F), // ink 8%
    cell: Color(0x0A12161F), // ink 4%
    groupHeader: Color(0xFF636D7D),
    icon: Color(0xFF5F6979),
    chevron: Color(0xFF8A94A6),
    accent: Color(0xFF3E6B1C),
    logoFill: Color(0x2692D64F), // lime 15%
    pillFill: Color(0x3392D64F), // lime 20%
    pillBorder: Color(0x665C9130), // rgba(92,145,48,0.40)
    actionFill: Color(0x2692D64F), // lime 15%
    actionBorder: Color(0x665C9130),
    noteFill: Color(0x0A12161F), // ink 4%
    noteBorder: Color(0x1412161F), // ink 8%
    dotOnline: Color(0xFF5C9130),
    dotPending: Color(0xFFD8AF19),
    dotOffline: Color(0xFFC2403A),
  );

  static AboutPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
