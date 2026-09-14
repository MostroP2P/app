import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/about/screens/about_screen.dart';
import 'package:mostro/features/about/screens/node_technical_data_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../../support/provider_harness.dart';

/// Goldens of the About redesign (`design_handoff_acerca_de`): 12a · About and
/// 12b · Technical data, with the handoff's node. 360 × 760, `es`, dark and
/// light. PNGs are generated in CI only — see `docs/golden-tests.md`.

final _node = MostroInstance.fromTags(const [
  ['d', '00007cb3a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a195d23f91'],
  ['min_order_amount', '500'],
  ['max_order_amount', '300000'],
  ['fee', '0'],
  ['expiration_hours', '23'],
  ['max_orders_per_response', '10'],
  ['lnd_node_alias', 'Bitcoin Bolivia'],
  [
    'lnd_node_pubkey',
    '02d3280ab2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2c5198fc9',
  ],
  [
    'lnd_uris',
    '02d3280ab2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2c5198fc9@node.example.onion:9735',
  ],
  ['lnd_version', '0.20.0-beta commit=v0.20.0-beta'],
  ['lnd_commit_hash', 'b9ea7070123456789abcdef0123456789abcdef0'],
  ['lnd_chains', 'bitcoin'],
  ['lnd_networks', 'mainnet'],
]);

Widget _app(Brightness brightness, Widget home) {
  final container = createContainer(
    overrides: [
      appVersionProvider.overrideWith((ref) async => '2.0.0'),
      activeNodeNameProvider.overrideWith((ref) => 'Mostro'),
      mostroNodeProvider.overrideWith((ref) async => _node),
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
    for (final (variant, screen) in [
      ('12a', const AboutScreen() as Widget),
      ('12b', const NodeTechnicalDataScreen() as Widget),
    ]) {
      testWidgets('$variant about · $name', (tester) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_app(brightness, screen));
        // Decode the logo up front: left to the frame, it lands in whichever
        // test happens to run after the first decode, and the image flickers
        // between goldens.
        await tester.runAsync(
          () => precacheImage(
            const AssetImage('assets/images/mostro_logo.webp'),
            tester.element(find.byType(Scaffold)),
          ),
        );
        await tester.pump();
        await tester.pump();

        await expectLater(
          find.byType(Scaffold),
          matchesGoldenFile('goldens/about_${variant}_$name.png'),
        );
      });
    }
  }
}
