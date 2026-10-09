import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/mostro_defaults.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/providers/node_stats_provider.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/features/walkthrough/providers/first_run_provider.dart';
import 'package:mostro/features/walkthrough/providers/node_prefetch_provider.dart';
import 'package:mostro/features/walkthrough/screens/node_choice_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/src/rust/api/node_stats.dart';
import 'package:mostro/src/rust/api/types.dart'
    show BondPolicy, BondPolicyInfo, MostroNodeEntry;
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/load_app_fonts.dart';

const _home = 'home screen';
const _cubaPubkey =
    '00000235a3e904cfe1213a8a54d6f1ec1bef7cc6bfaabd6193e82931ccf1366a';

MostroNodeEntry _entry(String pubkey, String name, {bool isActive = false}) =>
    MostroNodeEntry(
      pubkey: pubkey,
      region: null,
      isTrusted: true,
      isActive: isActive,
      name: name,
      picture: null,
      about: null,
      website: null,
    );

MostroNodeStats _stats(String pubkey, int arsOrders) => MostroNodeStats(
  pubkey: pubkey,
  infoSeenAt: null,
  latestOrderAt: null,
  feePct: 0.6,
  minOrderAmount: BigInt.from(5000),
  maxOrderAmount: BigInt.from(2000000),
  acceptedCurrencies: const ['ARS'],
  escrowMode: 'lightning',
  cashuMintUrls: const [],
  bond: const BondPolicyInfo(policy: BondPolicy.disabled),
  bondRequired: false,
  bondPct: null,
  ordersByFiat: [FiatOrderCount(fiatCode: 'ARS', count: arsOrders)],
  totalOrders: arsOrders,
);

/// Serves fixed registry entries and records selections — no Rust bridge.
class _FakeNodesNotifier extends MostroNodesNotifier {
  _FakeNodesNotifier(this.nodes, {this.failSelect = false});

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

/// A first-run flag whose write fails, as a full disk would.
class _FailingFirstRun extends FirstRunNotifier {
  _FailingFirstRun() : super(initialValue: false);

  @override
  Future<void> markFirstRunComplete() async => throw Exception('disk full');
}

class _Harness {
  _Harness(this.container, this.nodes);

