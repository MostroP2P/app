import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/order/screens/pay_lightning_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';

/// Goldens of the invoice redesign (`design_handoff_factura_lightning`) on
/// the handoff's 360 × 760 dp canvas, in Spanish like the mockups:
/// 13a — the buyer with a valid invoice for 250 sats and 14:38 left;
/// 13b — the seller's 252 sats hold invoice with 09:12 left.
const _id = '09150348-1a2b-4c3d-8e9f-0a1b2c3d99b5';
final _now = DateTime.utc(2026, 9, 12, 12);
int get _nowSeconds => _now.millisecondsSinceEpoch ~/ 1000;

const _holdInvoice =
    'lnbc2520n1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3'
    'zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7'
    'enxv4jsxqzpu9qrsgquk0rl77nj30yxdy8j9vdx85fkpmdla2087ne0xh8nhedh8w27kyke0lp5';

TradeInfo _trade({required BigInt sats, String? holdInvoice}) => fakeTrade(
  id: _id,
  status: OrderStatus.waitingPayment,
  fiatCode: 'ARS',
  paymentMethod: 'Mercado Pago',
  amountSats: sats,
  holdInvoice: holdInvoice,
  peerRating: 4.9,
  peerReviews: 16,
  peerDays: 120,
);

Future<void> _pump(
  WidgetTester tester,
  Widget screen, {
  required TradeInfo trade,
  required Duration left,
  required Brightness brightness,
}) async {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await withClock(Clock.fixed(_now), () async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isWalletConnectedProvider.overrideWithValue(false),
          tradeAmountProvider.overrideWith(
            (ref, id) => Stream.value(trade.order.amountSats!),
          ),
          tradeInfoProvider.overrideWith((ref, id) async => trade),
          tradeInfoStreamProvider.overrideWith(
            (ref, id) => Stream.value(trade),
          ),
          tradeStatusProvider.overrideWith(
            (ref, id) => const Stream<OrderStatus>.empty(),
          ),
          tradeUpdatesProvider.overrideWith(
            (ref) => const Stream<TradeUpdate>.empty(),
          ),
          invoiceDeadlineProvider.overrideWith(
            (ref, id) async => _nowSeconds + left.inSeconds,
          ),
          invoiceCheckerProvider.overrideWithValue(
            (request) async => const InvoiceCheckValid(250),
          ),
          mostroNodeProvider.overrideWith((ref) async => null),
          activeNodeNameProvider.overrideWithValue('Bitcoin Bolivia'),
          nymLookupProvider.overrideWithValue(
            (pubkey) async => const NymIdentity(
              pseudonym: 'bright-fox-41',
              iconIndex: 3,
              colorHue: 120,
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme:
              brightness == Brightness.dark
                  ? buildDarkTheme()
                  : buildLightTheme(),
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  });
}

void main() {
  for (final (name, brightness) in [
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    testWidgets('13a_receive · $name', (tester) async {
      await _pump(
        tester,
        const AddLightningInvoiceScreen(orderId: _id),
        trade: _trade(sats: BigInt.from(250)),
        left: const Duration(minutes: 14, seconds: 38),
        brightness: brightness,
      );
      await withClock(Clock.fixed(_now), () async {
        await tester.enterText(find.byType(TextField), 'lnbc2500n1pvjluez…');
        // Past the validation debounce.
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
      });
      await expectLater(
        find.byType(AddLightningInvoiceScreen),
        matchesGoldenFile('goldens/invoice_13a_receive_$name.png'),
      );
    });

    testWidgets('13b_lock · $name', (tester) async {
      await _pump(
        tester,
        const PayLightningInvoiceScreen(orderId: _id),
        trade: _trade(sats: BigInt.from(252), holdInvoice: _holdInvoice),
        left: const Duration(minutes: 9, seconds: 12),
        brightness: brightness,
      );
      await expectLater(
        find.byType(PayLightningInvoiceScreen),
        matchesGoldenFile('goldens/invoice_13b_lock_$name.png'),
      );
    });
  }
}
