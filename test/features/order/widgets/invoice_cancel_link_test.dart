import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/invoice_widgets.dart';

/// Issue #721: a button's `textStyle` replaces the theme's `labelLarge`
/// instead of merging with it, so a style without a family drops Outfit and
/// the label falls back to the platform font (Roboto on Android and Linux).
void main() {
  for (final danger in [true, false]) {
    testWidgets('the cancel link renders in the interface family '
        '(danger: $danger)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildDarkTheme(),
          home: Scaffold(
            body: InvoiceCancelLink(
              label: 'Cancel trade',
              danger: danger,
              onPressed: () {},
            ),
          ),
        ),
      );

      final label = tester.widget<RichText>(
        find.descendant(
          of: find.byType(InvoiceCancelLink),
          matching: find.byType(RichText),
        ),
      );
      expect(label.text.style?.fontFamily, AppFonts.ui);
    });
  }
}
