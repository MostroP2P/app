import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/add_lightning_invoice_screen.dart';
import 'package:mostro/features/order/screens/bond_payout_invoice_screen.dart';
import 'package:mostro/features/order/screens/pay_bond_invoice_screen.dart';
import 'package:mostro/features/order/screens/pay_lightning_invoice_screen.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_trades.dart';

/// Issue #724, DS-CMP-22: the invoice screens show the order id as an "ID"
/// row of their card, `09150348…99b5` with a copy icon, never as a `#` tag in
/// the app bar. The automation readout keeps its identifier and full id.

const _orderId = '09150348-1a2b-4c3d-8e9f-0a1b2c3d99b5';
const _shortId = '09150348…99b5';

Widget _app(List<Override> overrides, Widget home) => ProviderScope(
  overrides: overrides,
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
    home: home,
  ),
);

Finder _readout(String id) =>
    find.byWidgetPredicate((w) => w is AutomationId && w.id == id);

Future<void> _expectIdRowInCard(
  WidgetTester tester,
  String automationId,
) async {
  final semantics = tester.ensureSemantics();
  await tester.pump();
  final readout = _readout(automationId);
  expect(readout, findsOneWidget);
  expect(tester.widget<AutomationId>(readout).label, _orderId);
  expect(
    find.descendant(of: find.byType(AppBar), matching: readout),
    findsNothing,
    reason: 'DS-CMP-22: never in the app bar',
  );
  final card = find.byType(OrderDataCard);
  expect(find.descendant(of: card, matching: readout), findsOneWidget);
  expect(
    find.descendant(of: card, matching: find.text(_shortId)),
    findsOneWidget,
  );
  expect(
    find.descendant(of: card, matching: find.byIcon(Icons.copy_rounded)),
    findsOneWidget,
  );
  expect(find.text('#09150348'), findsNothing);

  // DS-CMP-8: the card sits on the screen's surface, like the hero card.
  final box = tester.widget<Container>(
    find.descendant(of: card, matching: find.byType(Container)).first,
  );
  expect(
    (box.decoration! as BoxDecoration).color,
    OrderBookPalette.of(tester.element(card)).surface,
  );

  // DS-A11Y-1: the copy row is a button, and the readout keeps its own node.
  final row = find.ancestor(
    of: find.text(_shortId),
    matching: find.byType(InkWell),
  );
  expect(
    tester.getSemantics(row.first),
    isSemantics(isButton: true, hasTapAction: true),
  );
  expect(tester.widget<AutomationId>(readout).label, _orderId);
  semantics.dispose();
}

