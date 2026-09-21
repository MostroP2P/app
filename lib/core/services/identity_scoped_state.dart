import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/features/disputes/providers/disputes_providers.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/shared/providers/session_provider.dart';

/// Empties the UI-layer state that belongs to one identity, after that
/// identity was replaced (issue #533).
///
/// Rust wipes the rows and its own in-memory stores in `delete_identity`;
/// this is the Dart half. These providers cache what they read — the trade
/// list, chat rooms, disputes, per-order roles — and none of them is
/// `autoDispose`, so without this the previous user's trades and chats stay
/// on screen until the app restarts, whatever the database says.
///
/// Device preferences are not identity data and stay: theme, language, the
/// node and relay choice, the wallet connection, the trade-list filter.
///
/// New identity-scoped state must be added here, or it leaks into the next
/// user's session.
Future<void> resetIdentityScopedState(WidgetRef ref) async {
  ref.read(sessionProvider.notifier).clearSession();
  ref.invalidate(adminSharedKeyProvider);
  ref.invalidate(tradeRoleProvider);
  ref.invalidate(rawTradesProvider);
  ref.invalidate(chatRoomsNotifierProvider);
  ref.invalidate(chatReadStatusProvider);
  ref.invalidate(disputeNotifierProvider);
  // Persisted (sembast), so it needs a real wipe, not just an invalidation.
  await ref.read(notificationsProvider.notifier).wipeForIdentityChange();
}
