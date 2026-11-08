import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/providers/backup_reminder_provider.dart';
import 'package:mostro/features/account/restore/restore_after_switch.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/notifications/screens/notifications_screen.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../support/provider_harness.dart';

/// #811: a notification of a trade on another node offers to switch to that
/// node, and once switched opens what was tapped.

final _en = AppLocalizationsEn();

const _nodeA =
    'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111';
const _nodeB =
    'bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222';
const _orderId = 'd5f425ca-1111-4c3d-8e9f-0a1b2c3d99b5';

/// Serves a registry holding [_nodeA] (unless [knowsA] is false) and makes
/// a selected node the active one, as the real switch does — no bridge.
class _FakeNodes extends MostroNodesNotifier {
  _FakeNodes({this.knowsA = true, this.failSelect = false});

  final bool knowsA;
  final bool failSelect;
  final List<String> selected = [];

  @override
  Future<List<MostroNodeEntry>> build() async => [
    if (knowsA)
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

  @override
  Future<void> selectNode(String pubkey) async {
    if (failSelect) throw Exception('boom');
    selected.add(pubkey);
    ref.read(mostroPubkeyProvider.notifier).state = pubkey;
  }
}

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

NotificationModel _chat() => NotificationModel.chatMessages(
  tradeId: _orderId,
  fromSolver: false,
  count: 1,
  at: DateTime.utc(2026, 1, 1, 2),
  nodePubkey: _nodeA,
);

/// Notifications on [_nodeB], over a router whose chat and trade screens
/// read their own names. Returns the fake nodes and the restores asked for.
Future<(_FakeNodes, List<int>)> _pump(
  WidgetTester tester, {
  bool knowsA = true,
  bool failSelect = false,
}) async {
  final nodes = _FakeNodes(knowsA: knowsA, failSelect: failSelect);
  final restores = [0];
  final notifier = NotificationsNotifier();
  await notifier.add(_chat());
  final container = createContainer(
    overrides: [
      notificationsProvider.overrideWith((_) => notifier),
      tradeRowsProvider.overrideWithValue(AsyncValue.data([_row()])),
      backupReminderProvider.overrideWith(
        (_) => BackupReminderNotifier(initialValue: false),
      ),
      mostroNodesProvider.overrideWith(() => nodes),
      mostroPubkeyProvider.overrideWith((_) => _nodeB),
      restoreAfterNodeSwitchProvider.overrideWithValue(
        (_) async => restores[0]++,
      ),
    ],
  );
  final router = GoRouter(
    initialLocation: AppRoute.notifications,
    routes: [
      GoRoute(
        path: AppRoute.notifications,
        builder: (_, __) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoute.chatRoom,
        builder: (_, __) => const Scaffold(body: Text('chat')),
      ),
      GoRoute(
        path: AppRoute.tradeDetail,
        builder: (_, __) => const Scaffold(body: Text('trade')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (nodes, restores);
}

void main() {
  testWidgets('switching from a chat card restores, then opens the chat', (
    tester,
  ) async {
    final (nodes, restores) = await _pump(tester);

    await tester.tap(find.text(_en.chatCardTitle));
    await tester.pumpAndSettle();
    expect(find.text(_en.otherNodeCardSwitchPrompt('Node A')), findsOneWidget);

    await tester.tap(find.text(_en.nodeSwitchConfirmAction));
    await tester.pumpAndSettle();

    expect(nodes.selected, [_nodeA]);
    expect(restores.single, 1);
    expect(find.text('chat'), findsOneWidget);
  });

  testWidgets('switching from Go to trade opens the trade', (tester) async {
    final (nodes, _) = await _pump(tester);

    await tester.tap(find.text(_en.goToTrade));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.nodeSwitchConfirmAction));
    await tester.pumpAndSettle();

    expect(nodes.selected, [_nodeA]);
    expect(find.text('trade'), findsOneWidget);
  });

  testWidgets('Cancel stays on the node and opens nothing', (tester) async {
    final (nodes, restores) = await _pump(tester);

    await tester.tap(find.text(_en.goToTrade));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.cancel));
    await tester.pumpAndSettle();

    expect(nodes.selected, isEmpty);
    expect(restores.single, 0);
    expect(find.text(_en.otherNodeCardLine('Node A')), findsOneWidget);
    expect(find.text('trade'), findsNothing);
  });

  testWidgets('a failed switch says so and opens nothing', (tester) async {
    final (_, restores) = await _pump(tester, failSelect: true);

    await tester.tap(find.text(_en.goToTrade));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_en.nodeSwitchConfirmAction));
    await tester.pumpAndSettle();

    expect(find.text(_en.errorSwitchingNode), findsOneWidget);
    expect(restores.single, 0);
    expect(find.text('trade'), findsNothing);
  });

  testWidgets('a node the registry does not hold is offered too', (
    tester,
  ) async {
    final (nodes, _) = await _pump(tester, knowsA: false);
    final shortKey = truncatePubkey(_nodeA);

    await tester.tap(find.text(_en.goToTrade));
    await tester.pumpAndSettle();
    expect(find.text(_en.otherNodeCardSwitchPrompt(shortKey)), findsOneWidget);

    await tester.tap(find.text(_en.nodeSwitchConfirmAction));
    await tester.pumpAndSettle();

    expect(nodes.selected, [_nodeA]);
    expect(find.text('trade'), findsOneWidget);
  });
}
