import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/features/trades/widgets/cancel_request_notice.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';

final _en = AppLocalizationsEn();

Future<void> _pump(
  WidgetTester tester, {
  required TradeInfo? trade,
  required OrderStatus status,
}) async {
  final container = ProviderContainer(
    overrides: [
      rawTradesProvider.overrideWith(
        (ref) async => trade == null ? const [] : [trade],
      ),
      tradeStatusProvider(
        'order-1',
      ).overrideWith((ref) => Stream.value(status)),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const Scaffold(body: CancelRequestNotice(orderId: 'order-1')),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Protocol `cancel.md`, "Cancel cooperatively": a request moves nothing,
/// so the trade row is the only place that knows one is pending. The notice
/// reads it back for the trade screen — for the requester, who otherwise
/// sees a trade that looks untouched, and for the counterparty, who was
/// never told at all.
void main() {
  testWidgets('says this side asked and now waits', (tester) async {
    await _pump(
      tester,
      trade: fakeTrade(
        id: '1',
        cooperativeCancelState: CooperativeCancelState.requestedByMe,
      ),
      status: OrderStatus.active,
    );

    expect(find.text(_en.tradeCancelRequestedByMeNotice), findsOneWidget);
    expect(find.text(_en.tradeCancelRequestedByPeerNotice), findsNothing);
  });

  testWidgets('says the counterparty asked, after fiat sent too', (
    tester,
  ) async {
    await _pump(
      tester,
      trade: fakeTrade(
        id: '1',
        status: OrderStatus.fiatSent,
        cooperativeCancelState: CooperativeCancelState.requestedByPeer,
      ),
      status: OrderStatus.fiatSent,
    );

    expect(find.text(_en.tradeCancelRequestedByPeerNotice), findsOneWidget);
  });

  testWidgets('nothing without a request', (tester) async {
    await _pump(tester, trade: fakeTrade(id: '1'), status: OrderStatus.active);

    expect(find.byType(Text), findsNothing);
  });

  for (final status in [
    OrderStatus.cooperativelyCanceled,
    OrderStatus.dispute,
    OrderStatus.success,
  ]) {
    testWidgets('nothing once the trade is over, whatever the row remembers '
        '($status)', (tester) async {
      await _pump(
        tester,
        trade: fakeTrade(
          id: '1',
          status: status,
          cooperativeCancelState: CooperativeCancelState.requestedByPeer,
        ),
        status: status,
      );

      expect(find.byType(Text), findsNothing);
    });
  }

  testWidgets('nothing without a trade row', (tester) async {
    await _pump(tester, trade: null, status: OrderStatus.active);

    expect(find.byType(Text), findsNothing);
  });
}
