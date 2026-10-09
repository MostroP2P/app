import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
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

/// 13a's countdown is the client's estimate of mostrod's window, not its
/// verdict: the scheduler acts tens of seconds after it and accepts an
/// invoice until then. So 00:00 leaves the form in place, and only the
/// daemon's own message closes the step (#569).
void main() {
  final l10n = AppLocalizationsEn();
  final now = DateTime.utc(2026, 9, 12, 12);
  final nowSeconds = now.millisecondsSinceEpoch ~/ 1000;

  /// [kind] gives the trade row its order side; without one the row is not
  /// loaded yet.
  Future<void> pump(
    WidgetTester tester, {
    required int deadline,
    OrderKind? kind,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isWalletConnectedProvider.overrideWithValue(false),
          tradeAmountProvider.overrideWith(
            (ref, id) => Stream.value(BigInt.from(250)),
          ),
          tradeInfoProvider.overrideWith(
            (ref, id) async =>
                kind == null
                    ? null
                    : fakeTrade(
                      orderId: id,
                      status: OrderStatus.waitingBuyerInvoice,
                      kind: kind,
                    ),
          ),
          tradeUpdatesProvider.overrideWith(
            (ref) => const Stream<TradeUpdate>.empty(),
          ),
          invoiceDeadlineProvider.overrideWith((ref, id) async => deadline),
          mostroNodeProvider.overrideWith((ref) async => null),
          activeNodeNameProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const AddLightningInvoiceScreen(orderId: 'order-1'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('keeps the form while time is left', (tester) async {
    await withClock(Clock.fixed(now), () async {
      await pump(tester, deadline: nowSeconds + 90);
    });
    expect(_semantics('invoice.submit'), findsOneWidget);
    expect(find.byType(InvoiceTimeUpView), findsNothing);
    expect(find.text(l10n.invoiceStepElapsed), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('keeps the form at 00:00 before the trade loads', (tester) async {
    await withClock(Clock.fixed(now), () async {
      await pump(tester, deadline: nowSeconds - 1);
    });
    expect(find.byType(InvoiceTimeUpView), findsNothing);
    expect(_semantics('invoice.text'), findsOneWidget);
    expect(_semantics('invoice.submit'), findsOneWidget);
    expect(find.text(l10n.invoiceStepElapsed), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  // The buyer owes the invoice: as the taker of a sell order, mostrod puts
  // the order back in the book when the step runs out; as the maker of a buy
  // order, it cancels it.
  for (final side in const [
    (
      kind: OrderKind.sell,
      notice:
          'Time is up. If it is not completed, Mostro will return the order '
          'to the book shortly.',
    ),
    (
      kind: OrderKind.buy,
      notice:
          'Time is up. If it is not completed, Mostro will cancel the order '
          'shortly.',
    ),
  ]) {
    testWidgets('at 00:00 on a ${side.kind.name} order says what Mostro is '
        'about to do', (tester) async {
      await withClock(Clock.fixed(now), () async {
        await pump(tester, deadline: nowSeconds - 1, kind: side.kind);
      });
      expect(_semantics('invoice.submit'), findsOneWidget);
      expect(find.text(side.notice), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
