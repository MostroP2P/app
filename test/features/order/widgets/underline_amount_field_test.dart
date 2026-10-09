import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/underline_amount_field.dart';

/// The decoration the field's [TextField] actually renders with, after the
/// theme's defaults are applied to it.
InputDecoration _rendered(WidgetTester tester) =>
    tester
        .widget<InputDecorator>(
          find.descendant(
            of: find.byType(UnderlineAmountField),
            matching: find.byType(InputDecorator),
          ),
        )
        .decoration;

Future<void> _pump(
  WidgetTester tester,
  ThemeData theme, {
  bool hasError = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: theme,
    home: Scaffold(
      body: UnderlineAmountField(
        controller: TextEditingController(text: '1.111'),
        hasError: hasError,
        trailing: const Text('ARS'),
      ),
    ),
  ),
);

/// The field draws its own underline under the value and the trailing
/// widget; the [TextField] inside must paint nothing of its own.
void _expectNoThemeChrome(InputDecoration d) {
  expect(d.filled, isFalse, reason: 'the v1 fill shows behind the value');
  for (final border in [
    d.enabledBorder,
    d.focusedBorder,
    d.errorBorder,
    d.focusedErrorBorder,
    d.disabledBorder,
  ]) {
    expect(
      border,
      InputBorder.none,
      reason: "the theme's underline doubles the field's own",
    );
  }
}

void main() {
  // Issue #728 (DS-CMP-10, DS-CMP-19): the field set only
  // `border: InputBorder.none`, so v1's input theme still painted its fill
  // behind the figure and its own underline above the field's.
  for (final (name, theme) in [
    ('dark', buildDarkTheme()),
    ('light', buildLightTheme()),
  ]) {
    group('under the $name theme', () {
      testWidgets('paints no fill and no second underline', (tester) async {
        await _pump(tester, theme);
        _expectNoThemeChrome(_rendered(tester));
      });

      testWidgets('still none once focused', (tester) async {
        await _pump(tester, theme);
        await tester.tap(find.byType(TextField));
        await tester.pump();
        _expectNoThemeChrome(_rendered(tester));
      });

      testWidgets('still none in the error state', (tester) async {
        await _pump(tester, theme, hasError: true);
        _expectNoThemeChrome(_rendered(tester));
      });
    });
  }
}
