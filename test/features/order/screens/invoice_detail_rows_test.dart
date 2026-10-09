import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/order/screens/pay_lightning_invoice_screen.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';

/// DS-CMP-24: the invoice screens show the counterpart and the fiat side of
/// the trade as the same label → value rows as order detail and take order
/// (`OrderDataCard` / `OrderDataRow`: icon, label, value, hairline), not as
/// a bare list of their own (#726).
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
}) async {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async =>
        call.method == 'Clipboard.hasStrings' ? {'value': false} : null,
  );
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );

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
            (ref, id) async => _nowSeconds + 600,
          ),
          invoiceCheckerProvider.overrideWithValue(
            (request) async =>
                InvoiceCheckValid(250, expiresAt: _nowSeconds + 3600),
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
          theme: buildDarkTheme(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder:
              (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: child!,
              ),
          home: screen,
        ),
      ),
    );
    await tester.pumpAndSettle();
  });
}

/// The [OrderDataRow] holding [text], which must sit in an [OrderDataCard].
Finder _dataRowOf(Finder text) => find.ancestor(
  of: text,
  matching: find.descendant(
    of: find.byType(OrderDataCard),
    matching: find.byType(OrderDataRow),
  ),
);

void _expectCounterpartRows(WidgetTester tester) {
  final counterpart = _dataRowOf(find.text('bright-fox-41'));
  expect(counterpart, findsOneWidget);
  // The reputation trails the name inside the same row.
  expect(
    find.descendant(of: counterpart, matching: find.text('★ 4.9')),
    findsOneWidget,
  );
  expect(
    find.descendant(of: counterpart, matching: find.byType(Icon)),
    findsOneWidget,
  );

  final fiat = _dataRowOf(find.textContaining('Mercado Pago'));
  expect(fiat, findsOneWidget);
  expect(
    find.descendant(of: fiat, matching: find.byType(Icon)),
    findsOneWidget,
  );

  // Both facts are rows of one card, with the order's ID row (DS-CMP-22),
  // split by its hairlines.
  expect(
    find.ancestor(of: counterpart, matching: find.byType(OrderDataCard)),
    findsOneWidget,
  );
  final card = find.ancestor(
    of: counterpart,
    matching: find.byType(OrderDataCard),
  );
  expect(find.descendant(of: card, matching: fiat), findsOneWidget);
  expect(
    find.descendant(of: card, matching: find.byType(OrderIdRow)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: card, matching: find.byType(Divider)),
    findsNWidgets(2),
  );
}

void main() {
  testWidgets('the buyer adding an invoice sees the seller as a data row', (
    tester,
  ) async {
    await _pump(
      tester,
      const AddLightningInvoiceScreen(orderId: _id),
      trade: _trade(sats: BigInt.from(250)),
    );
    _expectCounterpartRows(tester);
  });

  testWidgets('the seller paying the hold invoice sees the buyer as a row', (
    tester,
  ) async {
    await _pump(
      tester,
      const PayLightningInvoiceScreen(orderId: _id),
      trade: _trade(sats: BigInt.from(252), holdInvoice: _holdInvoice),
    );
    _expectCounterpartRows(tester);
  });
}
