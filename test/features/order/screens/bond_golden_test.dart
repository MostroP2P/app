import 'package:clock/clock.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_trades.dart';

/// Handoff 14a (default) and 14b (explanation expanded), 360 x 760, at a
/// frozen clock so the countdown reads 09:12.
final _now = DateTime.utc(2026, 9, 12, 12, 0, 0);
const _id = 'ce8b07a8-3a4e-4b8d-9d16-8b1a0c1d2e3f';

TradeInfo _trade() => fakeTrade(
  id: _id,
  fiatCode: 'ARS',
  bond: BondInfo(
    role: BondRole.taker,
    amountSats: BigInt.from(1648),
    invoice:
        'lnbc16480n1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqbond',
    state: BondState.requested,
    requestedAt: intToPlatformInt64(_now.millisecondsSinceEpoch ~/ 1000),
    expiresAt: intToPlatformInt64(
      _now.millisecondsSinceEpoch ~/ 1000 + 9 * 60 + 12,
    ),
    lockedAt: null,
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required bool explainerOpen,
}) async {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    kBondExplainerOpenKey: explainerOpen,
  });

  await withClock(Clock.fixed(_now), () async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isWalletConnectedProvider.overrideWithValue(false),
          tradeInfoProvider.overrideWith((ref, id) async => _trade()),
          tradeUpdatesProvider.overrideWith(
            (ref) => const Stream<TradeUpdate>.empty(),
          ),
          mostroNodeProvider.overrideWith((ref) async => null),
          // 1 648 sats at 125 000 000 ARS / BTC = 2 060 ARS.
          exchangeRateProvider.overrideWith((ref, code) async => 125000000.0),
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
          home: const PayBondInvoiceScreen(orderId: _id),
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
    testWidgets('14a_default · $name', (tester) async {
      await _pump(tester, brightness: brightness, explainerOpen: false);
      await expectLater(
        find.byType(PayBondInvoiceScreen),
        matchesGoldenFile('goldens/bond_14a_default_$name.png'),
      );
    });

    testWidgets('14b_explained · $name', (tester) async {
      await _pump(tester, brightness: brightness, explainerOpen: true);
      await expectLater(
        find.byType(PayBondInvoiceScreen),
        matchesGoldenFile('goldens/bond_14b_explained_$name.png'),
      );
    });
  }
}
