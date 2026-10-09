import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/widgets/nwc_payment_widget.dart';
import 'package:mostro/features/about/models/mostro_instance.dart' as instance;
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/pay_bond_invoice_screen.dart';
import 'package:mostro/features/order/widgets/invoice_widgets.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/src/rust/api/types.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_trades.dart';

BondInfo _bond({
  String? invoice = 'lnbc16480n1bond',
  BondRole role = BondRole.taker,
}) => BondInfo(
  role: role,
  amountSats: BigInt.from(1648),
  invoice: invoice,
  state: BondState.requested,
  requestedAt: intToPlatformInt64(1000),
  expiresAt: null,
  lockedAt: null,
);

Future<void> _pump(
  WidgetTester tester, {
  required TradeInfo trade,
  bool explainerOpen = false,
  bool walletConnected = false,
  bool? slashOnTimeout,
  Future<TradeInfo> Function(String)? requestAgain,
  Future<void> Function(String)? cancel,
  Future<void> Function(String)? abandon,
  Future<bool> Function(String)? closeExpired,
}) async {
  SharedPreferences.setMockInitialValues({
    kBondExplainerOpenKey: explainerOpen,
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isWalletConnectedProvider.overrideWithValue(walletConnected),
        tradeInfoProvider.overrideWith((ref, id) async => trade),
        tradeUpdatesProvider.overrideWith(
          (ref) => const Stream<TradeUpdate>.empty(),
        ),
        mostroNodeProvider.overrideWith(
          (ref) async =>
              slashOnTimeout == null
                  ? null
                  : instance.MostroInstance(
                    pubKey: 'node',
                    bondPolicy: instance.BondPolicy.enabled,
                    bondSlashOnWaitingTimeout: slashOnTimeout,
                  ),
        ),
        exchangeRateProvider.overrideWith((ref, code) async => null),
        if (requestAgain != null)
          requestBondInvoiceAgainProvider.overrideWithValue(requestAgain),
        if (cancel != null) cancelBondWindowProvider.overrideWithValue(cancel),
        if (abandon != null)
          abandonBondedOrderProvider.overrideWithValue(abandon),
        if (closeExpired != null)
          closeExpiredBondWindowProvider.overrideWithValue(closeExpired),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const PayBondInvoiceScreen(orderId: 'order-1'),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('14a: the amount first, the three consequences, the wallet', (
    tester,
  ) async {
    await _pump(tester, trade: fakeTrade(bond: _bond()), slashOnTimeout: false);

    expect(find.text('1,648'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    // Whole sentences: the bold part is spliced into the l10n message and
    // the prose on both sides of it must survive.
    expect(
      find.text(
        'The sats stay held in your wallet, they are not spent',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'If the trade ends well, it is released on its own',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'You only lose it if there is a dispute and you lose it',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('Open in my wallet'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text("Don't take the order"), findsOneWidget);
    expect(find.text('Read the documentation'), findsNothing);
  });

  testWidgets('with no node status the timeout warning stands', (tester) async {
    await _pump(tester, trade: fakeTrade(bond: _bond()), slashOnTimeout: null);
    expect(
      find.textContaining('let a step time out', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('a node that does not slash on timeout says so', (tester) async {
    await _pump(tester, trade: fakeTrade(bond: _bond()), slashOnTimeout: false);
    expect(
      find.textContaining('let a step time out', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('a connected wallet pays inside the same disclosures', (
    tester,
  ) async {
    await _pump(tester, trade: fakeTrade(bond: _bond()), walletConnected: true);
    expect(find.byType(NwcPaymentWidget), findsOneWidget);
    expect(find.text('Pay with Wallet'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(
      find.text(
        'The sats stay held in your wallet, they are not spent',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text("Don't take the order"), findsOneWidget);
    expect(find.text('Open in my wallet'), findsNothing);
  });

  testWidgets('14b: opening the explainer hides the QR and copy / share', (
    tester,
  ) async {
    await _pump(tester, trade: fakeTrade(bond: _bond()));
    await tester.tap(find.text('Why Mostro asks for a deposit'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Copy'), findsNothing);
    expect(find.text('Read the documentation'), findsOneWidget);
    expect(
      find.textContaining(
        'Your wallet holds the sats without sending them; when the trade '
        'completes, they are released on their own.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(find.text('You buy 100 USD'), findsOneWidget);
    expect(find.text('Open in my wallet'), findsOneWidget);
    expect(find.text("Don't take the order"), findsOneWidget);
  });

  testWidgets('the explainer opens the way the user last left it', (
    tester,
  ) async {
    await _pump(tester, trade: fakeTrade(bond: _bond()), explainerOpen: true);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Read the documentation'), findsOneWidget);
  });

  testWidgets('the deposit context reads as data rows (DS-CMP-24)', (
    tester,
  ) async {
    await _pump(tester, trade: fakeTrade(bond: _bond()), explainerOpen: true);
    final row = find.ancestor(
      of: find.text('You buy 100 USD'),
      matching: find.byType(OrderDataRow),
    );
    expect(row, findsOneWidget);
    expect(find.descendant(of: row, matching: find.byType(Icon)), findsOne);
    expect(
      find.ancestor(of: row, matching: find.byType(OrderDataCard)),
      findsOneWidget,
    );
  });

  testWidgets('a row without its bolt11 offers the same-take re-request', (
    tester,
  ) async {
    final requested = <String>[];
    await _pump(
      tester,
      trade: fakeTrade(bond: _bond(invoice: null)),
      requestAgain: (id) async {
        requested.add(id);
        return fakeTrade(bond: _bond());
      },
    );
    expect(find.byType(QrImageView), findsNothing);
    await tester.tap(find.text('Request the invoice again'));
    await tester.pump();
    expect(requested, ['order-1']);
  });

  // DS-CMP-20: leaving the bond window cancels something that exists (the
  // take, or the unpublished order), so the link is red and asks first.
  for (final maker in [false, true]) {
    final leave = maker ? "Don't publish the order" : "Don't take the order";
    testWidgets('${maker ? 'maker' : 'taker'}: the way out is red and asks '
        'before cancelling', (tester) async {
      final canceled = <String>[];
      await _pump(
        tester,
        trade: fakeTrade(
          isMine: maker,
          role: maker ? TradeRole.seller : TradeRole.buyer,
          status:
              maker
                  ? OrderStatus.waitingMakerBond
                  : OrderStatus.waitingTakerBond,
          bond: _bond(role: maker ? BondRole.maker : BondRole.taker),
        ),
        cancel: (id) async => canceled.add(id),
      );

      final link = find.byWidgetPredicate(
        (w) => w is InvoiceCancelLink && w.label == leave,
      );
      expect(link, findsOneWidget);
      expect(tester.widget<InvoiceCancelLink>(link).danger, isTrue);

      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();
      expect(canceled, isEmpty);
      final dialog = find.byType(MostroDialog);
      expect(dialog, findsOneWidget);
      final primary = tester.widget<MostroDialog>(dialog).primary;
      expect(primary?.label, 'Yes, cancel');
      expect(primary?.tone, ModalTone.destructive);

      await tester.tap(find.text('Yes, cancel'));
      await tester.pump();
      await tester.pump();
      expect(canceled, ['order-1']);
    });
  }

  group('maker variant (docs/ANTI_ABUSE_BOND.md §6.2)', () {
    TradeInfo makerTrade({String? invoice = 'lnbc16480n1bond'}) => fakeTrade(
      isMine: true,
      role: TradeRole.seller,
      status: OrderStatus.waitingMakerBond,
      bond: _bond(role: BondRole.maker, invoice: invoice),
    );

    testWidgets('says the order is not published and offers to drop it', (
      tester,
    ) async {
      await _pump(tester, trade: makerTrade(), slashOnTimeout: false);
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text("Don't publish the order"), findsOneWidget);
      expect(find.text("Don't take the order"), findsNothing);
      // The maker of a sell order sells.
      await tester.tap(find.text('Why Mostro asks for a deposit'));
      await tester.pump();
      await tester.pump();
      expect(find.text('You sell 100 USD'), findsOneWidget);
    });

    testWidgets('dropping the order sends the daemon a cancel (mostro#996)', (
      tester,
    ) async {
      final canceled = <String>[];
      await _pump(
        tester,
        trade: makerTrade(),
        cancel: (id) async => canceled.add(id),
      );
      await tester.ensureVisible(find.text("Don't publish the order"));
      await tester.tap(find.text("Don't publish the order"));
      // DS-CMP-20: dropping the order asks first.
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, cancel'));
      await tester.pump();
      await tester.pump();
      expect(canceled, ['order-1']);
      expect(
        find.text(
          'Order dropped. Nothing was published and nothing was charged.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'a refused cancel asks before removing the order from this device',
      (tester) async {
        final abandoned = <String>[];
        await _pump(
          tester,
          trade: makerTrade(),
          cancel: (id) async => throw Exception('MakerCancelRefused'),
          abandon: (id) async => abandoned.add(id),
        );
        await tester.ensureVisible(find.text("Don't publish the order"));
        await tester.tap(find.text("Don't publish the order"));
        // DS-CMP-20: dropping the order asks first.
        await tester.pumpAndSettle();
        await tester.tap(find.text('Yes, cancel'));
        await tester.pumpAndSettle();
        expect(find.text("The node didn't cancel the deposit"), findsOneWidget);
        expect(abandoned, isEmpty, reason: 'nothing is dropped on a guess');

        await tester.tap(find.text('Remove from this device'));
        await tester.pump();
        await tester.pump();
        expect(abandoned, ['order-1']);
      },
    );

    testWidgets('keeping the order after a refused cancel drops nothing', (
      tester,
    ) async {
      final abandoned = <String>[];
      await _pump(
        tester,
        trade: makerTrade(),
        cancel: (id) async => throw Exception('MakerCancelRefused'),
        abandon: (id) async => abandoned.add(id),
      );
      await tester.ensureVisible(find.text("Don't publish the order"));
      await tester.tap(find.text("Don't publish the order"));
      // DS-CMP-20: dropping the order asks first.
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep waiting'));
      await tester.pumpAndSettle();
      expect(abandoned, isEmpty);
      expect(find.byType(PayBondInvoiceScreen), findsOneWidget);
    });

    testWidgets('a cancel that lost to the bond says the order is live', (
      tester,
    ) async {
      await _pump(
        tester,
        trade: makerTrade(),
        cancel: (id) async => throw Exception('BondAlreadyLocked'),
      );
      await tester.ensureVisible(find.text("Don't publish the order"));
      await tester.tap(find.text("Don't publish the order"));
      // DS-CMP-20: dropping the order asks first.
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, cancel'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text(
          'Your deposit was already paid, so the order is published. '
          'Cancel it from the order screen.',
        ),
        findsOneWidget,
      );
      expect(find.byType(PayBondInvoiceScreen), findsOneWidget);
    });

    testWidgets('a maker row without its bolt11 has no re-request', (
      tester,
    ) async {
      await _pump(tester, trade: makerTrade(invoice: null));
      expect(find.text('Request the invoice again'), findsNothing);
      expect(find.textContaining('does not resend it'), findsOneWidget);
      expect(find.text("Don't publish the order"), findsOneWidget);
    });

    testWidgets(
      'a restored maker row with no bond at all can still be dropped',
      (tester) async {
        // A fresh-device restore rebuilds the row without BondInfo (§6.5).
        await _pump(
          tester,
          trade: fakeTrade(
            isMine: true,
            role: TradeRole.seller,
            status: OrderStatus.waitingMakerBond,
          ),
        );
        expect(find.textContaining('does not resend it'), findsOneWidget);
        expect(find.text("Don't publish the order"), findsOneWidget);
        expect(find.text('Request the invoice again'), findsNothing);
      },
    );

    testWidgets('the countdown ending asks the core to close the window', (
      tester,
    ) async {
      final closed = <String>[];
      await withClock(
        Clock.fixed(DateTime.fromMillisecondsSinceEpoch(2000000)),
        () async {
          await _pump(
            tester,
            trade: fakeTrade(
              isMine: true,
              role: TradeRole.seller,
              status: OrderStatus.waitingMakerBond,
              bond: BondInfo(
                role: BondRole.maker,
                amountSats: BigInt.from(1648),
                invoice: 'lnbc16480n1bond',
                state: BondState.requested,
                requestedAt: intToPlatformInt64(1000),
                // Already past: the screen opens on the expired view.
                expiresAt: intToPlatformInt64(1500),
                lockedAt: null,
              ),
            ),
            closeExpired: (id) async {
              closed.add(id);
              return true;
            },
          );
          await tester.pump();
          expect(find.text('The deposit invoice expired'), findsOneWidget);
          expect(find.textContaining('never published'), findsOneWidget);
          expect(closed, ['order-1']);
        },
      );
    });
  });
}
