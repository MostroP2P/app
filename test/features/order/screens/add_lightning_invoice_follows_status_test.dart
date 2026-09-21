import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

Finder _semantics(String identifier) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == identifier,
);

const _orderId = 'order-1';

Future<void> _pumpScreen(
  WidgetTester tester, {
  required Stream<OrderStatus> statuses,
  Future<void> Function(String, String, BigInt)? submitInvoice,
  Future<void> Function()? recoverState,
}) async {
  final router = GoRouter(
    initialLocation: AppRoute.addInvoicePath(_orderId),
    routes: [
      GoRoute(
        path: AppRoute.addInvoice,
        builder:
            (_, state) => AddLightningInvoiceScreen(
              orderId: state.pathParameters['orderId']!,
              submitInvoice: submitInvoice,
              recoverState: recoverState,
            ),
      ),
      GoRoute(
        path: AppRoute.tradeDetail,
        builder: (_, __) => const Scaffold(body: Text('trade-detail')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isWalletConnectedProvider.overrideWithValue(false),
        tradeAmountProvider.overrideWith(
          (ref, orderId) => Stream.value(BigInt.from(999)),
        ),
        tradeUpdatesProvider.overrideWith(
          (ref) => const Stream<TradeUpdate>.empty(),
        ),
        tradeStatusProvider.overrideWith((ref, orderId) => statuses),
        tradeInfoProvider.overrideWith((ref, orderId) async => null),
      ],
      child: MaterialApp.router(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  test('only a trade past the invoice step ends it', () {
    // Still this screen's business, or not a trade yet.
    for (final status in [
      OrderStatus.pending,
      OrderStatus.inProgress,
      OrderStatus.waitingPayment,
      OrderStatus.waitingBuyerInvoice,
      // A failed payout asks for a new invoice while the order reads settled.
      OrderStatus.settledHoldInvoice,
    ]) {
      expect(invoiceStepIsOver(status), isFalse, reason: '$status');
    }
    for (final status in [
      OrderStatus.active,
      OrderStatus.fiatSent,
      OrderStatus.dispute,
      OrderStatus.success,
      // How a dispute ends. A payout that fails after an admin settle comes
      // back as settledHoldInvoice, not as either of these.
      OrderStatus.settledByAdmin,
      OrderStatus.completedByAdmin,
    ]) {
      expect(invoiceStepIsOver(status), isTrue, reason: '$status');
    }
  });

  // The field failure: the daemon accepted the invoice, its acknowledgement
  // outran send_invoice's 10 s window, and the form kept asking for an
  // invoice the order no longer wanted — the retry died with CantDo.
  testWidgets('leaves for the trade once the order moves past the invoice', (
    tester,
  ) async {
    // Arrange
    final statuses = StreamController<OrderStatus>();
    addTearDown(statuses.close);
    await _pumpScreen(tester, statuses: statuses.stream);
    statuses.add(OrderStatus.waitingBuyerInvoice);
    await tester.pump();
    expect(_semantics('invoice.text'), findsOneWidget);

    // Act
    statuses.add(OrderStatus.active);
    await tester.pumpAndSettle();

    // Assert
    expect(find.text('trade-detail'), findsOneWidget);
  });

  testWidgets(
    'a status rejection recovers the trade state instead of showing raw prose',
    (tester) async {
      // Arrange
      final semantics = tester.ensureSemantics();
      final statuses = StreamController<OrderStatus>();
      addTearDown(statuses.close);
      var recoveries = 0;
      await _pumpScreen(
        tester,
        statuses: statuses.stream,
        submitInvoice: (_, __, ___) async {
          throw Exception(
            'AnyhowException(Action rejected: not allowed in the current '
            'order status.)',
          );
        },
        recoverState: () async => recoveries++,
      );
      statuses.add(OrderStatus.waitingBuyerInvoice);
      await tester.enterText(find.byType(TextField), 'lnbc1short');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // Act
      await tester.tap(_semantics('invoice.submit'));
      await tester.pump();
      await tester.pump();

      // Assert: a localized reason, and the missed message is asked for.
      expect(recoveries, 1);
      final error = _semantics('invoice.error');
      expect(error, findsOneWidget);
      expect(
        tester.getSemantics(error).getSemanticsData().label,
        'This order is no longer waiting for an invoice. Updating its status…',
      );

      // The recovered status then takes the buyer to the trade.
      statuses.add(OrderStatus.active);
      await tester.pumpAndSettle();
      expect(find.text('trade-detail'), findsOneWidget);
      semantics.dispose();
    },
  );
}
