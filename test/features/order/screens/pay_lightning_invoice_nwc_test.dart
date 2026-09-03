import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/pay_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/nwc_payment_widget.dart';
import 'package:mostro/shared/widgets/peer_reputation_card.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';

/// With NWC connected the seller pays the hold invoice automatically, so the
/// auto-pay branch is where the taker reputation (#305) matters most. It must
/// render the same card the manual QR branch does; this guards it.
void main() {
  testWidgets('renders the taker reputation card in NWC auto-pay mode',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isWalletConnectedProvider.overrideWithValue(true),
          tradeInfoStreamProvider.overrideWith(
            (ref, orderId) => Stream.value(fakeTrade(
              id: orderId,
              holdInvoice: 'lnbc1000n1holdinvoice',
              amountSats: BigInt.from(1000),
            )),
          ),
          tradeStatusProvider.overrideWith(
              (ref, orderId) => const Stream<OrderStatus>.empty()),
          tradeUpdatesProvider
              .overrideWith((ref) => const Stream<TradeUpdate>.empty()),
          tradeInfoProvider.overrideWith((ref, orderId) async => fakeTrade(
                id: orderId,
                peerRating: 4.4,
                peerReviews: 3,
                peerDays: 50,
              )),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PayLightningInvoiceScreen(orderId: 'order-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NwcPaymentWidget), findsOneWidget);
    expect(find.byType(PeerReputationCard), findsOneWidget);
    // The maker is the seller here (paying the hold invoice), so the taker is
    // the buyer.
    expect(find.text('Buyer reputation'), findsOneWidget);
  });
}
