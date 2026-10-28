import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/utils/btc_pegged.dart';

void main() {
  group('isBtcPeggedCode', () {
    test('knows the three codes pegged to bitcoin, in any case', () {
      for (final code in ['BTC', 'LBTC', 'RBTC', 'btc', 'Lbtc', 'rbtc']) {
        expect(isBtcPeggedCode(code), isTrue, reason: code);
      }
    });

    test('is false for fiat, stablecoins and look-alikes', () {
      for (final code in ['USD', 'USDT', 'DOC', 'L-BTC', 'WBTC', '']) {
        expect(isBtcPeggedCode(code), isFalse, reason: code);
      }
    });
  });

  group('formatBtcPeggedAmount', () {
    test('shows sats in the asset unit, 8 decimals at most', () {
      // `fa` for these codes counts sats: 100000 is 0.001 RBTC (#907).
      expect(formatBtcPeggedAmount(100000, 'en'), '0.001');
      expect(formatBtcPeggedAmount(1, 'en'), '0.00000001');
      expect(formatBtcPeggedAmount(250000000, 'en'), '2.5');
      expect(formatBtcPeggedAmount(123456789, 'en'), '1.23456789');
      expect(formatBtcPeggedAmount(100000000000, 'en'), '1,000');
    });

    test("uses the locale's separators", () {
      expect(formatBtcPeggedAmount(123456789, 'es'), '1,23456789');
      expect(formatBtcPeggedAmount(100000000000, 'es'), '1.000');
    });
  });
}
