import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';
import '../../../support/provider_harness.dart';

void main() {
  testWidgets('polling continues after escrow settles until payout succeeds', (
    tester,
  ) async {
    var lookups = 0;
    final requestedOrders = <String>[];
    final container = createContainer(
      overrides: [
        tradeStatusLookupProvider.overrideWithValue((orderId) async {
          requestedOrders.add(orderId);
          return lookups++ == 0
              ? OrderStatus.settledHoldInvoice
              : OrderStatus.success;
        }),
      ],
    );
    final observed = <OrderStatus>[];
    container.listen<AsyncValue<OrderStatus>>(
      tradeStatusProvider('order-payout'),
      (_, next) {
        if (next.hasValue) observed.add(next.requireValue);
      },
      fireImmediately: true,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SizedBox()),
    );
    await tester.pump();
    expect(
      container.read(tradeStatusProvider('order-payout')).hasError,
      false,
      reason: container.read(tradeStatusProvider('order-payout')).toString(),
    );
    expect(lookups, 1);
    expect(observed, [OrderStatus.settledHoldInvoice]);
    await tester.pump(const Duration(seconds: 2));
    expect(observed, [OrderStatus.settledHoldInvoice, OrderStatus.success]);
    await tester.pump(const Duration(seconds: 4));
    expect(lookups, 2);
    expect(requestedOrders, ['order-payout', 'order-payout']);
  });

  group('shownTradeStatus', () {
    test('an ended row wins over any live status', () {
      for (final row in OrderStatus.values.where(isTerminalTradeStatus)) {
        for (final live in OrderStatus.values) {
          for (final isTake in [true, false]) {
            expect(
              shownTradeStatus(row: row, live: live, isTake: isTake),
              row,
              reason: 'row=$row live=$live isTake=$isTake',
            );
          }
        }
      }
    });

    test('a public pending never shows over a take that is still open', () {
      final open = OrderStatus.values.where((s) => !isTerminalTradeStatus(s));
      for (final row in open) {
        expect(
          shownTradeStatus(row: row, live: OrderStatus.pending, isTake: true),
          row,
          reason: 'row=$row',
        );
        // The maker's own order is `pending` for real.
        expect(
          shownTradeStatus(row: row, live: OrderStatus.pending, isTake: false),
          OrderStatus.pending,
          reason: 'row=$row',
        );
      }
    });

    test('any other live status wins over an open row', () {
      final open = OrderStatus.values.where((s) => !isTerminalTradeStatus(s));
      for (final row in open) {
        for (final live in OrderStatus.values) {
          if (live == OrderStatus.pending) continue;
          for (final isTake in [true, false]) {
            expect(
              shownTradeStatus(row: row, live: live, isTake: isTake),
              live,
              reason: 'row=$row live=$live isTake=$isTake',
            );
          }
        }
      }
    });

    test('the row stands in while there is no live status yet', () {
      expect(
        shownTradeStatus(
          row: OrderStatus.waitingPayment,
          live: null,
          isTake: true,
        ),
        OrderStatus.waitingPayment,
      );
    });
  });

  group('participatingRole', () {
    const orderId = 'order-x';

    test('no row on the order is no role', () {
      expect(participatingRole(const [], orderId), isNull);
      expect(
        participatingRole([fakeTrade(id: 'other')], orderId),
        isNull,
        reason: 'another order\'s row',
      );
    });

    test('a take still open is a participant', () {
      for (final status in OrderStatus.values.where(
        (s) => !isTerminalTradeStatus(s),
      )) {
        expect(
          participatingRole([
            fakeTrade(
              id: 'x',
              orderId: orderId,
              status: status,
              role: TradeRole.seller,
            ),
          ], orderId),
          TradeRole.seller,
          reason: '$status',
        );
      }
    });

    test('a take that has ended is not', () {
      for (final status in OrderStatus.values.where(isTerminalTradeStatus)) {
        final ended = fakeTrade(id: 'x', orderId: orderId, status: status);
        expect(isEndedTake(ended), isTrue, reason: '$status');
        expect(participatingRole([ended], orderId), isNull, reason: '$status');
      }
    });

    test("a maker's row always is, ended or not", () {
      final maker = fakeTrade(
        id: 'x',
        orderId: orderId,
        status: OrderStatus.canceled,
        isMine: true,
      );
      expect(isEndedTake(maker), isFalse);
      expect(participatingRole([maker], orderId), TradeRole.buyer);
    });

    test('an open row wins over an ended one on the same order', () {
      // Databases from before a take replaced its order's earlier row can
      // hold both, in either order.
      final ended = fakeTrade(
        id: 'ended',
        orderId: orderId,
        status: OrderStatus.canceled,
      );
      final open = fakeTrade(
        id: 'open',
        orderId: orderId,
        status: OrderStatus.active,
        role: TradeRole.seller,
      );
      expect(participatingRole([ended, open], orderId), TradeRole.seller);
      expect(participatingRole([open, ended], orderId), TradeRole.seller);
    });
  });
}
