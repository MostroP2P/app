import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one list of currencies the app knows, fiat and stablecoin alike.
const fiatCatalogueAsset = 'assets/data/fiat.json';

/// A currency entry loaded from [fiatCatalogueAsset].
///
/// A fiat has a [flag]. A stablecoin has none: it carries the fiat it is
/// pegged 1:1 to in [peg] (`USDT` → `USD`), which is what the node prices it
/// from and what its mark shows (DS-TYP-9).
class FiatCurrency {
  const FiatCurrency({
    required this.code,
    required this.name,
    this.flag = '',
    this.peg,
  });

  final String code;
  final String name;

  /// Flag emoji; empty for a stablecoin or a code the catalogue lacks.
  final String flag;

  /// The fiat a stablecoin is pegged to, null for a fiat.
  final String? peg;

  bool get isStablecoin => peg != null;
}

/// Parses the catalogue's JSON. The one parser: every loader reads the same
/// entries, so a field added here is never read in one place and dropped in
/// another. Entries without a code are skipped.
List<FiatCurrency> parseFiatCatalogue(String jsonStr) {
  final List<dynamic> data = json.decode(jsonStr) as List<dynamic>;
  return [
    for (final e in data.cast<Map<String, dynamic>>())
      if ((e['code'] as String?)?.isNotEmpty ?? false)
        FiatCurrency(
          code: e['code'] as String,
          name: (e['name'] as String?) ?? '',
          flag: (e['flag'] as String?) ?? '',
          peg: e['peg'] as String?,
        ),
  ];
}

/// A row of a currency picker: a currency, or the header that opens the
/// stablecoins group.
sealed class CurrencyPickerRow {
  const CurrencyPickerRow();
}

class CurrencyRow extends CurrencyPickerRow {
  const CurrencyRow(this.currency);

  final FiatCurrency currency;
}

class StablecoinsHeaderRow extends CurrencyPickerRow {
  const StablecoinsHeaderRow();
}

/// The rows every currency picker shows for [currencies]: the fiats in their
/// order, then, only when there is at least one, the stablecoins under their
/// own header (issue #884).
List<CurrencyPickerRow> currencyPickerRows(Iterable<FiatCurrency> currencies) {
  final fiats = <CurrencyPickerRow>[];
  final coins = <CurrencyPickerRow>[];
  for (final c in currencies) {
    (c.isStablecoin ? coins : fiats).add(CurrencyRow(c));
  }
  return [
    ...fiats,
    if (coins.isNotEmpty) const StablecoinsHeaderRow(),
    ...coins,
  ];
}

/// Loads the catalogue from the bundled asset.
/// Cached via Riverpod — loaded once per app session.
final fiatCurrenciesProvider = FutureProvider<List<FiatCurrency>>((ref) async {
  return parseFiatCatalogue(await rootBundle.loadString(fiatCatalogueAsset));
});

/// Currency code → flag emoji map, derived from the loaded catalogue. A
/// stablecoin has no entry here: its mark comes from [stablecoinPegsProvider].
final currencyFlagsProvider = Provider<Map<String, String>>((ref) {
  final currencies = ref.watch(fiatCurrenciesProvider);
  return currencies.maybeWhen(
    data:
        (list) => {
          for (final c in list)
            if (c.flag.isNotEmpty) c.code: c.flag,
        },
    orElse: () => {},
  );
});

/// Stablecoin code → the fiat it is pegged to, derived from the loaded
/// catalogue.
final stablecoinPegsProvider = Provider<Map<String, String>>((ref) {
  final currencies = ref.watch(fiatCurrenciesProvider);
  return currencies.maybeWhen(
    data:
        (list) => {
          for (final c in list)
            if (c.peg != null) c.code: c.peg!,
        },
    orElse: () => {},
  );
});

/// All available currency codes, derived from the loaded catalogue.
final availableCurrencyCodesProvider = Provider<List<String>>((ref) {
  final currencies = ref.watch(fiatCurrenciesProvider);
  return currencies.maybeWhen(
    data: (list) => list.map((c) => c.code).toList(),
    orElse: () => [],
  );
});
