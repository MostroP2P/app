import 'package:flutter/material.dart';

import 'package:mostro/core/order_book_palette.dart';

/// Tokens of the Account and backup redesign (`design_handoff_cuenta_respaldo`:
/// 15a–15c Account and its sheet, 16a–16d the 3-step backup), added on top of
/// [OrderBookPalette], which it shares for the page, the card, the lime and
/// the text roles.
///
/// Dark values are the handoff's. The handoff is dark-only, so [light] maps
/// each role onto the light surfaces the order book already uses. Where a text
/// role fails WCAG AA (4.5:1) on the surface it renders on it is lifted just
/// enough — in dark only [wordIndex]. The mask, the empty-slot dash, the
/// unselected radio and the disabled label keep the handoff's `#5D6879`: they
/// carry no text a reader needs. `test/core/backup_palette_contrast_test.dart`
/// locks every pair.
@immutable
class BackupPalette {
  const BackupPalette({
    required this.accent,
    required this.cell,
    required this.noteFill,
    required this.wordIndex,
    required this.muted,
    required this.amber,
    required this.amberTitle,
    required this.amberFill,
    required this.amberBorder,
    required this.amberText,
    required this.chipFill,
    required this.revealFill,
    required this.revealBorder,
    required this.outlineBorder,
    required this.scrim,
    required this.sheetBorder,
    required this.grabber,
    required this.heroFill,
    required this.stepsFill,
    required this.stepDivider,
    required this.stepNumberFill,
    required this.slotFill,
    required this.slotActiveFill,
    required this.slotDoneFill,
    required this.slotDoneBorder,
    required this.optionFill,
    required this.optionBorder,
    required this.secondaryBorder,
    required this.disabledFill,
    required this.progressTrack,
    required this.doneFill,
    required this.wrong,
  });

  /// Lime as a stroke: the active slot, the selected radio, a finished
  /// progress segment, the checks.
  final Color accent;

  /// A word cell inside a card.
  final Color cell;

  /// The "hidden when you leave" note under the 16a grid.
  final Color noteFill;

  /// `01`…`12` in front of each word. The handoff's `#5D6879` is 3:1 on the
  /// cell, so dark lifts it to AA.
  final Color wordIndex;

  /// `••••••••`, the empty-slot dash, the unselected radio and the disabled
  /// `Confirm` label.
  final Color muted;

  /// Shield of the banner, star of the sheet, triangle of 16a.
  final Color amber;

  /// `Secure your reputation` on the banner and the lead sentence of the 16a
  /// warning. The same yellow as [amber] in dark; in light [amber] is an icon
  /// tone that cannot carry text on white, so the title darkens.
  final Color amberTitle;

  /// The amber banner of 15a and the warning of 16a.
  final Color amberFill;
  final Color amberBorder;

  /// Body of the 16a warning; its lead sentence is set in [amber].
  final Color amberText;

  /// `Backed up` chip.
  final Color chipFill;

  /// `Show words`.
  final Color revealFill;
  final Color revealBorder;

  /// `Import user` and the refresh square.
  final Color outlineBorder;

  /// Behind the 15c sheet.
  final Color scrim;
  final Color sheetBorder;
  final Color grabber;

  /// Circle behind the star of 15c.
  final Color heroFill;

  /// The three-step list of 15c.
  final Color stepsFill;
  final Color stepDivider;
  final Color stepNumberFill;

  /// Verification slots: empty, active (bordered by [accent]) and solved.
  final Color slotFill;
  final Color slotActiveFill;
  final Color slotDoneFill;
  final Color slotDoneBorder;

  /// The four options for the active slot.
  final Color optionFill;
  final Color optionBorder;

  /// `View words` next to `Confirm`.
  final Color secondaryBorder;

  /// `Confirm` while a slot is still open.
  final Color disabledFill;

  /// A progress segment not reached yet.
  final Color progressTrack;

  /// Circle behind the check of 16d.
  final Color doneFill;

  /// A wrong pick: the option's border and the message under the grid.
  final Color wrong;

