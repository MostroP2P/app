import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/pay_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/nwc_payment_widget.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';

/// A trade with a usable hold invoice so the screen passes the
/// invoice.isEmpty / amountSats guard and reaches the NWC / QR branches.
TradeInfo _payableTrade() {
  final base = fakeTrade(
    id: 'x',
    status: OrderStatus.waitingPayment,
    amountSats: BigInt.from(1000),
  );
  return TradeInfo(
    id: base.id,
    order: base.order,
    role: base.role,
    counterpartyPubkey: base.counterpartyPubkey,
    currentStep: base.currentStep,
    tradeKeyIndex: base.tradeKeyIndex,
    startedAt: base.startedAt,
    holdInvoice: 'lnbc1000n1pxxxxxxx',
  );
}

Widget _app({required bool walletConnected, required TradeInfo trade}) {
  return ProviderScope(
    overrides: [
      isWalletConnectedProvider.overrideWithValue(walletConnected),
      tradeInfoStreamProvider('order-x').overrideWith(
        (ref) => Stream.value(trade),
      ),
      // Keep the status poller quiet so it doesn't fire navigation during the
      // test; the NWC success callback is what drives _waiting here.
      tradeStatusProvider('order-x').overrideWith(
        (ref) => const Stream.empty(),
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PayLightningInvoiceScreen(orderId: 'order-x'),
    ),
  );
}

void main() {
  testWidgets(
    '#244: after NWC payment the pay widget is replaced by a waiting spinner',
    (tester) async {
      await tester.pumpWidget(
        _app(walletConnected: true, trade: _payableTrade()),
      );
      await tester.pump(); // resolve the trade stream
      await tester.pump(const Duration(milliseconds: 50)); // let the stream settle

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // Before payment: the NWC auto-pay widget is shown, no waiting text.
      expect(find.byType(NwcPaymentWidget), findsOneWidget);
      expect(find.text(l10n.waitingForPaymentConfirmation), findsNothing);

      // Simulate a successful NWC payment by invoking the widget's success
      // callback (what the real wallet flow calls). This sets _waiting = true.
      final nwc = tester.widget<NwcPaymentWidget>(find.byType(NwcPaymentWidget));
      nwc.onPaymentSuccess();
      await tester.pump();

      // After payment: the pay widget is gone and the confirmation spinner
      // (with its label) is shown instead — no re-armed pay button.
      expect(find.byType(NwcPaymentWidget), findsNothing);
      expect(find.text(l10n.waitingForPaymentConfirmation), findsOneWidget);
    },
  );
}
