import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/notifications/services/push_refresh_job.dart';

void main() {
  const k1 = '1111111111111111111111111111111111111111111111111111111111111111';
  const k2 = '2222222222222222222222222222222222222222222222222222222222222222';
  const node =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  String mirror({
    Object? token = 'fcm-token',
    Object? registrations = const [
      {'trade_pubkey': k1, 'mostro_pubkey': node},
      {'trade_pubkey': k2, 'mostro_pubkey': node},
    ],
  }) => jsonEncode({
    'server_url': 'https://push.example',
    'token': token,
    'platform': 'android',
    'registrations': registrations,
  });

  group('refreshFromMirror', () {
    test(
      're-POSTs every registration with exactly the register body',
      () async {
        // Arrange
        final posted = <(Uri, Map<String, Object?>)>[];

        // Act
        final outcome = await refreshFromMirror(mirror(), (url, body) async {
          posted.add((url, body));
          return 200;
        });

        // Assert
        expect(outcome.sent, 2);
        expect(outcome.failed, 0);
        expect(posted.map((p) => p.$1.toString()).toSet(), {
          'https://push.example/api/register',
        });
        expect(posted.first.$2, {
          'trade_pubkey': k1,
          'token': 'fcm-token',
          'platform': 'android',
          'mostro_pubkey': node,
        });
        expect(posted.first.$2.keys, hasLength(4), reason: 'nothing extra');
      },
    );

    test('a failure on one entry does not stop the rest', () async {
      var calls = 0;
      final outcome = await refreshFromMirror(mirror(), (url, body) async {
        calls++;
        if (calls == 1) throw const SocketException('down');
        return 202;
      });
      expect(outcome.sent, 1);
      expect(outcome.failed, 1);
    });

    test('a status other than 200 or 202 counts as failed', () async {
      final outcome = await refreshFromMirror(
        mirror(),
        (url, body) async => 403,
      );
      expect(outcome.failed, 2);
      expect(outcome.sent, 0);
    });

    test('a malformed, tokenless or empty mirror sends nothing', () async {
      var calls = 0;
      Future<int> count(Uri url, Map<String, Object?> body) async {
        calls++;
        return 200;
      }

      for (final json in [
        'not json',
        '[]',
        mirror(token: ''),
        mirror(token: null),
        mirror(registrations: const []),
        mirror(registrations: 'nope'),
      ]) {
        final outcome = await refreshFromMirror(json, count);
        expect(outcome.sent + outcome.failed, 0, reason: json);
      }
      expect(calls, 0);
    });

    test('an entry without both pubkeys is skipped, not sent', () async {
      var calls = 0;
      final outcome = await refreshFromMirror(
        mirror(
          registrations: const [
            {'trade_pubkey': k1},
            {'trade_pubkey': k2, 'mostro_pubkey': node},
          ],
        ),
        (url, body) async {
          calls++;
          return 200;
        },
      );
      expect(calls, 1);
      expect(outcome.sent, 1);
    });
  });

  group('runPushRefresh', () {
    test('no mirror file means nothing to refresh', () async {
      final dir = await Directory.systemTemp.createTemp('push-refresh-');
      addTearDown(() => dir.delete(recursive: true));

      final outcome = await runPushRefresh(dataDir: dir.path);

      expect(outcome.sent + outcome.failed, 0);
    });
  });

  group('the job is HTTP plumbing, not a second writer', () {
    test('its file imports no bridge, database or protocol code', () {
      // The rule of docs/PUSH_NOTIFICATIONS.md §6 principle 2, held down
      // where it would otherwise rot: the file may read a JSON mirror and
      // POST it, and nothing else.
      final source =
          File(
            'lib/features/notifications/services/push_refresh_job.dart',
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
        'shared_preferences',
        'notifications_provider',
        'firebase',
      ]) {
        expect(
          imports.where((i) => i.contains(forbidden)),
          isEmpty,
          reason: 'the refresh job must not import $forbidden',
        );
      }
    });

    test('the task identifier matches Info.plist and AppDelegate', () {
      final plist = File('ios/Runner/Info.plist').readAsStringSync();
      final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(plist, contains('<string>$kPushRefreshTask</string>'));
      expect(delegate, contains('"$kPushRefreshTask"'));
    });
  });
}
