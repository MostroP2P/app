import 'package:flutter/material.dart';

/// Palette of the order-book handoff (`design_handoff_orderbook`, variants
/// 4b · order card and 4d · create-order button), shared by the bottom bar.
///
/// Dark values are the handoff's tokens. The handoff is dark-only, so [light]
/// is a legibility mapping onto the drawer's light (3c) surfaces. Where a text
/// role fails WCAG AA (4.5:1) on the surface it really renders on it is
/// adjusted just enough to pass — in dark only [textFaint]. Every text-role /
/// surface pair is locked by `test/core/order_book_palette_contrast_test.dart`.
@immutable
class OrderBookPalette {
  const OrderBookPalette({
    required this.bg,
    required this.surface,
    required this.surfaceNav,
    required this.inset,
    required this.border,
    required this.borderHighlight,
    required this.pressed,
    required this.lime,
    required this.onLime,
    required this.limeText,
    required this.limeInk,
    required this.limeIcon,
    required this.sell,
    required this.onSell,
    required this.yellow,
    required this.yellowInk,
    required this.premiumMid,
    required this.premiumHigh,
    required this.textPrimary,
    required this.textStrong,
    required this.textBody,
    required this.textMuted,
    required this.textSecondary,
    required this.textTertiary,
    required this.textFaint,
    required this.textNew,
    required this.sortLabel,
    required this.starEmpty,
    required this.divider,
    required this.notif,
    required this.tabTrack,
    required this.tabActiveFill,
    required this.tabActiveBorder,
    required this.chipFill,
    required this.chipBorder,
    required this.currencyChipFill,
    required this.bestChipFill,
    required this.bestChipBorder,
    required this.reputableChipFill,
    required this.reputableChipBorder,
    required this.navBorder,
    required this.scrim,
    required this.scrimText,
    required this.fabClose,
    required this.fabCloseBorder,
    required this.fabCloseIcon,
    required this.fabShadow,
    required this.buyShadow,
    required this.sellShadow,
  });

  /// Page background.
  final Color bg;

  /// Order card.
  final Color surface;

  /// Bottom navigation bar.
  final Color surfaceNav;

  /// Reputation strip inside a card (translucent over [surface]).
  final Color inset;

  /// Card hairline.
  final Color border;

  /// Border of the best-premium card — the one highlighted card per list.
  final Color borderHighlight;

  /// Ink highlight of a pressed card.
  final Color pressed;

  /// Brand fill: the create-order button and the Buy button.
  final Color lime;
  final Color onLime;

  /// Lime used as text or icon on a surface: active destination, premium in
  /// the taker's favour, the clear-filters action. In light it is darkened,
  /// since [lime] itself is unreadable on white.
  final Color limeText;

  /// Text on lime tints: the active tab, the best-premium chip, the sats
  /// figure.
  final Color limeInk;

  /// The filter chip's funnel.
  final Color limeIcon;

  /// The Sell button.
  final Color sell;
  final Color onSell;

  /// Rating star.
  final Color yellow;

  /// Most-reputable chip text.
  final Color yellowInk;

  /// Premium up to 3 points against the taker.
  final Color premiumMid;

  /// Premium more than 3 points against the taker.
  final Color premiumHigh;

  final Color textPrimary;
  final Color textStrong;
  final Color textBody;
  final Color textMuted;
  final Color textSecondary;
  final Color textTertiary;

  /// Relative time and the "premium" caption.
  final Color textFaint;

  /// "New" in place of the rating of a maker without trades.
  final Color textNew;

  /// Current sort criterion on the filter row.
  final Color sortLabel;

  /// Rating star of a maker nobody has rated.
  final Color starEmpty;

  /// `|` separators of the reputation strip.
  final Color divider;

  /// Notification dot.
  final Color notif;

  final Color tabTrack;
  final Color tabActiveFill;
  final Color tabActiveBorder;

  /// "Filter" chip.
  final Color chipFill;
  final Color chipBorder;

  final Color currencyChipFill;
  final Color bestChipFill;
  final Color bestChipBorder;
  final Color reputableChipFill;
  final Color reputableChipBorder;

  /// Top edge of the bottom bar.
  final Color navBorder;

  /// Full-screen scrim of the open create-order button.
  final Color scrim;

  /// "Tap outside to close" on the scrim.
  final Color scrimText;

  /// The create-order button in its open (✕) state.
  final Color fabClose;
  final Color fabCloseBorder;
  final Color fabCloseIcon;

  final List<BoxShadow> fabShadow;
  final List<BoxShadow> buyShadow;
  final List<BoxShadow> sellShadow;

