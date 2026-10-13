import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/deep_links/providers/order_link_providers.dart';
import 'package:mostro/features/deep_links/screens/order_link_screen.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/order_link.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../support/fake_orders.dart';
import '../../support/fake_trades.dart';
import '../../support/provider_harness.dart';

const _id = 'e215c07e-b1f9-45b0-9640-0295067ee99a';
const _link = 'mostro:$_id?relays=wss://nos.lol';
const _active =
    '0000000000000000000000000000000000000000000000000000000000000001';
const _other =
    '82fa8cb978b43c79b2156585bac2c011176a21d2aead6d9f7c575c005be88390';

final _en = AppLocalizationsEn();

MostroNodeEntry _node(String pubkey, String name, {bool active = false}) =>
    MostroNodeEntry(
      pubkey: pubkey,
      region: null,
      isTrusted: true,
      isActive: active,
      name: name,
      picture: null,
      about: null,
      website: null,
    );

final _registry = [
  _node(_active, 'Home node', active: true),
  _node(_other, 'Far node'),
];

OrderLinkTarget _target({
  OrderStatus status = OrderStatus.pending,
  OrderKind kind = OrderKind.sell,
  String node = _active,
}) => OrderLinkTarget(
  order: fakeTrade(orderId: _id, kind: kind, status: status).order,
  nodePubkey: node,
  onActiveNode: node == _active,
);

/// The live book the take screen reads, as a test sets it.
final _book = StateProvider<Map<String, OrderItem>>((ref) => const {});

/// Serves [nodes] and records the node changes it is asked for — no bridge.
class _FakeNodes extends MostroNodesNotifier {
  _FakeNodes(this.nodes, {this.failSelect = false});

  final List<MostroNodeEntry> nodes;
  final bool failSelect;
  final List<String> selected = [];

  @override
  Future<List<MostroNodeEntry>> build() async => nodes;

  @override
  Future<void> refreshMetadata() async {}

  @override
  Future<void> selectNode(String pubkey) async {
    if (failSelect) throw Exception('boom');
    selected.add(pubkey);
  }
}

