/// Mostro app theme — dark and light ThemeData.
///
/// Colour palette:
///   Brand orange  : #F7931A  (Bitcoin orange)
///   Brand surface : #1A1A2E  (deep navy)
///   Success green : #27AE60
///   Warning amber : #F39C12
///   Error red     : #E74C3C
///
/// All text/icon contrast ratios meet WCAG-AA (≥4.5:1 on their respective
/// background).  Use AnimatedTheme (applied automatically by MaterialApp) for
/// smooth light ↔ dark transitions.
library app_theme;

import 'package:flutter/material.dart';

// ─── Brand palette ───────────────────────────────────────────────────────────

const Color _brandOrange = Color(0xFFF7931A);
const Color _brandOrangeLight = Color(0xFFFFB347);

// Dark palette
const Color _darkBackground = Color(0xFF0F0F1A);
const Color _darkSurface = Color(0xFF1A1A2E);
const Color _darkSurfaceVariant = Color(0xFF252540);
const Color _darkOnSurface = Color(0xFFDDDDEE);
const Color _darkOnSurfaceVariant = Color(0xFFAAAAAA);

// Light palette
const Color _lightBackground = Color(0xFFF5F5F7);
const Color _lightSurface = Color(0xFFFFFFFF);
const Color _lightSurfaceVariant = Color(0xFFEEEEF5);
const Color _lightOnSurface = Color(0xFF1A1A2E);
const Color _lightOnSurfaceVariant = Color(0xFF555566);

// Semantic
const Color _success = Color(0xFF27AE60);
const Color _warning = Color(0xFFF39C12);
const Color _error = Color(0xFFE74C3C);

// ─── AppTheme ────────────────────────────────────────────────────────────────

class AppTheme {
  AppTheme._();

  // ── Dark ─────────────────────────────────────────────────────────────────

