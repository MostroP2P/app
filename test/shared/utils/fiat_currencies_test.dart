import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/utils/btc_pegged.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';

void main() {
  group('parseFiatCatalogue', () {
    test('reads a fiat with its flag and a stablecoin with its peg', () {
      const json = '''
[
  {"code": "USD", "name": "US Dollar", "flag": "🇺🇸"},
  {"code": "USDT", "name": "Tether USD", "peg": "USD"},
  {"code": "RBTC", "name": "RBTC (Rootstock)", "peg": "BTC"},
  {"code": "", "name": "dropped"}
]''';

      final entries = parseFiatCatalogue(json);

      expect(entries.map((e) => e.code), ['USD', 'USDT', 'RBTC']);
      expect(entries[0].flag, '🇺🇸');
      expect(entries[0].isPegged, isFalse);
      expect(entries[0].isStablecoin, isFalse);
      expect(entries[1].flag, isEmpty);
      expect(entries[1].peg, 'USD');
      expect(entries[1].isPegged, isTrue);
      expect(entries[1].isStablecoin, isTrue);
      expect(entries[1].isBtcPegged, isFalse);
      // Bitcoin on another network: pegged, but not a stablecoin (#907).
      expect(entries[2].peg, 'BTC');
      expect(entries[2].isPegged, isTrue);
      expect(entries[2].isBtcPegged, isTrue);
      expect(entries[2].isStablecoin, isFalse);
    });
  });

  group('the bundled catalogue', () {
    final entries = parseFiatCatalogue(
      File('assets/data/fiat.json').readAsStringSync(),
    );

    test('lists the three dollar stablecoins pegged to a fiat it knows', () {
      final fiats = {
        for (final e in entries)
          if (!e.isPegged) e.code,
      };
      final coins = {
        for (final e in entries)
          if (e.isStablecoin) e.code: e,
      };

      expect(coins.keys, containsAll(['USDT', 'USDC', 'DOC']));
      for (final coin in coins.values) {
        expect(fiats, contains(coin.peg), reason: '${coin.code} peg');
        expect(coin.flag, isEmpty, reason: '${coin.code} has no flag');
      }
    });

    test('gives every fiat a flag and no peg', () {
      for (final e in entries.where((e) => !e.isPegged)) {
        expect(e.flag, isNotEmpty, reason: e.code);
      }
    });

    test('lists bitcoin on other networks, pegged to BTC (#907)', () {
      final btcPegged = entries.where((e) => e.isBtcPegged).toList();

      // The same codes pure formatting code knows without the catalogue.
      expect(btcPegged.map((e) => e.code).toSet(), btcPeggedCodes);
      for (final e in btcPegged) {
        expect(e.flag, isEmpty, reason: '${e.code} has no flag');
        expect(e.name, isNotEmpty, reason: e.code);
      }
    });

    test(
      'is read by one parser only, so both pickers see the same entries',
      () {
        // The Settings dialog used to have a loader of its own; a field read
        // in one and dropped in the other was the failure (issue #884).
        final loaders = Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where(
              (f) => f.readAsStringSync().contains("'assets/data/fiat.json'"),
            )
            .map((f) => f.path);
        expect(loaders, ['lib/shared/utils/fiat_currencies.dart']);
      },
    );
  });

  group('currencyPickerRows', () {
    const usd = FiatCurrency(code: 'USD', name: 'US Dollar', flag: '🇺🇸');
    const ars = FiatCurrency(code: 'ARS', name: 'Peso', flag: '🇦🇷');
    const usdt = FiatCurrency(code: 'USDT', name: 'Tether USD', peg: 'USD');
    const rbtc = FiatCurrency(code: 'RBTC', name: 'RBTC', peg: 'BTC');

    test('puts the stablecoins after the fiats, under a header', () {
      final rows = currencyPickerRows([usdt, usd, ars]);

      expect(rows, hasLength(4));
      expect((rows[0] as CurrencyRow).currency, usd);
      expect((rows[1] as CurrencyRow).currency, ars);
      expect(rows[2], isA<StablecoinsHeaderRow>());
      expect((rows[3] as CurrencyRow).currency, usdt);
    });

    test('puts bitcoin on other networks last, under its own header', () {
      final rows = currencyPickerRows([rbtc, usdt, usd]);

      expect(rows, hasLength(5));
      expect((rows[0] as CurrencyRow).currency, usd);
      expect(rows[1], isA<StablecoinsHeaderRow>());
      expect((rows[2] as CurrencyRow).currency, usdt);
      expect(rows[3], isA<BitcoinNetworksHeaderRow>());
      expect((rows[4] as CurrencyRow).currency, rbtc);
    });

    test('shows no header when no stablecoin is offered', () {
      final rows = currencyPickerRows([usd, ars]);

      expect(rows.whereType<StablecoinsHeaderRow>(), isEmpty);
      expect(rows.whereType<BitcoinNetworksHeaderRow>(), isEmpty);
      expect(rows, hasLength(2));
    });
  });
}
