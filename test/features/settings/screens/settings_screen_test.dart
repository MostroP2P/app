import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/escrow_mode_provider.dart';
import 'package:mostro/features/settings/screens/settings_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/provider_harness.dart';

const _mint = 'https://mint.example.com';

EscrowModeInfo _escrow({required String mode, String? mintUrl}) =>
    EscrowModeInfo(
      mode: mode,
      mintUrl: mintUrl,
      escrowLocktimeDays: null,
      settlementMarginDays: null,
      isOverridden: false,
      isCashuAvailable: mode == 'cashu' && mintUrl != null,
      forceCashuOverride: false,
      mintUrlOverride: null,
    );

Future<void> _pump(
  WidgetTester tester, {
  required String mode,
  String? mintUrl,
}) async {
  // The entry sits ninth in a lazy ListView, past the default 800px test
  // viewport. A tall surface makes both "present" and "absent" assertions
  // about the whole list rather than about what happened to be built.
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final info = _escrow(mode: mode, mintUrl: mintUrl);
  final container = createContainer(
    overrides: [
      // The stream every escrow gate derives from — overridden so nothing on
      // this screen reaches Rust.
      escrowModeProvider.overrideWith((ref) => Stream.value(info)),
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
  group('SettingsScreen — Cashu wallet entry', () {
    testWidgets('is absent when the node does not run Cashu', (tester) async {
      // The phase's acceptance criterion: with no usable Cashu node there is
      // no trace of the feature. An entry leading to a permanently empty
      // wallet would be worse than none.
      await _pump(tester, mode: 'lightning');

      expect(find.text('Cashu wallet'), findsNothing);
    });

    testWidgets('appears when the node runs Cashu with a usable mint', (
      tester,
    ) async {
      await _pump(tester, mode: 'cashu', mintUrl: _mint);

      expect(find.text('Cashu wallet'), findsOneWidget);
    });
  });

  group('SettingsScreen — payments follow the node\'s escrow mode', () {
    testWidgets('a Lightning node shows the Lightning rows and no mint', (
      tester,
    ) async {
      await _pump(tester, mode: 'lightning');

      expect(find.text('Lightning Address'), findsOneWidget);
      expect(find.text('NWC Wallet'), findsOneWidget);
      expect(find.text('Mint'), findsNothing);
    });

    testWidgets('a node that has not said yet reads as Lightning', (
      tester,
    ) async {
      // An old daemon publishes no escrow_mode tag, and nothing has been
      // fetched before the first answer: the rest of the app treats both as
      // Lightning, and so does this screen.
      await _pump(tester, mode: 'unknown');

      expect(find.text('Lightning Address'), findsOneWidget);
      expect(find.text('NWC Wallet'), findsOneWidget);
      expect(find.text('Mint'), findsNothing);
    });

    testWidgets('a Cashu node shows its mint and hides the Lightning rows', (
      tester,
    ) async {
      await _pump(tester, mode: 'cashu', mintUrl: _mint);

      expect(find.text('Mint'), findsOneWidget);
      expect(find.text('mint.example.com'), findsOneWidget);
      expect(find.text('Lightning Address'), findsNothing);
      expect(find.text('NWC Wallet'), findsNothing);
    });

    testWidgets('a Cashu node without a mint says so, and still hides '
        'the Lightning rows', (tester) async {
      // Misconfigured, not Lightning: no invoice step and no bond exist on a
      // Cashu node, so the Lightning rows are no more use here.
      await _pump(tester, mode: 'cashu');

      expect(find.text('Mint'), findsOneWidget);
      expect(find.text('Not advertised'), findsOneWidget);
      expect(find.text('Cashu wallet'), findsNothing);
      expect(find.text('Lightning Address'), findsNothing);
      expect(find.text('NWC Wallet'), findsNothing);
    });

    testWidgets('tapping the mint copies its full URL', (tester) async {
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
      await _pump(tester, mode: 'cashu', mintUrl: _mint);

      await tester.tap(find.text('Mint'));
      await tester.pump();

      expect(copied, _mint);
      expect(find.text('Mint URL copied'), findsOneWidget);
    });
  });
}
