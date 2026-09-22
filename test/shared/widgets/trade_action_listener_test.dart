import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

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

  // Not awaited: a controller nobody listened to (the router tests below)
  // never completes its close().
  tearDown(() => unawaited(updates.close()));

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
      const TradeUpdate(
        orderId: 'o1',
        occurredAt: 0,
        status: OrderStatus.waitingPayment,
      ),
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
      const TradeUpdate(
        orderId: 'o1',
        occurredAt: 0,
        status: OrderStatus.waitingBuyerInvoice,
      ),
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
      const TradeUpdate(
        orderId: 'o1',
        occurredAt: 0,
        status: OrderStatus.waitingTakerBond,
      ),
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
      const TradeUpdate(
        orderId: 'o1',
        occurredAt: 0,
        status: OrderStatus.waitingTakerBond,
      ),
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
      const TradeUpdate(
        orderId: 'o1',
        occurredAt: 0,
        status: OrderStatus.waitingPayment,
      ),
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
      const TradeUpdate(
        orderId: 'o1',
        occurredAt: 0,
        status: OrderStatus.waitingPayment,
      ),
    );
    await tester.pump();
    updates.add(
      const TradeUpdate(
        orderId: 'o1',
        occurredAt: 0,
        status: OrderStatus.active,
      ),
    );
    await tester.pump();

    role.complete(TradeRole.seller);
    await tester.pump();

    expect(navigated, isEmpty);
  });

  group('pushUnlessVisible', () {
    GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        for (final path in ['/', '/trade/:id', '/add_invoice/:id'])
          GoRoute(
            path: path,
            builder: (context, state) => const SizedBox.shrink(),
          ),
      ],
    );

    Future<void> pumpRouter(WidgetTester tester, GoRouter router) {
      addTearDown(router.dispose);
      return tester.pumpWidget(MaterialApp.router(routerConfig: router));
    }

    int stackCount(GoRouter router, String location) =>
        router.routerDelegate.currentConfiguration.matches
            .whereType<ImperativeRouteMatch>()
            .where((m) => m.matches.uri.toString() == location)
            .length;

    testWidgets('does not stack a route another screen already pushed', (
      tester,
    ) async {
      // The pay-bond screen hands a buyer over with go(trade) + push(invoice)
      // on the same emission this listener reacts to. A second copy of the
      // add-invoice screen generates and submits a second NWC invoice.
      final router = buildRouter();
      await pumpRouter(tester, router);
      router.go('/trade/o1');
      unawaited(router.push('/add_invoice/o1'));
      await tester.pumpAndSettle();

      pushUnlessVisible(router, '/add_invoice/o1');
      await tester.pumpAndSettle();

      expect(stackCount(router, '/add_invoice/o1'), 1);
    });

    testWidgets('pushes a route that is not the visible one', (tester) async {
      final router = buildRouter();
      await pumpRouter(tester, router);
      router.go('/trade/o1');
      await tester.pumpAndSettle();

      pushUnlessVisible(router, '/add_invoice/o1');
      await tester.pumpAndSettle();

      expect(stackCount(router, '/add_invoice/o1'), 1);
    });

    testWidgets('does not push over the same location reached with go', (
      tester,
    ) async {
      final router = buildRouter();
      await pumpRouter(tester, router);
      router.go('/add_invoice/o1');
      await tester.pumpAndSettle();

      pushUnlessVisible(router, '/add_invoice/o1');
      await tester.pumpAndSettle();

      expect(stackCount(router, '/add_invoice/o1'), 0);
    });
  });
}
