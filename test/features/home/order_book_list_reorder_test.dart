import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';
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
    // index callback in `OrderBookList`. The list only: the grid cannot move
    // children by key (see the group below).
    testWidgets('as a list', (tester) async {
      await withClock(Clock.fixed(kFakeNow), () async {
        // Arrange — three orders on screen.
        await _pump(tester, _book([10, 20, 30]), columns: 1);
        const key = ValueKey<String>('order-20');
        final before = tester.element(find.byKey(key));
        expect(
          find.byType(OrderListItem),
          findsNWidgets(3),
          reason: 'all three rows should be laid out',
        );

        // Act — a newer order arrives and sorts to the top, shifting every
        // row below it by one.
        await _pump(tester, _book([5, 10, 20, 30]), columns: 1);

        // Assert — the row moved rather than being torn down and rebuilt.
        final after = tester.element(find.byKey(key));
        expect(
          identical(before, after),
          isTrue,
          reason:
              'the element should have been moved to its new index, not '
              'deactivated and re-inflated',
        );
      });
    });

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

  group('OrderBookList grid lays out an order that comes back', () {
    // An order leaves the book when someone takes it and comes back when the
    // take is cancelled or times out. `SliverMasonryGrid` cannot lay out a
    // child moved by `findChildIndexCallback`: with the list's index callback
    // the grid threw `Null check operator used on a null value` in
    // `performLayout` on every frame, blanking the whole book for a while.
    final changes = <String, List<List<int>>>{
      'an order in the middle leaves and comes back': [
        [10, 20, 30, 40],
        [10, 30, 40],
        [10, 20, 30, 40],
      ],
      'the first order leaves and comes back': [
        [10, 20, 30, 40],
        [20, 30, 40],
        [10, 20, 30, 40],
      ],
      'an older order comes back in the middle': [
        [10, 30, 40],
        [10, 20, 30, 40],
      ],
    };

    for (final columns in [2, 3]) {
      for (final MapEntry(key: name, value: books) in changes.entries) {
        testWidgets('with $columns columns: $name', (tester) async {
          await withClock(Clock.fixed(kFakeNow), () async {
            for (final book in books) {
              await _pump(tester, _book(book), columns: columns);
              await tester.pump();
              expect(tester.takeException(), isNull, reason: 'book $book');
            }

            expect(find.byType(OrderListItem), findsNWidgets(4));
          });
        });
      }
    }
  });

  group('OrderBookList grid fits long cards at 200% text', () {
    // Worst case for height: chips that wrap, two lines of payment methods,
    // a reputation strip that wraps.
    final orders = [
      for (var i = 0; i < 4; i++)
        fakeOrder(
          id: 'order-$i',
          fiatAmount: null,
          fiatAmountMin: 100000,
          fiatAmountMax: 2500000,
          paymentMethod:
              'SPEI, Retiro Cajero BBVA, Transferencia Banorte, '
              'Depósito en efectivo, Mercado Pago',
          rating: 4.78,
          tradeCount: 1600,
          daysActive: 2190,
          isMine: i.isEven,
          minutesAgo: i * 10,
        ),
    ];

    for (final (columns, width) in [(2, 700.0), (3, 900.0)]) {
      testWidgets('with $columns columns', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await withClock(Clock.fixed(kFakeNow), () async {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildDarkTheme(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder:
                  (context, child) => MediaQuery(
                    data: MediaQuery.of(
                      context,
                    ).copyWith(textScaler: const TextScaler.linear(2)),
                    child: child!,
                  ),
              home: Scaffold(
                body: OrderBookList(
                  orders: orders,
                  currencyFlags: const {'USD': '🇺🇸'},
                  reasons: const {'order-1': OrderReason.mostReputable},
                  columns: columns,
                  onOrderTap: (_) {},
                ),
              ),
            ),
          );
        });

        expect(tester.takeException(), isNull);
        expect(find.byType(OrderListItem), findsWidgets);
      });
    }
  });
}
