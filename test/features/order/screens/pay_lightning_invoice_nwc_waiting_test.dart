import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/pay_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/nwc_payment_widget.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';

/// The seller's hold-invoice screen with a connected wallet: the branch that
/// hands the payment to NWC (#244).
Widget _screen() => ProviderScope(
  overrides: [
    isWalletConnectedProvider.overrideWithValue(true),
    tradeAmountProvider.overrideWith(
      (ref, id) => Stream.value(BigInt.from(11612)),
    ),
    tradeInfoStreamProvider.overrideWith(
      (ref, id) => Stream.value(
        fakeTrade(
          id: id,
          holdInvoice: 'lnbc116120n1holdinvoice',
          amountSats: BigInt.from(11612),
        ),
      ),
    ),
    // Quiet: the screen leaves on mostrod's confirmation, and this test is
    // about the window before it arrives.
    tradeStatusProvider.overrideWith(
      (ref, id) => const Stream<OrderStatus>.empty(),
    ),
    tradeUpdatesProvider.overrideWith((ref) => const Stream<TradeUpdate>.empty()),
    tradeInfoProvider.overrideWith((ref, id) async => null),
    invoiceDeadlineProvider.overrideWith((ref, id) async => null),
    mostroNodeProvider.overrideWith((ref) async => null),
    activeNodeNameProvider.overrideWithValue(null),
  ],
  child: MaterialApp(
    theme: buildDarkTheme(),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const PayLightningInvoiceScreen(orderId: 'order-x'),
  ),
);

void main() {
  testWidgets('the wallet branch waits for confirmation once it has paid', (
    tester,
  ) async {
    await tester.pumpWidget(_screen());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Before paying: the wallet button, and nothing to wait for.
    expect(find.byType(NwcPaymentWidget), findsOneWidget);
    expect(find.text(l10n.waitingForPaymentConfirmation), findsNothing);

    // What the wallet calls when the invoice is paid. Driven through the
    // widget's own callback because `nwc_api.payInvoice` needs a live bridge.
    tester.widget<NwcPaymentWidget>(find.byType(NwcPaymentWidget))
        .onPaymentSuccess();
    await tester.pump();

    // After paying: no way left to send the same bolt11 again, and the seller
    // is told what the app is waiting for.
    expect(find.byType(NwcPaymentWidget), findsNothing);
    expect(find.text(l10n.payWithWalletButton), findsNothing);
    expect(find.text(l10n.waitingForPaymentConfirmation), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
