import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/shared/widgets/trade_action_listener.dart';
import 'package:mostro/src/rust/api/types.dart';

void main() {
  late StreamController<TradeUpdate> updates;
  late List<String> navigated;

  setUp(() {
    updates = StreamController<TradeUpdate>();
    navigated = [];
  });

  tearDown(() => updates.close());

  Future<ProviderContainer> pumpListener(
    WidgetTester tester, {
    required Future<TradeRole?> Function(String orderId) resolveRole,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [tradeUpdatesProvider.overrideWith((ref) => updates.stream)],
        child: TradeActionListener(
          resolveRole: resolveRole,
          navigate: navigated.add,
          child: const SizedBox.shrink(),
        ),
      ),
    );
    return ProviderScope.containerOf(
      tester.element(find.byType(TradeActionListener)),
      listen: false,
    );
  }

  testWidgets('actionable status navigates and records the role', (
    tester,
  ) async {
    final container = await pumpListener(
      tester,
      resolveRole: (_) async => TradeRole.seller,
    );

    updates.add(
      const TradeUpdate(orderId: 'o1', status: OrderStatus.waitingPayment),
    );
    await tester.pump();
    await tester.pump();

    expect(navigated, [AppRoute.payInvoicePath('o1')]);
    expect(container.read(tradeRoleProvider), {'o1': false});
  });

  testWidgets('buyer is sent to add-invoice on WaitingBuyerInvoice', (
    tester,
  ) async {
    final container = await pumpListener(
      tester,
      resolveRole: (_) async => TradeRole.buyer,
    );

    updates.add(
      const TradeUpdate(orderId: 'o1', status: OrderStatus.waitingBuyerInvoice),
    );
    await tester.pump();
    await tester.pump();

    expect(navigated, [AppRoute.addInvoicePath('o1')]);
    expect(container.read(tradeRoleProvider), {'o1': true});
  });

  testWidgets('WaitingTakerBond opens the pay-bond screen for either side', (
    tester,
  ) async {
    final container = await pumpListener(
      tester,
      resolveRole: (_) async => TradeRole.seller,
    );

    updates.add(
      const TradeUpdate(orderId: 'o1', status: OrderStatus.waitingTakerBond),
    );
    await tester.pump();
    await tester.pump();

    expect(navigated, [AppRoute.payBondPath('o1')]);
    expect(container.read(tradeRoleProvider), {'o1': false});
  });

  testWidgets('WaitingTakerBond without a local row does not navigate', (
    tester,
  ) async {
    // No trade row (replay for an order this device never took, or a
    // failed lookup): the pay-bond screen would have nothing to load.
    final container = await pumpListener(
      tester,
      resolveRole: (_) async => null,
    );

    updates.add(
      const TradeUpdate(orderId: 'o1', status: OrderStatus.waitingTakerBond),
    );
    await tester.pump();
    await tester.pump();

    expect(navigated, isEmpty);
    expect(container.read(tradeRoleProvider), isEmpty);
  });

  testWidgets('informational copy for the counterparty does not navigate', (
    tester,
  ) async {
    // waiting-seller-to-pay persists WaitingPayment on the buyer side too.
    await pumpListener(tester, resolveRole: (_) async => TradeRole.buyer);

    updates.add(
      const TradeUpdate(orderId: 'o1', status: OrderStatus.waitingPayment),
    );
    await tester.pump();
    await tester.pump();

    expect(navigated, isEmpty);
  });

  testWidgets('WaitingPayment superseded by Active during the role lookup '
      'does not navigate', (tester) async {
    // Startup replay delivers the historical statuses milliseconds apart:
    // the WaitingPayment handler is still awaiting the role when Active
    // lands, so it must drop its stale navigation.
    final role = Completer<TradeRole?>();
    await pumpListener(tester, resolveRole: (_) => role.future);

    updates.add(
      const TradeUpdate(orderId: 'o1', status: OrderStatus.waitingPayment),
    );
    await tester.pump();
    updates.add(const TradeUpdate(orderId: 'o1', status: OrderStatus.active));
    await tester.pump();

    role.complete(TradeRole.seller);
    await tester.pump();

    expect(navigated, isEmpty);
  });
}
