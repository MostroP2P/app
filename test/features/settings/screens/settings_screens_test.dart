import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/settings_palette.dart';
import 'package:mostro/features/about/screens/about_screen.dart'
    show appVersionProvider;
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart';
import 'package:mostro/features/settings/providers/notification_permission_provider.dart';
import 'package:mostro/features/settings/providers/notification_prefs_provider.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/settings/providers/push_settings_provider.dart';
import 'package:mostro/features/settings/providers/relay_auto_sync_provider.dart';
import 'package:mostro/features/settings/providers/relays_provider.dart';
import 'package:mostro/features/settings/screens/notification_settings_screen.dart';
import 'package:mostro/features/settings/screens/relays_screen.dart';
import 'package:mostro/features/settings/screens/settings_screen.dart';
import 'package:mostro/features/settings/widgets/settings_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/src/rust/api/types.dart'
    show MostroNodeEntry, PushStatus, RelayInfo, RelaySource, RelayStatus;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/provider_harness.dart';

RelayInfo _relay(
  String url, {
  bool isActive = true,
  RelayStatus status = RelayStatus.connected,
}) => RelayInfo(
  url: url,
  isActive: isActive,
  isDefault: true,
  source: RelaySource.default_,
  isBlacklisted: false,
  status: status,
);

/// Three enabled relays with one down — the handoff's `3 de 4` case, minus a
/// relay, so the tally reads `2 de 3`.
final _mixedRelays = [
  _relay('wss://relay.damus.io'),
  _relay('wss://nos.lol'),
  _relay('wss://relay.mostro.network', status: RelayStatus.error),
];

PushStatus _push({
  bool enabled = true,
  int registered = 0,
  DateTime? nodeRefusedUntil,
}) => PushStatus(
  enabled: enabled,
  hasToken: true,
  registered: registered,
  wanted: registered,
  nodeRefusedUntil:
      nodeRefusedUntil == null
          ? null
          : nodeRefusedUntil.millisecondsSinceEpoch ~/ 1000,
);

/// Records what the master toggle asked for, without a bridge or a device.
class _RecordingToggle implements PushToggle {
  final asked = <bool>[];

  @override
  Future<bool> set(bool enabled) async {
    asked.add(enabled);
    return true;
  }
}

List<Override> _overrides({
  List<RelayInfo>? relays,
  NwcWalletState? wallet,
  bool permissionDenied = false,
  bool pushSupported = true,
  PushStatus? push,
  PushToggle? toggle,
}) => [
  pushSupportedProvider.overrideWithValue(pushSupported),
  pushStatusProvider.overrideWith((ref) => Stream.value(push ?? _push())),
  pushToggleProvider.overrideWithValue(toggle ?? _RecordingToggle()),
  relayListLoaderProvider.overrideWithValue(() async => relays ?? _mixedRelays),
  // A reader that never completes: the list under test comes from the load.
  relayStatusStreamProvider.overrideWithValue(
    () async => () => Completer<RelayInfo?>().future,
  ),
  relayAutoSyncProvider.overrideWith((ref) => const Stream.empty()),
  // No screen test should reach the bridge: a toggle here asserts on the UI,
  // not on what Rust does with it.
  relayMutatorProvider.overrideWithValue(const _NoopMutator()),
  mostroNodesProvider.overrideWith(_FixedNodes.new),
  appVersionProvider.overrideWith((ref) async => '2.0.1'),
  notificationPermissionDeniedProvider.overrideWith(
    (ref) async => permissionDenied,
  ),
  if (wallet != null)
    nwcProvider.overrideWith((ref) => _FixedNwc(wallet))
  else
    nwcProvider.overrideWith((ref) => _FixedNwc(null)),
];

class _NoopMutator extends RelayMutator {
  const _NoopMutator();

  @override
  Future<void> add(String url) async {}

  @override
  Future<void> remove(String url) async {}
}

/// Serves one active node, so the `Nodo Mostro` row has a name to show.
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

class _FixedNwc extends NwcNotifier {
  _FixedNwc(NwcWalletState? initial) {
    if (initial != null) state = initial;
  }
}

Widget _app(ProviderContainer container, Widget home) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

