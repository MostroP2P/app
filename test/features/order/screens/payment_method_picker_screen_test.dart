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

/// Pumps the picker on top of a host screen, so a cancel or a confirm has
/// somewhere to pop back to — as it does in the create-order flow.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<String> selected = const [],
  List<String> custom = const [],
}) async {
  final container = createContainer(
    overrides: [
      selectedFiatCodeProvider.overrideWith((ref) => 'USD'),
      // Seeded before the screen opens: it copies the form's methods into
      // its draft in initState.
      selectedPaymentMethodsProvider.overrideWith((ref) => selected),
      customPaymentMethodsProvider.overrideWith((ref) => custom),
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
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PaymentMethodPickerScreen(),
                        ),
                      ),
                  child: const Text('open'),
                ),
              ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

Future<void> _addCustom(WidgetTester tester, String text) async {
  await tester.tap(find.text('Add custom payment method'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, text);
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, 'Add'));
  await tester.pumpAndSettle();
}

Finder get _confirm => find.widgetWithText(FilledButton, 'Confirm methods');

void main() {
  group('PaymentMethodPickerScreen', () {
    testWidgets('a tap marks a method without writing the form yet', (
      tester,
    ) async {
      final container = await _pump(tester);
      expect(find.text('Zelle'), findsOneWidget);
      expect(find.text('Wire'), findsOneWidget);

      await tester.tap(find.text('Zelle'));
      await tester.pumpAndSettle();

      // Chosen: the summary chip is a second copy of the name.
      expect(find.text('Chosen'), findsOneWidget);
      expect(find.text('Zelle'), findsNWidgets(2));
      expect(find.text('1 method selected'), findsOneWidget);
      // Nothing reached the form: only `Confirm methods` does that.
      expect(container.read(selectedPaymentMethodsProvider), isEmpty);
    });

    testWidgets('confirm writes the selection to the form and closes', (
      tester,
    ) async {
      final container = await _pump(tester);
      await tester.tap(find.text('Zelle'));
      await tester.tap(find.text('Wire'));
      await tester.pumpAndSettle();
      expect(find.text('2 methods selected'), findsOneWidget);

      await tester.tap(_confirm);
      await tester.pumpAndSettle();

      expect(container.read(selectedPaymentMethodsProvider), ['Zelle', 'Wire']);
      expect(find.byType(PaymentMethodPickerScreen), findsNothing);
    });

    testWidgets('confirm is disabled while nothing is selected', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Choose at least one method'), findsOneWidget);
      expect(tester.widget<FilledButton>(_confirm).onPressed, isNull);
    });

    testWidgets('back with changes asks, and discarding keeps the form', (
      tester,
    ) async {
      final container = await _pump(tester, selected: ['Wire']);
      await tester.tap(find.text('Zelle'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Discard the changes?'), findsOneWidget);

      // Keeping stays on the screen with the draft intact.
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.byType(PaymentMethodPickerScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();

      expect(find.byType(PaymentMethodPickerScreen), findsNothing);
      expect(container.read(selectedPaymentMethodsProvider), ['Wire']);
    });

    testWidgets('back without changes leaves without asking', (tester) async {
      await _pump(tester);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Discard the changes?'), findsNothing);
      expect(find.byType(PaymentMethodPickerScreen), findsNothing);
    });

    testWidgets('the search narrows the list but not the summary', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Zelle'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'wi');
      await tester.pumpAndSettle();

      expect(find.text('Wire'), findsOneWidget);
      // Out of the list, still in the summary chip and in the count.
      expect(find.text('Zelle'), findsOneWidget);
      expect(find.text('1 method selected'), findsOneWidget);
    });

    testWidgets('the sheet turns free text into a chosen method, sanitized', (
      tester,
    ) async {
      final container = await _pump(tester);
      await _addCustom(tester, '  My, "bank"   [x]  ');

      expect(find.text('My bank x'), findsNWidgets(2)); // row + summary chip
      expect(find.text('1 method selected'), findsOneWidget);

      await tester.tap(_confirm);
      await tester.pumpAndSettle();
      expect(container.read(customPaymentMethodsProvider), ['My bank x']);
    });

    testWidgets('a custom name the catalogue has selects that entry instead', (
      tester,
    ) async {
      final container = await _pump(tester);
      await _addCustom(tester, ' zelle ');

      await tester.tap(_confirm);
      await tester.pumpAndSettle();
      expect(container.read(selectedPaymentMethodsProvider), ['Zelle']);
      expect(container.read(customPaymentMethodsProvider), isEmpty);
    });

    testWidgets('an empty custom method cannot be added', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Add custom payment method'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, ' , ');
      await tester.pump();

      final add = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add'),
      );
      expect(add.onPressed, isNull);
    });

    testWidgets('the same custom method is not added twice', (tester) async {
      final container = await _pump(tester);
      await _addCustom(tester, 'Pix');
      await _addCustom(tester, 'pix');

      await tester.tap(_confirm);
      await tester.pumpAndSettle();
      expect(container.read(customPaymentMethodsProvider), ['Pix']);
    });

    testWidgets('every row carries its own key', (tester) async {
      // The list is rebuilt on every keystroke of the search. Unkeyed, its
      // children reconcile by position and a row's 120ms tint animation
      // lands on whichever method took its place. The `custom-` prefix
      // keeps a custom method apart from a catalogue entry of the same
      // name — a currency switch can put both in the list, and two equal
      // keys throw.
      await _pump(tester, custom: ['Zelle']);

      final keys =
          tester
              .widgetList<Padding>(
                find.descendant(
                  of: find.byType(ListView),
                  matching: find.byType(Padding),
                ),
              )
              .map((p) => p.key)
              .whereType<ValueKey<String>>()
              .map((k) => k.value)
              .toList();

      expect(keys, containsAll(['Zelle', 'Cash App', 'Wire', 'custom-Zelle']));
      expect(keys.toSet(), hasLength(keys.length));
    });

    testWidgets('a summary chip removes its method', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);
      await tester.tap(find.text('Zelle'));
      await tester.pumpAndSettle();

      // The "×" is announced apart from the chip's own label.
      expect(
        tester.getSemantics(find.byIcon(Icons.close)).label,
        'Remove Zelle',
      );
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Chosen'), findsNothing);
      expect(find.text('Choose at least one method'), findsOneWidget);
      semantics.dispose();
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
