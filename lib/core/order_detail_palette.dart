import 'package:flutter/material.dart';

import 'package:mostro/core/order_book_palette.dart';

/// Tokens the order-detail redesign adds on top of [OrderBookPalette]: the
/// maker's own order (handoff 6a · screen, 6b · status states) and the
/// taker's view of someone else's order (handoff 7a).
///
/// Dark values are the handoffs'. Both are dark-only, so [light] maps each
/// role onto the light surfaces the order book already uses, adjusted where
/// a text role would fail WCAG AA (4.5:1) on the surface it renders on.
/// `test/core/order_detail_palette_contrast_test.dart` locks every pair.
@immutable
class OrderDetailPalette {
  const OrderDetailPalette({
    required this.rowDivider,
    required this.sellChipBg,
    required this.sellChipBorder,
    required this.sellInk,
    required this.buyChipBg,
    required this.buyChipBorder,
    required this.buyInk,
    required this.statusWaitBg,
    required this.statusWaitBorder,
    required this.statusWaitDot,
    required this.statusWaitRing,
    required this.statusWaitText,
    required this.statusWaitAside,
    required this.statusHoldBg,
    required this.statusHoldBorder,
    required this.statusHoldDot,
    required this.statusHoldText,
    required this.statusDeadBg,
    required this.statusDeadBorder,
    required this.statusDeadDot,
    required this.statusDeadText,
    required this.statusDeadAside,
    required this.statusCancelBg,
    required this.statusCancelBorder,
    required this.statusCancelDot,
    required this.statusCancelText,
    required this.progressTrack,
    required this.progressFill,
    required this.danger,
    required this.dangerBorder,
    required this.avatarBg,
    required this.avatarBorder,
    required this.avatarNewBg,
    required this.avatarNewBorder,
    required this.ctaLoadingBg,
    required this.ctaLoadingInk,
    required this.ctaLoadingRing,
    required this.ctaDeadBg,
    required this.ctaDeadBorder,
    required this.ctaDeadInk,
    required this.sheetHandle,
    required this.ctaShadow,
  });

  /// Hairline between the rows of the data card.
  final Color rowDivider;

  /// `SELLING BTC` chip on the maker's own sell order.
  final Color sellChipBg;
  final Color sellChipBorder;
  final Color sellInk;

  /// `BUYING BTC` chip on the maker's own buy order.
  final Color buyChipBg;
  final Color buyChipBorder;
  final Color buyInk;

  /// Status block while the order waits for a taker — and, by family, once
  /// the trade completed.
  final Color statusWaitBg;
  final Color statusWaitBorder;
  final Color statusWaitDot;

  /// Halo around the pulsing dot.
  final Color statusWaitRing;
  final Color statusWaitText;

  /// The countdown on the right of the row.
  final Color statusWaitAside;

  /// Status block once the order is taken and a payment is pending.
  final Color statusHoldBg;
  final Color statusHoldBorder;
  final Color statusHoldDot;

  /// Label and countdown of the hold state.
  final Color statusHoldText;

  /// Status block of an expired order.
  final Color statusDeadBg;
  final Color statusDeadBorder;
  final Color statusDeadDot;
  final Color statusDeadText;

  /// "2 h ago" on the right of the expired row. The handoff's #7E899E is
  /// 4.1:1 on the tinted box in dark — lifted to pass AA.
  final Color statusDeadAside;

  /// Status block of a cancelled order — and, by family, a disputed one.
  final Color statusCancelBg;
  final Color statusCancelBorder;
  final Color statusCancelDot;
  final Color statusCancelText;

  /// Elapsed-life bar under the waiting row.
  final Color progressTrack;
  final Color progressFill;

  /// `Cancel` text and border; the countdown under five minutes.
  final Color danger;
  final Color dangerBorder;

  /// Rating avatar of the counterparty card.
  final Color avatarBg;
  final Color avatarBorder;

  /// The same avatar for a maker nobody has rated.
  final Color avatarNewBg;
  final Color avatarNewBorder;

