import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/screens/about_screen.dart'
    show appVersionProvider;
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/providers/notification_permission_provider.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/settings/providers/relay_auto_sync_provider.dart';
import 'package:mostro/features/settings/providers/relays_provider.dart';
import 'package:mostro/features/settings/screens/notification_settings_screen.dart';
import 'package:mostro/features/settings/screens/nwc_wallet_screen.dart';
import 'package:mostro/features/settings/screens/relays_screen.dart';
import 'package:mostro/features/settings/screens/settings_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart'
    show MostroNodeEntry, RelayInfo, RelaySource, RelayStatus;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/provider_harness.dart';

/// Goldens of the settings redesign (`design_handoff_configuracion`):
/// 10a · the grouped list, 10b · relays, 10c · the NWC wallet,
/// 10d · push notifications. 360 × 760, `es`, dark and light. PNGs are
/// generated in CI only — see `docs/golden-tests.md`.

RelayInfo _relay(String url, {RelayStatus status = RelayStatus.connected}) =>
    RelayInfo(
      url: url,
      isActive: true,
      isDefault: true,
      source: RelaySource.default_,
      isBlacklisted: false,
      status: status,
    );

/// The handoff's case: one relay of four not connected, so the summary and
/// the settings tally both render their amber state.
final _relays = [
  _relay('wss://relay.damus.io'),
  _relay('wss://nos.lol'),
  _relay('wss://relay.mostro.network'),
  _relay('wss://nostr.bitcoiner.social', status: RelayStatus.error),
];

class _FixedNodes extends MostroNodesNotifier {
  @override
  Future<List<MostroNodeEntry>> build() async => [
    MostroNodeEntry(
      pubkey: 'a' * 64,
      region: null,
      isTrusted: true,
      isActive: true,
      name: 'Mostro',
      picture: null,
      about: null,
      website: null,
    ),
  ];
}

class _NoWallet extends NwcNotifier {}

Widget _app(Brightness brightness, Widget home) => UncontrolledProviderScope(
  container: createContainer(
    overrides: [
      relayListLoaderProvider.overrideWithValue(() async => _relays),
      relayStatusStreamProvider.overrideWithValue(
        () async => () => Completer<RelayInfo?>().future,
      ),
      relayAutoSyncProvider.overrideWith((ref) => const Stream.empty()),
      mostroNodesProvider.overrideWith(_FixedNodes.new),
      nwcProvider.overrideWith((ref) => _NoWallet()),
      appVersionProvider.overrideWith((ref) async => '2.0.1'),
      notificationPermissionDeniedProvider.overrideWith((ref) async => false),
    ],
  ),
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (mode, brightness) in [
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    for (final (name, screen) in <(String, Widget)>[
      ('10a_settings', const SettingsScreen()),
      ('10b_relays', const RelaysScreen()),
      ('10c_wallet', const NwcWalletScreen()),
      ('10d_notifications', const NotificationSettingsScreen()),
    ]) {
      testWidgets('$name · $mode', (tester) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_app(brightness, screen));
        await tester.pumpAndSettle();

        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/settings_${name}_$mode.png'),
        );
      });
    }
  }
}