  final ProviderContainer container;
  final _FakeNodesNotifier nodes;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  String activePubkey = defaultMostroPubkey,
  bool failSelect = false,
  bool failSave = false,
  Size size = const Size(1200, 3000),
  Locale locale = const Locale('en'),
  Brightness brightness = Brightness.dark,
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // The Cuban node has more orders, so the selector's own order would put it
  // first: the default node must still lead.
  final notifier = _FakeNodesNotifier([
    _entry(_cubaPubkey, 'Kmbalache'),
    _entry(
      defaultMostroPubkey,
      'Mostro',
      isActive: activePubkey == defaultMostroPubkey,
    ),
  ], failSelect: failSelect);
  final container = ProviderContainer(
    overrides: [
      firstRunProvider.overrideWith(
        (ref) =>
            failSave
                ? _FailingFirstRun()
                : FirstRunNotifier(initialValue: false),
      ),
      firstRunNodePrefetchProvider.overrideWith((ref) {}),
      mostroPubkeyProvider.overrideWith((ref) => activePubkey),
      mostroNodesProvider.overrideWith(() => notifier),
      cachedNodeStatsProvider.overrideWith((ref) async => const {}),
      nodeStatsProvider.overrideWith(
        (ref) async => {
          _cubaPubkey: _stats(_cubaPubkey, 30),
          defaultMostroPubkey: _stats(defaultMostroPubkey, 5),
        },
      ),
      settingsProvider.overrideWith(
        (ref) => SettingsNotifier(
          initial: const AppSettingsState(defaultFiatCode: 'ARS'),
        ),
      ),
      currencyFlagsProvider.overrideWithValue(const {'ARS': '🇦🇷'}),
      exchangeRateProvider.overrideWith((ref, code) async => 36000000.0),
    ],
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: AppRoute.chooseNode,
    routes: [
      GoRoute(
        path: AppRoute.home,
        builder: (_, __) => const Scaffold(body: Text(_home)),
      ),
      GoRoute(
        path: AppRoute.chooseNode,
        builder: (_, __) => const NodeChoiceScreen(),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        theme:
            brightness == Brightness.dark
                ? buildDarkTheme()
                : buildLightTheme(),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
  return _Harness(container, notifier);
}

AppLocalizations _en() => lookupAppLocalizations(const Locale('en'));

/// "Use this node" is a [FilledButton]; enabled when it has a callback.
bool _confirmEnabled(WidgetTester tester, [AppLocalizations? l10n]) =>
    tester
        .widget<FilledButton>(
          find.ancestor(
            of: find.text((l10n ?? _en()).nodeChoiceConfirm),
            matching: find.byType(FilledButton),
          ),
        )
        .onPressed !=
    null;

void main() {
  setUpAll(loadAppFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('shows the default node first, then the others', (tester) async {
    await _pump(tester);

    final mostro = tester.getTopLeft(find.text('Mostro')).dy;
    final cuba = tester.getTopLeft(find.text('Kmbalache')).dy;
    expect(mostro, lessThan(cuba));
  });

  testWidgets('shows the operator disclaimer in full', (tester) async {
    await _pump(tester);

    expect(find.text(_en().nodeOperatorDisclaimer), findsOneWidget);
  });

  testWidgets('"Use this node" waits for a card to be picked', (tester) async {
    await _pump(tester);
    expect(_confirmEnabled(tester), isFalse);

    await tester.tap(find.text('Kmbalache'));
    await tester.pump();

    expect(_confirmEnabled(tester), isTrue);
  });

  testWidgets('picking a node makes it active and completes the first run', (
    tester,
  ) async {
    final h = await _pump(tester);

    await tester.tap(find.text('Kmbalache'));
    await tester.pump();
    await tester.tap(find.text(_en().nodeChoiceConfirm));
    await tester.pumpAndSettle();

    expect(h.nodes.selected, [_cubaPubkey]);
    expect(find.text(_home), findsOneWidget);
    expect(h.container.read(firstRunProvider), const AsyncData<bool>(true));
    expect(h.container.read(backupReminderProvider), isTrue);
  });

  testWidgets('Skip keeps the default node and completes the first run', (
    tester,
  ) async {
    final h = await _pump(tester);

    await tester.tap(find.text(_en().skip));
    await tester.pumpAndSettle();

    // The default node is already the active one: nothing to switch.
    expect(h.nodes.selected, isEmpty);
    expect(find.text(_home), findsOneWidget);
    expect(h.container.read(firstRunProvider), const AsyncData<bool>(true));
    expect(h.container.read(backupReminderProvider), isTrue);
  });

  testWidgets('Skip switches back to the default node when another is active', (
    tester,
  ) async {
    final h = await _pump(tester, activePubkey: _cubaPubkey);

    await tester.tap(find.text(_en().skip));
    await tester.pumpAndSettle();

    expect(h.nodes.selected, [defaultMostroPubkey]);
    expect(find.text(_home), findsOneWidget);
  });

  testWidgets('a failed switch stays on the choice, first run not complete', (
    tester,
  ) async {
    final h = await _pump(tester, failSelect: true);

    await tester.tap(find.text('Kmbalache'));
    await tester.pump();
    await tester.tap(find.text(_en().nodeChoiceConfirm));
    await tester.pumpAndSettle();

    expect(find.text(_en().errorSwitchingNode), findsOneWidget);
    expect(find.text(_home), findsNothing);
    expect(h.container.read(firstRunProvider), const AsyncData<bool>(false));
    // Both actions are live again for a retry.
    expect(_confirmEnabled(tester), isTrue);
  });

  testWidgets('a failed save says so and lets the user retry', (tester) async {
    final h = await _pump(tester, failSave: true);

    await tester.tap(find.text(_en().skip));
    await tester.pumpAndSettle();

    expect(find.text(_en().nodeChoiceSaveFailed), findsOneWidget);
    expect(find.text(_home), findsNothing);
    expect(h.container.read(firstRunProvider), const AsyncData<bool>(false));
    expect(tester.takeException(), isNull);
    final skip = tester.widget<TextButton>(
      find.ancestor(
        of: find.text(_en().skip),
        matching: find.byType(TextButton),
      ),
    );
    expect(skip.onPressed, isNotNull);
  });

  // DS-SPC-5 / DS-A11Y-4: the longest locale, the narrowest screen, the
  // largest text. The disclaimer scrolls with the cards; the actions stay.
  for (final brightness in Brightness.values) {
    testWidgets('fits 320 x 640 in German at 2x text (${brightness.name})', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(320, 640),
        locale: const Locale('de'),
        brightness: brightness,
        textScale: 2,
      );
      final de = lookupAppLocalizations(const Locale('de'));

      expect(tester.takeException(), isNull);
      expect(find.text(de.nodeChoiceConfirm).hitTestable(), findsOneWidget);
      expect(find.text(de.skip).hitTestable(), findsOneWidget);

      // The cards are reachable below the disclaimer.
      // Built lazily below the tall header: scroll to it, and let the scroll
      // settle so the tap is not taken as a stop.
      await tester.scrollUntilVisible(
        find.text('Mostro'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mostro'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(_confirmEnabled(tester, de), isTrue);
    });
  }
}
