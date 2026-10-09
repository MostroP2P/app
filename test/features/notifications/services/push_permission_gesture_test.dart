import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
// Firebase's official test adapters are supplied by the resolved plugins.
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_messaging_platform_interface/firebase_messaging_platform_interface.dart';
import 'package:mostro/features/notifications/services/push_notification_service.dart';
import 'package:mostro/src/rust/frb_generated.dart';
import 'package:mostro/src/rust/api/types.dart';
// Use the Android channel implementation so the host test never runs systemd.
// ignore: depend_on_referenced_packages
import 'package:workmanager_android/workmanager_android.dart';
// ignore: depend_on_referenced_packages
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

class _Api implements RustLibApi {
  int tokens = 0;

  @override
  Future<PushStatus> crateApiPushGetPushStatus() async => const PushStatus(
    enabled: true,
    hasToken: false,
    registered: 0,
    wanted: 0,
  );

  @override
  Future<void> crateApiPushSetPushToken({
    required String token,
    required PushPlatform platform,
  }) async {
    tokens++;
  }

  @override
  Future<void> crateApiPushClearPushToken() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A browser's permission: `default` until a prompt is answered.
class _Messaging extends FirebaseMessagingPlatform {
  AuthorizationStatus status = AuthorizationStatus.notDetermined;

  /// What the user answers the next prompt with.
  AuthorizationStatus answer = AuthorizationStatus.authorized;
  int prompts = 0;
  int tokenRequests = 0;

  NotificationSettings get settings => NotificationSettings(
    authorizationStatus: status,
    alert: AppleNotificationSetting.enabled,
    announcement: AppleNotificationSetting.enabled,
    badge: AppleNotificationSetting.enabled,
    carPlay: AppleNotificationSetting.enabled,
    lockScreen: AppleNotificationSetting.enabled,
    notificationCenter: AppleNotificationSetting.enabled,
    showPreviews: AppleShowPreviewSetting.always,
    timeSensitive: AppleNotificationSetting.enabled,
    criticalAlert: AppleNotificationSetting.enabled,
    sound: AppleNotificationSetting.enabled,
    providesAppNotificationSettings: AppleNotificationSetting.enabled,
  );

  @override
  FirebaseMessagingPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseMessagingPlatform setInitialValues({bool? isAutoInitEnabled}) => this;

  /// Counted synchronously, like the browser call the web plugin makes
  /// before its first await.
  @override
  Future<NotificationSettings> requestPermission({
    bool alert = true,
    bool announcement = false,
    bool badge = true,
    bool carPlay = false,
    bool criticalAlert = false,
    bool provisional = false,
    bool sound = true,
    bool providesAppNotificationSettings = false,
  }) {
    // A prompt shows only while the permission is unanswered; after that
    // the browser returns the stored answer.
    if (status == AuthorizationStatus.notDetermined) {
      prompts++;
      status = answer;
    }
    return Future.value(settings);
  }

  @override
  Future<NotificationSettings> getNotificationSettings() async => settings;
  @override
  Future<void> registerBackgroundMessageHandler(
    BackgroundMessageHandler handler,
  ) async {}
  @override
  Stream<String> get onTokenRefresh => const Stream.empty();
  @override
  Future<String?> getToken({String? vapidKey}) async {
    tokenRequests++;
    return 'test-token';
  }

  @override
  Future<RemoteMessage?> getInitialMessage() async => null;
  @override
  Future<void> deleteToken() async {}
  @override
  Future<void> setAutoInitEnabled(bool enabled) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  test('a prompt that needs a gesture is asked only from the tap, and a grant '
      'starts push', () async {
    // Arrange — a browser: the prompt shows only from a user gesture.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (call) async =>
              call.method == 'getNotificationAppLaunchDetails'
                  ? {'notificationLaunchedApp': false}
                  : true,
        );
    await Firebase.initializeApp();
    final messaging = _Messaging();
    FirebaseMessagingPlatform.instance = messaging;
    final api = _Api();
    RustLib.initMock(api: api);
    WorkmanagerPlatform.instance = WorkmanagerAndroid();
    final service = PushNotificationService.instance..promptNeedsGesture = true;

    // Act — startup.
    await service.initialize();

    // Assert — no prompt from startup, so no token either; Settings is told
    // to offer the tap.
    expect(messaging.prompts, 0);
    expect(messaging.tokenRequests, 0);
    expect(api.tokens, 0);
    expect(await service.awaitsPermissionFromGesture(), isTrue);

    // Act — the user dismisses the prompt without answering.
    messaging.answer = AuthorizationStatus.notDetermined;
    await service.requestPermissionFromGesture();

    // Assert — still nothing, and the tap is still offered.
    expect(messaging.tokenRequests, 0);
    expect(await service.awaitsPermissionFromGesture(), isTrue);

    // Act — a second tap, granted.
    messaging
      ..status = AuthorizationStatus.notDetermined
      ..answer = AuthorizationStatus.authorized;
    final prompts = messaging.prompts;
    final asked = service.requestPermissionFromGesture();

    // Assert — the prompt went out before anything was awaited, while the
    // tap's user activation lasts.
    expect(messaging.prompts, prompts + 1);
    await asked;
    expect(messaging.tokenRequests, 1);
    expect(api.tokens, 1);
    expect(await service.awaitsPermissionFromGesture(), isFalse);
  });
}
