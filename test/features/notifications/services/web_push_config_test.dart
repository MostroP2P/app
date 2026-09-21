import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/notifications/services/web_push_config.dart';

void main() {
  group('webPushAvailable', () {
    test('a browser with push, a VAPID key and the flag on can push', () {
      // Arrange / Act
      final available = webPushAvailable(
        enabled: true,
        vapidKey: 'BExampleKey',
        browserSupportsPush: true,
      );

      // Assert
      expect(available, isTrue);
    });

    test('the flag stays off until the push server accepts web', () {
      // Arrange / Act — mostro-push-server#44 (docs/PUSH_NOTIFICATIONS.md §3.5)
      final available = webPushAvailable(
        enabled: false,
        vapidKey: 'BExampleKey',
        browserSupportsPush: true,
      );

      // Assert
      expect(available, isFalse);
    });

    test('a build without a VAPID key cannot ask for a token', () {
      // Arrange / Act — a fork that never set FCM_VAPID_KEY
      final available = webPushAvailable(
        enabled: true,
        vapidKey: '',
        browserSupportsPush: true,
      );

      // Assert
      expect(available, isFalse);
    });

    test('a browser without Notification or PushManager cannot push', () {
      // Arrange / Act — Safari outside an installed PWA, for one
      final available = webPushAvailable(
        enabled: true,
        vapidKey: 'BExampleKey',
        browserSupportsPush: false,
      );

      // Assert
      expect(available, isFalse);
    });
  });

  test('the production build keeps web push off', () {
    // Arrange / Act / Assert — only a build that passes PUSH_WEB_ENABLED
    // turns it on; the test run passes nothing.
    expect(kPushWebEnabled, isFalse);
  });
}