  static const dark = BackupPalette(
    accent: Color(0xFF92D64F),
    cell: Color(0x0BFFFFFF), // rgba(255,255,255,0.045)
    noteFill: Color(0x08FFFFFF), // rgba(255,255,255,0.03)
    wordIndex: Color(0xFF8A94A8), // #5D6879 lifted for AA on the cell
    muted: Color(0xFF5D6879),
    amber: Color(0xFFF7DE72),
    amberTitle: Color(0xFFF7DE72),
    amberFill: Color(0x12F7DE72), // rgba(247,222,114,0.07)
    amberBorder: Color(0x47F7DE72), // rgba(247,222,114,0.28)
    amberText: Color(0xFFE8D89A),
    chipFill: Color(0x1F92D64F), // rgba(146,214,79,0.12)
    revealFill: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    revealBorder: Color(0x17FFFFFF), // rgba(255,255,255,0.09)
    outlineBorder: Color(0x7392D64F), // rgba(146,214,79,0.45)
    scrim: Color(0x8C06080C), // rgba(6,8,12,0.55)
    sheetBorder: Color(0x14FFFFFF), // rgba(255,255,255,0.08)
    grabber: Color(0x2EFFFFFF), // rgba(255,255,255,0.18)
    heroFill: Color(0x1FF7DE72), // rgba(247,222,114,0.12)
    stepsFill: Color(0x0AFFFFFF), // rgba(255,255,255,0.04)
    stepDivider: Color(0x0DFFFFFF), // rgba(255,255,255,0.05)
    stepNumberFill: Color(0x2492D64F), // rgba(146,214,79,0.14)
    slotFill: Color(0x0AFFFFFF), // rgba(255,255,255,0.04)
    slotActiveFill: Color(0x0F92D64F), // rgba(146,214,79,0.06)
    slotDoneFill: Color(0x1492D64F), // rgba(146,214,79,0.08)
    slotDoneBorder: Color(0x6692D64F), // rgba(146,214,79,0.40)
    optionFill: Color(0x0AFFFFFF), // rgba(255,255,255,0.04)
    optionBorder: Color(0x14FFFFFF), // rgba(255,255,255,0.08)
    secondaryBorder: Color(0x24FFFFFF), // rgba(255,255,255,0.14)
    disabledFill: Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
    progressTrack: Color(0x1AFFFFFF), // rgba(255,255,255,0.10)
    doneFill: Color(0x2492D64F), // rgba(146,214,79,0.14)
    wrong: Color(0xFFFF8B8B),
  );

  static const light = BackupPalette(
    accent: Color(0xFF5C9130),
    cell: Color(0x0B12161F), // ink 4.5%
    noteFill: Color(0x0812161F), // ink 3%
    wordIndex: Color(0xFF636D7D),
    muted: Color(0xFF8A94A6),
    amber: Color(0xFFD8AF19),
    amberTitle: Color(0xFF7A5D00),
    amberFill: Color(0x1FF2D14B), // yellow 12%
    amberBorder: Color(0x73D8AF19), // rgba(216,175,25,0.45)
    amberText: Color(0xFF5E4A00),
    chipFill: Color(0x3392D64F), // lime 20%
    revealFill: Color(0x0A12161F), // ink 4%
    revealBorder: Color(0x1A12161F), // ink 10%
    outlineBorder: Color(0x995C9130), // rgba(92,145,48,0.60)
    scrim: Color(0x8C06080C),
    sheetBorder: Color(0x1412161F), // ink 8%
    grabber: Color(0x2E12161F), // ink 18%
    heroFill: Color(0x40F2D14B), // yellow 25%
    stepsFill: Color(0x0A12161F), // ink 4%
    stepDivider: Color(0x1412161F), // ink 8%
    stepNumberFill: Color(0x3392D64F), // lime 20%
    slotFill: Color(0x0A12161F), // ink 4%
    slotActiveFill: Color(0x1A92D64F), // lime 10%
    slotDoneFill: Color(0x2692D64F), // lime 15%
    slotDoneBorder: Color(0x995C9130), // rgba(92,145,48,0.60)
    optionFill: Color(0xFFFFFFFF),
    optionBorder: Color(0x1F12161F), // ink 12%
    secondaryBorder: Color(0x2912161F), // ink 16%
    disabledFill: Color(0x0F12161F), // ink 6%
    progressTrack: Color(0x1A12161F), // ink 10%
    doneFill: Color(0x2692D64F), // lime 15%
    wrong: Color(0xFFC2403A),
  );

  static BackupPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
