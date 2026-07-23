import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/utils/platform_int64.dart';

void main() {
  group('platformInt64ToInt', () {
    test('returns the value unchanged when it is already an int (native)', () {
      // Arrange
      const dynamic value = 1721764800;

      // Act
      final result = platformInt64ToInt(value);

      // Assert
      expect(result, 1721764800);
      expect(result, isA<int>());
    });

    test('converts a BigInt to int (web/dart2js representation)', () {
      // Arrange
      final dynamic value = BigInt.from(1721764800);

      // Act
      final result = platformInt64ToInt(value);

      // Assert
      expect(result, 1721764800);
      expect(result, isA<int>());
    });

    test('result is usable in int arithmetic (guards the LUB regression)', () {
      // A ternary that does not cast the else branch yields `Object`, which
      // fails to compile in arithmetic. This asserts the helper returns a
      // usable int for both input representations.
      final fromInt = platformInt64ToInt(100);
      final fromBigInt = platformInt64ToInt(BigInt.from(40));

      expect(fromInt - fromBigInt, 60);
    });
  });

  group('intToPlatformInt64', () {
    test('returns an int on native (kIsWeb is false under the VM test runner)',
        () {
      // Act
      final result = intToPlatformInt64(1721764800);

      // Assert
      expect(result, 1721764800);
      expect(result, isA<int>());
    });
  });
}