void main() {
  testWidgets('add invoice: the id is a row of the card', (tester) async {
    await tester.pumpWidget(
      _app([
        isWalletConnectedProvider.overrideWithValue(false),
        tradeAmountProvider.overrideWith(
          (ref, id) => Stream.value(BigInt.from(999)),
        ),
        tradeUpdatesProvider.overrideWith(
          (ref) => const Stream<TradeUpdate>.empty(),
        ),
        tradeInfoProvider.overrideWith((ref, id) async => null),
      ], const AddLightningInvoiceScreen(orderId: _orderId)),
    );
    await tester.pump();
    await tester.pump();

    await _expectIdRowInCard(tester, AutomationIds.invoiceOrderId);
  });

  testWidgets('pay invoice: the id is a row of the card, even while loading', (
    tester,
  ) async {
    final pending = StreamController<TradeInfo?>();
    addTearDown(pending.close);
    await tester.pumpWidget(
      _app([
        isWalletConnectedProvider.overrideWithValue(false),
        tradeAmountProvider.overrideWith(
          (ref, id) => const Stream<BigInt?>.empty(),
        ),
        tradeInfoStreamProvider.overrideWith((ref, id) => pending.stream),
        tradeInfoProvider.overrideWith((ref, id) async => null),
        tradeStatusProvider.overrideWith(
          (ref, id) => const Stream<OrderStatus>.empty(),
        ),
        tradeUpdatesProvider.overrideWith(
          (ref) => const Stream<TradeUpdate>.empty(),
        ),
        invoiceDeadlineProvider.overrideWith((ref, id) async => null),
        mostroNodeProvider.overrideWith((ref) async => null),
        activeNodeNameProvider.overrideWithValue(null),
      ], const PayLightningInvoiceScreen(orderId: _orderId)),
    );
    await tester.pump();

    await _expectIdRowInCard(tester, AutomationIds.payOrderId);
  });

  testWidgets('pay invoice: the id is a row of the counterpart card', (
    tester,
  ) async {
    final trade = fakeTrade(
      orderId: _orderId,
      status: OrderStatus.waitingPayment,
      role: TradeRole.seller,
      isMine: true,
      amountSats: BigInt.from(163069),
      holdInvoice: 'lnbc1630690n1holdinvoice',
    );
    await tester.pumpWidget(
      _app([
        isWalletConnectedProvider.overrideWithValue(false),
        tradeAmountProvider.overrideWith(
          (ref, id) => Stream.value(BigInt.from(163069)),
        ),
        tradeInfoStreamProvider.overrideWith((ref, id) => Stream.value(trade)),
        tradeInfoProvider.overrideWith((ref, id) async => trade),
        tradeStatusProvider.overrideWith(
          (ref, id) => const Stream<OrderStatus>.empty(),
        ),
        tradeUpdatesProvider.overrideWith(
          (ref) => const Stream<TradeUpdate>.empty(),
        ),
        invoiceDeadlineProvider.overrideWith((ref, id) async => null),
        mostroNodeProvider.overrideWith((ref) async => null),
        activeNodeNameProvider.overrideWithValue(null),
      ], const PayLightningInvoiceScreen(orderId: _orderId)),
    );
    await tester.pumpAndSettle();

    await _expectIdRowInCard(tester, AutomationIds.payOrderId);
  });

  testWidgets('pay bond: the id is a row of the card', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final trade = fakeTrade(
      orderId: _orderId,
      bond: BondInfo(
        role: BondRole.taker,
        amountSats: BigInt.from(1648),
        invoice: 'lnbc16480n1bond',
        state: BondState.requested,
        requestedAt: intToPlatformInt64(1000),
        expiresAt: null,
        lockedAt: null,
      ),
    );
    await tester.pumpWidget(
      _app([
        isWalletConnectedProvider.overrideWithValue(false),
        tradeInfoProvider.overrideWith((ref, id) async => trade),
        tradeUpdatesProvider.overrideWith(
          (ref) => const Stream<TradeUpdate>.empty(),
        ),
        mostroNodeProvider.overrideWith((ref) async => null),
        exchangeRateProvider.overrideWith((ref, code) async => null),
      ], const PayBondInvoiceScreen(orderId: _orderId)),
    );
    await tester.pump();
    await tester.pump();

    await _expectIdRowInCard(tester, AutomationIds.bondOrderId);
  });

  testWidgets('bond payout: the id is a row of the card', (tester) async {
    const now = 1789300800;
    final claim = BondClaim(
      orderId: _orderId,
      nodePubkey: 'node-a',
      tradeIndex: 3,
      amountSats: BigInt.from(1500),
      slashedAt: intToPlatformInt64(now - 3600),
      deadlineAt: intToPlatformInt64(now + 86400),
      phase: BondClaimPhase.pending,
      submittedInvoice: null,
      fiatCode: 'USD',
      fiatAmount: 100,
      paymentMethod: 'Wire',
      updatedAt: intToPlatformInt64(now - 60),
    );
    await withClock(
      Clock.fixed(DateTime.fromMillisecondsSinceEpoch(now * 1000)),
      () async {
        await tester.pumpWidget(
          _app([
            isWalletConnectedProvider.overrideWithValue(false),
            bondClaimProvider.overrideWith((ref, id) async => claim),
            bondClaimUpdatesProvider.overrideWith(
              (ref) => const Stream<BondClaimUpdate>.empty(),
            ),
          ], const BondPayoutInvoiceScreen(orderId: _orderId)),
        );
        await tester.pump();
        await tester.pump();

        await _expectIdRowInCard(tester, AutomationIds.bondClaimOrderId);
      },
    );
  });
}
