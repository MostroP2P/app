import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Pumps [child] inside a themed [MaterialApp] for golden capture.
///
/// Wires the app themes and [AppLocalizations] delegates so widgets that read
/// `Theme.of(context).extension<AppColors>()` or `AppLocalizations.of(context)`
/// render correctly. Pass [width] to bound width-hungry widgets (e.g. cards).
Future<void> pumpForGolden(
  WidgetTester tester,
  Widget child, {
  required Brightness brightness,
  double? width,
}) async {
  final theme =
      brightness == Brightness.dark ? buildDarkTheme() : buildLightTheme();

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Center(
          child: width != null ? SizedBox(width: width, child: child) : child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
