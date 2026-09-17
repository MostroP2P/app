import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/notifications/services/push_notification_service.dart';
import 'package:mostro/src/rust/api/types.dart';

void main() {
  group('platformFor', () {
    test('Android and iOS are the platforms the push server accepts', () {
      expect(platformFor(false, TargetPlatform.android), PushPlatform.android);
      expect(platformFor(false, TargetPlatform.iOS), PushPlatform.ios);
    });

    test('desktop has no push transport', () {
      for (final p in [
        TargetPlatform.linux,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      ]) {
        expect(platformFor(false, p), isNull, reason: '$p');
      }
    });

    test('web is held back until web push is available (T4.5)', () {
      // A browser reports whatever host platform it runs on; `isWeb` wins.
      expect(platformFor(true, TargetPlatform.android), isNull);
      expect(platformFor(true, TargetPlatform.macOS), isNull);
    });

    test('web pushes as web once available, whatever the host OS', () {
      expect(
        platformFor(true, TargetPlatform.android, webPush: true),
        PushPlatform.web,
      );
      expect(
        platformFor(true, TargetPlatform.macOS, webPush: true),
        PushPlatform.web,
      );
    });

    test('web push availability means nothing off web', () {
      expect(
        platformFor(false, TargetPlatform.linux, webPush: true),
        isNull,
      );
      expect(
        platformFor(false, TargetPlatform.android, webPush: true),
        PushPlatform.android,
      );
    });
  });
}
