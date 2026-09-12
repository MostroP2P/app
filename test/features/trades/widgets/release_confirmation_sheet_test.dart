import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/trades/widgets/release_confirmation_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';

/// Releasing cannot be undone, so the trade screen asks first — in a sheet
/// whose answer decides whether the release is published at all.
void main() {
  final en = AppLocalizationsEn();

  Future<Future<bool?>> open(WidgetTester tester) async {
    late Future<bool?> result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => result = showReleaseConfirmationSheet(context),
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('shows the question, the warning and both answers', (
    tester,
  ) async {
    await open(tester);

    expect(find.text(en.releaseSheetTitle), findsOneWidget);
    expect(find.text(en.releaseSheetBody), findsOneWidget);
    expect(find.text(en.releaseSheetConfirm), findsOneWidget);
    expect(find.text(en.releaseSheetBack), findsOneWidget);
  });

  testWidgets('Yes, release resolves true', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text(en.releaseSheetConfirm));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
    expect(find.text(en.releaseSheetTitle), findsNothing);
  });

  testWidgets('Back resolves false', (tester) async {
    final result = await open(tester);
    await tester.tap(find.text(en.releaseSheetBack));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
  });

  testWidgets('dismissing by the scrim resolves null', (tester) async {
    final result = await open(tester);
    await tester.tapAt(const Offset(400, 20));
    await tester.pumpAndSettle();

    expect(await result, isNull);
  });
}
