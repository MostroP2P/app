import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/providers/node_stats_provider.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/settings/widgets/mostro_node_selector.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/src/rust/api/node_stats.dart';
import 'package:mostro/src/rust/api/types.dart' show MostroNodeEntry;
import 'package:shimmer/shimmer.dart';
import '../../../support/provider_harness.dart';

/// Syntactically valid hex that is deliberately not any real node.
const _customPubkey =
    '0000000000000000000000000000000000000000000000000000000000000001';
const _cubaPubkey =
    '00000235a3e904cfe1213a8a54d6f1ec1bef7cc6bfaabd6193e82931ccf1366a';

final _now = DateTime.utc(2026, 9, 11, 12, 0);
int _secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

MostroNodeEntry _entry({
  required String pubkey,
  String? region,
  bool isTrusted = false,
  bool isActive = false,
  String? name,
  String? about,
}) => MostroNodeEntry(
  pubkey: pubkey,
  region: region,
  isTrusted: isTrusted,
  isActive: isActive,
  name: name,
  picture: null,
  about: about,
  website: null,
);

MostroNodeStats _stats(
  String pubkey, {
  DateTime? infoSeenAt,
  Map<String, int> orders = const {},
  List<String> accepted = const ['ARS', 'VES'],
  double? feePct = 0.6,
  String escrowMode = 'lightning',
  String? mint,
  bool? bondRequired = false,
}) => MostroNodeStats(
  pubkey: pubkey,
  infoSeenAt: infoSeenAt == null ? null : _secs(infoSeenAt),
  latestOrderAt: null,
  feePct: feePct,
  minOrderAmount: BigInt.from(5000),
  maxOrderAmount: BigInt.from(2000000),
  acceptedCurrencies: accepted,
  escrowMode: escrowMode,
  cashuMintUrl: mint,
  bondRequired: bondRequired,
  bondPct: null,
  ordersByFiat: [
    for (final e in orders.entries)
      FiatOrderCount(fiatCode: e.key, count: e.value),
  ],
  totalOrders: orders.values.fold(0, (a, b) => a + b),
);

final _fixtureNodes = [
  _entry(
    pubkey: defaultMostroPubkey,
    region: '🌐',
    isTrusted: true,
    isActive: true,
    name: 'Mostro',
  ),
  _entry(
    pubkey: _cubaPubkey,
    region: '🇨🇺 Cuba',
    isTrusted: true,
    name: 'Kmbalache',
    about: 'Where Bitcoin becomes P2P again',
  ),
  _entry(pubkey: _customPubkey, name: 'My Node'),
];

final _fixtureStats = {
  defaultMostroPubkey: _stats(
    defaultMostroPubkey,
    infoSeenAt: _now,
    orders: {'ARS': 12, 'VES': 26},
  ),
  _cubaPubkey: _stats(
    _cubaPubkey,
    infoSeenAt: _now,
    orders: {'CUP': 6},
    accepted: ['CUP', 'USD'],
    escrowMode: 'cashu',
    mint: 'https://mint.cashu.space',
  ),
  _customPubkey: _stats(_customPubkey, infoSeenAt: _now, orders: {'ARS': 40}),
};

/// Serves fixed registry entries and records mutations — no Rust bridge.
class _FakeNodesNotifier extends MostroNodesNotifier {
  _FakeNodesNotifier(this.nodes, {this.failSelect = false});

  final List<MostroNodeEntry> nodes;
  final bool failSelect;
  final List<String> selected = [];
  final List<String> removed = [];
  final List<String> added = [];

  /// When set, [selectNode] waits on it — lets a test hold a switch in
  /// flight while interacting with the UI.
  Future<void>? selectGate;

  /// Same, for [addCustomNode].
  Future<void>? addGate;

  @override
  Future<List<MostroNodeEntry>> build() async => nodes;

  @override
  Future<void> refreshMetadata() async {}

  @override
  Future<void> selectNode(String pubkey) async {
    final gate = selectGate;
    if (gate != null) await gate;
    if (failSelect) throw Exception('boom');
    selected.add(pubkey);
  }

