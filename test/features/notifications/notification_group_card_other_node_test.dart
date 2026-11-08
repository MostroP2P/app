import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/widgets/notification_group_card.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_de.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/types.dart';

/// #811: a card of a trade on another node says so, and every way into it
/// goes through `onOtherNode`, which offers the switch first.

final _en = AppLocalizationsEn();
final _de = AppLocalizationsDe();

const _nodeA =
    'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111';
const _nodeB =
    'bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222';
const _orderId = 'd5f425ca-1111-4c3d-8e9f-0a1b2c3d99b5';

class _Nodes extends MostroNodesNotifier {
  @override
  Future<List<MostroNodeEntry>> build() async => [
    const MostroNodeEntry(
      pubkey: _nodeA,
      region: null,
      isTrusted: true,
      isActive: false,
      name: 'Node A',
      picture: null,
      about: null,
      website: null,
    ),
  ];

  @override
  Future<void> refreshMetadata() async {}
}

NotificationModel _card(String status, int hour, {String? node}) =>
    NotificationModel.tradeStatus(
      orderId: _orderId,
      status: status,
      at: DateTime.utc(2026, 1, 1, hour),
      nodePubkey: node,
    );

TradeRow _row() => TradeRow(
  orderId: _orderId,
  status: OrderStatus.active,
  rowStatus: OrderStatus.active,
  state: TradeRowState.of(
    status: OrderStatus.active,
    isBuyer: false,
    ratedByMe: true,
    canRate: false,
  ),
  isSelling: true,
  isMaker: false,
  fiatAmount: 50000,
  fiatAmountMin: null,
  fiatAmountMax: null,
  fiatCode: 'ARS',
  premium: 0,
  amountSats: 95004,
  paymentMethod: 'Bank transfer',
  startedAt: 0,
  peerHandle: null,
  node: _nodeA,
);

void main() {
  late List<NotificationModel> tapped;
  late int wentToTrade;
  late List<(String, String, VoidCallback)> offered;

  Future<void> pump(
    WidgetTester tester, {
    required String active,
    required List<NotificationModel> cards,
    Locale locale = const Locale('en'),
  }) async {
    tapped = [];
    wentToTrade = 0;
    offered = [];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mostroPubkeyProvider.overrideWith((_) => active),
          mostroNodesProvider.overrideWith(_Nodes.new),
          tradeRowsProvider.overrideWithValue(AsyncValue.data([_row()])),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          locale: locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: NotificationGroupCard(
                notifications: cards,
                tradeRow: _row(),
                onTapNotification: tapped.add,
                onGoToTrade: () => wentToTrade++,
                onOtherNode:
                    (node, name, open) => offered.add((node, name, open)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('on another node the card names it and offers its node', (
    tester,
  ) async {
    await pump(
      tester,
      active: _nodeB,
      cards: [_card('fiatSent', 2, node: _nodeA), _card('active', 1)],
    );

    expect(find.text(_en.otherNodeCardLine('Node A')), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);

    // Each way into the trade offers its node instead of opening.
    await tester.tap(find.text(_en.tradeCardFiatSentTitle));
    await tester.tap(find.text(_en.goToTrade));
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.tradeCardActiveTitle));
    await tester.pump();

    expect(tapped, isEmpty, reason: 'no event opens on another node');
    expect(wentToTrade, 0, reason: 'nor does Go to trade');
    expect(
      [for (final (node, name, _) in offered) (node, name)],
      [(_nodeA, 'Node A'), (_nodeA, 'Node A'), (_nodeA, 'Node A')],
    );

    // What each would have done on the trade's node, run once switched.
    for (final (_, _, open) in offered) {
      open();
    }
    expect(tapped.map((n) => n.id), [
      'trade-$_orderId-fiatSent',
      'trade-$_orderId-active',
    ]);
    expect(wentToTrade, 1);
  });

  // DS-A11Y-4: the card's line at 320 dp, 2× text, German.
  testWidgets('the line fits 320 dp at 2× text in German', (tester) async {
    tester.view.physicalSize = const Size(320, 760);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pump(
      tester,
      active: _nodeB,
      cards: [_card('fiatSent', 2, node: _nodeA)],
      locale: const Locale('de'),
    );
    expect(find.text(_de.otherNodeCardLine('Node A')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('on its own node the card has no line and opens as usual', (
    tester,
  ) async {
    await pump(
      tester,
      active: _nodeA,
      cards: [_card('fiatSent', 2, node: _nodeA)],
    );

    expect(find.text(_en.otherNodeCardLine('Node A')), findsNothing);

    await tester.tap(find.text(_en.tradeCardFiatSentTitle));
    await tester.tap(find.text(_en.goToTrade));
    await tester.pump();

    expect(tapped.single.id, 'trade-$_orderId-fiatSent');
    expect(wentToTrade, 1);
    expect(offered, isEmpty);
  });

  testWidgets('a card that recorded no node reads as the active node\'s', (
    tester,
  ) async {
    await pump(tester, active: _nodeB, cards: [_card('fiatSent', 2)]);

    expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);

    await tester.tap(find.text(_en.tradeCardFiatSentTitle));
    await tester.pump();

    expect(tapped, hasLength(1));
  });

  testWidgets('a node the registry does not hold reads as its short key', (
    tester,
  ) async {
    const unknown =
        'cccc3333cccc3333cccc3333cccc3333cccc3333cccc3333cccc3333cccc3333';
    await pump(
      tester,
      active: _nodeB,
      cards: [_card('fiatSent', 2, node: unknown)],
    );

    expect(
      find.text(_en.otherNodeCardLine(truncatePubkey(unknown))),
      findsOneWidget,
    );
  });
}
