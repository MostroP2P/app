import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/l10n/app_localizations.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';

/// Root application widget.
///
/// Wraps the widget tree with [ProviderScope] and wires GoRouter +
/// localisation. RustLib initialisation is deferred to Phase 3 (US1)
/// when the identity API is ready.
class MostroApp extends ConsumerWidget {
  const MostroApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Expose the Riverpod container to the router's redirect callback so it
    // can read firstRunProvider without a BuildContext.
    routerContainer = ProviderScope.containerOf(context, listen: false);

    // Theme selection is wired in Phase 3; dark mode is the default.
    return MaterialApp.router(
      title: 'Mostro',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: ThemeMode.dark,
      routerConfig: appRouter,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
