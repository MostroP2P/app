import 'package:flutter/material.dart';

export 'package:mostro/core/order_book_palette.dart';

/// Mostro design system tokens.
///
/// All colors are defined here — zero hardcoded colors in widgets.
/// Access via `Theme.of(context).extension<AppColors>()!`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.backgroundDark,
    required this.backgroundCard,
    required this.backgroundInput,
    required this.backgroundElevated,
    required this.mostroGreen,
    required this.mostroGreenBright,
    required this.sellColor,
    required this.destructiveRed,
    required this.purpleButton,
    required this.tealAccent,
    required this.blueAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textSubtle,
    required this.textDisabled,
    required this.textLink,
    required this.messageSent,
    required this.messageReceived,
    required this.systemMessage,
    required this.badgeGold,
    required this.warningAmber,
  });

  final Color backgroundDark;
  final Color backgroundCard;
  final Color backgroundInput;
  final Color backgroundElevated;
  final Color mostroGreen;
  final Color mostroGreenBright;
  final Color sellColor;
  final Color destructiveRed;
  final Color purpleButton;
  final Color tealAccent;
  final Color blueAccent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textSubtle;
  final Color textDisabled;
  final Color textLink;
  final Color messageSent;
  final Color messageReceived;
  final Color systemMessage;

  /// Dark-gold color used for the notification count badge.
  final Color badgeGold;

  /// Amber used for time-sensitive warnings (running timers, backup nags).
  final Color warningAmber;

  /// Status chip colors — [background, text].
  static const statusPending = (Color(0xFF854D0E), Color(0xFFFCD34D));
  static const statusWaiting = (Color(0xFF7C2D12), Color(0xFFFED7AA));
  static const statusActive = (Color(0xFF1E3A8A), Color(0xFF93C5FD));
  static const statusSuccess = (Color(0xFF065F46), Color(0xFF6EE7B7));
  static const statusDispute = (Color(0xFF7F1D1D), Color(0xFFFCA5A5));
  static const statusSettled = (Color(0xFF581C87), Color(0xFFC084FC));
  static const statusInactive = (Color(0xFF1F2937), Color(0xFFD1D5DB));

  @override
  AppColors copyWith({
    Color? backgroundDark,
    Color? backgroundCard,
    Color? backgroundInput,
    Color? backgroundElevated,
    Color? mostroGreen,
    Color? mostroGreenBright,
    Color? sellColor,
    Color? destructiveRed,
    Color? purpleButton,
    Color? tealAccent,
    Color? blueAccent,
    Color? textPrimary,
    Color? textSecondary,
    Color? textSubtle,
    Color? textDisabled,
    Color? textLink,
    Color? messageSent,
    Color? messageReceived,
    Color? systemMessage,
    Color? badgeGold,
    Color? warningAmber,
  }) {
    return AppColors(
      backgroundDark: backgroundDark ?? this.backgroundDark,
      backgroundCard: backgroundCard ?? this.backgroundCard,
      backgroundInput: backgroundInput ?? this.backgroundInput,
      backgroundElevated: backgroundElevated ?? this.backgroundElevated,
      mostroGreen: mostroGreen ?? this.mostroGreen,
      mostroGreenBright: mostroGreenBright ?? this.mostroGreenBright,
      sellColor: sellColor ?? this.sellColor,
      destructiveRed: destructiveRed ?? this.destructiveRed,
      purpleButton: purpleButton ?? this.purpleButton,
      tealAccent: tealAccent ?? this.tealAccent,
      blueAccent: blueAccent ?? this.blueAccent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textSubtle: textSubtle ?? this.textSubtle,
      textDisabled: textDisabled ?? this.textDisabled,
      textLink: textLink ?? this.textLink,
      messageSent: messageSent ?? this.messageSent,
      messageReceived: messageReceived ?? this.messageReceived,
      systemMessage: systemMessage ?? this.systemMessage,
      badgeGold: badgeGold ?? this.badgeGold,
      warningAmber: warningAmber ?? this.warningAmber,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      backgroundDark: Color.lerp(backgroundDark, other.backgroundDark, t)!,
      backgroundCard: Color.lerp(backgroundCard, other.backgroundCard, t)!,
      backgroundInput: Color.lerp(backgroundInput, other.backgroundInput, t)!,
      backgroundElevated:
          Color.lerp(backgroundElevated, other.backgroundElevated, t)!,
      mostroGreen: Color.lerp(mostroGreen, other.mostroGreen, t)!,
      mostroGreenBright:
          Color.lerp(mostroGreenBright, other.mostroGreenBright, t)!,
      sellColor: Color.lerp(sellColor, other.sellColor, t)!,
      destructiveRed: Color.lerp(destructiveRed, other.destructiveRed, t)!,
      purpleButton: Color.lerp(purpleButton, other.purpleButton, t)!,
      tealAccent: Color.lerp(tealAccent, other.tealAccent, t)!,
      blueAccent: Color.lerp(blueAccent, other.blueAccent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textSubtle: Color.lerp(textSubtle, other.textSubtle, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      textLink: Color.lerp(textLink, other.textLink, t)!,
      messageSent: Color.lerp(messageSent, other.messageSent, t)!,
      messageReceived: Color.lerp(messageReceived, other.messageReceived, t)!,
      systemMessage: Color.lerp(systemMessage, other.systemMessage, t)!,
      badgeGold: Color.lerp(badgeGold, other.badgeGold, t)!,
      warningAmber: Color.lerp(warningAmber, other.warningAmber, t)!,
    );
  }
}

// ── Drawer redesign palette ───────────────────────────────────────────────────

/// Palette of the drawer redesign handoff (`design_handoff_drawer`, variants
/// 3b · dark and 3c · light): a floating gradient panel with decorative halos,
/// tinted icon tiles and a release-stage chip. Values follow the handoff
/// except where a text role fails WCAG AA (4.5:1) on the surface it really
/// renders on — [tagline] sits at the centre of the green halo, and the light
/// [footerText] on the panel's bottom tone — so those are adjusted just enough
/// to pass. Locked by `test/core/drawer_palette_contrast_test.dart`.
@immutable
class DrawerPalette {
  const DrawerPalette({
    required this.panelGradient,
    required this.panelGradientStops,
    required this.panelBorder,
    required this.panelShadow,
    required this.scrim,
    required this.haloGreen,
    required this.haloYellow,
    required this.logoShadow,
    required this.logoShadowBlur,
    required this.wordmark,
    required this.tagline,
    required this.chipText,
    required this.chipFill,
    required this.chipBorder,
    required this.chipGlow,
    required this.accentDivider,
    required this.itemFill,
    required this.itemBorder,
    required this.itemShadow,
    required this.itemFillActive,
    required this.itemBorderActive,
    required this.iconTileGradient,
    required this.iconTileBorder,
    required this.icon,
    required this.itemLabel,
    required this.chevron,
    required this.footerHairline,
    required this.footerGlyph,
    required this.footerText,
  });

  /// Panel background, top → bottom (the handoff's 175° gradient).
  final List<Color> panelGradient;
  final List<double> panelGradientStops;

  /// 1px hairline on the panel's right edge (floating overlay only).
  final Color panelBorder;
  final List<BoxShadow> panelShadow;

  /// Dims the screen behind the overlay drawer.
  final Color scrim;

  /// Centre colors of the two radial halos; each fades to transparent.
  final Color haloGreen;
  final Color haloYellow;

  /// Tint and blur of the drop shadow under the mascot.
  final Color logoShadow;
  final double logoShadowBlur;

  final Color wordmark;
  final Color tagline;
  final Color chipText;
  final Color chipFill;
  final Color chipBorder;
  final List<BoxShadow> chipGlow;

  /// Left → right stops of the accent line under the header.
  final List<Color> accentDivider;

  /// Menu row at rest.
  final Color itemFill;
  final Color itemBorder;
  final List<BoxShadow> itemShadow;

  /// Menu row while pressed or hovered (and the active desktop destination).
  final Color itemFillActive;
  final Color itemBorderActive;

  final List<Color> iconTileGradient;
  final Color iconTileBorder;
  final Color icon;
  final Color itemLabel;
  final Color chevron;

  /// Left → right stops of the hairline above the version footer.
  final List<Color> footerHairline;
  final Color footerGlyph;
  final Color footerText;

  static const dark = DrawerPalette(
    panelGradient: [Color(0xFF212A3C), Color(0xFF181E2C), Color(0xFF141926)],
    panelGradientStops: [0, 0.45, 1],
    panelBorder: Color(0x1F92D64F), // rgba(146,214,79,0.12)
    panelShadow: [
      BoxShadow(
        color: Color(0xE6000000), // black 90%
        offset: Offset(26, 0),
        blurRadius: 70,
        spreadRadius: -18,
      ),
    ],
    scrim: Color(0x9E06080C), // rgba(6,8,12,0.62)
    haloGreen: Color(0x2192D64F), // rgba(146,214,79,0.13)
    haloYellow: Color(0x1AF2D14B), // rgba(242,209,75,0.10)
    logoShadow: Color(0x3392D64F), // rgba(146,214,79,0.20)
    logoShadowBlur: 16,
    wordmark: Color(0xFFEEF1F6),
    // Handoff #8B97AD is 3.7:1 over the green halo — lightened to pass AA.
    tagline: Color(0xFFA0AABD),
    chipText: Color(0xFFF7DE72),
    chipFill: Color(0x24F2D14B), // rgba(242,209,75,0.14)
    chipBorder: Color(0x59F2D14B), // rgba(242,209,75,0.35)
    chipGlow: [
      BoxShadow(
        color: Color(0x73F2D14B), // rgba(242,209,75,0.45)
        blurRadius: 18,
        spreadRadius: -4,
      ),
    ],
    accentDivider: [Color(0xB392D64F), Color(0x0D92D64F)],
    itemFill: Color(0x09FFFFFF), // white 3.5%
    itemBorder: Color(0x0DFFFFFF), // white 5%
    itemShadow: [],
    itemFillActive: Color(0x1792D64F), // rgba(146,214,79,0.09)
    itemBorderActive: Color(0x4092D64F), // rgba(146,214,79,0.25)
    iconTileGradient: [Color(0x3892D64F), Color(0x0F92D64F)],
    iconTileBorder: Color(0x3892D64F), // rgba(146,214,79,0.22)
    icon: Color(0xFFB7E38A),
    itemLabel: Color(0xFFEEF1F6),
    chevron: Color(0xFF6C7789),
    footerHairline: [Color(0x1AFFFFFF), Color(0x00FFFFFF)],
    footerGlyph: Color(0xFF92D64F),
    footerText: Color(0xFF7E899E),
  );

  static const light = DrawerPalette(
    panelGradient: [Color(0xFFFFFFFF), Color(0xFFFBFCFA), Color(0xFFF3F6F1)],
    panelGradientStops: [0, 0.55, 1],
    panelBorder: Color(0x295C9130), // rgba(92,145,48,0.16)
    panelShadow: [
      BoxShadow(
        color: Color(0x5912161F), // rgba(18,22,31,0.35)
        offset: Offset(26, 0),
        blurRadius: 70,
        spreadRadius: -18,
      ),
    ],
    scrim: Color(0x5712161F), // rgba(18,22,31,0.34)
    haloGreen: Color(0x4792D64F), // rgba(146,214,79,0.28)
    haloYellow: Color(0x33F2D14B), // rgba(242,209,75,0.20)
    logoShadow: Color(0x475C9130), // rgba(92,145,48,0.28)
    logoShadowBlur: 14,
    wordmark: Color(0xFF12161F),
    // Handoff #6F7A8C is 3.7:1 over the green halo — darkened to pass AA.
    tagline: Color(0xFF5F6979),
    chipText: Color(0xFF7A5D00),
    chipFill: Color(0x47F2D14B), // rgba(242,209,75,0.28)
    chipBorder: Color(0x73D8AF19), // rgba(216,175,25,0.45)
    chipGlow: [],
    accentDivider: [Color(0x995C9130), Color(0x0D5C9130)],
    itemFill: Color(0xE6FFFFFF), // white 90%
    itemBorder: Color(0x0F12161F), // rgba(18,22,31,0.06)
    itemShadow: [
      BoxShadow(
        color: Color(0x0A12161F), // rgba(18,22,31,0.04)
        offset: Offset(0, 1),
        blurRadius: 2,
      ),
    ],
    itemFillActive: Color(0x2492D64F), // rgba(146,214,79,0.14)
    itemBorderActive: Color(0x4D5C9130), // rgba(92,145,48,0.30)
    iconTileGradient: [Color(0x4D92D64F), Color(0x1A92D64F)],
    iconTileBorder: Color(0x385C9130), // rgba(92,145,48,0.22)
    icon: Color(0xFF4E7D28),
    itemLabel: Color(0xFF2A303C),
    chevron: Color(0xFF9AA4B8),
    footerHairline: [Color(0x1A12161F), Color(0x0012161F)],
    footerGlyph: Color(0xFF5C9130),
    // Handoff #6F7A8C is 4.0:1 on the panel bottom — darkened to pass AA.
    footerText: Color(0xFF5F6979),
  );

  static DrawerPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

// ── Spacing tokens ─────────────────────────────────────────────────────────────

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

// ── Responsive breakpoints ────────────────────────────────────────────────────

/// Logical-pixel breakpoints for responsive layouts.
///
/// - < [tablet]  → mobile   (single-column, overlay drawer, bottom nav)
/// - [tablet] – [desktop] → tablet (2-column grid, side panel)
/// - ≥ [desktop] → desktop  (3-column grid, persistent sidebar, no bottom nav)
abstract final class AppBreakpoints {
  static const double tablet = 600;
  static const double desktop = 1200;
}

// ── Border-radius tokens ───────────────────────────────────────────────────────

abstract final class AppRadius {
  static const double card = 12;
  static const double button = 8;
  static const double chip = 6;
  static const double bubble = 16;
  static const double input = 8;
}

// ── Typography tokens ─────────────────────────────────────────────────────────

/// Font families bundled in `pubspec.yaml` (`fonts:`).
abstract final class AppFonts {
  /// Interface text. Both themes set it as the default family, so a
  /// `TextStyle` without a family inherits it.
  static const String ui = 'Outfit';

  /// Figures that must line up from card to card — amounts, premiums, sats,
  /// ratings. Its digits are tabular.
  static const String figures = 'Manrope';
}

// ── Predefined colour instances ────────────────────────────────────────────────

const _dark = AppColors(
  backgroundDark: Color(0xFF1B1E28),
  backgroundCard: Color(0xFF1E2230),
  backgroundInput: Color(0xFF252A3A),
  backgroundElevated: Color(0xFF2A2D35),
  mostroGreen: Color(0xFF8CC63F),
  mostroGreenBright: Color(0xFFA5FF00),
  sellColor: Color(0xFFFF8A8A),
  destructiveRed: Color(0xFFD84D4D),
  purpleButton: Color(0xFF8359C2),
  tealAccent: Color(0xFF2DA69D),
  blueAccent: Color(0xFF35485E),
  textPrimary: Color(0xFFFFFFFF),
  textSecondary: Color(0xFFB0B3C6),
  textSubtle: Color(0xFF9A9A9C),
  textDisabled: Color(0xFF6C757D),
  textLink: Color(0xFF8CC63F),
  messageSent: Color(0xFF8359C2),
  messageReceived: Color(0xFF4B6349),
  systemMessage: Color(0xFF2A2D35),
  badgeGold: Color(0xFFB8860B),
  warningAmber: Color(0xFFE89C3C),
);

const _light = AppColors(
  backgroundDark: Color(0xFFFFFFFF),
  backgroundCard: Color(0xFFF5F5F5),
  backgroundInput: Color(0xFFEEEEEE),
  backgroundElevated: Color(0xFFE0E0E0),
  mostroGreen: Color(0xFF8CC63F),
  mostroGreenBright: Color(0xFF6A9E00),
  sellColor: Color(0xFFFF8A8A),
  destructiveRed: Color(0xFFD84D4D),
  purpleButton: Color(0xFF8359C2),
  tealAccent: Color(0xFF2DA69D),
  blueAccent: Color(0xFF35485E),
  textPrimary: Color(0xFF1A1A1A),
  textSecondary: Color(0xFF666666),
  textSubtle: Color(0xFF888888),
  textDisabled: Color(0xFFAAAAAA),
  textLink: Color(0xFF6A9E00),
  messageSent: Color(0xFF8359C2),
  messageReceived: Color(0xFF4B6349),
  systemMessage: Color(0xFFE0E0E0),
  badgeGold: Color(0xFFB8860B),
  warningAmber: Color(0xFFC97B1F),
);

// ── ThemeData factories ────────────────────────────────────────────────────────

// Built once and shared. ThemeData is immutable, and `MaterialApp.router` asks
// for both themes on every rebuild — which includes every locale change,
// theme-mode change and route change.
ThemeData? _darkTheme;
ThemeData? _lightTheme;

ThemeData buildDarkTheme() => _darkTheme ??= _buildTheme(
  brightness: Brightness.dark,
  colors: _dark,
  scaffold: const Color(0xFF1B1E28),
);

ThemeData buildLightTheme() => _lightTheme ??= _buildTheme(
  brightness: Brightness.light,
  colors: _light,
  scaffold: const Color(0xFFFFFFFF),
);

ThemeData _buildTheme({
  required Brightness brightness,
  required AppColors colors,
  required Color scaffold,
}) {
  final base = ThemeData(
    brightness: brightness,
    fontFamily: AppFonts.ui,
    scaffoldBackgroundColor: scaffold,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _NoTransitionBuilder(),
        TargetPlatform.iOS: _NoTransitionBuilder(),
        TargetPlatform.linux: _NoTransitionBuilder(),
        TargetPlatform.macOS: _NoTransitionBuilder(),
        TargetPlatform.windows: _NoTransitionBuilder(),
      },
    ),
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: colors.mostroGreen,
      onPrimary: Colors.white,
      secondary: colors.purpleButton,
      onSecondary: Colors.white,
      error: colors.destructiveRed,
      onError: Colors.white,
      surface: colors.backgroundCard,
      onSurface: colors.textPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scaffold,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      iconTheme: IconThemeData(color: colors.textPrimary),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: scaffold,
      selectedItemColor: colors.mostroGreen,
      unselectedItemColor: colors.textDisabled,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: colors.backgroundCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.backgroundInput,
      labelStyle: TextStyle(color: colors.textSecondary),
      hintStyle: TextStyle(color: colors.textSubtle),
      enabledBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: colors.textSubtle),
      ),
      focusedBorder: UnderlineInputBorder(
        borderSide: BorderSide(color: colors.mostroGreen, width: 2),
      ),
    ),
    textTheme: TextTheme(
      displayLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.bold,
        color: colors.textPrimary,
        height: 1.2,
      ),
      headlineLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.bold,
        color: colors.textPrimary,
        height: 1.3,
      ),
      headlineMedium: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.bold,
        color: colors.textPrimary,
        height: 1.3,
      ),
      headlineSmall: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w500,
        color: colors.textPrimary,
        height: 1.4,
      ),
      bodyLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: colors.textPrimary,
        height: 1.5,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: colors.textSecondary,
        height: 1.5,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.normal,
        color: colors.textSubtle,
        height: 1.4,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: colors.textPrimary,
        height: 1.3,
      ),
      labelSmall: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: colors.textPrimary,
        height: 1.2,
      ),
    ),
    extensions: [colors],
  );
  return base;
}

// Instant page transition — no animation.
class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
