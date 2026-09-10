import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/screens/add_order_screen.dart';

void main() {
  group('satsOutOfNodeRange (#282)', () {
    test('returns null when the node advertises no bounds', () {
      expect(satsOutOfNodeRange('5000', null, null), isNull);
    });

    test('returns null when only the min is advertised (needs both)', () {
      expect(satsOutOfNodeRange('100', 500, null), isNull);
    });

    test('returns null when only the max is advertised (needs both)', () {
      expect(satsOutOfNodeRange('999999', null, 500000), isNull);
    });

    test('returns null for non-numeric or empty input', () {
      expect(satsOutOfNodeRange('abc', 500, 500000), isNull);
      expect(satsOutOfNodeRange('', 500, 500000), isNull);
    });

    test('below the minimum returns the accepted range', () {
      expect(satsOutOfNodeRange('300', 500, 500000), (min: 500, max: 500000));
    });

    test('above the maximum returns the accepted range', () {
      expect(
        satsOutOfNodeRange('600000', 500, 500000),
        (min: 500, max: 500000),
      );
    });

    test('exactly at either bound is in range (null)', () {
      expect(satsOutOfNodeRange('500', 500, 500000), isNull);
      expect(satsOutOfNodeRange('500000', 500, 500000), isNull);
    });

    test('inside the range returns null', () {
      expect(satsOutOfNodeRange('5000', 500, 500000), isNull);
    });

    test('amounts beyond the 64-bit int range are still caught (BigInt)', () {
      // 2^63 = 9223372036854775808, one past int64 max. int.tryParse would
      // return null here and fail open; BigInt.tryParse must catch it as
      // above-max instead.
      expect(
        satsOutOfNodeRange('9223372036854775808', 500, 500000),
        (min: 500, max: 500000),
      );
    });

    test('trims surrounding whitespace before parsing', () {
      expect(satsOutOfNodeRange('  300  ', 500, 500000), (min: 500, max: 500000));
    });
  });
}
