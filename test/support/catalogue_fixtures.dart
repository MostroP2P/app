import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';

/// A small catalogue for widget tests: three fiats and one stablecoin.
const kTestCatalogue = [
  FiatCurrency(code: 'USD', name: 'US Dollar', flag: '🇺🇸'),
  FiatCurrency(code: 'EUR', name: 'Euro', flag: '🇪🇺'),
  FiatCurrency(code: 'ARS', name: 'Argentine Peso', flag: '🇦🇷'),
  FiatCurrency(code: 'USDT', name: 'Tether USD', peg: 'USD'),
];

/// Overrides the catalogue with [kTestCatalogue] (or [entries]), so a widget
/// that draws a currency's mark finds its flag or its coin.
Override catalogueOverride([List<FiatCurrency> entries = kTestCatalogue]) =>
    fiatCurrenciesProvider.overrideWith((ref) async => entries);
