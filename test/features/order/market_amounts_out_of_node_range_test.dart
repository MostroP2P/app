import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/screens/add_order_screen.dart';

void main() {
  // The node used throughout: 200000–500000 sats, which at 50000 per BTC is
  // 100–250 units of fiat.
  const minSats = 200000;
  const maxSats = 500000;
  const rate = 50000.0;

  group('marketAmountsOutOfNodeRange (#337)', () {
    test('returns null for a single amount inside the range', () {
      expect(
        marketAmountsOutOfNodeRange(['150'], minSats, maxSats, rate),
        isNull,
      );
    });

    test('returns the range for a single amount outside it', () {
      final error =
          marketAmountsOutOfNodeRange(['500'], minSats, maxSats, rate);

      expect(error, isNotNull);
      expect(error!.minSats, minSats);
      expect(error.limits.minFiat, 100);
      expect(error.limits.maxFiat, 250);
    });

    test('accepts a range order with both ends inside', () {
      expect(
        marketAmountsOutOfNodeRange(['100', '250'], minSats, maxSats, rate),
        isNull,
      );
    });

    /// The daemon prices every amount of a range order and rejects the order
    /// if any one is out of range, so a valid minimum must not carry an
    /// invalid maximum past the check.
    test('rejects a range order whose maximum is out of range', () {
      expect(
        marketAmountsOutOfNodeRange(['100', '400'], minSats, maxSats, rate),
        isNotNull,
      );
    });

    test('rejects a range order whose minimum is out of range', () {
      expect(
        marketAmountsOutOfNodeRange(['10', '250'], minSats, maxSats, rate),
        isNotNull,
      );
    });

    test('ignores an empty field, so a half-typed range is not flagged', () {
      expect(
        marketAmountsOutOfNodeRange(['100', ''], minSats, maxSats, rate),
        isNull,
      );
    });

    test('fails open without a rate', () {
      expect(
        marketAmountsOutOfNodeRange(['500'], minSats, maxSats, null),
        isNull,
      );
    });

    test('fails open when the node advertises no bounds', () {
      expect(marketAmountsOutOfNodeRange(['500'], null, null, rate), isNull);
    });

    test('fails open on a non-finite amount, which the form rejects', () {
      for (final amount in ['Infinity', '-Infinity', 'NaN']) {
        expect(
          marketAmountsOutOfNodeRange([amount], minSats, maxSats, rate),
          isNull,
          reason: '$amount must not reach truncate()',
        );
      }
    });
  });

  group('enteredAmount (#337)', () {
    test('returns the amount for a submittable value', () {
      expect(enteredAmount('150'), 150);
      expect(enteredAmount(' 150.5 '), 150.5);
    });

    test('rejects a non-numeric or non-positive value', () {
      expect(enteredAmount(''), isNull);
      expect(enteredAmount('abc'), isNull);
      expect(enteredAmount('0'), isNull);
      expect(enteredAmount('-10'), isNull);
    });

    /// Nothing filters the amount fields' input, so these can be pasted in.
    /// They parse as doubles and pass a bare positivity check, then throw in
    /// the sats conversion while the screen is building.
    test('rejects a non-finite value', () {
      expect(enteredAmount('Infinity'), isNull);
      expect(enteredAmount('-Infinity'), isNull);
      expect(enteredAmount('NaN'), isNull);
      expect(enteredAmount('1e309'), isNull);
    });
  });
}
