import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/create_order_palette.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/order_side_provider.dart';
import 'package:mostro/features/order/widgets/price_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import '../../../support/provider_harness.dart';

/// Pump [PriceSection] in Market mode with the premium provider seeded to
/// [premium]. A tall surface keeps the layout from overflowing the viewport.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required double premium,
  OrderType side = OrderType.sell,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = createContainer(
    overrides: [
      premiumValueProvider.overrideWith((ref) => premium),
      orderSideProvider.overrideWith((ref) => side),
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
        home: const Scaffold(
          resizeToAvoidBottomInset: false,
          body: PriceSection(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// The premium figure is plain text until tapped; tapping it opens the
/// numeric field in place.
Future<void> _openPremiumField(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('premium-figure')));
  await tester.pumpAndSettle();
}

Color _blockColor(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find.byKey(const ValueKey('premium-block')),
  );
  return (container.decoration! as BoxDecoration).color!;
}

void main() {
  group('PriceSection premium slider', () {
    double sliderMax(WidgetTester tester) =>
        tester.widget<Slider>(find.byType(Slider)).max;

    testWidgets(
      'expands to fit a value entered above the default range',
      (tester) async {
        await _pump(tester, premium: 20.0);
        // Slider grows to the entered value instead of clamping to +10%.
        expect(sliderMax(tester), 20.0);
      },
    );

    testWidgets('shows the premium as a signed whole percent', (tester) async {
      await _pump(tester, premium: 3.0);
      expect(find.text('+3%'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets(
      'accepts a whole-percent value typed into the field',
      (tester) async {
        final container = await _pump(tester, premium: 0.0);
        await _openPremiumField(tester);
        await tester.enterText(find.byType(TextField), '7');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(container.read(premiumValueProvider), 7.0);
        // The field closes again and the figure shows the new value.
        expect(find.byType(TextField), findsNothing);
        expect(find.text('+7%'), findsOneWidget);
      },
    );

    testWidgets(
      'rejects a decimal typed into the field',
      (tester) async {
        final container = await _pump(tester, premium: 3.0);
        await _openPremiumField(tester);
        // The formatter drops '.' / ',', so a decimal never reaches state and
        // the premium stays a whole number.
        await tester.enterText(find.byType(TextField), '5.5');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        final value = container.read(premiumValueProvider);
        expect(value, value.roundToDouble());
        expect(value, isNot(5.5));
      },
    );

    testWidgets(
      'applies a typed value after the debounce without pressing enter',
      (tester) async {
        final container = await _pump(tester, premium: 0.0);
        await _openPremiumField(tester);
        await tester.enterText(find.byType(TextField), '50');
        // No submit action: the value must land on its own once the debounce
        // window elapses, and the slider expands to fit it.
        expect(container.read(premiumValueProvider), 0.0);
        await tester.pump(const Duration(seconds: 2));
        expect(container.read(premiumValueProvider), 50.0);
        expect(sliderMax(tester), 50.0);
      },
    );

    testWidgets(
      'accepts a value typed with an explicit plus sign',
      (tester) async {
        final container = await _pump(tester, premium: 0.0);
        await _openPremiumField(tester);
        await tester.enterText(find.byType(TextField), '+20');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(container.read(premiumValueProvider), 20.0);
      },
    );

    testWidgets(
      'keeps the premium on invalid submission',
      (tester) async {
        final container = await _pump(tester, premium: 3.0);
        await _openPremiumField(tester);
        // A lone sign does not parse: the premium must stay put and the figure
        // must show it again instead of the invalid text.
        await tester.enterText(find.byType(TextField), '-');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(container.read(premiumValueProvider), 3.0);
        expect(find.text('+3%'), findsOneWidget);
      },
    );

    testWidgets(
      'keeps expanded bounds stable while dragging 20 toward 0',
      (tester) async {
        final container = await _pump(tester, premium: 20.0);
        expect(sliderMax(tester), 20.0);

        // Grab the thumb near the right edge (value == max == 20) and drag left.
        final rect = tester.getRect(find.byType(Slider));
        final gesture = await tester.startGesture(
          Offset(rect.right - 24, rect.center.dy),
        );
        await tester.pump();

        // Drag toward zero in steps; the frozen max must not shrink under the
        // finger on any intermediate rebuild (the regression this guards). The
        // total distance is enough to cross back into the default range.
        for (var i = 0; i < 12; i++) {
          await gesture.moveBy(const Offset(-60, 0));
          await tester.pump();
          expect(
            sliderMax(tester),
            20.0,
            reason: 'max must stay frozen during the drag',
          );
        }

        // The value actually moved down while dragging (thumb is not pinned).
        expect(container.read(premiumValueProvider), lessThan(20.0));

        await gesture.up();
        await tester.pumpAndSettle();

        // Once the gesture ends the bounds recompute; the value landed inside
        // the default range, so the slider collapses back to +10%.
        expect(container.read(premiumValueProvider), lessThanOrEqualTo(10.0));
        expect(sliderMax(tester), kPremiumSliderDefault);
      },
    );
  });

  group('PriceSection premium colour (maker side)', () {
    testWidgets('a positive premium is lime when selling', (tester) async {
      await _pump(tester, premium: 3.0, side: OrderType.sell);
      expect(_blockColor(tester), CreateOrderPalette.dark.premiumGoodBg);
      expect(find.text('You sell 3% above market price'), findsOneWidget);
    });

    testWidgets('the same premium is amber when buying', (tester) async {
      await _pump(tester, premium: 3.0, side: OrderType.buy);
      expect(_blockColor(tester), CreateOrderPalette.dark.premiumBadBg);
      expect(find.text('You pay 3% more'), findsOneWidget);
    });

    testWidgets('switching side inverts the colour in place', (tester) async {
      final container = await _pump(tester, premium: -2.0, side: OrderType.sell);
      expect(_blockColor(tester), CreateOrderPalette.dark.premiumBadBg);

      container.read(orderSideProvider.notifier).state = OrderType.buy;
      await tester.pumpAndSettle();

      expect(_blockColor(tester), CreateOrderPalette.dark.premiumGoodBg);
      expect(container.read(premiumValueProvider), -2.0);
      expect(find.text('You pay 2% less than market'), findsOneWidget);
    });

    testWidgets('zero is neutral on both sides', (tester) async {
      await _pump(tester, premium: 0.0, side: OrderType.buy);
      expect(_blockColor(tester), CreateOrderPalette.dark.premiumZeroBg);
      expect(find.text('0%'), findsOneWidget);
      expect(find.text('Exact market price'), findsOneWidget);
    });
  });

  group('PriceSection price type control', () {
    testWidgets('Fixed swaps the premium block for the sats field',
        (tester) async {
      final container = await _pump(tester, premium: 0.0);
      await tester.tap(find.text('Fixed'));
      await tester.pumpAndSettle();

      expect(container.read(isMarketPriceProvider), isFalse);
      expect(find.byKey(const ValueKey('premium-block')), findsNothing);
      expect(find.byKey(const ValueKey('fixed-block')), findsOneWidget);

      await tester.enterText(find.byType(TextField), '5000');
      await tester.pump();
      expect(container.read(fixedSatsProvider), '5000');
      expect(find.text('5,000'), findsOneWidget);
    });

    testWidgets('Fixed is locked while a range order is being written',
        (tester) async {
      final container = await _pump(tester, premium: 0.0);
      container.read(isRangeOrderProvider.notifier).state = true;
      await tester.pumpAndSettle();

      await tester.tap(find.text('Fixed'));
      await tester.pumpAndSettle();
      expect(container.read(isMarketPriceProvider), isTrue);
    });
  });
}
