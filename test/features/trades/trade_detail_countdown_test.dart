import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/features/trades/screens/trade_detail_screen.dart';
import 'package:mostro/features/trades/widgets/trade_countdown.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../support/fake_trades.dart';
import '../../support/provider_harness.dart';

const _orderId = 'order-countdown';

/// The window the node advertises for a waiting step.
const _stepWindow = 60;
final _now = DateTime.utc(2026, 9, 22, 12);
final _nowSeconds = _now.millisecondsSinceEpoch ~/ 1000;

MostroInstance _node() =>
    const MostroInstance(pubKey: 'node', expirationSeconds: _stepWindow);

/// Pumps the screen on a waiting step, with [deadline] as what the invoice
/// step resolves to (null = not recorded).
///
/// [status] and [isBuyer] go together: the side that owes the step is the one
/// the screen gives the clock to (`TradeTimerOwner.user`). A seller waits to
/// pay the hold invoice; a buyer waits to send theirs. Pairing them the other
/// way round would still render a countdown, but one no trade produces.
Future<void> _pumpWaiting(
  WidgetTester tester, {
  required int? deadline,
  OrderStatus status = OrderStatus.waitingPayment,
  bool isBuyer = false,
  OrderKind kind = OrderKind.sell,
}) async {
  final trade = fakeTrade(
    id: _orderId,
    orderId: _orderId,
    status: status,
    kind: kind,
    amountSats: BigInt.from(11612),
  );
  final container = createContainer(
    overrides: [
      tradeRoleProvider.overrideWith((ref) => {_orderId: isBuyer}),
      tradeStatusProvider(_orderId).overrideWith((ref) => Stream.value(status)),
      orderBookProvider.overrideWith((ref) => Stream.value(const [])),
      rawTradesProvider.overrideWith((ref) async => [trade]),
      mostroNodeProvider.overrideWith((ref) async => _node()),
      invoiceDeadlineProvider(_orderId).overrideWith((ref) async => deadline),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TradeDetailScreen(orderId: _orderId),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  // Both waiting steps, because they are two arms of the same condition and
  // covering one leaves the other free to regress: with only the seller's
  // case here, dropping `waitingInvoice` from the screen's step check left all
  // 180 tests green — and the buyer's step is the one this fix was reported
  // for (a countdown reading 359:59 on `waiting-buyer-invoice`).
  for (final step in const [
    (
      name: 'the seller waiting to pay',
      status: OrderStatus.waitingPayment,
      isBuyer: false,
    ),
    (
      name: 'the buyer waiting to send their invoice',
      status: OrderStatus.waitingBuyerInvoice,
      isBuyer: true,
    ),
  ]) {
    testWidgets('${step.name} counts to the node deadline, not to expires_at', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final deadline = _now.add(const Duration(seconds: 45));
        await _pumpWaiting(
          tester,
          status: step.status,
          isBuyer: step.isBuyer,
          deadline: deadline.millisecondsSinceEpoch ~/ 1000,
        );

        final countdown = tester.widget<TradeCountdown>(
          find.byType(TradeCountdown),
        );
        // 45 s left of the node's 60 s window. Counting to `expires_at` would
        // have shown the event's retention instead: ~336 hours.
        expect(countdown.remaining, const Duration(seconds: 45));
        expect(countdown.total, const Duration(seconds: _stepWindow));
      });
    });

    testWidgets('${step.name} with no deadline gets no countdown', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        // What a maker gets: the reply that opened the step was consumed by
        // the take, so nothing recorded when it started.
        await _pumpWaiting(
          tester,
          status: step.status,
          isBuyer: step.isBuyer,
          deadline: null,
        );

        expect(find.byType(TradeCountdown), findsNothing);
      });
    });
  }

  // What happens when a waiting step runs out depends on who owes it, and
  // both sides read the same consequence. mostrod (`scheduler.rs`) puts the
  // order back in the book when the taker misses the step (a buyer's invoice
  // on a sell order, a seller's payment on a buy order) and cancels it when
  // the maker does. 00:00 is the client's estimate: the note then says what
  // the daemon is about to do, not that it did (#569).
  const backToBook = 'If it expires, the order goes back to the book.';
  const cancelled = 'If it expires, the order is cancelled.';
  const elapsedBackToBook =
      'Time is up. If it is not completed, Mostro will return the order to '
      'the book shortly.';
  const elapsedCancelled =
      'Time is up. If it is not completed, Mostro will cancel the order '
      'shortly.';
  for (final step in const [
    (
      name: 'the taker owes the invoice',
      status: OrderStatus.waitingBuyerInvoice,
      kind: OrderKind.sell,
      returnsToBook: true,
    ),
    (
      name: 'the maker owes the invoice',
      status: OrderStatus.waitingBuyerInvoice,
      kind: OrderKind.buy,
      returnsToBook: false,
    ),
    (
      name: 'the taker owes the payment',
      status: OrderStatus.waitingPayment,
      kind: OrderKind.buy,
      returnsToBook: true,
    ),
    (
      name: 'the maker owes the payment',
      status: OrderStatus.waitingPayment,
      kind: OrderKind.sell,
      returnsToBook: false,
    ),
  ]) {
    for (final isBuyer in const [true, false]) {
      final side = isBuyer ? 'buyer' : 'seller';

      testWidgets('${step.name}: the $side reads what expiry does', (
        tester,
      ) async {
        await withClock(Clock.fixed(_now), () async {
          await _pumpWaiting(
            tester,
            status: step.status,
            isBuyer: isBuyer,
            kind: step.kind,
            deadline: _nowSeconds + 45,
          );
          expect(
            tester.widget<TradeCountdown>(find.byType(TradeCountdown)).note,
            step.returnsToBook ? backToBook : cancelled,
          );
        });
      });

      testWidgets('${step.name}: the $side reads what Mostro is about to do '
          'at 00:00', (tester) async {
        await withClock(Clock.fixed(_now), () async {
          await _pumpWaiting(
            tester,
            status: step.status,
            isBuyer: isBuyer,
            kind: step.kind,
            deadline: _nowSeconds - 1,
          );
          final countdown = tester.widget<TradeCountdown>(
            find.byType(TradeCountdown),
          );
          expect(countdown.remaining, Duration.zero);
          expect(
            countdown.note,
            step.returnsToBook ? elapsedBackToBook : elapsedCancelled,
          );
        });
      });
    }
  }
}
