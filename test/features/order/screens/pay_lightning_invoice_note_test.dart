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
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/explanatory_note_finders.dart';
import '../../../support/fake_trades.dart';

void main() {
  testWidgets('the seller reads why the sats are held in the shared note', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isWalletConnectedProvider.overrideWithValue(false),
          tradeAmountProvider.overrideWith(
            (ref, id) => Stream.value(BigInt.from(1000)),
          ),
          tradeInfoStreamProvider.overrideWith(
            (ref, id) => Stream.value(
              fakeTrade(
                id: id,
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
          invoiceDeadlineProvider.overrideWith((ref, id) async => null),
          mostroNodeProvider.overrideWith((ref) async => null),
          activeNodeNameProvider.overrideWithValue(null),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const PayLightningInvoiceScreen(orderId: 'order-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expectExplanatoryNote(
      tester,
      find.textContaining("they don't leave your wallet", findRichText: true),
    );
  });
}
