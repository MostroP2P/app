/// The push registration refresh that outlives the process
/// (docs/PUSH_NOTIFICATIONS.md §7.1, T1.5).
///
/// The push server forgets a token 48 h after its last registration, and
/// none of the app's own triggers fire while it is suspended or not running.
/// So the OS runs this job on a schedule — `workmanager` on Android,
/// `BGAppRefreshTask` on iOS — and it re-POSTs every accepted registration.
///
/// It does one thing, and does it without the app: it reads the small JSON
/// mirror Rust writes next to the database (`push_mirror.json`: the server
/// URL, the token, the platform and the accepted registrations) and calls
/// `/api/register` for each entry. It never loads the Rust core, never
/// opens the database and never touches protocol state, which is what keeps
/// the "doorbell, not courier" rule intact (§6 principle 2): the job is HTTP
/// plumbing, not a second writer. A test holds that boundary down by
/// reading this file's imports.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'package:mostro/core/storage/app_data_dir.dart';

/// The task's name on both platforms. On iOS it is also the identifier listed
/// under `BGTaskSchedulerPermittedIdentifiers` in `Info.plist` and registered
/// in `AppDelegate.swift`; rename all three together.
const kPushRefreshTask = 'network.mostro.app.pushRefresh';

/// The mirror file Rust writes next to the database.
const kPushMirrorFile = 'push_mirror.json';

/// How often the OS is asked to run the job. A quarter of the server's TTL;
/// Android honours it on stock builds, iOS treats it as a request.
const kPushRefreshPeriod = Duration(hours: 12);

/// What one run did, for the log and the tests.
@immutable
class PushRefreshOutcome {
  const PushRefreshOutcome({required this.sent, required this.failed});

  /// Nothing to refresh: no mirror, or an empty one.
  static const nothing = PushRefreshOutcome(sent: 0, failed: 0);

  final int sent;
  final int failed;
}

/// One `POST` of a JSON body; returns the status code. Injected so the run
/// is tested without a network.
typedef PostJson = Future<int> Function(Uri url, Map<String, Object?> body);

/// Re-POST every registration in [mirrorJson] through [post].
///
/// Pure: the file is read and the client built by [runPushRefresh]. A
/// malformed mirror, or one with no token or registrations, sends nothing.
/// Every entry is attempted; a failure never stops the rest, and the
/// outcome counts both. The body is exactly `/api/register`'s
/// (docs/PUSH_NOTIFICATIONS.md §3.1) — nothing the app would not send.
Future<PushRefreshOutcome> refreshFromMirror(
  String mirrorJson,
  PostJson post,
) async {
  final Object? decoded;
  try {
    decoded = jsonDecode(mirrorJson);
  } catch (_) {
    return PushRefreshOutcome.nothing;
  }
  if (decoded is! Map<String, Object?>) return PushRefreshOutcome.nothing;
  final serverUrl = decoded['server_url'];
  final token = decoded['token'];
  final platform = decoded['platform'];
  final registrations = decoded['registrations'];
  if (serverUrl is! String ||
      token is! String ||
      token.isEmpty ||
      platform is! String ||
      registrations is! List) {
    return PushRefreshOutcome.nothing;
  }
  final Uri url;
  try {
    url = Uri.parse('$serverUrl/api/register');
  } catch (_) {
    return PushRefreshOutcome.nothing;
  }

  var sent = 0;
  var failed = 0;
  for (final entry in registrations) {
    if (entry is! Map) continue;
    final tradePubkey = entry['trade_pubkey'];
    final mostroPubkey = entry['mostro_pubkey'];
    if (tradePubkey is! String || mostroPubkey is! String) continue;
    try {
      final status = await post(url, {
        'trade_pubkey': tradePubkey,
        'token': token,
        'platform': platform,
        'mostro_pubkey': mostroPubkey,
      });
      if (status == 200 || status == 202) {
        sent++;
      } else {
        failed++;
      }
    } catch (_) {
      failed++;
    }
  }
  return PushRefreshOutcome(sent: sent, failed: failed);
}

/// The real run: the mirror from disk, `dart:io`'s client, 10 s per request.
Future<PushRefreshOutcome> runPushRefresh({String? dataDir}) async {
  final dir = dataDir ?? await appDataDirPath();
  final file = File('$dir/$kPushMirrorFile');
  if (!await file.exists()) return PushRefreshOutcome.nothing;
  final mirror = await file.readAsString();
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    return await refreshFromMirror(mirror, (url, body) async {
      final request = await client.postUrl(url);
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      await response.drain<void>();
      return response.statusCode;
    });
  } finally {
    client.close(force: true);
  }
}

/// The isolate entry point the OS calls. Top-level and pinned, as
/// `workmanager` requires.
@pragma('vm:entry-point')
void pushRefreshDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != kPushRefreshTask) return true;
    try {
      final outcome = await runPushRefresh();
      debugPrint(
        '[push] refresh job: sent=${outcome.sent} failed=${outcome.failed}',
      );
    } catch (e) {
      debugPrint('[push] refresh job failed: $e');
    }
    // Always "done": the next period retries, and a failure here is never
    // the OS's problem. The server's TTL is the backstop either way.
    return true;
  });
}

/// Ask the OS to run the job every [kPushRefreshPeriod]. Idempotent: an
/// existing schedule is kept. Android and iOS only; the caller gates on the
/// platform capability.
Future<void> schedulePushRefresh() async {
  try {
    await Workmanager().initialize(pushRefreshDispatcher);
    await Workmanager().registerPeriodicTask(
      kPushRefreshTask,
      kPushRefreshTask,
      frequency: kPushRefreshPeriod,
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  } catch (e) {
    // A missing platform channel (a build without the plugin) or an iOS
    // identifier not in Info.plist: the in-app refresh still runs.
    debugPrint('[push] refresh job not scheduled: $e');
  }
}
