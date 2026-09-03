import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/utils/order_amount_limits.dart';

void main() {
  group('satsFromFiat (#337)', () {
    test('converts at the given rate', () {
      expect(satsFromFiat(1, 50000), 2000);
      expect(satsFromFiat(100, 50000), 200000);
    });

    test('truncates, as the daemon does', () {
      // 1 / 30000 * 1e8 = 3333.33…; the daemon casts to i64, so 3333.
      expect(satsFromFiat(1, 30000), 3333);
    });

    test('saturates instead of overflowing on an absurd amount', () {
      // 1e300 / 50000 * 1e8 overflows to infinity, which truncate() cannot
      // convert; the capped result still reads as out of any node's range.
      expect(satsFromFiat(1e300, 50000), greaterThan(0));
      expect(satsFromFiat(double.infinity, 50000), greaterThan(0));
    });

    test('reports a conversion that is not a number as 0 sats', () {
      expect(satsFromFiat(double.nan, 50000), 0);
    });
  });

  group('wireFiatAmount (#337)', () {
    /// `new_order` casts the fiat amount to `i64`, so the daemon prices the
    /// whole unit, never the decimal the user typed.
    test('truncates to the whole unit the wire carries', () {
      expect(wireFiatAmount(1.1), 1);
      expect(wireFiatAmount(100.9), 100);
      expect(wireFiatAmount(100), 100);
      expect(wireFiatAmount(0.9), 0);
    });
  });

  group('fiatAmountLimits (#337)', () {
    test('converts the node bounds to whole fiat units', () {
      final limits =
          fiatAmountLimits(minSats: 200000, maxSats: 500000, rate: 50000);

      expect(limits.minFiat, 100);
      expect(limits.maxFiat, 250);
      expect(limits.isDisplayable, isTrue);
    });

    test('floors the minimum at 1, since the field takes whole numbers', () {
      final limits =
          fiatAmountLimits(minSats: 100, maxSats: 500000, rate: 50000);

      expect(limits.minFiat, 1);
    });

    test('is not displayable when the range collapses below one fiat unit', () {
      // 100–1000 sats is 0.05–0.5 USD at 50k: no whole number fits.
      final limits =
          fiatAmountLimits(minSats: 100, maxSats: 1000, rate: 50000);

      expect(limits.isDisplayable, isFalse);
    });

    test('is not displayable without a usable rate', () {
      expect(
        fiatAmountLimits(minSats: 100, maxSats: 500000, rate: 0).isDisplayable,
        isFalse,
      );
    });

    test('is not displayable for a non-finite rate', () {
      for (final rate in [double.infinity, double.negativeInfinity, double.nan]) {
        expect(
          fiatAmountLimits(minSats: 200000, maxSats: 500000, rate: rate)
              .isDisplayable,
          isFalse,
          reason: 'rate $rate must not reach ceil()/floor()',
        );
      }
    });

    /// The acceptance criterion of #337: a bound shown to the user must never
    /// be one the daemon rejects. Guaranteed by rounding the minimum up and
    /// the maximum down, and checked here against the same conversion the
    /// daemon performs.
    test('every whole fiat value in the shown range is inside the sats range',
        () {
      const cases = [
        (min: 100, max: 500000, rate: 50000.0),
        (min: 1000, max: 20000000, rate: 12345.67),
        (min: 4321, max: 987654, rate: 1000000.0),
        (min: 100, max: 500000, rate: 0.37),
      ];

      for (final c in cases) {
        final limits =
            fiatAmountLimits(minSats: c.min, maxSats: c.max, rate: c.rate);
        if (!limits.isDisplayable) continue;

        for (final fiat in [
          limits.minFiat,
          limits.minFiat + 1,
          (limits.minFiat + limits.maxFiat) ~/ 2,
          limits.maxFiat - 1,
          limits.maxFiat,
        ].where((f) => f >= limits.minFiat && f <= limits.maxFiat)) {
          final sats = satsFromFiat(fiat.toDouble(), c.rate);
          expect(
            sats,
            inInclusiveRange(c.min, c.max),
            reason: '$fiat fiat at rate ${c.rate} priced $sats sats, outside '
                '${c.min}–${c.max}',
          );
        }
      }
    });
  });

  group('fiatOutOfNodeRange (#337)', () {
    test('returns null when the node advertises no bounds', () {
      expect(fiatOutOfNodeRange('100', null, null, 50000), isNull);
    });

    test('returns null when only one bound is advertised', () {
      expect(fiatOutOfNodeRange('100', 200000, null, 50000), isNull);
      expect(fiatOutOfNodeRange('100', null, 500000, 50000), isNull);
    });

    test('returns null without a usable rate — the daemon still decides', () {
      expect(fiatOutOfNodeRange('1', 200000, 500000, null), isNull);
      expect(fiatOutOfNodeRange('1', 200000, 500000, 0), isNull);
      expect(fiatOutOfNodeRange('1', 200000, 500000, -50000), isNull);
    });

    test('returns null for a non-numeric or non-positive amount', () {
      expect(fiatOutOfNodeRange('abc', 200000, 500000, 50000), isNull);
      expect(fiatOutOfNodeRange('', 200000, 500000, 50000), isNull);
      expect(fiatOutOfNodeRange('0', 200000, 500000, 50000), isNull);
      expect(fiatOutOfNodeRange('-10', 200000, 500000, 50000), isNull);
    });

    test('returns null for an amount inside the range', () {
      // 100 USD at 50k = 200000 sats, the node's minimum.
      expect(fiatOutOfNodeRange('100', 200000, 500000, 50000), isNull);
      expect(fiatOutOfNodeRange('250', 200000, 500000, 50000), isNull);
    });

    test('below the minimum returns both the sats and the fiat range', () {
      final error = fiatOutOfNodeRange('50', 200000, 500000, 50000);

      expect(error, isNotNull);
      expect(error!.minSats, 200000);
      expect(error.maxSats, 500000);
      expect(error.limits.minFiat, 100);
      expect(error.limits.maxFiat, 250);
    });

    test('above the maximum returns the accepted range', () {
      final error = fiatOutOfNodeRange('300', 200000, 500000, 50000);

      expect(error, isNotNull);
      expect(error!.limits.isDisplayable, isTrue);
    });

    test('reports a collapsed fiat range as not displayable', () {
      // The whole 100–1000 sats range is under 1 USD, so the caller must fall
      // back to showing sats.
      final error = fiatOutOfNodeRange('5', 100, 1000, 50000);

      expect(error, isNotNull);
      expect(error!.limits.isDisplayable, isFalse);
      expect(error.minSats, 100);
      expect(error.maxSats, 1000);
    });

    test('accepts a decimal amount, as the field does', () {
      expect(fiatOutOfNodeRange('100.5', 200000, 500000, 50000), isNull);
      expect(fiatOutOfNodeRange('0.5', 200000, 500000, 50000), isNotNull);
    });

    /// The decimal never reaches the daemon: `new_order` casts the fiat amount
    /// to `i64`. Judging the untruncated value would accept 1.1 as 3666 sats
    /// and let the daemon reject the 1 it actually receives, priced at 3333.
    test('judges the truncated amount the wire carries, not the decimal', () {
      expect(fiatOutOfNodeRange('1.1', 3334, 500000, 30000), isNotNull);
      expect(fiatOutOfNodeRange('2.9', 3334, 500000, 30000), isNull);
    });

    test('returns null for a non-finite amount, which the form rejects', () {
      for (final amount in ['Infinity', '-Infinity', 'NaN', '1e309']) {
        expect(
          fiatOutOfNodeRange(amount, 200000, 500000, 50000),
          isNull,
          reason: '$amount must not reach truncate()',
        );
      }
    });

    test('returns null for a non-finite rate', () {
      for (final rate in [double.infinity, double.negativeInfinity, double.nan]) {
        expect(fiatOutOfNodeRange('100', 200000, 500000, rate), isNull);
      }
    });
  });
}
