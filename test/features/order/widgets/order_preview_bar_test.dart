import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/models/create_order_rules.dart';
import 'package:mostro/features/order/widgets/order_preview_bar.dart';
import 'package:mostro/l10n/app_localizations.dart';

void main() {
  // DS-CMP-20: leaving the create form undoes nothing, so it is a neutral
  // link, never an outlined button that weighs as much as publishing.
  testWidgets('leaving the form is a neutral link, not an outlined button', (
    tester,
  ) async {
    var cancelled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          bottomNavigationBar: OrderPreviewBar(
            fragments: null,
            error: null,
            premiumFavour: PremiumFavour.zero,
            canSubmit: true,
            isSubmitting: false,
            onCancel: () => cancelled = true,
            onSubmit: () {},
          ),
        ),
      ),
    );

    expect(find.widgetWithText(OutlinedButton, 'Cancel'), findsNothing);
    final link = find.widgetWithText(TextButton, 'Cancel');
    expect(link, findsOneWidget);
    final label = tester.widget<RichText>(
      find.descendant(of: link, matching: find.byType(RichText)),
    );
    expect(label.text.style?.color, OrderBookPalette.dark.textSecondary);

    await tester.tap(link);
    expect(cancelled, isTrue);
  });
}
