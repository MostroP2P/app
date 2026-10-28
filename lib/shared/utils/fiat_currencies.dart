import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The one list of currencies the app knows: fiat, stablecoins and bitcoin
/// on other networks alike.
const fiatCatalogueAsset = 'assets/data/fiat.json';

/// A currency entry loaded from [fiatCatalogueAsset].
///
/// A fiat has a [flag]. A pegged code has none: it carries what it is pegged
/// 1:1 to in [peg], which is what the node prices it from and what its mark
/// shows (DS-TYP-9). That is a fiat for a stablecoin (`USDT` → `USD`), or
/// `BTC` for bitcoin on another network (`RBTC` → `BTC`, #907), whose amounts
/// count sats.
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

  /// What a pegged code is pegged to, null for a fiat.
  final String? peg;

  /// Pegged to anything: drives the Market lock, which applies to every code
  /// a node may or may not quote.
  bool get isPegged => peg != null;

  /// Pegged to bitcoin itself: on-chain BTC, L-BTC or RBTC (#907).
  bool get isBtcPegged => peg == btcPeg;

  /// Pegged to a fiat.
  bool get isStablecoin => isPegged && !isBtcPegged;
}

/// The [FiatCurrency.peg] of bitcoin on another network.
const btcPeg = 'BTC';

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

/// A row of a currency picker: a currency, or the header that opens one of
/// the pegged groups.
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

class BitcoinNetworksHeaderRow extends CurrencyPickerRow {
  const BitcoinNetworksHeaderRow();
}

/// The rows every currency picker shows for [currencies]: the fiats in their
/// order, then, each only when it has at least one entry, the stablecoins
/// under their own header (issue #884) and bitcoin on other networks under
/// theirs (#907).
List<CurrencyPickerRow> currencyPickerRows(Iterable<FiatCurrency> currencies) {
  final fiats = <CurrencyPickerRow>[];
  final coins = <CurrencyPickerRow>[];
  final networks = <CurrencyPickerRow>[];
  for (final c in currencies) {
    (c.isBtcPegged
            ? networks
            : c.isStablecoin
            ? coins
            : fiats)
        .add(CurrencyRow(c));
  }
  return [
    ...fiats,
    if (coins.isNotEmpty) const StablecoinsHeaderRow(),
    ...coins,
    if (networks.isNotEmpty) const BitcoinNetworksHeaderRow(),
    ...networks,
  ];
}

/// Loads the catalogue from the bundled asset.
/// Cached via Riverpod — loaded once per app session.
final fiatCurrenciesProvider = FutureProvider<List<FiatCurrency>>((ref) async {
  return parseFiatCatalogue(await rootBundle.loadString(fiatCatalogueAsset));
});

/// Currency code → flag emoji map, derived from the loaded catalogue. A
/// pegged code has no entry here: its mark comes from [currencyPegsProvider].
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

/// Pegged code → what it is pegged to, stablecoins and bitcoin on other
/// networks alike, derived from the loaded catalogue. Their mark is drawn
/// from it (DS-TYP-9).
final currencyPegsProvider = Provider<Map<String, String>>((ref) {
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

/// Stablecoin code → the fiat it is pegged to, derived from the loaded
/// catalogue. Bitcoin on other networks is not in it (#907): it is grouped,
/// unit-counted and explained apart.
final stablecoinPegsProvider = Provider<Map<String, String>>((ref) {
  final currencies = ref.watch(fiatCurrenciesProvider);
  return currencies.maybeWhen(
    data:
        (list) => {
          for (final c in list)
            if (c.isStablecoin) c.code: c.peg!,
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
