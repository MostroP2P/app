import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/invoice_widgets.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// The invoice screens lay their hero out under an `IntrinsicHeight` (to push
/// the actions to the bottom), so the hero must pick its figure size without
/// a `LayoutBuilder`, which cannot answer intrinsic sizes.
Future<void> _pump(WidgetTester tester, {required int sats}) async {
  tester.view.physicalSize = const Size(300, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InvoiceHeroCard(
                  label: 'To pay',
                  sats: sats,
                  semanticsLabel: '$sats satoshis to pay',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  // DS-CMP-23: a figure that does not fit at 38 drops to 26 before it wraps.
  testWidgets(
    'a sats figure too wide for 38 drops to 26 under IntrinsicHeight',
    (tester) async {
      await _pump(tester, sats: 1234567890);

      expect(tester.takeException(), isNull);
      final figure = tester.widget<Text>(find.text('1,234,567,890'));
      expect(figure.style?.fontSize, 26);
      // At 26 it fits on one line beside its unit.
      final unit = tester.getRect(find.text('sats'));
      expect(
        unit.left,
        greaterThan(tester.getRect(find.text('1,234,567,890')).right),
      );
    },
  );

  testWidgets('a sats figure that fits stays at 38', (tester) async {
    await _pump(tester, sats: 252);

    expect(tester.takeException(), isNull);
    expect(tester.widget<Text>(find.text('252')).style?.fontSize, 38);
  });
}
