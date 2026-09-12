import 'package:flutter/material.dart';

import 'package:mostro/core/order_book_palette.dart';

/// Tokens of the `Operaciones` and `Chat` tabs redesign
/// (`design_handoff_operaciones_chat`, variants 11a · my trades and
/// 11b · chat), added on top of [OrderBookPalette], which it shares for
/// surfaces, text roles and the lime.
///
/// Dark values are the handoff's. The handoff is dark-only, so [light] maps
/// each role onto the light surfaces the order book already uses, adjusted
/// where a text role would fail WCAG AA (4.5:1) on the surface it renders on.
/// `test/core/activity_palette_contrast_test.dart` locks every pair.
@immutable
class ActivityPalette {
  const ActivityPalette({
    required this.borderAction,
    required this.rowDivider,
    required this.groupHeader,
    required this.chipActionBg,
    required this.chipActionBorder,
    required this.chipActionInk,
    required this.chipActionDot,
    required this.chipWaitBg,
    required this.chipWaitBorder,
    required this.chipWaitInk,
    required this.chipWaitDot,
    required this.chipDoneBg,
    required this.chipDoneBorder,
    required this.chipDoneInk,
    required this.chipDoneDot,
    required this.chipDisputeBg,
    required this.chipDisputeBorder,
    required this.chipDisputeInk,
    required this.segIdleBg,
    required this.segIdleBorder,
    required this.filterBg,
    required this.filterBorder,
    required this.badgeBg,
    required this.badgeInk,
    required this.avatarActiveBg,
    required this.avatarWaitBg,
    required this.avatarClosedBg,
    required this.avatarClosedInk,
    required this.sellArrow,
    required this.buyArrow,
    required this.chevronIdle,
  });

  /// The one highlight a card gets: a lime hairline when the next step is
  /// the user's. No card changes its fill by state.
  final Color borderAction;

  /// Between two rows of the same card (chat groups) and above a trade
  /// card's status row.
  final Color rowDivider;

  /// `REQUIEREN TU ACCIÓN` / `EN CURSO` / `CERRADAS` and their counters. The
  /// handoff's `#6B7589` is 3.9:1 on the page, so both themes lift it to the
  /// nearest tone that passes AA.
  final Color groupHeader;

  /// `Te toca`.
  final Color chipActionBg;
  final Color chipActionBorder;
  final Color chipActionInk;
  final Color chipActionDot;

  /// `Esperando pago`, `Esperando sats` and the other waits.
  final Color chipWaitBg;
  final Color chipWaitBorder;
  final Color chipWaitInk;
  final Color chipWaitDot;

  /// `Completada`, `Cancelada`, `Expirada`.
  final Color chipDoneBg;
  final Color chipDoneBorder;
  final Color chipDoneInk;
  final Color chipDoneDot;

  /// `En disputa`: its ink doubles as its dot.
  final Color chipDisputeBg;
  final Color chipDisputeBorder;
  final Color chipDisputeInk;

  /// The `Mensajes` / `Disputas` segment that is not selected. The selected
  /// one takes the action chip's fill and border.
  final Color segIdleBg;
  final Color segIdleBorder;

  /// The `Todas` filter pill while no filter is applied.
  final Color filterBg;
  final Color filterBorder;

  /// Unread and pending counters.
  final Color badgeBg;
  final Color badgeInk;

  /// Conversation avatars are tinted by state, never by a hash of the key:
  /// active and the user's turn (ink: `limeInk`), active and waiting (ink:
  /// the wait chip's), closed.
  final Color avatarActiveBg;
  final Color avatarWaitBg;
  final Color avatarClosedBg;
  final Color avatarClosedInk;

  /// Direction arrows: up for a sale, down for a purchase.
  final Color sellArrow;
  final Color buyArrow;

  /// The chevron of a card with nothing to do.
  final Color chevronIdle;

  /// Closed conversations stay readable but step back.
  static const double closedOpacity = 0.72;

