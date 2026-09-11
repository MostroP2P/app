import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/models/mostro_instance.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/providers/exchange_rate_provider.dart';
import 'package:mostro/features/order/providers/payment_methods_provider.dart';
import 'package:mostro/features/order/screens/add_order_screen.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/features/order/widgets/payment_method_section.dart';
import 'package:mostro/features/order/widgets/price_section.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import '../../../support/provider_harness.dart';

/// The handoff's two approved states on its 360 × 760 dp canvas, in Spanish
/// like the mockups: 5a — a sell of 5 000 – 25 000 ARS at market +3 %;
/// 5b — a sell of 5 000 ARS for 5 000 sats at a fixed price.
const _node = MostroInstance(
  pubKey: 'npub-golden',
  minOrderAmount: 100,
  maxOrderAmount: 100000000,
  expirationHours: 24,
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required Brightness brightness,
}) async {
  tester.view.physicalSize = const Size(360, 760);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final container = createContainer(
    overrides: [
      mostroNodeProvider.overrideWith((ref) async => _node),
      exchangeRateProvider.overrideWith(
        (ref, code) async => switch (code) {
          'USD' => 100000.0,
          'ARS' => 145000000.0,
          _ => null,
        },
      ),
      fiatCurrenciesProvider.overrideWith(
        (ref) async => const [
          FiatCurrency(code: 'ARS', name: 'Peso argentino', flag: '🇦🇷'),
        ],
      ),
      paymentMethodsDataProvider.overrideWith(
        (ref) async => {
          'ARS': ['Mercado Pago', 'Transferencia'],
        },
      ),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: brightness == Brightness.dark
            ? buildDarkTheme()
            : buildLightTheme(),
        locale: const Locale('es'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AddOrderScreen(orderType: 'sell'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  container.read(selectedFiatCodeProvider.notifier).state = 'ARS';
  container.read(selectedPaymentMethodsProvider.notifier).state = [
    'Mercado Pago',
  ];
  await tester.pumpAndSettle();
  return container;
}

Future<void> _state5a(WidgetTester tester, ProviderContainer container) async {
  await tester.tap(find.text('Rango'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), '5000');
  await tester.enterText(find.byType(TextField).at(1), '25000');
  container.read(premiumValueProvider.notifier).state = 3;
  // Drop focus so no field shows the caret.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

Future<void> _state5b(WidgetTester tester, ProviderContainer container) async {
  await tester.enterText(find.byType(TextField).first, '5000');
  await tester.tap(find.text('Fijo'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).last, '5000');
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
}

void main() {
  group('AddOrderScreen goldens', () {
    for (final (name, brightness) in [
      ('dark', Brightness.dark),
      ('light', Brightness.light),
    ]) {
      testWidgets('5a range at market price, $name', (tester) async {
        final container = await _pump(tester, brightness: brightness);
        await _state5a(tester, container);
        await expectLater(
          find.byType(AddOrderScreen),
          matchesGoldenFile('goldens/add_order_5a_range_market_$name.png'),
        );
      });

      testWidgets('5b single amount at fixed price, $name', (tester) async {
        final container = await _pump(tester, brightness: brightness);
        await _state5b(tester, container);
        await expectLater(
          find.byType(AddOrderScreen),
          matchesGoldenFile('goldens/add_order_5b_single_fixed_$name.png'),
        );
      });
    }
  });
}
