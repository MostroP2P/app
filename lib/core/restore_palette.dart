import 'package:flutter/material.dart';

/// Tokens of the restore sheet (`design_handoff_restaurar_ordenes`, 20a–20d):
/// the sheet an imported account shows while it asks its node for its orders.
///
/// Dark values are the handoff's, except [textPending]: the handoff's
/// `#5D6778` reads 2.99:1 on the sheet, and a stage not reached yet is still
/// text the user reads, so it is lifted just enough for AA. The handoff is
/// dark-only, so [light] maps each role onto the light surfaces the order
/// book already uses. `test/core/restore_palette_contrast_test.dart` holds
/// every text role to WCAG AA on the surface it renders on.
@immutable
class RestorePalette {
  const RestorePalette({
    required this.sheet,
    required this.card,
    required this.cardBorder,
    required this.handle,
    required this.text,
    required this.textSecondary,
    required this.textPending,
    required this.emphasis,
    required this.lime,
    required this.onLime,
    required this.limeSoft,
    required this.borderRunning,
    required this.borderDone,
    required this.iconFill,
    required this.iconBorder,
    required this.activeFill,
    required this.activeBorder,
    required this.ringTrack,
    required this.pendingRing,
    required this.barTrack,
    required this.error,
    required this.errorDetail,
    required this.errorFill,
    required this.errorBorder,
    required this.errorIconFill,
    required this.errorMarkFill,
    required this.borderError,
    required this.outlineBorder,
    required this.noticeFill,
    required this.noticeBorder,
    required this.amber,
    required this.amberFill,
    required this.amberBorder,
  });

  final Color sheet;

  /// A summary card (20d).
  final Color card;
  final Color cardBorder;
  final Color handle;

  final Color text;
  final Color textSecondary;

  /// A stage not reached yet.
  final Color textPending;

  /// `Cuenta` in the failure paragraph, and the secondary button's label.
  final Color emphasis;

  final Color lime;
  final Color onLime;

  /// The `n/N` counter and the action notice.
  final Color limeSoft;

  /// The sheet's top edge while the restore runs.
  final Color borderRunning;

  /// The sheet's top edge once restored.
  final Color borderDone;

  /// Disc behind the restore icon.
  final Color iconFill;
  final Color iconBorder;

  /// The stage in flight.
  final Color activeFill;
  final Color activeBorder;

  /// The spinner ring behind its lime arc.
  final Color ringTrack;

  /// The empty circle of a stage not reached.
  final Color pendingRing;

  final Color barTrack;

  final Color error;

  /// `Sin respuesta` on the failed stage.
  final Color errorDetail;

  /// The failed stage.
  final Color errorFill;
  final Color errorBorder;

  /// Disc behind the alert icon.
  final Color errorIconFill;

  /// Disc behind the failed stage's cross.
  final Color errorMarkFill;

  /// The sheet's top edge on failure.
  final Color borderError;

  /// `Continuar sin restaurar`.
  final Color outlineBorder;

  /// `Tienes N órdenes activas esperando tu acción`.
  final Color noticeFill;
  final Color noticeBorder;

  /// `N de M órdenes no se pudieron cargar`.
  final Color amber;
  final Color amberFill;
  final Color amberBorder;

  static const dark = RestorePalette(
    sheet: Color(0xFF161C28),
    card: Color(0xFF1A2030),
    cardBorder: Color(0x0FFFFFFF), // rgba(255,255,255,0.06)
    handle: Color(0x29FFFFFF), // rgba(255,255,255,0.16)
    text: Color(0xFFEEF1F6),
    textSecondary: Color(0xFF8B97AD),
    textPending: Color(0xFF7C8492), // #5D6778 lifted for AA on the sheet
    emphasis: Color(0xFFC3CBD9),
    lime: Color(0xFF92D64F),
    onLime: Color(0xFF12161F),
    limeSoft: Color(0xFFC6F09A),
    borderRunning: Color(0x3892D64F), // rgba(146,214,79,0.22)
    borderDone: Color(0x4D92D64F), // rgba(146,214,79,0.30)
    iconFill: Color(0x2492D64F), // rgba(146,214,79,0.14)
    iconBorder: Color(0x4D92D64F), // rgba(146,214,79,0.30)
    activeFill: Color(0x1492D64F), // rgba(146,214,79,0.08)
    activeBorder: Color(0x4792D64F), // rgba(146,214,79,0.28)
    ringTrack: Color(0x4092D64F), // rgba(146,214,79,0.25)
    pendingRing: Color(0x29FFFFFF), // rgba(255,255,255,0.16)
    barTrack: Color(0x17FFFFFF), // rgba(255,255,255,0.09)
    error: Color(0xFFF27868),
    errorDetail: Color(0xFFE0857A),
    errorFill: Color(0x14F27868), // rgba(242,120,104,0.08)
    errorBorder: Color(0x47F27868), // rgba(242,120,104,0.28)
    errorIconFill: Color(0x24F27868), // rgba(242,120,104,0.14)
    errorMarkFill: Color(0x33F27868), // rgba(242,120,104,0.20)
    borderError: Color(0x4DF27868), // rgba(242,120,104,0.30)
    outlineBorder: Color(0x1FFFFFFF), // rgba(255,255,255,0.12)
    noticeFill: Color(0x1292D64F), // rgba(146,214,79,0.07)
    noticeBorder: Color(0x3892D64F), // rgba(146,214,79,0.22)
    amber: Color(0xFFF7DE72),
    amberFill: Color(0x14F7DE72), // rgba(247,222,114,0.08)
    amberBorder: Color(0x47F7DE72), // rgba(247,222,114,0.28)
  );

  static const light = RestorePalette(
    sheet: Color(0xFFFFFFFF),
    card: Color(0xFFF4F6F4),
    cardBorder: Color(0x1412161F), // ink 8%
    handle: Color(0x2E12161F), // ink 18%
    text: Color(0xFF12161F),
    textSecondary: Color(0xFF5A6474),
    textPending: Color(0xFF636D7D),
    emphasis: Color(0xFF12161F),
    lime: Color(0xFF92D64F),
    onLime: Color(0xFF12161F),
    limeSoft: Color(0xFF3E6B1C),
    borderRunning: Color(0x4D5C9130), // rgba(92,145,48,0.30)
    borderDone: Color(0x805C9130), // rgba(92,145,48,0.50)
    iconFill: Color(0x3392D64F), // lime 20%
    iconBorder: Color(0x805C9130), // rgba(92,145,48,0.50)
    activeFill: Color(0x1A92D64F), // lime 10%
    activeBorder: Color(0x805C9130), // rgba(92,145,48,0.50)
    ringTrack: Color(0x4D92D64F), // lime 30%
    pendingRing: Color(0x3312161F), // ink 20%
    barTrack: Color(0x1A12161F), // ink 10%
    error: Color(0xFFC2403A),
    errorDetail: Color(0xFFA8352F),
    errorFill: Color(0x14C2403A), // 8%
    errorBorder: Color(0x59C2403A), // 35%
    errorIconFill: Color(0x24C2403A), // 14%
    errorMarkFill: Color(0x33C2403A), // 20%
    borderError: Color(0x66C2403A), // 40%
    outlineBorder: Color(0x2912161F), // ink 16%
    noticeFill: Color(0x1A92D64F), // lime 10%
    noticeBorder: Color(0x665C9130), // rgba(92,145,48,0.40)
    amber: Color(0xFF7A5D00),
    amberFill: Color(0x1FF2D14B), // yellow 12%
    amberBorder: Color(0x73D8AF19), // rgba(216,175,25,0.45)
  );

  static RestorePalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}