  static const dark = ActivityPalette(
    borderAction: Color(0x4D92D64F), // rgba(146,214,79,0.30)
    rowDivider: Color(0x0DFFFFFF), // white 5%
    // Handoff #6B7589 is 3.9:1 on the page — lightened to pass AA.
    groupHeader: Color(0xFF828CA0),
    chipActionBg: Color(0x2492D64F), // rgba(146,214,79,0.14)
    chipActionBorder: Color(0x4D92D64F), // rgba(146,214,79,0.30)
    chipActionInk: Color(0xFFC6F09A),
    chipActionDot: Color(0xFF92D64F),
    chipWaitBg: Color(0x1FF2D14B), // rgba(242,209,75,0.12)
    chipWaitBorder: Color(0x42F2D14B), // rgba(242,209,75,0.26)
    chipWaitInk: Color(0xFFF7DE72),
    chipWaitDot: Color(0xFFF2D14B),
    chipDoneBg: Color(0x0DFFFFFF), // white 5%
    chipDoneBorder: Color(0x14FFFFFF), // white 8%
    chipDoneInk: Color(0xFFA6B0C2),
    chipDoneDot: Color(0xFF5D6879),
    chipDisputeBg: Color(0x1FFF8B8B), // rgba(255,139,139,0.12)
    chipDisputeBorder: Color(0x47FF8B8B), // rgba(255,139,139,0.28)
    chipDisputeInk: Color(0xFFFF8B8B),
    segIdleBg: Color(0x0AFFFFFF), // white 4%
    segIdleBorder: Color(0x12FFFFFF), // white 7%
    filterBg: Color(0x0DFFFFFF), // white 5%
    filterBorder: Color(0x17FFFFFF), // white 9%
    badgeBg: Color(0xFF92D64F),
    badgeInk: Color(0xFF12161F),
    avatarActiveBg: Color(0x2492D64F), // rgba(146,214,79,0.14)
    avatarWaitBg: Color(0x24F2D14B), // rgba(242,209,75,0.14)
    avatarClosedBg: Color(0x0FFFFFFF), // white 6%
    avatarClosedInk: Color(0xFFA6B0C2),
    sellArrow: Color(0xFFF7DE72),
    buyArrow: Color(0xFFB7E38A),
    chevronIdle: Color(0xFF5D6879),
  );

  static const light = ActivityPalette(
    borderAction: Color(0x735C9130), // rgba(92,145,48,0.45)
    rowDivider: Color(0x1212161F), // ink 7%
    groupHeader: Color(0xFF5F6979),
    chipActionBg: Color(0x3392D64F), // lime 20%
    chipActionBorder: Color(0x665C9130), // rgba(92,145,48,0.40)
    chipActionInk: Color(0xFF3E6B1C),
    chipActionDot: Color(0xFF5C9130),
    chipWaitBg: Color(0x40F2D14B), // yellow 25%
    chipWaitBorder: Color(0x73D8AF19), // rgba(216,175,25,0.45)
    chipWaitInk: Color(0xFF6E5400),
    chipWaitDot: Color(0xFFC49A12),
    chipDoneBg: Color(0x0F12161F), // ink 6%
    chipDoneBorder: Color(0x1712161F), // ink 9%
    chipDoneInk: Color(0xFF3F4756),
    chipDoneDot: Color(0xFFA3ACBA),
    chipDisputeBg: Color(0x1FE5484D), // rgba(229,72,77,0.12)
    chipDisputeBorder: Color(0x59E5484D), // rgba(229,72,77,0.35)
    chipDisputeInk: Color(0xFFA8262B),
    segIdleBg: Color(0xFFFFFFFF),
    segIdleBorder: Color(0x1712161F), // ink 9%
    filterBg: Color(0xFFFFFFFF),
    filterBorder: Color(0x1A12161F), // ink 10%
    badgeBg: Color(0xFF92D64F),
    badgeInk: Color(0xFF12161F),
    avatarActiveBg: Color(0x3392D64F), // lime 20%
    avatarWaitBg: Color(0x40F2D14B), // yellow 25%
    avatarClosedBg: Color(0x0F12161F), // ink 6%
    avatarClosedInk: Color(0xFF3F4756),
    sellArrow: Color(0xFF8A6A00),
    buyArrow: Color(0xFF4E7D28),
    chevronIdle: Color(0xFF8C95A3),
  );

  static ActivityPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