/// Opens the link screen over a stand-in home, under a router whose every
/// destination reads its own name. [answers] are what the core says to each
/// lookup in turn: an [OrderLinkTarget], or an error to throw. The order is
/// in the live book unless [inBook] is false.
Future<(_FakeNodes, ProviderContainer)> _pump(
  WidgetTester tester, {
  required List<Object> answers,
  TradeRole? role,
  bool? tradeInProgress = false,
  List<MostroNodeEntry>? nodes,
  bool failSelect = false,
  bool inBook = true,
  Locale locale = const Locale('en'),
  double textScale = 1,
  Size size = const Size(360, 760),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final fakeNodes = _FakeNodes(nodes ?? _registry, failSelect: failSelect);
  final pending = [...answers];
  final container = createContainer(
    overrides: [
      orderLinkResolverProvider.overrideWithValue((link) async {
        expect(link, _link);
        final answer = pending.removeAt(0);
        if (answer is OrderLinkTarget) return answer;
        if (answer is Completer<OrderLinkTarget>) return answer.future;
        throw answer;
      }),
      tradeRoleLookupProvider.overrideWithValue((_) async => role),
      tradeInProgressLookupProvider.overrideWithValue(
        () async => tradeInProgress,
      ),
      mostroNodesProvider.overrideWith(() => fakeNodes),
      mostroPubkeyProvider.overrideWith((ref) => _active),
      _book.overrideWith((ref) => inBook ? {_id: fakeOrder(id: _id)} : {}),
      orderBookIndexProvider.overrideWith((ref) => ref.watch(_book)),
    ],
  );
  final router = GoRouter(
    initialLocation: AppRoute.home,
    routes: [
      GoRoute(
        path: AppRoute.home,
        builder: (_, __) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: AppRoute.orderLink,
        builder:
            (_, state) =>
                OrderLinkScreen(link: state.uri.queryParameters['link']!),
      ),
      for (final (path, name) in [
        (AppRoute.takeSell, 'take sell'),
        (AppRoute.takeBuy, 'take buy'),
        (AppRoute.tradeDetail, 'trade'),
      ])
        GoRoute(path: path, builder: (_, __) => Scaffold(body: Text(name))),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildDarkTheme(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
      ),
    ),
  );
  router.push(AppRoute.orderLinkPath(_link));
  await _settle(tester);
  return (fakeNodes, container);
}

/// Frames enough for the lookups, a dialog's entrance and a route change. Not
/// `pumpAndSettle`: the spinner and the mascot never settle.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('on the active node', () {
    testWidgets('a pending order opens the take screen of its side', (
      tester,
    ) async {
      // Act
      await _pump(tester, answers: [_target(kind: OrderKind.buy)]);

      // Assert
      expect(find.text('take buy'), findsOneWidget);
      expect(find.byType(OrderLinkScreen), findsNothing);
    });

    testWidgets('the take screen replaces it: back returns to where the user '
        'was', (tester) async {
      // Arrange
      await _pump(tester, answers: [_target()]);
      expect(find.text('take sell'), findsOneWidget);

      // Act
      GoRouter.of(tester.element(find.text('take sell'))).pop();
      await _settle(tester);

      // Assert
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('the take screen waits for the order to reach the book', (
      tester,
    ) async {
      // Arrange
      final (_, container) = await _pump(
        tester,
        answers: [_target()],
        inBook: false,
      );
      expect(find.text(_en.orderLinkLooking), findsOneWidget);

      // Act
      container.read(_book.notifier).state = {_id: fakeOrder(id: _id)};
      await _settle(tester);

      // Assert
      expect(find.text('take sell'), findsOneWidget);
    });

    testWidgets('a book that never shows the order does not hold it back', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, answers: [_target()], inBook: false);

      // Act
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);

      // Assert
      expect(find.text('take sell'), findsOneWidget);
    });

    testWidgets('a participant lands on their trade', (tester) async {
      // Act
      await _pump(tester, answers: [_target()], role: TradeRole.buyer);

      // Assert
      expect(find.text('trade'), findsOneWidget);
    });

    testWidgets('an order that left the book says so, with nothing to retry', (
      tester,
    ) async {
      // Act
      await _pump(tester, answers: [_target(status: OrderStatus.inProgress)]);

      // Assert
      expect(find.text(_en.orderLinkUnavailableTitle), findsOneWidget);
      expect(find.text(_en.retry), findsNothing);
    });
  });

  testWidgets('says what it is doing while it looks', (tester) async {
    // Arrange
    final lookup = Completer<OrderLinkTarget>();

    // Act
    await _pump(tester, answers: [lookup]);

    // Assert
    expect(find.text(_en.orderLinkLooking), findsOneWidget);
    lookup.complete(_target());
    await _settle(tester);
    expect(find.text('take sell'), findsOneWidget);
  });

  testWidgets('a link the core cannot read is told, with nothing to retry', (
    tester,
  ) async {
    // Act
    await _pump(tester, answers: [Exception('InvalidOrderLink: no UUID')]);

    // Assert
    expect(find.text(_en.orderLinkInvalidTitle), findsOneWidget);
    expect(find.text(_en.orderLinkInvalidBody), findsOneWidget);
    expect(find.text(_en.retry), findsNothing);
  });

  testWidgets('an order no relay answered with can be looked up again', (
    tester,
  ) async {
    // Arrange
    await _pump(
      tester,
      answers: [Exception('OrderLinkNotFound: $_id'), _target()],
    );
    expect(find.text(_en.orderNotFoundTitle), findsOneWidget);
    expect(find.text(_en.orderLinkNotFoundBody), findsOneWidget);

    // Act
    await tester.tap(find.text(_en.retry));
    await _settle(tester);

    // Assert
    expect(find.text('take sell'), findsOneWidget);
  });

  group('on another node', () {
    testWidgets('asks first, changes node, then opens the order', (
      tester,
    ) async {
      // Arrange
      final (nodes, _) = await _pump(
        tester,
        answers: [_target(node: _other), _target()],
      );
      expect(find.text(_en.orderLinkOtherNodeTitle), findsOneWidget);
      expect(find.text(_en.orderLinkOtherNodeBody('Far node')), findsOneWidget);
      expect(nodes.selected, isEmpty, reason: 'nothing changes unasked');

      // Act
      await tester.tap(find.text(_en.nodeSwitchConfirmAction));
      await _settle(tester);

      // Assert
      expect(nodes.selected, [_other]);
      expect(find.text('take sell'), findsOneWidget);
    });

    testWidgets('a node the user trusts or added comes with no warning', (
      tester,
    ) async {
      // Act
      await _pump(tester, answers: [_target(node: _other)]);

      // Assert
      expect(find.text(_en.orderLinkUnknownNodeWarning), findsNothing);
    });

    testWidgets('a node outside the list comes with a warning and its key', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        answers: [_target(node: _other)],
        nodes: [_registry.first],
      );

      // Assert
      expect(find.text(_en.orderLinkUnknownNodeWarning), findsOneWidget);
      expect(
        find.text(_en.orderLinkOtherNodeBody(truncatePubkey(_other))),
        findsOneWidget,
      );
    });

    testWidgets('a trade in progress is named before the change', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        answers: [_target(node: _other)],
        tradeInProgress: true,
      );

      // Assert
      expect(
        find.text(_en.nodeSwitchConfirmBody('Home node', 'Far node')),
        findsOneWidget,
      );
    });

    testWidgets('declining leaves the link and the node as they were', (
      tester,
    ) async {
      // Arrange
      final (nodes, _) = await _pump(tester, answers: [_target(node: _other)]);

      // Act
      await tester.tap(find.text(_en.cancel));
      await _settle(tester);

      // Assert
      expect(nodes.selected, isEmpty);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('unreadable trades stop the change before it is offered', (
      tester,
    ) async {
      // Act
      await _pump(
        tester,
        answers: [_target(node: _other)],
        tradeInProgress: null,
      );

      // Assert
      expect(find.text(_en.orderLinkOtherNodeTitle), findsNothing);
      expect(find.text(_en.nodeTradesCheckFailed), findsOneWidget);
    });

    testWidgets('a failed change is told, and can be tried again', (
      tester,
    ) async {
      // Arrange
      await _pump(tester, answers: [_target(node: _other)], failSelect: true);

      // Act
      await tester.tap(find.text(_en.nodeSwitchConfirmAction));
      await _settle(tester);

      // Assert
      expect(find.text(_en.orderLinkFailedTitle), findsOneWidget);
      expect(find.text(_en.errorSwitchingNode), findsOneWidget);
      expect(find.text(_en.retry), findsOneWidget);
    });

    testWidgets('a change that does not take is not asked again', (
      tester,
    ) async {
      // Arrange
      final (nodes, _) = await _pump(
        tester,
        answers: [_target(node: _other), _target(node: _other)],
      );

      // Act
      await tester.tap(find.text(_en.nodeSwitchConfirmAction));
      await _settle(tester);

      // Assert
      expect(nodes.selected, [_other]);
      expect(find.text(_en.orderLinkOtherNodeTitle), findsNothing);
      expect(find.text(_en.errorSwitchingNode), findsOneWidget);
    });
  });

  // DS-A11Y-4: German, 2× text, 320 dp wide, in every state the screen shows.
  group('fits at 2× text in German on 320 dp', () {
    for (final (name, answer) in [
      ('invalid link', Exception('InvalidOrderLink: x')),
      ('not found', Exception('OrderLinkNotFound: x')),
      ('no longer available', _target(status: OrderStatus.canceled)),
    ]) {
      testWidgets(name, (tester) async {
        await _pump(
          tester,
          answers: [answer],
          locale: const Locale('de'),
          textScale: 2,
          size: const Size(320, 640),
        );

        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the change-node dialog, with every note', (tester) async {
      await _pump(
        tester,
        answers: [_target(node: _other)],
        nodes: [_registry.first],
        tradeInProgress: true,
        locale: const Locale('de'),
        textScale: 2,
        size: const Size(320, 640),
      );

      expect(find.byType(Dialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
