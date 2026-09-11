import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/providers/payment_methods_provider.dart';
import 'package:mostro/features/order/screens/payment_method_picker_screen.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/features/order/widgets/payment_method_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import '../../../support/provider_harness.dart';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  final container = createContainer(
    overrides: [
      selectedFiatCodeProvider.overrideWith((ref) => 'USD'),
      paymentMethodsDataProvider.overrideWith(
        (ref) async => {
          'USD': ['Zelle', 'Cash App', 'Wire'],
        },
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PaymentMethodPickerScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('PaymentMethodPickerScreen', () {
    testWidgets('lists the currency\'s methods and toggles them in place',
        (tester) async {
      final container = await _pump(tester);
      expect(find.text('Zelle'), findsOneWidget);
      expect(find.text('Wire'), findsOneWidget);

      await tester.tap(find.text('Zelle'));
      await tester.pump();
      expect(container.read(selectedPaymentMethodsProvider), ['Zelle']);

      await tester.tap(find.text('Zelle'));
      await tester.pump();
      expect(container.read(selectedPaymentMethodsProvider), isEmpty);
    });

    testWidgets('the search narrows the list', (tester) async {
      await _pump(tester);
      await tester.enterText(find.byType(TextField).first, 'wi');
      await tester.pump();

      expect(find.text('Wire'), findsOneWidget);
      expect(find.text('Zelle'), findsNothing);
    });

    testWidgets('turns a custom method into a chip, sanitized', (tester) async {
      final container = await _pump(tester);
      final customField = find.byType(TextField).last;

      await tester.enterText(customField, '  My, "bank"   [x]  ');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();

      expect(container.read(customPaymentMethodsProvider), ['My bank x']);
      // The field is cleared and the new method shows as chosen in the list.
      expect(tester.widget<TextField>(customField).controller!.text, isEmpty);
      expect(find.text('My bank x'), findsOneWidget);
    });

    testWidgets('a custom name the catalogue has selects that entry instead',
        (tester) async {
      final container = await _pump(tester);
      await tester.enterText(find.byType(TextField).last, ' zelle ');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();

      expect(container.read(selectedPaymentMethodsProvider), ['Zelle']);
      expect(container.read(customPaymentMethodsProvider), isEmpty);
      expect(find.text('Zelle'), findsOneWidget);
    });

    testWidgets('an empty or duplicate custom method adds nothing',
        (tester) async {
      final container = await _pump(tester);
      final customField = find.byType(TextField).last;

      await tester.enterText(customField, ' , ');
      await tester.pump();
      final addButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add'),
      );
      expect(addButton.onPressed, isNull);

      await tester.enterText(customField, 'Pix');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      await tester.enterText(customField, 'Pix');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();

      expect(container.read(customPaymentMethodsProvider), ['Pix']);
    });
  });

  group('sanitizeCustomMethod', () {
    test('strips wire-breaking characters and collapses whitespace', () {
      expect(sanitizeCustomMethod('  a,b  "c" [d] {e}\\f '), 'a b c d e f');
    });

    test('is empty when nothing survives', () {
      expect(sanitizeCustomMethod(' , "" '), isEmpty);
    });
  });
}
