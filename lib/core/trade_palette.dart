import 'package:flutter/material.dart';

import 'package:mostro/core/order_book_palette.dart';

/// Tokens the trade-screen redesign (variants 8a · waiting for the
/// counterpart, 8b/8c · active, 8d · fiat sent, 8e · completed) adds on top
/// of [OrderBookPalette], which it shares for surfaces and text roles.
///
/// Dark values are the handoff's. The handoff is dark-only, so [light] maps
/// each role onto the light surfaces the order book already uses, adjusted
/// where a text role would fail WCAG AA (4.5:1) on the surface it renders on.
/// `test/core/trade_palette_contrast_test.dart` locks every pair.
@immutable
class TradePalette {
  const TradePalette({
    required this.stepBorderWait,
    required this.stepBorderActive,
    required this.chipWaitBg,
    required this.chipWaitBorder,
    required this.chipWaitInk,
    required this.chipActiveBg,
    required this.chipActiveBorder,
    required this.chipActiveInk,
    required this.chipDisputeBg,
    required this.chipDisputeBorder,
    required this.chipDisputeInk,
    required this.warnBg,
    required this.warnBorder,
    required this.warnInk,
    required this.trackBg,
    required this.stepPending,
    required this.cancelBorder,
    required this.cancelInk,
    required this.neutralBorder,
    required this.neutralInk,
    required this.chatBorder,
    required this.avatarBg,
    required this.avatarBorder,
    required this.avatarNewBg,
    required this.lockedBg,
    required this.lockedBorder,
    required this.timerActive,
    required this.timerWait,
    required this.timerUrgent,
    required this.doneBg,
    required this.doneBorder,
    required this.ctaShadow,
  });

  /// Step block border while the user waits on the counterpart.
  final Color stepBorderWait;

  /// Step block border while the trade is active (8b–8d), and the chat card.
  final Color stepBorderActive;

  /// `WAITING` chip.
  final Color chipWaitBg;
  final Color chipWaitBorder;
  final Color chipWaitInk;

  /// `ACTIVE` / `YOUR TURN` chip.
  final Color chipActiveBg;
  final Color chipActiveBorder;
  final Color chipActiveInk;

  /// `DISPUTE` chip — outside the handoff, on the coral of the cancel action.
  final Color chipDisputeBg;
  final Color chipDisputeBorder;
  final Color chipDisputeInk;

  /// `Releasing the sats cannot be undone.` (8d).
  final Color warnBg;
  final Color warnBorder;
  final Color warnInk;

  /// Unfilled part of the countdown bar.
  final Color trackBg;

  /// Ring of a timeline step not reached yet.
  final Color stepPending;

  /// `Cancel` — outlined coral, never a filled red.
  final Color cancelBorder;
  final Color cancelInk;

  /// `Open dispute` — outlined neutral: grave, not destructive.
  final Color neutralBorder;
  final Color neutralInk;

  /// Chat card border.
  final Color chatBorder;

  /// Avatar of the chat card and of the reputation row.
  final Color avatarBg;
  final Color avatarBorder;

  /// Avatar of a counterpart nobody has rated (`New`).
  final Color avatarNewBg;

  /// The "no chat yet" line (8a).
  final Color lockedBg;
  final Color lockedBorder;

  /// Countdown while the user acts / while they wait / under five minutes.
  final Color timerActive;
  final Color timerWait;
  final Color timerUrgent;

  /// Check circle of the completed card.
  final Color doneBg;
  final Color doneBorder;

  final List<BoxShadow> ctaShadow;

