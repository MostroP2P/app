import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A fiat currency entry loaded from assets/data/fiat.json.
class FiatCurrency {
  const FiatCurrency({
    required this.code,
    required this.name,
    required this.flag,
  });

  final String code;
  final String name;
  final String flag;
}

/// Loads fiat currencies from the bundled JSON asset.
/// Cached via Riverpod — loaded once per app session.
final fiatCurrenciesProvider = FutureProvider<List<FiatCurrency>>((ref) async {
  final jsonStr = await rootBundle.loadString('assets/data/fiat.json');
  final List<dynamic> data = json.decode(jsonStr) as List<dynamic>;
  return data
      .map(
        (e) => FiatCurrency(
          code: e['code'] as String,
          name: e['name'] as String,
          flag: e['flag'] as String,
        ),
      )
      .toList();
});

/// Currency code → flag emoji map, derived from the loaded fiat currencies.
final currencyFlagsProvider = Provider<Map<String, String>>((ref) {
  final currencies = ref.watch(fiatCurrenciesProvider);
  return currencies.maybeWhen(
    data: (list) => {for (final c in list) c.code: c.flag},
    orElse: () => {},
  );
});

/// All available currency codes, derived from the loaded fiat currencies.
final availableCurrencyCodesProvider = Provider<List<String>>((ref) {
  final currencies = ref.watch(fiatCurrenciesProvider);
  return currencies.maybeWhen(
    data: (list) => list.map((c) => c.code).toList(),
    orElse: () => [],
  );
});