  /// `Take order` while the relay answers. Light ink on a lime tint — the
  /// dark ink of the resting button does not read on it.
  final Color ctaLoadingBg;
  final Color ctaLoadingInk;
  final Color ctaLoadingRing;

  /// `Take order` once the order is gone.
  final Color ctaDeadBg;
  final Color ctaDeadBorder;
  final Color ctaDeadInk;

  /// Drag handle of the cancel confirmation sheet.
  final Color sheetHandle;

  /// Shadow under the filled lime button.
  final List<BoxShadow> ctaShadow;

  static const dark = OrderDetailPalette(
    rowDivider: Color(0x0DFFFFFF), // white 5%
    sellChipBg: Color(0x1FFF8B8B), // rgba(255,139,139,0.12)
    sellChipBorder: Color(0x42FF8B8B), // rgba(255,139,139,0.26)
    sellInk: Color(0xFFFFB4B4),
    buyChipBg: Color(0x1F92D64F), // rgba(146,214,79,0.12)
    buyChipBorder: Color(0x4292D64F), // rgba(146,214,79,0.26)
    buyInk: Color(0xFFC6F09A),
    statusWaitBg: Color(0x1292D64F), // rgba(146,214,79,0.07)
    statusWaitBorder: Color(0x3892D64F), // rgba(146,214,79,0.22)
    statusWaitDot: Color(0xFF92D64F),
    statusWaitRing: Color(0x5992D64F), // rgba(146,214,79,0.35)
    statusWaitText: Color(0xFFC6F09A),
    statusWaitAside: Color(0xFFB7E38A),
    statusHoldBg: Color(0x12F2D14B), // rgba(242,209,75,0.07)
    statusHoldBorder: Color(0x2EF2D14B), // rgba(242,209,75,0.18)
    statusHoldDot: Color(0xFFF2D14B),
    statusHoldText: Color(0xFFF7DE72),
    statusDeadBg: Color(0x0AFFFFFF), // white 4%
    statusDeadBorder: Color(0x12FFFFFF), // white 7%
    statusDeadDot: Color(0xFF5D6879),
    statusDeadText: Color(0xFFA6B0C2),
    statusDeadAside: Color(0xFF8B97AD),
    statusCancelBg: Color(0x12FF8B8B), // rgba(255,139,139,0.07)
    statusCancelBorder: Color(0x33FF8B8B), // rgba(255,139,139,0.20)
    statusCancelDot: Color(0xFFFF8B8B),
    statusCancelText: Color(0xFFFFB4B4),
    progressTrack: Color(0x14FFFFFF), // white 8%
    progressFill: Color(0xFF92D64F),
    danger: Color(0xFFFF8B8B),
    dangerBorder: Color(0x59FF8B8B), // rgba(255,139,139,0.35)
    avatarBg: Color(0x1F92D64F), // rgba(146,214,79,0.12)
    avatarBorder: Color(0x3892D64F), // rgba(146,214,79,0.22)
    avatarNewBg: Color(0x0DFFFFFF), // white 5%
    avatarNewBorder: Color(0x14FFFFFF), // white 8%
    ctaLoadingBg: Color(0x2992D64F), // rgba(146,214,79,0.16)
    ctaLoadingInk: Color(0xFFC6F09A),
    ctaLoadingRing: Color(0x4D92D64F), // rgba(146,214,79,0.30)
    ctaDeadBg: Color(0x0DFFFFFF), // white 5%
    ctaDeadBorder: Color(0x12FFFFFF), // white 7%
    ctaDeadInk: Color(0xFF7E899E),
    sheetHandle: Color(0x2EFFFFFF), // white 18%
    ctaShadow: [
      BoxShadow(
        color: Color(0xA692D64F), // rgba(146,214,79,0.65)
        offset: Offset(0, 10),
        blurRadius: 24,
        spreadRadius: -10,
      ),
    ],
  );