  static const dark = TradePalette(
    stepBorderWait: Color(0x33F2D14B), // rgba(242,209,75,0.20)
    stepBorderActive: Color(0x3892D64F), // rgba(146,214,79,0.22)
    chipWaitBg: Color(0x1FF2D14B), // rgba(242,209,75,0.12)
    chipWaitBorder: Color(0x42F2D14B), // rgba(242,209,75,0.26)
    chipWaitInk: Color(0xFFF7DE72),
    chipActiveBg: Color(0x2492D64F), // rgba(146,214,79,0.14)
    chipActiveBorder: Color(0x4D92D64F), // rgba(146,214,79,0.30)
    chipActiveInk: Color(0xFFC6F09A),
    chipDisputeBg: Color(0x24FF8B8B), // rgba(255,139,139,0.14)
    chipDisputeBorder: Color(0x4DFF8B8B), // rgba(255,139,139,0.30)
    chipDisputeInk: Color(0xFFFFB4B4),
    warnBg: Color(0x12F2D14B), // rgba(242,209,75,0.07)
    warnBorder: Color(0x2EF2D14B), // rgba(242,209,75,0.18)
    warnInk: Color(0xFFF7DE72),
    trackBg: Color(0x14FFFFFF), // white 8%
    stepPending: Color(0x1FFFFFFF), // white 12%
    cancelBorder: Color(0x4DFF8B8B), // rgba(255,139,139,0.30)
    cancelInk: Color(0xFFFF8B8B),
    neutralBorder: Color(0x1FFFFFFF), // white 12%
    neutralInk: Color(0xFFA6B0C2),
    chatBorder: Color(0x3892D64F), // rgba(146,214,79,0.22)
    avatarBg: Color(0x1F92D64F), // rgba(146,214,79,0.12)
    avatarBorder: Color(0x3892D64F), // rgba(146,214,79,0.22)
    avatarNewBg: Color(0x0DFFFFFF), // white 5%
    lockedBg: Color(0x0AFFFFFF), // white 4%
    lockedBorder: Color(0x12FFFFFF), // white 7%
    timerActive: Color(0xFF92D64F),
    timerWait: Color(0xFFF7DE72),
    timerUrgent: Color(0xFFFF8B8B),
    doneBg: Color(0x2492D64F), // rgba(146,214,79,0.14)
    doneBorder: Color(0x4D92D64F), // rgba(146,214,79,0.30)
    ctaShadow: [
      BoxShadow(
        color: Color(0xA692D64F), // rgba(146,214,79,0.65)
        offset: Offset(0, 10),
        blurRadius: 24,
        spreadRadius: -10,
      ),
    ],
  );

  static const light = TradePalette(
    stepBorderWait: Color(0x59D8AF19), // rgba(216,175,25,0.35)
    stepBorderActive: Color(0x735C9130), // rgba(92,145,48,0.45)
    chipWaitBg: Color(0x24F2D14B), // yellow 14%
    chipWaitBorder: Color(0x59D8AF19),
    chipWaitInk: Color(0xFF7A5D00),
    chipActiveBg: Color(0x3392D64F), // lime 20%
    chipActiveBorder: Color(0x665C9130), // rgba(92,145,48,0.40)
    chipActiveInk: Color(0xFF3E6B1C),
    chipDisputeBg: Color(0x2EFF8B8B), // rgba(255,139,139,0.18)
    chipDisputeBorder: Color(0x66C2453F), // rgba(194,69,63,0.40)
    chipDisputeInk: Color(0xFF9A2F2A),
    warnBg: Color(0x24F2D14B),
    warnBorder: Color(0x59D8AF19),
    warnInk: Color(0xFF7A5D00),
    trackBg: Color(0x1F12161F), // ink 12%
    stepPending: Color(0x2E12161F), // ink 18%
    cancelBorder: Color(0x66C2453F),
    cancelInk: Color(0xFFC2403A),
    neutralBorder: Color(0x3312161F), // ink 20%
    neutralInk: Color(0xFF3F4756),
    chatBorder: Color(0x735C9130),
    avatarBg: Color(0x1F92D64F), // lime 12%
    avatarBorder: Color(0x5C5C9130), // rgba(92,145,48,0.36)
    avatarNewBg: Color(0x0A12161F), // ink 4%
    lockedBg: Color(0x0A12161F),
    lockedBorder: Color(0x1412161F), // ink 8%
    timerActive: Color(0xFF3E6B1C),
    timerWait: Color(0xFF7A5D00),
    timerUrgent: Color(0xFFC2403A),
    doneBg: Color(0x3392D64F),
    doneBorder: Color(0x665C9130),
    ctaShadow: [
      BoxShadow(
        color: Color(0x6692D64F), // lime 40%
        offset: Offset(0, 10),
        blurRadius: 24,
        spreadRadius: -10,
      ),
    ],
  );

  static TradePalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