  @override
  Future<void> removeCustomNode(String pubkey) async {
    removed.add(pubkey);
  }

  @override
  Future<void> addCustomNode({required String input, String? name}) async {
    final gate = addGate;
    if (gate != null) await gate;
    added.add(input);
  }
}

List<Override> _overrides(
  _FakeNodesNotifier notifier, {
  Map<String, MostroNodeStats>? stats,
  Completer<Map<String, MostroNodeStats>>? statsGate,
  String? fiat = 'ARS',
}) => [
  mostroNodesProvider.overrideWith(() => notifier),
  nodeStatsProvider.overrideWith(
    (ref) => statsGate?.future ?? Future.value(stats ?? _fixtureStats),
  ),
  settingsProvider.overrideWith(
    (ref) => SettingsNotifier(initial: AppSettingsState(defaultFiatCode: fiat)),
  ),
  currencyFlagsProvider.overrideWithValue(const {
    'ARS': '🇦🇷',
    'VES': '🇻🇪',
    'CUP': '🇨🇺',
    'USD': '🇺🇸',
  }),
  exchangeRateProvider.overrideWith((ref, code) async => 36000000.0),
  rawTradesProvider.overrideWith((ref) async => const []),
];

Widget _app(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

Future<_FakeNodesNotifier> _pump(
  WidgetTester tester, {
  List<MostroNodeEntry>? nodes,
  Map<String, MostroNodeStats>? stats,
  Completer<Map<String, MostroNodeStats>>? statsGate,
  String? fiat = 'ARS',
  bool failSelect = false,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final notifier = _FakeNodesNotifier(
    nodes ?? _fixtureNodes,
    failSelect: failSelect,
  );
  final container = createContainer(
    overrides: _overrides(
      notifier,
      stats: stats,
      statsGate: statsGate,
      fiat: fiat,
    ),
  );
  await tester.pumpWidget(
    _app(container, const Scaffold(body: MostroNodeSelector())),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  return notifier;
}

/// Selecting waits the 200 ms close delay before the switch resolves.
Future<void> _settleSelection(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  group('MostroNodeSelector', () {
    testWidgets('lists every node flat, ordered by orders in my currency', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        await _pump(tester);
        // No section headers any more.
        expect(find.text('Trusted Nodes'), findsNothing);
        expect(find.text('Custom Nodes'), findsNothing);
        // 40 ARS (custom) > 12 ARS (default) > 0 ARS (Cuba).
        final myNode = tester.getTopLeft(find.text('My Node'));
        final mostro = tester.getTopLeft(find.text('Mostro 🌐'));
        final cuba = tester.getTopLeft(find.text('Kmbalache 🇨🇺'));
        expect(myNode.dy, lessThan(mostro.dy));
        expect(mostro.dy, lessThan(cuba.dy));
        // Trusted chip on the two trusted nodes only.
        expect(find.text('TRUSTED'), findsNWidgets(2));
        // The operator description left the card.
        expect(find.text('Where Bitcoin becomes P2P again'), findsNothing);
      });
    });

    testWidgets('card shows currencies, liquidity, fee, range and custody', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        await _pump(tester);
        expect(
          find.text('Orders and currencies for ARS, your currency'),
          findsOneWidget,
        );
        expect(find.text('· 12 in ARS'), findsOneWidget);
        expect(find.text('38'), findsOneWidget);
        expect(find.text('0.6'), findsNWidgets(3));
        expect(find.text('5k–2M'), findsNWidgets(3));
        expect(find.text('≈ 1,800 – 720,000 ARS'), findsNWidgets(3));
        expect(find.text('Lightning custody'), findsNWidgets(2));
        expect(find.text('Cashu custody · mint.cashu.space'), findsOneWidget);
        // Cuba does not accept ARS: amber chip, zero-in-mine unit.
        expect(find.text('NO ARS'), findsOneWidget);
        expect(find.text('· 0 in ARS'), findsOneWidget);
        expect(find.text('No orders in your currencies'), findsOneWidget);
      });
    });

    testWidgets('shows skeletons while stats load, never a spinner', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final gate = Completer<Map<String, MostroNodeStats>>();
        await _pump(tester, statsGate: gate);
        expect(find.byType(Shimmer), findsWidgets);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        gate.complete(_fixtureStats);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byType(Shimmer), findsNothing);
        expect(find.text('38'), findsOneWidget);
      });
    });

    testWidgets('a failed stats fetch shows dashes and keeps cards tappable', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final gate = Completer<Map<String, MostroNodeStats>>();
        final notifier = await _pump(tester, statsGate: gate);
        gate.completeError(Exception('relay down'));
        await tester.pump();
        await tester.pump();
        expect(find.text('—'), findsWidgets);
        await tester.tap(find.text('Kmbalache 🇨🇺'));
        await _settleSelection(tester);
        expect(notifier.selected, [_cubaPubkey]);
      });
    });

    testWidgets('active node shows the filled radio and ignores taps', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final notifier = await _pump(tester);
        expect(find.byIcon(Icons.check), findsOneWidget);
        await tester.tap(find.text('Mostro 🌐'));
        await _settleSelection(tester);
        expect(notifier.selected, isEmpty);
      });
    });

    testWidgets('tapping a node fills its radio, then selects it', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final notifier = await _pump(tester);
        await tester.tap(find.text('Kmbalache 🇨🇺'));
        await tester.pump();
        await tester.pump();
        expect(find.byIcon(Icons.check), findsNWidgets(2));
        await _settleSelection(tester);
        expect(notifier.selected, [_cubaPubkey]);
      });
    });

    testWidgets('a failed switch keeps the sheet open and reports the error', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        await _pump(tester, failSelect: true);
        await tester.tap(find.text('Kmbalache 🇨🇺'));
        await _settleSelection(tester);
        expect(find.byType(MostroNodeSelector), findsOneWidget);
        expect(find.text('Failed to switch node'), findsOneWidget);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.byIcon(Icons.check), findsOneWidget);
      });
    });

    testWidgets('a node that requires a bond is not selectable', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final notifier = await _pump(
          tester,
          stats: {
            ..._fixtureStats,
            _cubaPubkey: _stats(
              _cubaPubkey,
              infoSeenAt: _now,
              orders: {'ARS': 3},
              bondRequired: true,
            ),
          },
        );
        expect(find.text('Bond: not supported'), findsOneWidget);
        await tester.tap(find.text('Kmbalache 🇨🇺'));
        await _settleSelection(tester);
        expect(notifier.selected, isEmpty);
        expect(
          find.text(
            'This node requires a bond, which this app does not support yet',
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets('an unreachable node sorts last, dimmed, not selectable', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final notifier = await _pump(
          tester,
          stats: {
            ..._fixtureStats,
            _customPubkey: _stats(
              _customPubkey,
              infoSeenAt: _now.subtract(const Duration(hours: 2)),
            ),
          },
        );
        expect(find.text('Not responding · last seen 2h ago'), findsOneWidget);
        final myNode = tester.getTopLeft(find.text('My Node'));
        final cuba = tester.getTopLeft(find.text('Kmbalache 🇨🇺'));
        expect(cuba.dy, lessThan(myNode.dy));
        final opacity = tester.widget<Opacity>(
          find
              .ancestor(
                of: find.text('My Node'),
                matching: find.byType(Opacity),
              )
              .first,
        );
        expect(opacity.opacity, 0.55);
        await tester.tap(find.text('My Node'));
        await _settleSelection(tester);
        expect(notifier.selected, isEmpty);
        expect(find.text('This node is not responding'), findsOneWidget);
      });
    });

    testWidgets('without a preferred currency the subtitle is generic', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        await _pump(tester, fiat: null);
        expect(find.text('Open orders on each node'), findsOneWidget);
        expect(find.textContaining(' in ARS'), findsNothing);
        expect(find.text('NO ARS'), findsNothing);
      });
    });

    testWidgets(
      'dismissing the sheet during a slow switch never pops the route beneath',
      (tester) async {
        await withClock(Clock.fixed(_now), () async {
          tester.view.physicalSize = const Size(1200, 3000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          final gate = Completer<void>();
          final notifier = _FakeNodesNotifier(_fixtureNodes)
            ..selectGate = gate.future;
          final container = createContainer(overrides: _overrides(notifier));
          await tester.pumpWidget(
            _app(
              container,
              Scaffold(
                body: Builder(
                  builder:
                      (context) => TextButton(
                        onPressed: () => showMostroNodeSelector(context),
                        child: const Text('open selector'),
                      ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open selector'));
          await tester.pumpAndSettle();
          expect(find.byType(MostroNodeSelector), findsOneWidget);

          await tester.tap(find.text('Kmbalache 🇨🇺'));
          await tester.pump();
          await tester.pump(); // switch now pending behind the gate

          // Dismiss the sheet while the switch is still in flight.
          await tester.tap(find.byIcon(Icons.close));
          await tester.pumpAndSettle();
          expect(find.byType(MostroNodeSelector), findsNothing);

          gate.complete();
          await tester.pumpAndSettle();

          // The stale continuation must not pop the underlying route.
          expect(find.text('open selector'), findsOneWidget);
        });
      },
    );

    testWidgets(
      'dismissing the add dialog during a slow add never pops the sheet beneath',
      (tester) async {
        await withClock(Clock.fixed(_now), () async {
          tester.view.physicalSize = const Size(1200, 3000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.reset);
          final gate = Completer<void>();
          final notifier = _FakeNodesNotifier(_fixtureNodes)
            ..addGate = gate.future;
          final container = createContainer(overrides: _overrides(notifier));
          await tester.pumpWidget(
            _app(
              container,
              Scaffold(
                body: Builder(
                  builder:
                      (context) => TextButton(
                        onPressed: () => showMostroNodeSelector(context),
                        child: const Text('open selector'),
                      ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open selector'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Add your own node'));
          await tester.pumpAndSettle();

          await tester.enterText(find.byType(TextField).first, _customPubkey);
          await tester.pump();
          await tester.tap(find.text('Add'));
          await tester.pump(); // add now pending behind the gate

          // Barrier-dismiss the dialog while the add is still in flight —
          // neither the barrier nor the back gesture is gated by _submitting.
          await tester.tapAt(const Offset(10, 10));
          await tester.pumpAndSettle();
          expect(find.byType(AddCustomNodeDialog), findsNothing);
          expect(find.byType(MostroNodeSelector), findsOneWidget);

          gate.complete();
          await tester.pumpAndSettle();

          // The stale continuation must not pop the selector sheet beneath.
          expect(notifier.added, [_customPubkey]);
          expect(find.byType(MostroNodeSelector), findsOneWidget);
        });
      },
    );

    testWidgets('long-pressing a custom node offers to remove it', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final notifier = await _pump(tester);
        await tester.longPress(find.text('My Node'));
        await tester.pumpAndSettle();
        expect(
          find.text('Remove this custom node from your list?'),
          findsOneWidget,
        );
        await tester.tap(find.text('Remove'));
        await tester.pumpAndSettle();
        expect(notifier.removed, [_customPubkey]);
      });
    });

    testWidgets('long-pressing a trusted node does nothing', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        await _pump(tester);
        await tester.longPress(find.text('Kmbalache 🇨🇺'));
        await tester.pumpAndSettle();
        expect(
          find.text('Remove this custom node from your list?'),
          findsNothing,
        );
      });
    });

    testWidgets('shows the short operator disclaimer', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        await _pump(tester);
        expect(
          find.textContaining('Each node is run by an independent third party'),
          findsOneWidget,
        );
      });
    });

    testWidgets('add button opens the custom-node dialog', (tester) async {
      await withClock(Clock.fixed(_now), () async {
        await _pump(tester);
        await tester.tap(find.text('Add your own node'));
        await tester.pumpAndSettle();
        expect(find.byType(AddCustomNodeDialog), findsOneWidget);
        expect(find.text('PUBLIC KEY'), findsOneWidget);
        expect(find.text('NAME (OPTIONAL)'), findsOneWidget);
        expect(
          find.text(
            'Verify the key with the operator. A fake node can see your orders.',
          ),
          findsOneWidget,
        );
      });
    });

    testWidgets(
      'Add stays disabled until the key looks valid; blur paints the error',
      (tester) async {
        await withClock(Clock.fixed(_now), () async {
          final notifier = await _pump(tester);
          await tester.tap(find.text('Add your own node'));
          await tester.pumpAndSettle();

          final addButton = find.widgetWithText(FilledButton, 'Add');
          expect(tester.widget<FilledButton>(addButton).enabled, isFalse);

          await tester.enterText(find.byType(TextField).first, 'not-a-key');
          await tester.pump();
          expect(tester.widget<FilledButton>(addButton).enabled, isFalse);
          // Leaving the field paints the shape error.
          await tester.tap(find.byType(TextField).last);
          await tester.pump();
          expect(find.text('This is not a valid public key.'), findsOneWidget);

          await tester.enterText(find.byType(TextField).first, _customPubkey);
          await tester.pump();
          expect(find.text('This is not a valid public key.'), findsNothing);
          expect(tester.widget<FilledButton>(addButton).enabled, isTrue);
          await tester.tap(addButton);
          await tester.pumpAndSettle();
          expect(notifier.added, [_customPubkey]);
        });
      },
    );

    testWidgets('an nsec is refused before it reaches the bridge', (
      tester,
    ) async {
      await withClock(Clock.fixed(_now), () async {
        final notifier = await _pump(tester);
        await tester.tap(find.text('Add your own node'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).first,
          'nsec1${'q' * 58}',
        );
        await tester.pump();
        await tester.tap(find.byType(TextField).last);
        await tester.pump();
        expect(find.textContaining('That is a private key'), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
              .enabled,
          isFalse,
        );
        expect(notifier.added, isEmpty);
      });
    });
  });

  group('nodeDisplayName', () {
    test('prefers name, appends region flag', () {
      final e = _entry(
        pubkey: _customPubkey,
        region: '🇨🇺 Cuba',
        name: 'Kmbalache',
      );
      expect(nodeDisplayName(e), 'Kmbalache 🇨🇺');
    });

    test('falls back to region place name', () {
      final e = _entry(pubkey: _customPubkey, region: '🇨🇺 Cuba');
      expect(nodeDisplayName(e), 'Cuba 🇨🇺');
    });

    test('default node without metadata reads Mostro', () {
      final e = _entry(pubkey: defaultMostroPubkey, region: '🌐');
      expect(nodeDisplayName(e), 'Mostro 🌐');
    });

    test('nameless custom node shows truncated pubkey', () {
      final e = _entry(pubkey: _customPubkey);
      expect(nodeDisplayName(e), '00000000…00000001');
    });
  });

  group('localizedNodeError', () {
    // Marker → message mapping is the seam between Rust errors and the UI;
    // a renamed marker on one side only would silently fall back to the
    // generic message.
    for (final (marker, probe) in [
      ('PrivateKeyNotAllowed', 'private key'),
      ('NodeAlreadyExists', 'already in the list'),
      ('InvalidPubkey', 'valid public key'),
      ('CannotRemoveActiveNode', 'active node'),
      ('NotInitialized', 'database'),
    ]) {
      testWidgets('maps $marker', (tester) async {
        late AppLocalizations l10n;
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) {
                l10n = AppLocalizations.of(context);
                return const SizedBox();
              },
            ),
          ),
        );
        final msg = localizedNodeError(l10n, Exception('$marker: some detail'));
        expect(msg.toLowerCase(), contains(probe));
      });
    }
  });
}
