import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/widgets/order_book_list.dart';
import 'package:mostro/features/home/widgets/order_list_item.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../support/fake_orders.dart';

/// Newest first, which is the order `filteredOrdersProvider` produces.
List<OrderItem> _book(List<int> minutesAgo) => [
  for (final m in minutesAgo) fakeOrder(id: 'order-$m', minutesAgo: m),
];

Future<void> _pump(
  WidgetTester tester,
  List<OrderItem> orders, {
  required int columns,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: OrderBookList(
          orders: orders,
          currencyFlags: const {'USD': '🇺🇸'},
          reasons: const {},
          columns: columns,
          onOrderTap: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  group('OrderBookList keeps a row with its order across a re-sort', () {
    // A `ValueKey` on its own does the opposite: in a lazy sliver the new
    // widget at index *i* is compared against the old element at *i*, two
    // different keys fail `Widget.canUpdate`, and the element is discarded and
    // re-inflated. Element identity is therefore the assertion — a rebuilt row
    // keeps its Element, a re-created one does not — and it fails without the
    // index callbacks in `OrderBookList`.
    for (final (label, columns) in [('list', 1), ('grid', 2)]) {
      testWidgets('as a $label', (tester) async {
        await withClock(Clock.fixed(kFakeNow), () async {
          // Arrange — three orders on screen.
          await _pump(tester, _book([10, 20, 30]), columns: columns);
          const key = ValueKey<String>('order-20');
          final before = tester.element(find.byKey(key));
          expect(
            find.byType(OrderListItem),
            findsNWidgets(3),
            reason: 'all three rows should be laid out',
          );

          // Act — a newer order arrives and sorts to the top, shifting every
          // row below it by one.
          await _pump(tester, _book([5, 10, 20, 30]), columns: columns);

          // Assert — the row moved rather than being torn down and rebuilt.
          final after = tester.element(find.byKey(key));
          expect(
            identical(before, after),
            isTrue,
            reason: 'the element should have been moved to its new index, not '
                'deactivated and re-inflated',
          );
        });
      });
    }

    testWidgets('and a removed order takes its row with it', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        // Arrange
        await _pump(tester, _book([10, 20, 30]), columns: 1);

        // Act — the middle order is taken and leaves the book.
        await _pump(tester, _book([10, 30]), columns: 1);

        // Assert — the survivors are still there and the gone one is not, so
        // the index callback returning null for an unknown key is handled.
        expect(find.byKey(const ValueKey('order-20')), findsNothing);
        expect(find.byKey(const ValueKey('order-10')), findsOneWidget);
        expect(find.byKey(const ValueKey('order-30')), findsOneWidget);
      });
    });
  });
}
