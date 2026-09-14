import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/widgets/order_sort_sheet.dart';
import 'package:mostro/l10n/app_localizations.dart';

void main() {
  testWidgets('lists the three criteria and applies the one tapped', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildDarkTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed: () => showOrderSortSheet(context),
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

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Sort by'), findsOneWidget);
    expect(find.text('Newest'), findsOneWidget);
    expect(find.text('Best premium'), findsOneWidget);
    await tester.tap(find.text('Best reputation'));
    await tester.pumpAndSettle();

    expect(container.read(orderSortProvider), OrderSort.bestReputation);
    expect(find.text('Sort by'), findsNothing);
  });
}
