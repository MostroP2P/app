import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/install/providers/pwa_install_provider.dart';
import 'package:mostro/features/settings/providers/escrow_mode_provider.dart';
import 'package:mostro/features/settings/screens/settings_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_pwa_install_bridge.dart';
import '../../../support/provider_harness.dart';

const _mintA = 'https://mint.a.com';
const _mintB = 'https://mint.b.com';

/// What Rust reports for a node in [mode] that accepts [mints]: the wallet's
/// one mint, and the gate, only when there is exactly one.
EscrowModeInfo _escrow({required String mode, List<String> mints = const []}) {
  final single = mode == 'cashu' && mints.length == 1 ? mints.single : null;
  return EscrowModeInfo(
    mode: mode,
    mintUrl: single,
    mintUrls: mints,
    escrowLocktimeDays: null,
    settlementMarginDays: null,
    isOverridden: false,
    isCashuAvailable: single != null,
    forceCashuOverride: false,
    mintUrlOverride: null,
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required String mode,
  List<String> mints = const [],
  FakePwaInstallBridge? page,
}) async {
  // The payment rows sit past the default 800px test viewport in a lazy
  // ListView. A tall surface makes both "present" and "absent" assertions
  // about the whole list rather than about what happened to be built.
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final info = _escrow(mode: mode, mints: mints);
  final container = createContainer(
    overrides: [
      // The stream every escrow gate derives from — overridden so nothing on
      // this screen reaches Rust.
      escrowModeProvider.overrideWith((ref) => Stream.value(info)),
      if (page != null) ...[
        pwaInstallBridgeProvider.overrideWithValue(page),
        pwaInstallPlatformProvider.overrideWithValue(TargetPlatform.android),
      ],
    ],
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
        home: const SettingsScreen(),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('SettingsScreen — Lightning, NWC and Cashu are always available', () {
    // docs/cashu/README.md §1.2, FR-058a: the node's escrow mode decides how a
    // trade settles, never which payment methods the app offers.
    final nodes = <String, ({String mode, List<String> mints})>{
      'a Lightning node': (mode: 'lightning', mints: const []),
      'a node that has not said yet': (mode: 'unknown', mints: const []),
      'a Cashu node on one mint': (mode: 'cashu', mints: const [_mintA]),
      'a Cashu node on several mints': (
        mode: 'cashu',
        mints: const [_mintA, _mintB],
      ),
      'a Cashu node that accepts any mint': (mode: 'cashu', mints: const []),
    };

    for (final MapEntry(key: name, value: node) in nodes.entries) {
      testWidgets('$name shows the Lightning address, NWC and Cashu wallets', (
        tester,
      ) async {
        await _pump(tester, mode: node.mode, mints: node.mints);

        expect(find.text('Lightning Address'), findsOneWidget);
        expect(find.text('NWC Wallet'), findsOneWidget);
        expect(find.text('Cashu wallet'), findsOneWidget);
      });
    }
  });

  group('SettingsScreen — the node\'s mints', () {
    testWidgets('a Lightning node lists no mint', (tester) async {
      await _pump(tester, mode: 'lightning');

      expect(find.text('Mint'), findsNothing);
    });

    testWidgets('a node that has not said yet lists no mint', (tester) async {
      // An old daemon publishes no escrow_mode tag, and nothing has been
      // fetched before the first answer: both read as Lightning.
      await _pump(tester, mode: 'unknown');

      expect(find.text('Mint'), findsNothing);
    });

    testWidgets('a Cashu node shows its mint', (tester) async {
      await _pump(tester, mode: 'cashu', mints: [_mintA]);

      expect(find.text('Mint'), findsOneWidget);
      expect(find.text('mint.a.com'), findsOneWidget);
    });

    testWidgets('a Cashu node with several mints shows one row per mint', (
      tester,
    ) async {
      await _pump(tester, mode: 'cashu', mints: [_mintA, _mintB]);

      expect(find.text('Mint'), findsNWidgets(2));
      expect(find.text('mint.a.com'), findsOneWidget);
      expect(find.text('mint.b.com'), findsOneWidget);
    });

    testWidgets('a Cashu node that lists no mint says it accepts any', (
      tester,
    ) async {
      await _pump(tester, mode: 'cashu');

      expect(find.text('Mint'), findsOneWidget);
      expect(find.text('Any mint'), findsOneWidget);
    });

    testWidgets('tapping a mint copies its full URL', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _pump(tester, mode: 'cashu', mints: [_mintA, _mintB]);

      await tester.tap(find.text('mint.b.com'));
      await tester.pump();

      expect(copied, _mintB);
      expect(find.text('Mint URL copied'), findsOneWidget);
    });
  });

  // #778: whoever answered "Not now" on the order book can still install.
  group('SettingsScreen — Install app', () {
    testWidgets('is offered while the browser can install the app', (
      tester,
    ) async {
      // Arrange — answered the card already: the row does not care.
      SharedPreferences.setMockInitialValues({kPwaInstallAnsweredKey: true});
      final page = FakePwaInstallBridge(canPromptNatively: true);
      await _pump(tester, mode: 'lightning', page: page);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.text('Install app'));
      await tester.pumpAndSettle();

      // Assert — the browser's dialog was asked for, and the row is gone.
      expect(page.prompts, 1);
      expect(find.text('Install app'), findsNothing);
    });

    testWidgets('is absent off web and in the installed app', (tester) async {
      // Arrange
      SharedPreferences.setMockInitialValues({});

      // Act
      await _pump(tester, mode: 'lightning');
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('Install app'), findsNothing);
    });
  });
}