Future<ProviderContainer> _pump(
  WidgetTester tester,
  Widget home, {
  List<Override>? overrides,
}) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = createContainer(overrides: overrides ?? _overrides());
  await tester.pumpWidget(_app(container, home));
  await tester.pumpAndSettle();
  return container;
}

final _masterToggle = find.byWidgetPredicate(
  (w) => w is MostroToggle && w.semanticLabel == 'Push notifications',
);

Color _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!.color!;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SettingsScreen · 10a', () {
    testWidgets('groups the nine cards into four', (tester) async {
      await _pump(tester, const SettingsScreen());

      expect(find.text('APPLICATION'), findsOneWidget);
      expect(find.text('PAYMENTS'), findsOneWidget);
      expect(find.text('NETWORK'), findsOneWidget);
      expect(find.text('HELP'), findsOneWidget);
      expect(find.byType(SettingsGroup), findsNWidgets(4));
    });

    testWidgets('shows the relay tally, in amber when one is down', (
      tester,
    ) async {
      await _pump(tester, const SettingsScreen());

      expect(find.text('2 of 3 connected'), findsOneWidget);
      expect(
        _colorOf(tester, '2 of 3 connected'),
        SettingsPalette.dark.warnInk,
      );
    });

    testWidgets('the tally is lime when every relay is connected', (
      tester,
    ) async {
      await _pump(
        tester,
        const SettingsScreen(),
        overrides: _overrides(relays: [_relay('wss://a'), _relay('wss://b')]),
      );

      final color = _colorOf(tester, '2 of 2 connected');
      expect(color, isNot(SettingsPalette.dark.warnInk));
    });

    testWidgets('warns in amber about an unconnected wallet and no address', (
      tester,
    ) async {
      await _pump(tester, const SettingsScreen());

      expect(_colorOf(tester, 'Not connected'), SettingsPalette.dark.warnInk);
      expect(_colorOf(tester, 'Not set'), SettingsPalette.dark.warnInk);
    });

    testWidgets('saving a lightning address closes the dialog cleanly', (
      tester,
    ) async {
      await _pump(tester, const SettingsScreen());

      await tester.tap(find.text('Not set'));
      await tester.pumpAndSettle();
      final dialog = find.byType(MostroDialog);
      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextField)),
        'alice@example.com',
      );
      await tester.tap(
        find.descendant(of: dialog, matching: find.text('Save')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(MostroDialog), findsNothing);
      expect(find.text('alice@example.com'), findsOneWidget);
    });

    testWidgets('shows a connected wallet by name, un-warned', (tester) async {
      await _pump(
        tester,
        const SettingsScreen(),
        overrides: _overrides(
          wallet: NwcWalletState(
            walletPubkey: 'b' * 64,
            relayUrls: const ['wss://nwc.example'],
            walletName: 'Alby',
          ),
        ),
      );

      expect(find.text('Alby'), findsOneWidget);
      expect(_colorOf(tester, 'Alby'), isNot(SettingsPalette.dark.warnInk));
    });

    testWidgets('no row repeats its own title as a subtitle', (tester) async {
      await _pump(tester, const SettingsScreen());

      // The old list said `Relays · Manage relay connections`; the value took
      // that slot.
      expect(find.text('Manage relay connections'), findsNothing);
      expect(find.text('View diagnostic logs'), findsNothing);
      expect(find.text('Manage notification preferences'), findsNothing);
    });

    testWidgets('drops "Default" from the fiat row label', (tester) async {
      await _pump(tester, const SettingsScreen());

      expect(find.text('Fiat currency'), findsOneWidget);
      expect(find.text('Default Fiat Currency'), findsNothing);
    });

    testWidgets('shows the version at the foot, for support', (tester) async {
      await _pump(tester, const SettingsScreen());

      expect(find.text('Mostro'), findsWidgets);
      expect(find.text('2.0.1'), findsOneWidget);
    });

    testWidgets('keeps the node pubkey readout automation compares on', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final container = await _pump(tester, const SettingsScreen());

      // The row shows the node's name; the readout carries the full key, as
      // docs/automation-contract.md promises. Found by identifier, because
      // the footer says "Mostro" too.
      final readout = find.byWidgetPredicate(
        (w) =>
            w is AutomationId && w.id == AutomationIds.settingsMostroNodePubkey,
      );
      expect(readout, findsOneWidget);
      expect(
        tester.getSemantics(readout).getSemanticsData().label,
        container.read(mostroPubkeyProvider),
      );
      handle.dispose();
    });

    testWidgets('counts the enabled push events', (tester) async {
      SharedPreferences.setMockInitialValues({
        NotificationEvent.newMessages.prefsKey: false,
      });
      await _pump(tester, const SettingsScreen());
      await tester.pumpAndSettle();

      expect(find.text('3 of 4'), findsOneWidget);
    });
  });

  group('RelaysScreen · 10b', () {
    testWidgets('drops the wss:// prefix from every row', (tester) async {
      await _pump(tester, const RelaysScreen());

      expect(find.text('relay.damus.io'), findsOneWidget);
      expect(find.text('wss://relay.damus.io'), findsNothing);
    });

    testWidgets('says per relay whether it is connected', (tester) async {
      await _pump(tester, const RelaysScreen());

      // The v2 card showed a green dot even on the ones that were down.
      expect(find.text('Connected'), findsNWidgets(2));
      expect(find.text('No connection'), findsOneWidget);
    });

    testWidgets('the summary reassures while two relays are up', (
      tester,
    ) async {
      await _pump(tester, const RelaysScreen());

      expect(
        find.text('You receive orders and messages normally'),
        findsOneWidget,
      );
    });

    testWidgets('the summary warns below two connected relays', (tester) async {
      await _pump(
        tester,
        const RelaysScreen(),
        overrides: _overrides(
          relays: [
            _relay('wss://a'),
            _relay('wss://b', status: RelayStatus.disconnected),
          ],
        ),
      );

      expect(find.text('You may stop seeing new orders'), findsOneWidget);
    });

    testWidgets('refuses to disable the last active relay and says why', (
      tester,
    ) async {
      final container = await _pump(
        tester,
        const RelaysScreen(),
        overrides: _overrides(relays: [_relay('wss://only')]),
      );

      await tester.tap(find.byType(MostroToggle));
      await tester.pump();

      // The core rejects it (`LastRelay`), so no step that can only fail.
      expect(find.textContaining('Keep at least one relay'), findsOneWidget);
      expect(container.read(relaysProvider).single.isActive, isTrue);
    });

    testWidgets('disables freely while another relay stays active', (
      tester,
    ) async {
      await _pump(tester, const RelaysScreen());

      await tester.tap(find.byType(MostroToggle).first);
      await tester.pump();

      expect(find.textContaining('Keep at least one relay'), findsNothing);
    });
  });

  group('NotificationSettingsScreen · 10d', () {
    testWidgets('shows the four events with their descriptions', (
      tester,
    ) async {
      await _pump(tester, const NotificationSettingsScreen());

      // The master push toggle, then the four events.
      expect(find.byType(MostroToggle), findsNWidgets(5));
      expect(find.text('Trade updates'), findsOneWidget);
      expect(find.text('Dispute updates'), findsOneWidget);
    });

    testWidgets('the event header no longer promises push filtering', (
      tester,
    ) async {
      await _pump(tester, const NotificationSettingsScreen());

      // A content-free push has no type to filter on: the rows gate the
      // in-app cards.
      expect(
        find.text('Choose which events show a notification in the app.'),
        findsOneWidget,
      );
      expect(find.textContaining('trigger push'), findsNothing);
    });

    testWidgets('the master toggle reports what Rust registered', (
      tester,
    ) async {
      await _pump(
        tester,
        const NotificationSettingsScreen(),
        overrides: _overrides(push: _push(registered: 2)),
      );

      expect(find.text('Push notifications'), findsOneWidget);
      expect(find.text('Registered for 2 trades'), findsOneWidget);
    });

    testWidgets('turning the master toggle off goes through the toggle', (
      tester,
    ) async {
      final toggle = _RecordingToggle();
      await _pump(
        tester,
        const NotificationSettingsScreen(),
        overrides: _overrides(toggle: toggle),
      );

      await tester.tap(_masterToggle);
      await tester.pumpAndSettle();

      expect(toggle.asked, [false]);
    });

    testWidgets('a refused node is reported under the toggle', (tester) async {
      await _pump(
        tester,
        const NotificationSettingsScreen(),
        overrides: _overrides(
          push: _push(
            registered: 1,
            nodeRefusedUntil: DateTime.now().add(const Duration(hours: 3)),
          ),
        ),
      );

      expect(
        find.text('This Mostro node is not accepted by the push server'),
        findsOneWidget,
      );
    });

    testWidgets('push off says nothing is registered', (tester) async {
      await _pump(
        tester,
        const NotificationSettingsScreen(),
        overrides: _overrides(push: _push(enabled: false)),
      );

      expect(tester.widget<MostroToggle>(_masterToggle).value, isFalse);
      expect(
        find.text('Off — nothing is registered with the push server'),
        findsOneWidget,
      );
    });

    testWidgets('push off warns about registrations awaiting removal', (
      tester,
    ) async {
      await _pump(
        tester,
        const NotificationSettingsScreen(),
        overrides: _overrides(push: _push(enabled: false, registered: 3)),
      );
      const copy = 'Off — removal of 3 push registrations is pending';
      expect(find.text(copy), findsOneWidget);
      expect(_colorOf(tester, copy), SettingsPalette.dark.warnInk);
      expect(
        find.text('Off — nothing is registered with the push server'),
        findsNothing,
      );
    });

    testWidgets(
      'a reopened screen remains disabled during the shared transaction',
      (tester) async {
        final container = await _pump(
          tester,
          const NotificationSettingsScreen(),
        );
        container.read(pushTogglePendingProvider.notifier).state = false;
        await tester.pumpAndSettle();
        await tester.pumpWidget(_app(container, const SizedBox.shrink()));
        await tester.pumpAndSettle();
        await tester.pumpWidget(
          _app(container, const NotificationSettingsScreen()),
        );
        await tester.pumpAndSettle();
        final toggle = tester.widget<MostroToggle>(_masterToggle);
        expect(toggle.value, isFalse);
        expect(toggle.onChanged, isNull);

        container.read(pushTogglePendingProvider.notifier).state = null;
        await tester.pumpAndSettle();
        expect(tester.widget<MostroToggle>(_masterToggle).onChanged, isNotNull);
      },
    );

    testWidgets('an unsupported platform shows an info row, not a toggle', (
      tester,
    ) async {
      await _pump(
        tester,
        const NotificationSettingsScreen(),
        overrides: _overrides(pushSupported: false),
      );

      expect(
        find.text('Push notifications are not available on this platform'),
        findsOneWidget,
      );
      expect(_masterToggle, findsNothing);
      // The in-app event rows still apply.
      expect(find.byType(MostroToggle), findsNWidgets(4));
    });

    testWidgets('no banner while the system permission is granted', (
      tester,
    ) async {
      await _pump(tester, const NotificationSettingsScreen());

      expect(
        find.textContaining('turned off in your system settings'),
        findsNothing,
      );
    });

    testWidgets('banners and disables the rows when the system refuses', (
      tester,
    ) async {
      await _pump(
        tester,
        const NotificationSettingsScreen(),
        overrides: _overrides(permissionDenied: true),
      );

      expect(
        find.textContaining('turned off in your system settings'),
        findsOneWidget,
      );
      expect(find.text('Open settings'), findsOneWidget);
      // Flipping an event row here would change nothing the user can see.
      for (final toggle in tester.widgetList<MostroToggle>(
        find.byType(MostroToggle),
      )) {
        if (toggle.semanticLabel == 'Push notifications') continue;
        expect(toggle.onChanged, isNull);
      }
      // Turning push off still unregisters every trade from the server.
      expect(tester.widget<MostroToggle>(_masterToggle).onChanged, isNotNull);
    });

    testWidgets('toggling an event persists it', (tester) async {
      await _pump(tester, const NotificationSettingsScreen());

      // The first toggle is the master push toggle; this is the first event.
      await tester.tap(
        find.byWidgetPredicate(
          (w) => w is MostroToggle && w.semanticLabel == 'Trade updates',
        ),
      );
      await tester.pumpAndSettle();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(NotificationEvent.tradeUpdates.prefsKey), isFalse);
    });
  });
}
