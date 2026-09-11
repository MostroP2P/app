import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/widgets/order_list_empty.dart';
import 'package:mostro/l10n/app_localizations.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<String> currencies = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [currencyFilterProvider.overrideWith((ref) => currencies)],
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: OrderListEmpty()),
      ),
    ),
  );
  return ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
}

void main() {
  testWidgets('without filters it explains and offers nothing to clear', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('No orders available'), findsOneWidget);
    expect(
      find.text('New orders appear here as soon as they are published.'),
      findsOneWidget,
    );
    expect(find.text('Clear filters'), findsNothing);
  });

  testWidgets('with filters it offers to clear them, and clearing works', (
    tester,
  ) async {
    final container = await _pump(tester, currencies: ['USD']);

    expect(find.text('No orders match your filters.'), findsOneWidget);
    await tester.tap(find.text('Clear filters'));
    await tester.pump();

    expect(container.read(currencyFilterProvider), isEmpty);
    expect(find.text('Clear filters'), findsNothing);
  });
}