  static const dark = OrderBookPalette(
    bg: Color(0xFF12161F),
    surface: Color(0xFF1A2030),
    surfaceNav: Color(0xFF151A24),
    inset: Color(0x0AFFFFFF), // white 4%
    border: Color(0x0FFFFFFF), // white 6%
    borderHighlight: Color(0x3892D64F), // rgba(146,214,79,0.22)
    pressed: Color(0x0DFFFFFF), // white 5%
    lime: Color(0xFF92D64F),
    onLime: Color(0xFF12161F),
    limeText: Color(0xFF92D64F),
    limeInk: Color(0xFFC6F09A),
    limeIcon: Color(0xFFB7E38A),
    sell: Color(0xFFFF8B8B),
    onSell: Color(0xFF2A1015),
    yellow: Color(0xFFF2D14B),
    yellowInk: Color(0xFFF7DE72),
    premiumMid: Color(0xFFC9A24D),
    premiumHigh: Color(0xFFD9A84E),
    textPrimary: Color(0xFFEEF1F6),
    textStrong: Color(0xFFE4E9F2),
    textBody: Color(0xFFD6DCE8),
    textMuted: Color(0xFFA6B0C2),
    textSecondary: Color(0xFF8B97AD),
    textTertiary: Color(0xFF7E899E),
    // Handoff #6B7589 is 3.5:1 on the card — lightened to pass AA.
    textFaint: Color(0xFF808A9E),
    textNew: Color(0xFFB8C0CF),
    sortLabel: Color(0xFF9AA4B8),
    starEmpty: Color(0xFF5D6879),
    divider: Color(0xFF4A5364),
    notif: Color(0xFFFF6B6B),
    tabTrack: Color(0x0DFFFFFF), // white 5%
    tabActiveFill: Color(0x2992D64F), // rgba(146,214,79,0.16)
    tabActiveBorder: Color(0x4D92D64F), // rgba(146,214,79,0.30)
    chipFill: Color(0x0DFFFFFF), // white 5%
    chipBorder: Color(0x12FFFFFF), // white 7%
    currencyChipFill: Color(0x0FFFFFFF), // white 6%
    bestChipFill: Color(0x2492D64F), // rgba(146,214,79,0.14)
    bestChipBorder: Color(0x4D92D64F), // rgba(146,214,79,0.30)
    reputableChipFill: Color(0x24F2D14B), // rgba(242,209,75,0.14)
    reputableChipBorder: Color(0x4DF2D14B), // rgba(242,209,75,0.30)
    navBorder: Color(0x12FFFFFF), // white 7%
    scrim: Color(0xD1080B10), // rgba(8,11,16,0.82)
    scrimText: Color(0xFF7E899E),
    fabClose: Color(0xFF2A3244),
    fabCloseBorder: Color(0x1AFFFFFF), // white 10%
    fabCloseIcon: Color(0xFFE4E9F2),
    fabShadow: [
      BoxShadow(
        color: Color(0x8C92D64F), // rgba(146,214,79,0.55)
        offset: Offset(0, 10),
        blurRadius: 24,
        spreadRadius: -6,
      ),
    ],
    buyShadow: [
      BoxShadow(
        color: Color(0x9992D64F), // rgba(146,214,79,0.60)
        offset: Offset(0, 10),
        blurRadius: 26,
        spreadRadius: -8,
      ),
    ],
    sellShadow: [
      BoxShadow(
        color: Color(0x73FF8B8B), // rgba(255,139,139,0.45)
        offset: Offset(0, 10),
        blurRadius: 26,
        spreadRadius: -8,
      ),
    ],
  );

  static const light = OrderBookPalette(
    bg: Color(0xFFF4F6F4),
    surface: Color(0xFFFFFFFF),
    surfaceNav: Color(0xFFFFFFFF),
    inset: Color(0x0A12161F), // ink 4%
    border: Color(0x1412161F), // ink 8%
    borderHighlight: Color(0x735C9130), // rgba(92,145,48,0.45)
    pressed: Color(0x0A12161F),
    lime: Color(0xFF92D64F),
    onLime: Color(0xFF12161F),
    limeText: Color(0xFF3E6B1C),
    limeInk: Color(0xFF3E6B1C),
    limeIcon: Color(0xFF4E7D28),
    sell: Color(0xFFFF8B8B),
    onSell: Color(0xFF2A1015),
    yellow: Color(0xFFE0B72C),
    yellowInk: Color(0xFF7A5D00),
    premiumMid: Color(0xFF7A5A12),
    premiumHigh: Color(0xFF9A4A0E),
    textPrimary: Color(0xFF12161F),
    textStrong: Color(0xFF1E2430),
    textBody: Color(0xFF2A303C),
    textMuted: Color(0xFF3F4756),
    textSecondary: Color(0xFF5A6474),
    textTertiary: Color(0xFF5F6979),
    textFaint: Color(0xFF636D7D),
    textNew: Color(0xFF4A5364),
    sortLabel: Color(0xFF4A5364),
    starEmpty: Color(0xFFA3ACBA),
    divider: Color(0xFFC3CAD6),
    notif: Color(0xFFE5484D),
    tabTrack: Color(0x0F12161F), // ink 6%
    tabActiveFill: Color(0x3392D64F), // lime 20%
    tabActiveBorder: Color(0x665C9130), // rgba(92,145,48,0.40)
    chipFill: Color(0xFFFFFFFF),
    chipBorder: Color(0x1412161F),
    currencyChipFill: Color(0x0F12161F),
    bestChipFill: Color(0x3392D64F),
    bestChipBorder: Color(0x665C9130),
    reputableChipFill: Color(0x40F2D14B), // yellow 25%
    reputableChipBorder: Color(0x73D8AF19), // rgba(216,175,25,0.45)
    navBorder: Color(0x1412161F),
    scrim: Color(0xD1080B10),
    // The scrim darkens a white page far less than a dark one, so the hint
    // needs a lighter tone than dark's to stay readable on it.
    scrimText: Color(0xFFA6B0C2),
    fabClose: Color(0xFF2A3244),
    fabCloseBorder: Color(0x1AFFFFFF),
    fabCloseIcon: Color(0xFFE4E9F2),
    fabShadow: [
      BoxShadow(
        color: Color(0x5992D64F), // lime 35%
        offset: Offset(0, 10),
        blurRadius: 24,
        spreadRadius: -6,
      ),
    ],
    buyShadow: [
      BoxShadow(
        color: Color(0x6692D64F), // lime 40%
        offset: Offset(0, 10),
        blurRadius: 26,
        spreadRadius: -8,
      ),
    ],
    sellShadow: [
      BoxShadow(
        color: Color(0x4DFF8B8B), // rgba(255,139,139,0.30)
        offset: Offset(0, 10),
        blurRadius: 26,
        spreadRadius: -8,
      ),
    ],
  );

  static OrderBookPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
