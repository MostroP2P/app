/// Mostro app entry point.
///
/// Wires together:
///   - Riverpod ProviderScope
///   - go_router (appRouter) with identity-based redirect guard
///   - AppTheme dark/light with AnimatedTheme
///   - flutter_localizations delegates
///   - ThemeMode driven by settingsProvider
library app;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/identity_provider.dart';
import 'router.dart';
import 'theme/app_theme.dart';
import 'providers/settings_provider.dart';

/// Root widget — wrap with [ProviderScope] in main.dart.
class MostroApp extends ConsumerWidget {
  const MostroApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themePreference = ref.watch(themePreferenceProvider);

    // Feed identity state into the router notifier so go_router re-evaluates
    // redirect guards whenever login/logout occurs.
    ref.listen<AsyncValue<IdentityInfo?>>(
      identityProvider,
      (_, state) => routerNotifier.update(state),
    );

    return MaterialApp.router(
      title: 'Mostro',
      debugShowCheckedModeBanner: false,

      // ── Theme ────────────────────────────────────────────────────────────
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: _toThemeMode(themePreference),

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
