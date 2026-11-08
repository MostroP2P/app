import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/shared/widgets/order_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/catalogue_fixtures.dart';
import '../../support/fake_orders.dart';

/// Opens the Filters dialog over a stored selection, with [book] as the
/// order book, and returns the scope's container.
Future<ProviderContainer> _open(
  WidgetTester tester,
  OrderFilters stored, {
  List<OrderItem> book = const [],
  List<String> currencies = const ['USD', 'EUR'],
  Size size = const Size(420, 1400),
  Locale locale = const Locale('en'),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        catalogueOverride(),
        availableCurrencyCodesProvider.overrideWithValue(currencies),
        orderBookProvider.overrideWith((ref) => Stream.value(book)),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: locale,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder:
              (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showOrderFilterDialog(context),
                  child: const Text('open'),
                ),
              ),
        ),
      ),
    ),
  );
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Scaffold)),
  );
  await container.read(orderFiltersProvider.notifier).set(stored);
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return container;
}

FilterChip _chip(WidgetTester tester, String label) => tester.widget(
  find.ancestor(of: find.text(label), matching: find.byType(FilterChip)),
);

void main() {
  // DS-A11Y-4: the stablecoins section (#884) is a header and a second
  // Wrap inside the modal; at 320 dp and 2x text in German nothing overflows.
  testWidgets('fits at 320 dp and 2x text in German with stablecoins', (
    tester,
  ) async {
    await _open(
      tester,
      const OrderFilters(),
      currencies: const ['USD', 'EUR', 'USDT'],
      size: const Size(320, 640),
      locale: const Locale('de'),
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('USDT'), findsOneWidget);
  });

  testWidgets('a stored value the catalogue does not list is shown, selected', (
    tester,
  ) async {
    // Filters outlive the app version that stored them (#575): a value the
    // dialog did not show would be one the user could never deselect.
    await _open(
      tester,
      const OrderFilters(currencies: ['XYZ'], paymentMethods: ['Nequi']),
    );

    expect(_chip(tester, 'XYZ').selected, isTrue);
    expect(_chip(tester, 'Nequi').selected, isTrue);
    // The catalogue is still there, unselected.
    expect(_chip(tester, 'USD').selected, isFalse);
  });

  testWidgets('and can be deselected like any other', (tester) async {
    final container = await _open(
      tester,
      const OrderFilters(currencies: ['XYZ', 'USD']),
    );

    await tester.tap(find.text('XYZ'));
    await tester.pumpAndSettle();

    expect(container.read(orderFiltersProvider).currencies, ['USD']);
    // Once deselected it is no longer anything the catalogue offers.
    expect(find.text('XYZ'), findsNothing);
  });

  testWidgets('the payment methods are the ones the book carries', (
    tester,
  ) async {
    final container = await _open(
      tester,
      const OrderFilters(),
      book: [
        fakeOrder(id: 'sepa', kind: 'sell', paymentMethod: 'SEPA instant'),
        fakeOrder(id: 'bizum', kind: 'sell', paymentMethod: 'Bizum'),
      ],
    );

    expect(_chip(tester, 'Bizum').selected, isFalse);
    // The fixed list is gone: no chip for a method no order offers.
    expect(find.text('Zelle'), findsNothing);

    await tester.tap(find.text('SEPA instant'));
    await tester.pumpAndSettle();

    expect(container.read(orderFiltersProvider).paymentMethods, [
      'SEPA instant',
    ]);
  });

  testWidgets('a stored method shows once, whatever its case', (tester) async {
    final container = await _open(
      tester,
      const OrderFilters(paymentMethods: ['sepa Instant']),
      book: [
        fakeOrder(id: 'sepa', kind: 'sell', paymentMethod: 'SEPA instant'),
      ],
    );

    expect(_chip(tester, 'sepa Instant').selected, isTrue);
    expect(find.text('SEPA instant'), findsNothing);

    await tester.tap(find.text('sepa Instant'));
    await tester.pumpAndSettle();

    expect(container.read(orderFiltersProvider).paymentMethods, isEmpty);
    expect(_chip(tester, 'SEPA instant').selected, isFalse);
  });

  testWidgets('a pick in the dialog is written to disk', (tester) async {
    await _open(tester, const OrderFilters());

    await tester.tap(find.text('EUR'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      OrderFilters.fromStored(prefs.getString(kOrderFiltersKey)).currencies,
      ['EUR'],
    );
  });

  testWidgets('Reset clears the stored filters too', (tester) async {
    final container = await _open(
      tester,
      const OrderFilters(currencies: ['USD'], rating: (min: 3.0, max: 5.0)),
    );

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();

    expect(container.read(orderFiltersProvider), const OrderFilters());
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(kOrderFiltersKey), isFalse);
  });
}
