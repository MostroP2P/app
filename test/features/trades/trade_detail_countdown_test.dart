import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/screens/trade_detail_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../support/fake_trades.dart';
import '../../support/provider_harness.dart';

const _orderId = 'order-bond-countdown';

/// Pumps [TradeDetailScreen] with the bridge accessors substituted, so the
/// countdown resolves against known deadlines.
///
/// [timeoutAt] is the trade's own bond deadline; [listingExpiresAt] the public
/// listing expiry, or `null` for an order that is no longer in the book.
Future<void> _pumpTradeDetail(
  WidgetTester tester, {
  required int? timeoutAt,
  required int? listingExpiresAt,
  OrderStatus status = OrderStatus.waitingTakerBond,
}) async {
  final trade = fakeTrade(
    orderId: _orderId,
    status: status,
    timeoutAt: timeoutAt,
    bondInvoice: 'lnbc1bond',
  );

  final container = createContainer(overrides: [
    tradeRoleProvider.overrideWith((ref) => {_orderId: true}),
    tradeStatusProvider(_orderId).overrideWith((ref) => Stream.value(status)),
    orderBookProvider.overrideWith((ref) => Stream.value(const [])),
    bridgeListTradesProvider.overrideWithValue(() async => [trade]),
    bridgeGetOrderProvider.overrideWithValue(
      (_) async => listingExpiresAt == null
          ? null
          : fakeTrade(orderId: _orderId, expiresAt: listingExpiresAt).order,
    ),
  ]);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const TradeDetailScreen(orderId: _orderId),
      ),
    ),
  );
  // Not pumpAndSettle: the screen runs a 1s-period countdown timer forever.
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// The rendered countdown, as `MM:SS` or `H:MM:SS`.
String? _countdown(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data)
    .firstWhere(
      (d) => d != null && RegExp(r'^(\d+:)?\d{2}:\d{2}$').hasMatch(d),
      orElse: () => null,
    );

int _epochIn(Duration d) =>
    DateTime.now().add(d).millisecondsSinceEpoch ~/ 1000;

void main() {
  group('TradeDetailScreen bond countdown', () {
    testWidgets('uses the bond timeout, not the far-off listing expiry',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        timeoutAt: _epochIn(const Duration(minutes: 10)),
        listingExpiresAt: _epochIn(const Duration(hours: 24)),
      );

      final shown = _countdown(tester);
      expect(shown, isNotNull, reason: 'the waitingBond timer must render');
      expect(shown, matches(RegExp(r'^(09|10):\d{2}$')),
          reason: 'showing the 24h listing expiry would be a false window, '
              'got $shown');
    });

    testWidgets('uses the bond timeout when the listing is already gone',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        timeoutAt: _epochIn(const Duration(minutes: 10)),
        listingExpiresAt: null,
      );

      final shown = _countdown(tester);
      expect(shown, matches(RegExp(r'^(09|10):\d{2}$')),
          reason: 'an absent listing must not restart a fresh 15:00, got $shown');
    });

    testWidgets('still uses the listing expiry once past the bond step',
        (tester) async {
      await _pumpTradeDetail(
        tester,
        status: OrderStatus.waitingBuyerInvoice,
        timeoutAt: _epochIn(const Duration(minutes: 10)),
        listingExpiresAt: _epochIn(const Duration(minutes: 30)),
      );

      expect(_countdown(tester), matches(RegExp(r'^(29|30):\d{2}$')),
          reason: 'the bond deadline only applies while the bond is owed');
    });
  });
}
