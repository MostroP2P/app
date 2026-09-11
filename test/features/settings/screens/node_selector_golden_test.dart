import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
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

import '../../../support/provider_harness.dart';

/// Goldens of the node selector redesign (`design_handoff_selector_nodo`):
/// 9a · the sheet with the handoff's two cards, 9b · the add-own-node dialog.
/// 360 × 760, `es`, dark and light. PNGs are generated in CI only — see
/// `docs/golden-tests.md`.

const _colombiaPubkey =
    '0000097843b5e2f1f2b2cd9a7a35b2a7e6d4b7d1c3a4c5e6f7a8b9c0d1e2f3a4';
final _now = DateTime.utc(2026, 9, 11, 12, 0);
int _secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

MostroNodeEntry _entry({
  required String pubkey,
  required String name,
  bool isActive = false,
}) => MostroNodeEntry(
  pubkey: pubkey,
  region: null,
  isTrusted: true,
  isActive: isActive,
  name: name,
  picture: null,
  about: null,
  website: null,
);

final _nodes = [
  _entry(pubkey: defaultMostroPubkey, name: 'Mostro', isActive: true),
  _entry(pubkey: _colombiaPubkey, name: 'MostroColombia'),
];

final _stats = {
  defaultMostroPubkey: MostroNodeStats(
    pubkey: defaultMostroPubkey,
    infoSeenAt: _secs(_now),
    latestOrderAt: null,
    feePct: 0.6,
    minOrderAmount: BigInt.from(5000),
    maxOrderAmount: BigInt.from(2000000),
    acceptedCurrencies: const ['ARS', 'VES', 'BRL', 'EUR'],
    escrowMode: 'lightning',
    cashuMintUrl: null,
    bondRequired: true,
    bondPct: 2,
    ordersByFiat: const [
      FiatOrderCount(fiatCode: 'ARS', count: 12),
      FiatOrderCount(fiatCode: 'BRL', count: 10),
      FiatOrderCount(fiatCode: 'VES', count: 16),
    ],
    totalOrders: 38,
  ),
  _colombiaPubkey: MostroNodeStats(
    pubkey: _colombiaPubkey,
    infoSeenAt: _secs(_now),
    latestOrderAt: null,
    feePct: 1,
    minOrderAmount: BigInt.from(10000),
    maxOrderAmount: BigInt.from(800000),
    acceptedCurrencies: const ['COP', 'VES'],
    escrowMode: 'cashu',
    cashuMintUrl: 'https://mint.cashu.space',
    bondRequired: false,
    bondPct: null,
    ordersByFiat: const [FiatOrderCount(fiatCode: 'COP', count: 6)],
    totalOrders: 6,
  ),
};

class _FakeNodesNotifier extends MostroNodesNotifier {
  @override
  Future<List<MostroNodeEntry>> build() async => _nodes;

  @override
  Future<void> refreshMetadata() async {}
}

Widget _app(Brightness brightness, Widget home) {
  final container = createContainer(
    overrides: [
      mostroNodesProvider.overrideWith(_FakeNodesNotifier.new),
      nodeStatsProvider.overrideWith((ref) async => _stats),
      settingsProvider.overrideWith(
        (ref) => SettingsNotifier(
          initial: const AppSettingsState(defaultFiatCode: 'ARS'),
        ),
      ),
      currencyFlagsProvider.overrideWithValue(const {
        'ARS': '🇦🇷',
        'VES': '🇻🇪',
        'BRL': '🇧🇷',
        'EUR': '🇪🇺',
        'COP': '🇨🇴',
      }),
      exchangeRateProvider.overrideWith((ref, code) async => 36000000.0),
      rawTradesProvider.overrideWith((ref) async => const []),
    ],
  );
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme:
          brightness == Brightness.dark ? buildDarkTheme() : buildLightTheme(),
      locale: const Locale('es'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

void main() {
  for (final (name, brightness) in [
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    testWidgets('9a node selector sheet · $name', (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await withClock(Clock.fixed(_now), () async {
        await tester.pumpWidget(
          _app(
            brightness,
            const Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: MostroNodeSelector(),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/node_selector_9a_sheet_$name.png'),
        );
      });
    });

    testWidgets('9b add own node dialog · $name', (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await withClock(Clock.fixed(_now), () async {
        await tester.pumpWidget(
          _app(
            brightness,
            const Scaffold(body: Center(child: AddCustomNodeDialog())),
          ),
        );
        await tester.pump();
        await tester.enterText(
          find.byType(TextField).first,
          'dbe0b1be0000000000000000000000000000000000000000000000002e13355a',
        );
        await tester.enterText(find.byType(TextField).last, 'Mostro local');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));
        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/node_selector_9b_dialog_$name.png'),
        );
      });
    });
  }
}
