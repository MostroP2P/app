import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/create_order_palette.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/order_side_provider.dart';
import 'package:mostro/features/order/providers/payment_methods_provider.dart';
import 'package:mostro/features/order/screens/add_order_screen.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/features/order/widgets/payment_method_section.dart';
import 'package:mostro/features/order/widgets/price_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import '../../../support/provider_harness.dart';

const _node = MostroInstance(
  pubKey: 'npub-test',
  minOrderAmount: 100,
  maxOrderAmount: 100000000,
  expirationHours: 24,
);

/// Pumps the screen with every Rust-backed provider stubbed: a node that
/// expires orders after 24 h, a USD rate of 100 000 and an ARS rate 1 000×
/// that (so 1 USD = 1 000 ARS), and a small currency and method catalogue.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String orderType = 'sell',
  Locale locale = const Locale('en'),
  MostroInstance node = _node,
  int? bondEstimate,
}) async {
  tester.view.physicalSize = const Size(400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = createContainer(
    overrides: [
      mostroNodeProvider.overrideWith((ref) async => node),
      bondEstimateProvider.overrideWith((ref, sats) async => bondEstimate),
      exchangeRateProvider.overrideWith(
        (ref, code) async => switch (code) {
          'USD' => 100000.0,
          'ARS' => 100000000.0,
          _ => null,
        },
      ),
      fiatCurrenciesProvider.overrideWith(
        (ref) async => const [
          FiatCurrency(code: 'USD', name: 'US Dollar', flag: '🇺🇸'),
          FiatCurrency(code: 'ARS', name: 'Argentine Peso', flag: '🇦🇷'),
        ],
      ),
      paymentMethodsDataProvider.overrideWith(
        (ref) async => {
          'USD': ['Zelle', 'Wire'],
          'ARS': ['Mercado Pago'],
        },
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: AddOrderScreen(orderType: orderType),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder _amountField() => find.byType(TextField).first;

FilledButton _publishButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Publish order'));

String _previewText(WidgetTester tester) {
  final rich = tester.widget<Text>(
    find.descendant(
      of: find.byKey(const ValueKey('preview-sentence')),
      matching: find.byType(Text),
    ),
  );
  return rich.textSpan!.toPlainText();
}

void main() {
  group('AddOrderScreen', () {
    testWidgets('has no presets: the full form is the screen', (tester) async {
      await _pump(tester);
      expect(find.text('New order'), findsOneWidget);
      expect(find.text('Conservative'), findsNothing);
      expect(find.text('Custom'), findsNothing);
      expect(find.text('How much you sell'), findsOneWidget);
      expect(find.text('Payment methods'), findsOneWidget);
      expect(find.text('Price'), findsOneWidget);
    });

    testWidgets('seeds the side from the route and lets the user switch it',
        (tester) async {
      final container = await _pump(tester, orderType: 'buy');
      expect(container.read(orderSideProvider), OrderType.buy);
      expect(find.text('How much you buy'), findsOneWidget);

      await tester.tap(find.text('Sell BTC'));
      await tester.pumpAndSettle();

      expect(container.read(orderSideProvider), OrderType.sell);
      expect(find.text('How much you sell'), findsOneWidget);
    });

    testWidgets('publish stays disabled until amount and a method exist',
        (tester) async {
      final container = await _pump(tester);
      expect(_publishButton(tester).onPressed, isNull);
      expect(find.byKey(const ValueKey('preview-hint')), findsOneWidget);

      await tester.enterText(_amountField(), '5000');
      await tester.pumpAndSettle();
      expect(_publishButton(tester).onPressed, isNull);

      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.pumpAndSettle();
      expect(_publishButton(tester).onPressed, isNotNull);
    });

    testWidgets('a node that bonds makers says so and still publishes', (
      tester,
    ) async {
      // docs/ANTI_ABUSE_BOND.md §6.2: the deposit is asked before the tap;
      // Publish lands on the pay-bond screen.
      final container = await _pump(
        tester,
        node: const MostroInstance(
          pubKey: 'npub-test',
          minOrderAmount: 100,
          maxOrderAmount: 100000000,
          expirationHours: 24,
          bondPolicy: BondPolicy.enabled,
          bondApplyTo: BondApplyTo.both,
        ),
      );
      await tester.enterText(_amountField(), '5000');
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.pumpAndSettle();
      expect(_publishButton(tester).onPressed, isNotNull);
      expect(
        find.textContaining('lock a refundable deposit before the order'),
        findsOneWidget,
      );
    });

    testWidgets('names the estimated deposit once the amount is known',
        (tester) async {
      final container = await _pump(
        tester,
        node: const MostroInstance(
          pubKey: 'npub-test',
          minOrderAmount: 100,
          maxOrderAmount: 100000000,
          expirationHours: 24,
          bondPolicy: BondPolicy.enabled,
          bondApplyTo: BondApplyTo.make,
        ),
        bondEstimate: 1500,
      );
      await tester.enterText(_amountField(), '5000');
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.pumpAndSettle();
      expect(
        find.textContaining('refundable deposit of ≈ 1,500 sats'),
        findsOneWidget,
      );
    });

    testWidgets('a node that bonds takers only says nothing about a deposit',
        (tester) async {
      final container = await _pump(
        tester,
        node: const MostroInstance(
          pubKey: 'npub-test',
          minOrderAmount: 100,
          maxOrderAmount: 100000000,
          expirationHours: 24,
          bondPolicy: BondPolicy.enabled,
          bondApplyTo: BondApplyTo.take,
        ),
      );
      await tester.enterText(_amountField(), '5000');
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.pumpAndSettle();
      expect(_publishButton(tester).onPressed, isNotNull);
      expect(find.textContaining('refundable deposit'), findsNothing);
    });

    testWidgets('previews a market sell with premium and the node expiry',
        (tester) async {
      final container = await _pump(tester);
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      container.read(premiumValueProvider.notifier).state = 3;
      await tester.enterText(_amountField(), '5000');
      await tester.pumpAndSettle();

      expect(
        _previewText(tester),
        'You sell BTC for 5,000 USD at market price +3% · active 24 h',
      );
    });

    testWidgets('previews a fixed-price buy with the sats figure',
        (tester) async {
      final container = await _pump(tester, orderType: 'buy');
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.enterText(_amountField(), '100');
      await tester.tap(find.text('Fixed'));
      await tester.pumpAndSettle();
      container.read(fixedSatsProvider.notifier).state = '120000';
      await tester.pumpAndSettle();

      expect(
        _previewText(tester),
        'You buy 120,000 sats for 100 USD at a fixed price · active 24 h',
      );
    });

    testWidgets('groups thousands with the locale separator and previews it',
        (tester) async {
      final container = await _pump(tester, locale: const Locale('es'));
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.enterText(_amountField(), '25000');
      await tester.pumpAndSettle();

      expect(find.text('25.000'), findsOneWidget);
      expect(
        _previewText(tester),
        'Vendes BTC por 25.000 USD a precio de mercado · activa 24 h',
      );
    });

    testWidgets('switching to range keeps the amount as the minimum',
        (tester) async {
      final container = await _pump(tester);
      await tester.enterText(_amountField(), '5000');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Range'));
      await tester.pumpAndSettle();

      expect(container.read(isRangeOrderProvider), isTrue);
      expect(find.text('MINIMUM'), findsOneWidget);
      expect(find.text('MAXIMUM'), findsOneWidget);
      final min = tester.widget<TextField>(find.byType(TextField).at(0));
      expect(min.controller!.text, '5,000');

      // And back: the minimum is kept as the single amount.
      await tester.tap(find.text('Single'));
      await tester.pumpAndSettle();
      expect(container.read(isRangeOrderProvider), isFalse);
      final single = tester.widget<TextField>(_amountField());
      expect(single.controller!.text, '5,000');
    });

    testWidgets('a range order is priced at market and previews both ends',
        (tester) async {
      final container = await _pump(tester);
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      await tester.tap(find.text('Fixed'));
      await tester.pumpAndSettle();
      expect(container.read(isMarketPriceProvider), isFalse);

      await tester.tap(find.text('Range'));
      await tester.pumpAndSettle();
      expect(container.read(isMarketPriceProvider), isTrue);

      await tester.enterText(find.byType(TextField).at(0), '5000');
      await tester.enterText(find.byType(TextField).at(1), '25000');
      await tester.pumpAndSettle();

      expect(
        _previewText(tester),
        'You sell BTC for 5,000 – 25,000 USD at market price · active 24 h',
      );
      expect(_publishButton(tester).onPressed, isNotNull);
    });

    testWidgets('quick chips fill the amount field', (tester) async {
      await _pump(tester);
      // 1 USD = 1 USD, so the chips are the base amounts.
      expect(find.text('25'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);

      await tester.tap(find.text('25'));
      await tester.pumpAndSettle();

      expect(tester.widget<TextField>(_amountField()).controller!.text, '25');
    });

    testWidgets('quick chips follow the chosen currency', (tester) async {
      final container = await _pump(tester);
      container.read(selectedFiatCodeProvider.notifier).state = 'ARS';
      await tester.pumpAndSettle();

      // 1 USD = 1 000 ARS → 10 000 / 25 000 / 50 000 / 100 000.
      expect(find.text('10,000'), findsOneWidget);
      expect(find.text('100,000'), findsOneWidget);
    });

    testWidgets('an out-of-range amount replaces the preview with the error',
        (tester) async {
      final container = await _pump(tester);
      container.read(selectedPaymentMethodsProvider.notifier).state = ['Zelle'];
      // 1 USD at 100 000 USD/BTC is 1 000 sats — above the node's max of
      // 100 000 000 sats only for absurd amounts, so go absurd.
      await tester.enterText(_amountField(), '999999999');
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('preview-error')), findsOneWidget);
      expect(find.byKey(const ValueKey('preview-sentence')), findsNothing);
      expect(_publishButton(tester).onPressed, isNull);
    });

    testWidgets('the Sell tab uses the coral tint', (tester) async {
      await _pump(tester);
      final tab = tester.widget<AnimatedContainer>(
        find
            .ancestor(
              of: find.text('Sell BTC'),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      expect(
        (tab.decoration! as BoxDecoration).color,
        CreateOrderPalette.dark.sellActiveBg,
      );
    });
  });
}
