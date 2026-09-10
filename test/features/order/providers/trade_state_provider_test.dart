import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/src/rust/api/types.dart';

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
}
