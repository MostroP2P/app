import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/chat/attachments/attachment_launcher.dart';
import 'package:mostro/features/chat/attachments/attachment_providers.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/providers/release_pending_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/shared/providers/session_provider.dart';

/// Empties the UI-layer state that belongs to one identity, after that
/// identity was replaced (issue #533).
///
/// Rust wipes the rows and its own in-memory stores in `delete_identity`;
/// this is the Dart half. These providers cache what they read — the trade
/// list, chat rooms, decrypted attachments, disputes, per-order roles — and
/// none of them is `autoDispose`, so without this the previous user's trades
/// and chats stay on screen until the app restarts, whatever the database
/// says.
///
/// Device preferences are not identity data and stay: theme, language, the
/// node and relay choice, the wallet connection, the trade-list filter, the
/// order-book filters.
///
/// New identity-scoped state must be added here, or it leaks into the next
/// user's session.
///
/// Takes the app's [ProviderContainer], not a widget's `ref`: the swap runs
/// across bridge calls long enough for the screen that started it to be
/// disposed, and a disposed widget's `ref` throws.
Future<void> resetIdentityScopedState(ProviderContainer container) async {
  container.read(sessionProvider.notifier).clearSession();
  container.invalidate(adminSharedKeyProvider);
  container.invalidate(tradeRoleProvider);
  container.invalidate(rawTradesProvider);
  container.invalidate(chatRoomsNotifierProvider);
  container.invalidate(chatReadStatusProvider);
  // Decrypted attachments of the previous user's chats, in memory.
  container.invalidate(decryptedAttachmentCacheProvider);
  // And any copy of one still handed to another app. Not awaited: disk
  // cleanup must not hold up the swap, and the sweep never throws.
  unawaited(container.read(attachmentLauncherProvider).sweep());
  container.invalidate(disputeNotifierProvider);
  // Releases the previous user published and is still waiting on.
  container.invalidate(releasePendingProvider);
  // Persisted (sembast), so it needs a real wipe, not just an invalidation.
  final notices = container.read(notificationsProvider).length;
  await container.read(notificationsProvider.notifier).wipeForIdentityChange();
  debugPrint(
    '[identity] identity-scoped state reset: $notices notification(s) wiped, '
    '${container.read(notificationsProvider).length} left',
  );
}
