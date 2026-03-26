/// Mostro app entry point.
///
/// Wires together:
///   - Riverpod ProviderScope
///   - go_router (appRouter)
///   - AppTheme dark/light with AnimatedTheme
///   - flutter_localizations delegates
///   - ThemeMode driven by settingsProvider
library app;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme/app_theme.dart';
import 'providers/settings_provider.dart';

/// Root widget — wrap with [ProviderScope] in main.dart.
class MostroApp extends ConsumerWidget {
  const MostroApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themePreference = ref.watch(themePreferenceProvider);

    return MaterialApp.router(
      title: 'Mostro',
      debugShowCheckedModeBanner: false,

      // ── Theme ────────────────────────────────────────────────────────────
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _toThemeMode(themePreference),
      // AnimatedTheme is applied automatically by MaterialApp; the duration
      // below is the default — override here if needed.
      // themeAnimationDuration: const Duration(milliseconds: 200),

      // ── Routing ──────────────────────────────────────────────────────────
      routerConfig: appRouter,

      // ── Localization ─────────────────────────────────────────────────────
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        // Additional locales added in Phase 12 (i18n).
      ],
    );
  }

  ThemeMode _toThemeMode(ThemePreference pref) {
    return switch (pref) {
      ThemePreference.light => ThemeMode.light,
      ThemePreference.dark => ThemeMode.dark,
      ThemePreference.system => ThemeMode.system,
    };
  }
}