  static const light = OrderDetailPalette(
    rowDivider: Color(0x1412161F), // ink 8%
    sellChipBg: Color(0x2EFF8B8B), // rgba(255,139,139,0.18)
    sellChipBorder: Color(0x66C2453F), // rgba(194,69,63,0.40)
    sellInk: Color(0xFF9A2F2A),
    buyChipBg: Color(0x1F92D64F), // lime 12%
    buyChipBorder: Color(0x5C5C9130), // rgba(92,145,48,0.36)
    buyInk: Color(0xFF3E6B1C),
    statusWaitBg: Color(0x1F92D64F), // lime 12%
    statusWaitBorder: Color(0x5C5C9130),
    statusWaitDot: Color(0xFF5C9130),
    statusWaitRing: Color(0x665C9130), // rgba(92,145,48,0.40)
    statusWaitText: Color(0xFF3E6B1C),
    statusWaitAside: Color(0xFF3E6B1C),
    statusHoldBg: Color(0x24F2D14B), // yellow 14%
    statusHoldBorder: Color(0x59D8AF19), // rgba(216,175,25,0.35)
    statusHoldDot: Color(0xFFE0B72C),
    statusHoldText: Color(0xFF7A5D00),
    statusDeadBg: Color(0x0A12161F), // ink 4%
    statusDeadBorder: Color(0x1412161F), // ink 8%
    statusDeadDot: Color(0xFFA3ACBA),
    statusDeadText: Color(0xFF3F4756),
    statusDeadAside: Color(0xFF5A6474),
    statusCancelBg: Color(0x2EFF8B8B), // rgba(255,139,139,0.18)
    statusCancelBorder: Color(0x66C2453F), // rgba(194,69,63,0.40)
    statusCancelDot: Color(0xFFC2403A),
    statusCancelText: Color(0xFF9A2F2A),
    progressTrack: Color(0x1F12161F), // ink 12%
    progressFill: Color(0xFF5C9130),
    danger: Color(0xFFC2403A),
    dangerBorder: Color(0x80C2403A), // rgba(194,64,58,0.50)
    avatarBg: Color(0x1F92D64F),
    avatarBorder: Color(0x5C5C9130),
    avatarNewBg: Color(0x0A12161F),
    avatarNewBorder: Color(0x1412161F),
    ctaLoadingBg: Color(0x3892D64F), // lime 22%
    ctaLoadingInk: Color(0xFF3E6B1C),
    ctaLoadingRing: Color(0x665C9130),
    ctaDeadBg: Color(0x0A12161F),
    ctaDeadBorder: Color(0x1412161F),
    ctaDeadInk: Color(0xFF5A6474),
    sheetHandle: Color(0x2E12161F), // ink 18%
    ctaShadow: [
      BoxShadow(
        color: Color(0x6692D64F), // lime 40%
        offset: Offset(0, 10),
        blurRadius: 24,
        spreadRadius: -10,
      ),
    ],
  );

  static OrderDetailPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

/// Colour family of the status block, keyed by how the order stands rather
/// than by each protocol status, so later states share a box with the state
/// they resemble (handoff 6b).
enum OrderStatusFamily { wait, hold, dead, cancel }

/// The status block's colours for [family].
({Color bg, Color border, Color dot, Color text, Color aside}) statusColors(
  OrderDetailPalette pal,
  OrderStatusFamily family,
) => switch (family) {
  OrderStatusFamily.wait => (
    bg: pal.statusWaitBg,
    border: pal.statusWaitBorder,
    dot: pal.statusWaitDot,
    text: pal.statusWaitText,
    aside: pal.statusWaitAside,
  ),
  OrderStatusFamily.hold => (
    bg: pal.statusHoldBg,
    border: pal.statusHoldBorder,
    dot: pal.statusHoldDot,
    text: pal.statusHoldText,
    aside: pal.statusHoldText,
  ),
  OrderStatusFamily.dead => (
    bg: pal.statusDeadBg,
    border: pal.statusDeadBorder,
    dot: pal.statusDeadDot,
    text: pal.statusDeadText,
    aside: pal.statusDeadAside,
  ),
  OrderStatusFamily.cancel => (
    bg: pal.statusCancelBg,
    border: pal.statusCancelBorder,
    dot: pal.statusCancelDot,
    text: pal.statusCancelText,
    aside: pal.statusDeadText,
  ),
};
