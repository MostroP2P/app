import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/notifications/services/device_token.dart';

void main() {
  group('fetchDeviceToken', () {
    test('Android asks FCM directly, never for an APNs token', () async {
      // Arrange
      var apnsAsked = 0;

      // Act
      final token = await fetchDeviceToken(
        waitsForApns: false,
        getApnsToken: () async {
          apnsAsked++;
          return null;
        },
        getToken: () async => 'fcm',
        retryDelay: Duration.zero,
      );

      // Assert
      expect(token, 'fcm');
      expect(apnsAsked, 0);
    });

    test('iOS waits for the APNs token before asking FCM', () async {
      // Arrange: APNs arrives on the third look.
      var looks = 0;
      var fcmAsked = 0;

      // Act
      final token = await fetchDeviceToken(
        waitsForApns: true,
        getApnsToken: () async => ++looks < 3 ? null : 'apns',
        getToken: () async {
          fcmAsked++;
          return 'fcm';
        },
        retryDelay: Duration.zero,
      );

      // Assert
      expect(token, 'fcm');
      expect(looks, 3);
      expect(fcmAsked, 1);
    });

    test('iOS without APNs gives up without asking FCM', () async {
      // Arrange: a build without the aps-environment entitlement, or a
      // device that cannot reach APNs, never receives one.
      var looks = 0;
      var fcmAsked = 0;

      // Act
      final token = await fetchDeviceToken(
        waitsForApns: true,
        getApnsToken: () async {
          looks++;
          return null;
        },
        getToken: () async {
          fcmAsked++;
          return 'fcm';
        },
        retryDelay: Duration.zero,
        apnsAttempts: 4,
      );

      // Assert
      expect(token, isNull);
      expect(looks, 4);
      expect(fcmAsked, 0);
    });

    test('a failing APNs lookup counts as not there yet', () async {
      // Arrange
      var looks = 0;

      // Act
      final token = await fetchDeviceToken(
        waitsForApns: true,
        getApnsToken: () async {
          if (++looks == 1) throw StateError('not yet');
          return 'apns';
        },
        getToken: () async => 'fcm',
        retryDelay: Duration.zero,
      );

      // Assert
      expect(token, 'fcm');
      expect(looks, 2);
    });
  });
}
