import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/pay_lightning_invoice_screen.dart';
import 'package:mostro/features/order/widgets/invoice_widgets.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/types.dart';
import '../../../support/fake_trades.dart';

Finder _semantics(String identifier) => find.byWidgetPredicate(
  (widget) => widget is Semantics && widget.properties.identifier == identifier,
);

/// 13b's countdown is the client's estimate of mostrod's window, not its
/// verdict: the hold invoice stays payable until the scheduler acts, tens of
/// seconds later. So 00:00 leaves the QR in place, and only the daemon's own
/// message closes the step (#569).
void main() {
  final l10n = AppLocalizationsEn();
  final now = DateTime.utc(2026, 9, 12, 12);
  final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;

  Future<void> pump(
    WidgetTester tester, {
    required int deadline,
    OrderKind kind = OrderKind.sell,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isWalletConnectedProvider.overrideWithValue(false),
          tradeInfoStreamProvider.overrideWith(
            (ref, id) => Stream.value(
              fakeTrade(
                id: id,
                status: OrderStatus.waitingPayment,
                kind: kind,
                holdInvoice: 'lnbc1000n1holdinvoice',
                amountSats: BigInt.from(1000),
              ),
            ),
          ),
          tradeStatusProvider.overrideWith(
            (ref, id) => const Stream<OrderStatus>.empty(),
          ),
          tradeUpdatesProvider.overrideWith(
            (ref) => const Stream<TradeUpdate>.empty(),
          ),
          tradeInfoProvider.overrideWith((ref, id) async => null),
          invoiceDeadlineProvider.overrideWith((ref, id) async => deadline),
          mostroNodeProvider.overrideWith((ref) async => null),
          activeNodeNameProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PayLightningInvoiceScreen(orderId: 'order-1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('shows the hold invoice while time is left', (tester) async {
    await withClock(Clock.fixed(now), () async {
      await pump(tester, deadline: nowSeconds + 90);
    });
    expect(_semantics('pay.invoice.text'), findsOneWidget);
    expect(find.byType(InvoiceTimeUpView), findsNothing);
    expect(find.text(l10n.invoiceStepElapsed), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // The seller owes the payment: as the taker of a buy order, mostrod puts
  // the order back in the book when the step runs out; as the maker of a
  // sell order, it cancels it.
  for (final side in const [
    (
      kind: OrderKind.buy,
      notice:
          'Time is up. If it is not completed, Mostro will return the order '
          'to the book shortly.',
    ),
    (
      kind: OrderKind.sell,
      notice:
          'Time is up. If it is not completed, Mostro will cancel the order '
          'shortly.',
    ),
  ]) {
    testWidgets('keeps the hold invoice at 00:00 on a ${side.kind.name} '
        'order and says what Mostro is about to do', (tester) async {
      await withClock(Clock.fixed(now), () async {
        await pump(tester, deadline: nowSeconds - 1, kind: side.kind);
      });
      expect(find.byType(InvoiceTimeUpView), findsNothing);
      expect(_semantics('pay.invoice.text'), findsOneWidget);
      expect(find.text(side.notice), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
