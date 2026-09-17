import 'dart:async';
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
  int cleared = 0;
  final statusRequested = Completer<void>();
  final statusGate = Completer<PushStatus>();
  @override
  Future<PushStatus> crateApiPushGetPushStatus() async {
    statusRequested.complete();
    return statusGate.future;
  }

  @override
  Future<void> crateApiPushSetPushToken({
    required String token,
    required PushPlatform platform,
  }) async {
    tokens++;
  }

  @override
  Future<void> crateApiPushClearPushToken() async {
    cleared++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Messaging extends FirebaseMessagingPlatform {
  bool denied = false;
  final refresh = StreamController<String>.broadcast();
  int tokenRequests = 0;
  int permissionChecks = 0;

  /// Thrown by the next permission request, then cleared.
  Object? permissionError;
  Completer<String?>? tokenGate;
  Completer<void>? tokenRequested;
  bool hasDeviceToken = false;
  NotificationSettings get settings => NotificationSettings(
    authorizationStatus:
        denied ? AuthorizationStatus.denied : AuthorizationStatus.authorized,
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
  }) async {
    permissionChecks++;
    final error = permissionError;
    if (error != null) {
      permissionError = null;
      throw error;
    }
    return settings;
  }

  @override
  Future<NotificationSettings> getNotificationSettings() async {
    permissionChecks++;
    return settings;
  }

  @override
  Future<void> registerBackgroundMessageHandler(
    BackgroundMessageHandler handler,
  ) async {}
  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Future<String?> getToken({String? vapidKey}) async {
    tokenRequests++;
    tokenRequested?.complete();
    final token = tokenGate == null ? 'test-token' : await tokenGate!.future;
    hasDeviceToken = token != null;
    return token;
  }

  @override
  Future<RemoteMessage?> getInitialMessage() async => null;
  @override
  Future<void> deleteToken() async {
    hasDeviceToken = false;
  }

  @override
  Future<void> setAutoInitEnabled(bool enabled) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();
  test(
    'startup opt-out and permission changes gate token delivery and recovery',
    () async {
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
      final service = PushNotificationService.instance;
      WorkmanagerPlatform.instance = WorkmanagerAndroid();
      // Setup that fails before any listener is attached must not leave the
      // service stuck: a later retry runs the whole initialization again.
      messaging.permissionError = Exception('permission request failed');
      await service.initialize();
      messaging.refresh.add('token-before-listeners');
      await Future<void>.delayed(Duration.zero);
      expect(api.tokens, 0);
      expect(api.statusRequested.isCompleted, isFalse);
      final initialized = service.retryInitialize();
      await api.statusRequested.future;
      final retriedDuringStartup = service.retryInitialize();
      messaging.refresh.add('rotated-test-token');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(messaging.tokenRequests, 0);
      api.statusGate.complete(
        const PushStatus(
          enabled: false,
          hasToken: false,
          registered: 0,
          wanted: 0,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await initialized;
      await retriedDuringStartup;
      expect(api.tokens, 0, reason: 'The persisted master setting is off');
      expect(messaging.tokenRequests, 0);

      await service.reacquire();
      expect(messaging.tokenRequests, 1);
      expect(api.tokens, 1);
      await service.release();

      messaging.denied = true;
      final before = messaging.tokenRequests;
      final cleared = api.cleared;
      await service.reacquire();
      expect(messaging.tokenRequests, before);
      expect(api.cleared, greaterThan(cleared));
      messaging.refresh.add('refresh-while-denied');
      await Future<void>.delayed(Duration.zero);
      expect(api.tokens, 1);
      await service.retryInitialize();
      expect(messaging.tokenRequests, before);

      messaging.denied = false;
      await service.retryInitialize();
      expect(messaging.tokenRequests, before + 1);
      expect(api.tokens, 2);
      messaging.refresh.add('refresh-after-grant');
      await Future<void>.delayed(Duration.zero);
      expect(
        api.tokens,
        3,
        reason: 'Exactly one listener survives permission changes',
      );

      await service.release();
      await service.retryInitialize();
      messaging.refresh.add('refresh-after-opt-out');
      await Future<void>.delayed(Duration.zero);
      expect(messaging.tokenRequests, before + 1);
      expect(api.tokens, 3);

      // Permission recovery/startup and opt-out share the device queue too:
      // a token acquisition finishing late must precede the final deletion.
      messaging.tokenGate = Completer<String?>();
      messaging.tokenRequested = Completer<void>();
      final acquiring = service.reacquire();
      await messaging.tokenRequested!.future;
      final releasing = service.release();
      messaging.tokenGate!.complete('late-token');
      await Future.wait([acquiring, releasing]);
      expect(messaging.hasDeviceToken, isFalse);
      expect(
        api.tokens,
        3,
        reason: 'Opt-out blocks an in-flight token handoff',
      );
      await messaging.refresh.close();
    },
  );
}
