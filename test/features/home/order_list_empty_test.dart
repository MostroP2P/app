import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/widgets/order_list_empty.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../support/fake_orders.dart';

const _genericHint = 'New orders appear here as soon as they are published.';
const _filteredHint = 'No orders match your filters.';

/// Pumps the empty state on the default Buy BTC tab, which lists sell orders.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required List<OrderItem> book,
  List<String> currencies = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currencyFilterProvider.overrideWith((ref) => currencies),
        orderBookProvider.overrideWith((ref) => Stream.value(book)),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: OrderListEmpty()),
      ),
    ),
  );
  // Let the overridden book stream deliver.
  await tester.pump();
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
}

void main() {
  testWidgets('without filters it explains and offers nothing to clear', (
    tester,
  ) async {
    await _pump(tester, book: []);

    expect(find.text('No orders available'), findsOneWidget);
    expect(find.text(_genericHint), findsOneWidget);
    expect(find.text('Clear filters'), findsNothing);
  });

  testWidgets('when filters hide the tab orders it offers to clear them', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      book: [fakeOrder(kind: 'sell', fiatCode: 'EUR')],
      currencies: ['USD'],
    );

    expect(find.text(_filteredHint), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pump();

    expect(container.read(currencyFilterProvider), isEmpty);
    expect(find.text('Clear filters'), findsNothing);
  });

  testWidgets('does not blame the filters when the tab is empty anyway', (
    tester,
  ) async {
    // Only a buy order, which the Buy BTC tab does not list.
    await _pump(
      tester,
      book: [fakeOrder(kind: 'buy', fiatCode: 'USD')],
      currencies: ['USD'],
    );

    expect(find.text(_genericHint), findsOneWidget);
    expect(find.text(_filteredHint), findsNothing);
    expect(find.text('Clear filters'), findsNothing);
  });
}
