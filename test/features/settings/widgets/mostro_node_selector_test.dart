import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/widgets/mostro_node_selector.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart' show MostroNodeEntry;
import '../../../support/provider_harness.dart';

/// Syntactically valid hex that is deliberately not any real node.
const _customPubkey =
    '0000000000000000000000000000000000000000000000000000000000000001';

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

final _fixtureNodes = [
  _entry(
    pubkey: defaultMostroPubkey,
    region: '🌐',
    isTrusted: true,
    isActive: true,
    name: 'Mostro',
  ),
  _entry(
    pubkey: '00000235a3e904cfe1213a8a54d6f1ec1bef7cc6bfaabd6193e82931ccf1366a',
    region: '🇨🇺 Cuba',
    isTrusted: true,
    name: 'Kmbalache',
    about: 'Where Bitcoin becomes P2P again',
  ),
  _entry(pubkey: _customPubkey, name: 'My Node'),
];

/// Serves fixed registry entries and records mutations — no Rust bridge.
class _FakeNodesNotifier extends MostroNodesNotifier {
  _FakeNodesNotifier(this.nodes, {this.failSelect = false});

  final List<MostroNodeEntry> nodes;
  final bool failSelect;
  final List<String> selected = [];
  final List<String> removed = [];

  /// When set, [selectNode] waits on it — lets a test hold a switch in
  /// flight while interacting with the UI.
  Future<void>? selectGate;

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
}

Future<_FakeNodesNotifier> _pump(
  WidgetTester tester, {
  List<MostroNodeEntry>? nodes,
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
    overrides: [mostroNodesProvider.overrideWith(() => notifier)],
  );
  await tester.pumpWidget(
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
        home: const Scaffold(body: MostroNodeSelector()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return notifier;
}

void main() {
  group('MostroNodeSelector', () {
    testWidgets('lists trusted and custom sections with node names', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Trusted Nodes'), findsOneWidget);
      expect(find.text('Custom Nodes'), findsOneWidget);
      expect(find.text('Kmbalache 🇨🇺'), findsOneWidget);
      expect(find.text('My Node'), findsOneWidget);
      expect(find.text('Where Bitcoin becomes P2P again'), findsOneWidget);
      // Trusted badge on both trusted nodes, none on the custom one.
      expect(find.text('Trusted'), findsNWidgets(2));
    });

    testWidgets('active node shows a checkmark and does not react to taps', (
      tester,
    ) async {
      final notifier = await _pump(tester);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await tester.tap(find.text('Mostro 🌐'));
      await tester.pumpAndSettle();
      expect(notifier.selected, isEmpty);
    });

    testWidgets('tapping a node selects it and closes the sheet', (
      tester,
    ) async {
      final notifier = await _pump(tester);
      await tester.tap(find.text('Kmbalache 🇨🇺'));
      await tester.pumpAndSettle();
      expect(notifier.selected, [
        '00000235a3e904cfe1213a8a54d6f1ec1bef7cc6bfaabd6193e82931ccf1366a',
      ]);
      // The success snackbar is hosted by the Scaffold *under* the sheet in
      // production; here the selector is the only route, so only the
      // selection itself is observable.
    });

    testWidgets('a failed switch keeps the sheet open and reports the error', (
      tester,
    ) async {
      await _pump(tester, failSelect: true);
      await tester.tap(find.text('Kmbalache 🇨🇺'));
      await tester.pumpAndSettle();
      expect(find.byType(MostroNodeSelector), findsOneWidget);
      expect(find.text('Failed to switch node'), findsOneWidget);
    });

    testWidgets(
      'dismissing the sheet during a slow switch never pops the route beneath',
      (tester) async {
        final gate = Completer<void>();
        final notifier = _FakeNodesNotifier(_fixtureNodes)
          ..selectGate = gate.future;
        final container = createContainer(
          overrides: [mostroNodesProvider.overrideWith(() => notifier)],
        );
        await tester.pumpWidget(
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
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showMostroNodeSelector(context),
                    child: const Text('open selector'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open selector'));
        await tester.pumpAndSettle();
        expect(find.byType(MostroNodeSelector), findsOneWidget);

        await tester.tap(find.text('Kmbalache 🇨🇺'));
        await tester.pump(); // switch now pending behind the gate

        // Dismiss the sheet while the switch is still in flight.
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();
        expect(find.byType(MostroNodeSelector), findsNothing);

        gate.complete();
        await tester.pumpAndSettle();

        // The stale continuation must not pop the underlying route.
        expect(find.text('open selector'), findsOneWidget);
      },
    );

    testWidgets('custom node exposes delete; confirming removes it', (
      tester,
    ) async {
      final notifier = await _pump(tester);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(
        find.text('Remove this custom node from your list?'),
        findsOneWidget,
      );
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(notifier.removed, [_customPubkey]);
    });

    testWidgets('trusted and active nodes expose no delete control', (
      tester,
    ) async {
      await _pump(
        tester,
        nodes: [
          _entry(
            pubkey: defaultMostroPubkey,
            region: '🌐',
            isTrusted: true,
            isActive: true,
          ),
          _entry(pubkey: _customPubkey, name: 'Active custom', isActive: true),
        ],
      );
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('shows the node-operator disclaimer', (tester) async {
      await _pump(tester);
      expect(
        find.textContaining('Each operator runs their own Mostro node'),
        findsOneWidget,
      );
    });

    testWidgets('add button opens the custom-node dialog', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Add Custom Node'));
      await tester.pumpAndSettle();
      expect(find.byType(AddCustomNodeDialog), findsOneWidget);
      expect(find.text('Public key'), findsOneWidget);
      expect(find.text('Name (optional)'), findsOneWidget);
    });

    testWidgets('empty pubkey submit shows validation error, no bridge call', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('Add Custom Node'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a valid public key (64-char hex or npub)'),
        findsOneWidget,
      );
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
        final msg = localizedNodeError(
          l10n,
          Exception('$marker: details here'),
        );
        expect(msg.toLowerCase(), contains(probe));
      });
    }
  });
}