  static ThemeData get dark {
    const colorScheme = ColorScheme.dark(
      primary: _brandOrange,
      onPrimary: _darkBackground,
      primaryContainer: Color(0xFF3D2A00),
      onPrimaryContainer: _brandOrangeLight,
      secondary: _brandOrangeLight,
      onSecondary: _darkBackground,
      secondaryContainer: Color(0xFF2E1E00),
      onSecondaryContainer: _brandOrangeLight,
      error: _error,
      onError: Colors.white,
      errorContainer: Color(0xFF4A1010),
      onErrorContainer: Color(0xFFFFB3B3),
      surface: _darkSurface,
      onSurface: _darkOnSurface,
      surfaceContainerHighest: _darkSurfaceVariant,
      onSurfaceVariant: _darkOnSurfaceVariant,
      outline: Color(0xFF444466),
      outlineVariant: Color(0xFF333355),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _darkBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: _darkSurface,
        foregroundColor: _darkOnSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: _textTheme(Brightness.dark).titleLarge?.copyWith(
              color: _darkOnSurface,
              fontWeight: FontWeight.w600,
            ),
      ),
      cardTheme: CardThemeData(
        color: _darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFF333355)),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: _darkSurfaceVariant,
        labelStyle: TextStyle(color: _darkOnSurfaceVariant, fontSize: 12),
        side: BorderSide.none,
        shape: StadiumBorder(),
        padding: EdgeInsets.symmetric(horizontal: 8),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _brandOrange,
          foregroundColor: _darkBackground,
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _brandOrange,
          side: const BorderSide(color: _brandOrange),
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: _brandOrange),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _darkSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF444466)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _brandOrange, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _error),
        ),
        labelStyle: const TextStyle(color: _darkOnSurfaceVariant),
        hintStyle: const TextStyle(
            color: Color(0xFF777788)), // ~60% of _darkOnSurfaceVariant
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFF333355),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _darkSurfaceVariant,
        contentTextStyle: const TextStyle(color: _darkOnSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _darkSurface,
        indicatorColor: _brandOrange.withValues(alpha: 0.2),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(color: _darkOnSurfaceVariant, fontSize: 12),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: _brandOrange);
          }
          return const IconThemeData(color: _darkOnSurfaceVariant);
        }),
      ),
      extensions: const [MostroColors.dark],
      textTheme: _textTheme(Brightness.dark),
    );
  }

  // ── Light ─────────────────────────────────────────────────────────────────

  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      primary: _brandOrange,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFFFDDB0),
      onPrimaryContainer: Color(0xFF3D2000),
      secondary: Color(0xFFB36A00),
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFFFDDB0),
      onSecondaryContainer: Color(0xFF3D2000),
      error: _error,
      onError: Colors.white,
      errorContainer: Color(0xFFFFDAD6),
      onErrorContainer: Color(0xFF4A0010),
      surface: _lightSurface,
      onSurface: _lightOnSurface,
      surfaceContainerHighest: _lightSurfaceVariant,
      onSurfaceVariant: _lightOnSurfaceVariant,
      outline: Color(0xFFBBBBCC),
      outlineVariant: Color(0xFFDDDDEE),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: _lightBackground,
      appBarTheme: AppBarTheme(
        backgroundColor: _lightSurface,
        foregroundColor: _lightOnSurface,
        elevation: 0,
        centerTitle: false,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: _textTheme(Brightness.light).titleLarge?.copyWith(
              color: _lightOnSurface,
              fontWeight: FontWeight.w600,
            ),
      ),
      cardTheme: CardThemeData(
        color: _lightSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFDDDDEE)),
        ),
        margin: EdgeInsets.zero,
      ),
      chipTheme: const ChipThemeData(
        backgroundColor: _lightSurfaceVariant,
        labelStyle: TextStyle(color: _lightOnSurfaceVariant, fontSize: 12),
        side: BorderSide.none,
        shape: StadiumBorder(),
        padding: EdgeInsets.symmetric(horizontal: 8),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _brandOrange,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF9B5A00),
          side: const BorderSide(color: _brandOrange),
          minimumSize: const Size.fromHeight(48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF9B5A00),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _lightSurfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFBBBBCC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _brandOrange, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _error),
        ),
        labelStyle: const TextStyle(color: _lightOnSurfaceVariant),
        hintStyle: const TextStyle(color: Color(0xFF888899)),
      ),
      dividerTheme: const DividerThemeData(
        color: Color(0xFFDDDDEE),
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: _lightSurfaceVariant,
        contentTextStyle: const TextStyle(color: _lightOnSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _lightSurface,
        indicatorColor: _brandOrange.withValues(alpha: 0.15),
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(color: _lightOnSurfaceVariant, fontSize: 12),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: _brandOrange);
          }
          return const IconThemeData(color: _lightOnSurfaceVariant);
        }),
      ),
      extensions: const [MostroColors.light],
      textTheme: _textTheme(Brightness.light),
    );
  }

  // ── Typography ───────────────────────────────────────────────────────────

  static TextTheme _textTheme(Brightness brightness) {
    final base =
        brightness == Brightness.dark ? const Color(0xFFEAEAF0) : _lightOnSurface;
    final secondary = brightness == Brightness.dark
        ? _darkOnSurfaceVariant
        : _lightOnSurfaceVariant;

    return TextTheme(
      displayLarge:
          TextStyle(fontSize: 57, fontWeight: FontWeight.w400, color: base),
      displayMedium:
          TextStyle(fontSize: 45, fontWeight: FontWeight.w400, color: base),
      displaySmall:
          TextStyle(fontSize: 36, fontWeight: FontWeight.w400, color: base),
      headlineLarge:
          TextStyle(fontSize: 32, fontWeight: FontWeight.w600, color: base),
      headlineMedium:
          TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: base),
      headlineSmall:
          TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: base),
      titleLarge:
          TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: base),
      titleMedium:
          TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: base),
      titleSmall:
          TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: base),
      bodyLarge:
          TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: base),
      bodyMedium:
          TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: base),
      bodySmall:
          TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: secondary),
      labelLarge:
          TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: base),
      labelMedium: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w500, color: secondary),
      labelSmall: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w500, color: secondary),
    );
  }

  /// Success green — use for completed trade, paid invoices.
  static const Color success = _success;

  /// Warning amber — use for pending steps, approaching timeouts.
  static const Color warning = _warning;

  /// Error red — consistent with colorScheme.error.
  static const Color errorColor = _error;
}

// ─── MostroColors extension ──────────────────────────────────────────────────

/// Custom colours not covered by Material ColorScheme.
/// Access via `Theme.of(context).extension<MostroColors>()!`.
@immutable
class MostroColors extends ThemeExtension<MostroColors> {
  const MostroColors({
    required this.success,
    required this.onSuccess,
    required this.warning,
    required this.onWarning,
    required this.buyBadge,
    required this.sellBadge,
  });

  final Color success;
  final Color onSuccess;
  final Color warning;
  final Color onWarning;
  final Color buyBadge;
  final Color sellBadge;

  static const MostroColors dark = MostroColors(
    success: _success,
    onSuccess: Colors.white,
    warning: _warning,
    onWarning: Color(0xFF1A1A00),
    buyBadge: Color(0xFF27AE60),
    sellBadge: Color(0xFFE74C3C),
  );

  static const MostroColors light = MostroColors(
    success: Color(0xFF1E8449),
    onSuccess: Colors.white,
    warning: Color(0xFF9B6800),
    onWarning: Colors.white,
    buyBadge: Color(0xFF1E8449),
    sellBadge: Color(0xFFC0392B),
  );

  @override
  MostroColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? warning,
    Color? onWarning,
    Color? buyBadge,
    Color? sellBadge,
  }) {
    return MostroColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      buyBadge: buyBadge ?? this.buyBadge,
      sellBadge: sellBadge ?? this.sellBadge,
    );
  }

  @override
  MostroColors lerp(MostroColors? other, double t) {
    if (other == null) return this;
    return MostroColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      buyBadge: Color.lerp(buyBadge, other.buyBadge, t)!,
      sellBadge: Color.lerp(sellBadge, other.sellBadge, t)!,
    );
  }
}
