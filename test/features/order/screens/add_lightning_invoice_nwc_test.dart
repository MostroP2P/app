import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/nwc_invoice_widget.dart';
import 'package:mostro/shared/widgets/peer_reputation_card.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';

/// With NWC connected the maker never touches the manual form and the invoice
/// can be generated and submitted automatically — so the auto-invoice branch is
/// exactly where the taker reputation (#305) matters most. It must render the
/// same card the manual branch does; this guards it from regressing.
void main() {
  testWidgets('renders the taker reputation card in NWC auto-invoice mode',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isWalletConnectedProvider.overrideWithValue(true),
          tradeAmountProvider.overrideWith(
              (ref, orderId) => Stream.value(BigInt.from(1000))),
          tradeUpdatesProvider
              .overrideWith((ref) => const Stream<TradeUpdate>.empty()),
          tradeInfoProvider.overrideWith((ref, orderId) async => fakeTrade(
                id: orderId,
                peerRating: 4.4,
                peerReviews: 4,
                peerDays: 64,
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
          home: AddLightningInvoiceScreen(
            orderId: 'order-1',
            amountSats: 1000,
            // Never completes: keeps the NWC widget in its loading state so the
            // test does not fall through to onInvoiceConfirmed → sendInvoice.
            generateInvoice: (_) => Completer<String>().future,
          ),
        ),
      ),
    );
    // The NWC widget sits on a spinner while its (never-completing) invoice
    // generation is in flight, so pumpAndSettle would time out — pump enough
    // for the amount stream and the trade future to resolve into the branch.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(NwcInvoiceWidget), findsOneWidget);
    expect(find.byType(PeerReputationCard), findsOneWidget);
    // The maker is the buyer here (adding an invoice), so the taker is the
    // seller.
    expect(find.text('Seller reputation'), findsOneWidget);
  });
}
