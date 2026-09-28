import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/escrow_mode_provider.dart';
import 'package:mostro/features/settings/screens/settings_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/provider_harness.dart';

EscrowModeInfo _escrow({required bool cashuAvailable}) => EscrowModeInfo(
      mode: cashuAvailable ? 'cashu' : 'lightning',
      mintUrl: cashuAvailable ? 'https://mint.example.com' : null,
      escrowLocktimeDays: null,
      settlementMarginDays: null,
      isOverridden: false,
      isCashuAvailable: cashuAvailable,
      forceCashuOverride: false,
      mintUrlOverride: null,
    );

Future<void> _pump(WidgetTester tester, {required bool cashuAvailable}) async {
  // The entry sits ninth in a lazy ListView, past the default 800px test
  // viewport. A tall surface makes both "present" and "absent" assertions
  // about the whole list rather than about what happened to be built.
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = createContainer(overrides: [
    // The gate itself, and the stream the developer card reads — overridden
    // so nothing on this screen reaches Rust.
    isCashuAvailableProvider.overrideWithValue(cashuAvailable),
    escrowModeProvider.overrideWith(
      (ref) => Stream.value(_escrow(cashuAvailable: cashuAvailable)),
    ),
  ]);

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
      await _pump(tester, cashuAvailable: false);

      expect(find.text('Cashu wallet'), findsNothing);
    });

    testWidgets('appears when the node runs Cashu with a usable mint',
        (tester) async {
      await _pump(tester, cashuAvailable: true);

      expect(find.text('Cashu wallet'), findsOneWidget);
    });
  });
}
