import 'dart:io';
import 'dart:ui' show Locale;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/notifications/services/local_notifications.dart';
import 'package:mostro/features/notifications/services/push_background_handler.dart';
import 'package:mostro/features/settings/providers/notification_prefs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('the background handler is display-only', () {
    test('its file imports no bridge, database, state or navigation code', () {
      // docs/PUSH_NOTIFICATIONS.md §6 principle 2 (issue #308): the push is
      // a doorbell, not a courier. Held down here, where it would rot.
      final source =
          File(
            'lib/features/notifications/services/push_background_handler.dart',
          ).readAsStringSync();
      final imports =
          RegExp(
            r"^import '([^']+)';",
            multiLine: true,
          ).allMatches(source).map((m) => m.group(1)!).toList();

      for (final forbidden in [
        'src/rust/',
        'sembast',
        'sqflite',
        'riverpod',
        'go_router',
        'app_routes',
        'notifications_provider',
        'dart:io',
      ]) {
        expect(
          imports.where((i) => i.contains(forbidden)),
          isEmpty,
          reason: 'the background handler must not import $forbidden',
        );
      }
    });

    test('a wake sets the flag, and the resume consumes it once', () async {
      // Arrange
      SharedPreferences.setMockInitialValues({});
      expect(await consumeWakePending(), isFalse);

      // Act — a push while the app is in the background.
      await pushBackgroundHandler(
        const RemoteMessage(data: {'type': 'trade_update'}),
      );

      // Assert — one flag, consumed once.
      expect(await consumeWakePending(), isTrue);
      expect(await consumeWakePending(), isFalse);
    });

    test('ten pushes cost one resync: the flag is not a counter', () async {
      SharedPreferences.setMockInitialValues({});
      for (var i = 0; i < 10; i++) {
        await pushBackgroundHandler(const RemoteMessage(data: {'type': 'x'}));
      }
      expect(await consumeWakePending(), isTrue);
      expect(await consumeWakePending(), isFalse);
    });
  });

  group('a peer chat wake', () {
    late List<(String, String)> shown;
    Future<void> record(String title, String body) async =>
        shown.add((title, body));

    setUp(() => shown = []);

    test('shows one content-free notice in the stored language', () async {
      SharedPreferences.setMockInitialValues({kLanguagePrefKey: 'es-MX'});

      await handleBackgroundWake({'type': kChatWakeType}, show: record);

      expect(shown, [('Mostro', 'Tienes un mensaje nuevo')]);
      expect(await consumeWakePending(), isTrue, reason: 'still a wake');
    });

    test(
      'an unset or unshipped language follows the device, like Settings',
      () {
        const device = [Locale('pt', 'BR'), Locale('fr')];

        expect(chatWakeLanguage(null, deviceLocales: device), 'fr');
        expect(chatWakeLanguage('pt', deviceLocales: device), 'fr');
        expect(chatWakeLanguage('de-AT', deviceLocales: device), 'de');
        expect(
          chatWakeLanguage(null, deviceLocales: const [Locale('pt')]),
          'en',
          reason: 'English when the device offers nothing the app ships',
        );
      },
    );

    test('is silent when message notifications are turned off', () async {
      SharedPreferences.setMockInitialValues({kNewMessagesPrefKey: false});

      await handleBackgroundWake({'type': kChatWakeType}, show: record);

      expect(shown, isEmpty);
      expect(
        await consumeWakePending(),
        isTrue,
        reason: 'the resync still runs',
      );
    });

    test(
      'a trade update is left to the notification the OS already shows',
      () async {
        SharedPreferences.setMockInitialValues({});

        await handleBackgroundWake({'type': 'trade_update'}, show: record);

        expect(shown, isEmpty);
      },
    );

    test('a notice that fails to render never breaks the handler', () async {
      SharedPreferences.setMockInitialValues({});

      await expectLater(
        handleBackgroundWake({
          'type': kChatWakeType,
        }, show: (_, __) async => throw StateError('no platform')),
        completes,
      );
    });

    test('its preference keys match the ones Settings writes', () {
      expect(kNewMessagesPrefKey, NotificationEvent.newMessages.prefsKey);
      final settings =
          File(
            'lib/features/settings/providers/settings_provider.dart',
          ).readAsStringSync();
      expect(settings, contains("'$kLanguagePrefKey'"));
    });
  });

  group('the notification channel', () {
    test('is the one the push server names in its payload', () {
      // The server's listener-path payload sets `channel_id`; the app must
      // own that channel or Android renders the push on a default one.
      final spec = File('docs/PUSH_NOTIFICATIONS.md').readAsStringSync();
      expect(spec, contains('"channel_id": "$kPushChannelId"'));
    });
  });
}
