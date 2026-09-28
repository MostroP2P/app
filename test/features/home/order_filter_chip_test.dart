import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/widgets/order_filter_chip.dart';
import 'package:mostro/l10n/app_localizations.dart';

import '../../support/load_app_fonts.dart';

Widget _app(Brightness brightness, Widget child) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: brightness == Brightness.dark ? buildDarkTheme() : buildLightTheme(),
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: Center(child: child)),
);

OrderBookPalette _palette(Brightness b) =>
    b == Brightness.dark ? OrderBookPalette.dark : OrderBookPalette.light;

/// The filter chip says whether the book is filtered (issue #575): once the
/// filters persist, the user can reopen the app to a narrowed book days after
/// choosing them.
void main() {
  setUpAll(loadAppFonts);

  Widget chip(int active, {Brightness b = Brightness.dark}) =>
      OrderFilterChip(palette: _palette(b), activeCount: active, onTap: () {});

  testWidgets('idle, it is the plain chip: no badge', (tester) async {
    await tester.pumpWidget(_app(Brightness.dark, chip(0)));

    expect(find.text('Filter'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.bySemanticsLabel('Filter'), findsOneWidget);
  });

  testWidgets('active, it counts the controls in use', (tester) async {
    await tester.pumpWidget(_app(Brightness.dark, chip(2)));

    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('a screen reader hears the count, not just a number', (
    tester,
  ) async {
    await tester.pumpWidget(_app(Brightness.dark, chip(2)));

    expect(find.bySemanticsLabel('Filter, 2 filters on'), findsOneWidget);
  });

  testWidgets('a screen reader can still open the filters', (tester) async {
    var taps = 0;
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        Brightness.dark,
        OrderFilterChip(
          palette: OrderBookPalette.dark,
          activeCount: 2,
          onTap: () => taps++,
        ),
      ),
    );

    final node = tester.getSemantics(find.byType(OrderFilterChip));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    tester.semantics.tap(find.semantics.byLabel('Filter, 2 filters on'));
    expect(taps, 1);
    handle.dispose();
  });

  testWidgets('active, the outline takes the accent', (tester) async {
    await tester.pumpWidget(
      _app(Brightness.light, chip(1, b: Brightness.light)),
    );

    final material = tester.widget<Material>(
      find.descendant(
        of: find.byType(OrderFilterChip),
        matching: find.byType(Material),
      ),
    );
    final border = (material.shape! as StadiumBorder).side.color;
    // The darkened lime, legible on white — not `lime`, which is 1.76:1.
    expect(border, OrderBookPalette.light.limeText);
  });

  for (final (mode, brightness) in [
    ('dark', Brightness.dark),
    ('light', Brightness.light),
  ]) {
    testWidgets('filter chip gallery · $mode', (tester) async {
      tester.view.physicalSize = const Size(600, 560);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final book = _palette(brightness);

      Widget caption(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: AppFonts.ui,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: book.textMuted,
          ),
        ),
      );

      await tester.pumpWidget(
        _app(
          brightness,
          Container(
            key: const ValueKey('filter-chip-gallery'),
            width: 260,
            color: book.bg,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                caption('NO FILTERS'),
                chip(0, b: brightness),
                const SizedBox(height: 14),
                caption('ONE FILTER ON'),
                chip(1, b: brightness),
                const SizedBox(height: 14),
                caption('THREE FILTERS ON'),
                chip(3, b: brightness),
              ],
            ),
          ),
        ),
      );

      await expectLater(
        find.byKey(const ValueKey('filter-chip-gallery')),
        matchesGoldenFile('goldens/order_filter_chip_$mode.png'),
      );
    });
  }
}
