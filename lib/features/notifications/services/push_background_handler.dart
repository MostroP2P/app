/// The FCM background handler, and the two things it may do.
///
/// Display-only, by rule (docs/PUSH_NOTIFICATIONS.md §6 principle 2, issue
/// #308): it never initialises the Rust core, never opens the database and
/// never decrypts. It records that a wake arrived, and the resume path —
/// `resync()` in Rust, then hydration — does every write, once, in the
/// foreground. A test reads this file's imports to hold that boundary.
///
/// What it may render: the server's `trade_update` push already carries its
/// own visible notification, which the OS shows. A `chat_wake` carries none
/// (a peer's `/api/notify`), so the handler shows a content-free "new
/// message" notice itself — unless the user turned message notifications
/// off (§7.2, T3.2).
library;

import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mostro/features/notifications/services/local_notifications.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Set by the handler, cleared by the next resume. A flag, not a counter:
/// ten pushes cost one resync.
const kPushWakePendingKey = 'push_wake_pending';

/// The push type a peer's `/api/notify` produces.
const kChatWakeType = 'chat_wake';

/// The "new messages" toggle of the notification settings. Duplicated from
/// `NotificationEvent.newMessages` because this isolate must not import the
/// Riverpod provider; a test keeps the two equal.
const kNewMessagesPrefKey = 'notify_new_messages';

/// The stored app language, duplicated from `settings_provider.dart` for the
/// same reason; a test keeps the two equal.
const kLanguagePrefKey = 'settings.language';

/// Renders a notice; injected so the decision is tested without a platform.
typedef ShowNotification = Future<void> Function(String title, String body);

/// Runs in its own isolate when a push arrives while the app is in the
/// background (docs/PUSH_NOTIFICATIONS.md §7.2). Top-level and pinned, as
/// `firebase_messaging` requires.
@pragma('vm:entry-point')
Future<void> pushBackgroundHandler(RemoteMessage message) =>
    handleBackgroundWake(message.data, show: showChatWakeNotification);

/// The handler's decision, with the rendering injected.
@visibleForTesting
Future<void> handleBackgroundWake(
  Map<String, dynamic> data, {
  required ShowNotification show,
}) async {
  final type = data['type'];
  debugPrint('[push] background wake: $type');
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    // The background isolate can outlive a delivery, and the instance caches
    // what it read then: a toggle or language changed in the app since would
    // otherwise go unseen.
    await prefs.reload();
    await prefs.setBool(kPushWakePendingKey, true);
  } catch (e) {
    // Diagnostic only: the resume resyncs whether or not the flag is set.
    debugPrint('[push] wake flag not recorded: $e');
    prefs = null;
  }

  if (type != kChatWakeType) return;
  // Unreadable preferences cannot say the user allows it: stay silent.
  if (prefs == null || prefs.getBool(kNewMessagesPrefKey) == false) return;
  final l10n = lookupAppLocalizations(
    Locale(chatWakeLanguage(prefs.getString(kLanguagePrefKey))),
  );
  try {
    await show(l10n.appName, l10n.pushNewMessageBody);
  } catch (e) {
    debugPrint('[push] new-message notice not shown: $e');
  }
}

/// The stored language as a supported code: the region stripped, and when
/// empty or unsupported the first supported device locale, then English —
/// the same rule the settings provider applies.
String chatWakeLanguage(String? stored, {Iterable<Locale>? deviceLocales}) {
  final supported =
      AppLocalizations.supportedLocales.map((l) => l.languageCode).toSet();
  final code = (stored ?? '').split(RegExp(r'[-_]')).first.toLowerCase();
  if (supported.contains(code)) return code;
  for (final locale in deviceLocales ?? PlatformDispatcher.instance.locales) {
    if (supported.contains(locale.languageCode)) return locale.languageCode;
  }
  return 'en';
}

/// Whether a wake arrived since the last resume, clearing the flag.
Future<bool> consumeWakePending() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool(kPushWakePendingKey) ?? false;
    if (pending) await prefs.remove(kPushWakePendingKey);
    return pending;
  } catch (e) {
    debugPrint('[push] wake flag not read: $e');
    return false;
  }
}
