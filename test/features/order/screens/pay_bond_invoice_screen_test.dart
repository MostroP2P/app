import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/pay_bond_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_trades.dart';

BondInfo _bond({String? invoice = 'lnbc16480n1bond'}) => BondInfo(
  role: BondRole.taker,
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
  Future<TradeInfo> Function(String)? requestAgain,
}) async {
  SharedPreferences.setMockInitialValues({
    kBondExplainerOpenKey: explainerOpen,
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isWalletConnectedProvider.overrideWithValue(false),
        tradeInfoProvider.overrideWith((ref, id) async => trade),
        tradeUpdatesProvider.overrideWith(
          (ref) => const Stream<TradeUpdate>.empty(),
        ),
        mostroNodeProvider.overrideWith((ref) async => null),
        exchangeRateProvider.overrideWith((ref, code) async => null),
        if (requestAgain != null)
          requestBondInvoiceAgainProvider.overrideWithValue(requestAgain),
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
    await _pump(tester, trade: fakeTrade(bond: _bond()));

    expect(find.text('1648'), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    expect(
      find.textContaining('held in your wallet', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('it is released on its own', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('you lose it', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Open in my wallet'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text("Don't take the order"), findsOneWidget);
    expect(find.text('Read the documentation'), findsNothing);
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
}
