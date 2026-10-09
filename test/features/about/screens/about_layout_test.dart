import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/about/screens/about_screen.dart';
import 'package:mostro/features/about/widgets/about_widgets.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../../support/load_app_fonts.dart';
import '../../../support/provider_harness.dart';

/// A node with every figure of the card, a deposit floor included.
final _node = MostroInstance.fromTags(const [
  ['d', '00007cb3a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a195d23f91'],
  ['min_order_amount', '500'],
  ['max_order_amount', '300000'],
  ['fee', '0.006'],
  ['expiration_hours', '24'],
  ['bond_enabled', 'true'],
  ['bond_amount_pct', '0.01'],
  ['bond_base_amount_sats', '1000'],
]);

/// The same node at the widest figures: a ten-million maximum and a floor
/// that does not fit three cells to a row.
final _wideNode = MostroInstance.fromTags(const [
  ['d', '00007cb3a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a195d23f91'],
  ['min_order_amount', '1000000'],
  ['max_order_amount', '10000000'],
  ['fee', '0.006'],
  ['expiration_hours', '24'],
  ['bond_enabled', 'true'],
  ['bond_amount_pct', '0.015'],
  ['bond_base_amount_sats', '100000'],
  ['fiat_currencies_accepted', 'ARS,BRL,CUP,EUR,USD,VES'],
]);

/// Pumps 12a on a [width] × 800 phone with a 24 dp status bar and a 48 dp
/// navigation bar, in [locale], with the app's fonts so text keeps its width.
Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required String locale,
  required MostroInstance? node,
  FakeViewPadding padding = const FakeViewPadding(top: 24, bottom: 48),
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1.0;
  tester.view.padding = padding;
  addTearDown(tester.view.reset);
  final container = createContainer(
    overrides: [
      appVersionProvider.overrideWith((ref) async => '2.0.0'),
      activeNodeNameProvider.overrideWith((ref) => 'Mostro'),
      mostroNodeProvider.overrideWith((ref) async => node),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: Locale(locale),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AboutScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(loadAppFonts);

  // One test per phone, so each starts from a fresh tree.
  for (final width in const [360.0, 393.0]) {
    for (final locale in AppLocalizations.supportedLocales) {
      for (final (state, node) in [
        ('loaded', _node),
        ('wide', _wideNode),
        ('loading', null),
      ]) {
        testWidgets('the way into the technical data is on the first screen: '
            '$width dp, $locale, $state', (tester) async {
          await _pump(
            tester,
            width: width,
            locale: locale.languageCode,
            node: node,
          );
          final row = find.ancestor(
            of: find.text(
              lookupAppLocalizations(locale).aboutNodeTechnicalDataRow,
            ),
            matching: find.byType(AboutNavRow),
          );

          expect(tester.getBottomLeft(row).dy, lessThanOrEqualTo(800 - 48));
        });
      }
    }
  }

  testWidgets('the grid measures the width it is laid out in', (tester) async {
    // Side insets too, so the SafeArea narrows the column.
    await _pump(
      tester,
      width: 400,
      locale: 'en',
      node: _node,
      padding: const FakeViewPadding(top: 24, bottom: 48, left: 48, right: 48),
    );
    final grid = find.byType(AboutFactGrid);
    final measured =
        tester
            .element(grid)
            .getInheritedWidgetOfExactType<AboutContentWidth>()!
            .width -
        2 * tester.widget<AboutFactGrid>(grid).inset;

    expect(tester.getSize(grid).width, measured);
  });
}
