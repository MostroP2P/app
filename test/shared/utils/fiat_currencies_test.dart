import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';

void main() {
  group('parseFiatCatalogue', () {
    test('reads a fiat with its flag and a stablecoin with its peg', () {
      const json = '''
[
  {"code": "USD", "name": "US Dollar", "flag": "🇺🇸"},
  {"code": "USDT", "name": "Tether USD", "peg": "USD"},
  {"code": "", "name": "dropped"}
]''';

      final entries = parseFiatCatalogue(json);

      expect(entries.map((e) => e.code), ['USD', 'USDT']);
      expect(entries[0].flag, '🇺🇸');
      expect(entries[0].isStablecoin, isFalse);
      expect(entries[1].flag, isEmpty);
      expect(entries[1].peg, 'USD');
      expect(entries[1].isStablecoin, isTrue);
    });
  });

  group('the bundled catalogue', () {
    final entries = parseFiatCatalogue(
      File('assets/data/fiat.json').readAsStringSync(),
    );

    test('lists the three dollar stablecoins pegged to a fiat it knows', () {
      final fiats = {
        for (final e in entries)
          if (!e.isStablecoin) e.code,
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
      for (final e in entries.where((e) => !e.isStablecoin)) {
        expect(e.flag, isNotEmpty, reason: e.code);
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

    test('puts the stablecoins after the fiats, under a header', () {
      final rows = currencyPickerRows([usdt, usd, ars]);

      expect(rows, hasLength(4));
      expect((rows[0] as CurrencyRow).currency, usd);
      expect((rows[1] as CurrencyRow).currency, ars);
      expect(rows[2], isA<StablecoinsHeaderRow>());
      expect((rows[3] as CurrencyRow).currency, usdt);
    });

    test('shows no header when no stablecoin is offered', () {
      final rows = currencyPickerRows([usd, ars]);

      expect(rows.whereType<StablecoinsHeaderRow>(), isEmpty);
      expect(rows, hasLength(2));
    });
  });
}
