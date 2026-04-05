import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/src/rust/api/identity.dart' as identity_api;
import 'package:mostro/src/rust/api/messages.dart' as messages_api;
import 'package:mostro/src/rust/api/types.dart' as rust_types;

// ── ChatRoomState ─────────────────────────────────────────────────────────────

/// Immutable UI-layer model representing one active chat room (trade session).
@immutable
class ChatRoomState {
  const ChatRoomState({
    required this.orderId,
    required this.peerPubkey,
    required this.peerHandle,
    required this.peerIconIndex,
    required this.peerColorHue,
    required this.isSelling,
    this.lastMessage,
    this.lastMessageIsOwn = false,
    this.lastMessageAt = 0,
    this.unreadCount = 0,
  })  : assert(
          peerIconIndex >= 0 && peerIconIndex <= 36,
          'peerIconIndex must be 0–36, got $peerIconIndex',
        ),
        assert(
          peerColorHue >= 0 && peerColorHue <= 359,
          'peerColorHue must be 0–359, got $peerColorHue',
        );

  /// The trade / order ID that identifies this chat room.
  final String orderId;

  /// Nostr public key of the counterparty.
  final String peerPubkey;

  /// Human-readable pseudonym (NymIdentity.pseudonym).
  final String peerHandle;

  /// Avatar icon index (0–36) derived from peer's pubkey.
  final int peerIconIndex;

  /// HSV hue (0–359) derived from peer's pubkey.
  final int peerColorHue;

  /// true  → "You are selling sats to [handle]"
  /// false → "You are buying sats from [handle]"
  final bool isSelling;

  /// Preview text of the most recent message; null when no messages yet.
  final String? lastMessage;

  /// Whether the most recent message was sent by the local user.
  final bool lastMessageIsOwn;

  /// Unix timestamp (seconds) of the most recent message; 0 = no messages.
  final int lastMessageAt;

  /// Number of messages not yet seen by the local user.
  final int unreadCount;

  // Sentinel used by copyWith to distinguish "not provided" from explicit null.
  static const Object _noChange = Object();

  ChatRoomState copyWith({
    String? orderId,
    String? peerPubkey,
    String? peerHandle,
    int? peerIconIndex,
    int? peerColorHue,
    bool? isSelling,
    Object? lastMessage = _noChange,
    bool? lastMessageIsOwn,
    int? lastMessageAt,
    int? unreadCount,
  }) {
    return ChatRoomState(
      orderId: orderId ?? this.orderId,
      peerPubkey: peerPubkey ?? this.peerPubkey,
      peerHandle: peerHandle ?? this.peerHandle,
      peerIconIndex: peerIconIndex ?? this.peerIconIndex,
      peerColorHue: peerColorHue ?? this.peerColorHue,
      isSelling: isSelling ?? this.isSelling,
      lastMessage: identical(lastMessage, _noChange)
          ? this.lastMessage
          : lastMessage as String?,
      lastMessageIsOwn: lastMessageIsOwn ?? this.lastMessageIsOwn,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

// ── ChatRoomsNotifier ─────────────────────────────────────────────────────────

/// Manages the list of active chat rooms.
///
/// Only includes trades that have a non-empty [counterpartyPubkey] — i.e.
/// trades where the peer's identity has been exchanged (hold invoice accepted).
class ChatRoomsNotifier extends StateNotifier<List<ChatRoomState>> {
  ChatRoomsNotifier() : super(const []);

  /// Replace the entire list of chat rooms (called when bridge emits an update).
  void setRooms(List<ChatRoomState> rooms) {
    state = rooms;
  }

  /// Upsert a single room (insert or update by orderId).
  void upsertRoom(ChatRoomState room) {
    final existing = state.indexWhere((r) => r.orderId == room.orderId);
    if (existing >= 0) {
      final updated = [...state];
      updated[existing] = room;
      state = updated;
    } else {
      state = [...state, room];
    }
  }

  /// Mark all messages in a room as read (zero unread count).
  void markRead(String orderId) {
    state = [
      for (final room in state)
        if (room.orderId == orderId) room.copyWith(unreadCount: 0) else room,
    ];
  }

  /// Remove a room by orderId.
  void removeRoom(String orderId) {
    state = state.where((r) => r.orderId != orderId).toList();
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Source-of-truth provider for the list of chat rooms.
///
/// Sorted order is provided by [sortedChatRoomsProvider].
final chatRoomsNotifierProvider =
    StateNotifierProvider<ChatRoomsNotifier, List<ChatRoomState>>(
  (_) => ChatRoomsNotifier(),
);

/// Chat rooms sorted by [ChatRoomState.lastMessageAt] descending (newest first).
final sortedChatRoomsProvider = Provider<List<ChatRoomState>>((ref) {
  final rooms = ref.watch(chatRoomsNotifierProvider);
  final sorted = [...rooms]
    ..sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
  return sorted;
});

/// Total unread message count across all rooms.
///
/// Consumed by [chatNotificationCountProvider] in BottomNavBar.
final chatCountProvider = Provider<int>((ref) {
  final rooms = ref.watch(chatRoomsNotifierProvider);
  return rooms.fold(0, (sum, r) => sum + r.unreadCount);
});

/// Maps orderId → last-read unix timestamp (seconds).
///
/// In-memory only. Sembast persistence deferred to a future phase.
final chatReadStatusProvider =
    StateProvider<Map<String, int>>((_) => const {});

// ── Trade → ChatRoom bridge ───────────────────────────────────────────────────

/// Converts a [rust_types.TradeInfo] to a [ChatRoomState] asynchronously.
///
/// Returns `null` when [TradeInfo.counterpartyPubkey] is empty — meaning the
/// peer identity has not been exchanged yet and there is no chat room to show.
Future<ChatRoomState?> tradeInfoToChatRoom(
  rust_types.TradeInfo trade,
) async {
  final peerPubkey = trade.counterpartyPubkey;
  if (peerPubkey.isEmpty) return null;

  // Derive NymIdentity from the peer's trade public key.
  rust_types.NymIdentity nym;
  try {
    nym = await identity_api.getNymIdentity(pubkeyHex: peerPubkey);
  } catch (e) {
    debugPrint('[chat] getNymIdentity failed for $peerPubkey: $e');
    // Fallback: generic identity derived from first bytes of pubkey hex.
    final hash = peerPubkey.codeUnits.fold(0, (a, b) => a ^ b);
    nym = rust_types.NymIdentity(
      pseudonym: 'Trader ${peerPubkey.substring(0, 6)}',
      iconIndex: hash % 37,
      colorHue: hash % 360,
    );
  }

  // Fetch persisted messages to populate last-message preview.
  List<rust_types.ChatMessage> msgs;
  try {
    msgs = await messages_api.getMessages(tradeId: trade.order.id);
  } catch (_) {
    msgs = const [];
  }

  final last = msgs.isNotEmpty ? msgs.last : null;
  final unreadCount = msgs.where((m) => !m.isRead && !m.isMine).length;

  final iconIndex = nym.iconIndex.clamp(0, 36).toInt();
  final colorHue = nym.colorHue.clamp(0, 359).toInt();

  return ChatRoomState(
    orderId: trade.order.id,
    peerPubkey: peerPubkey,
    peerHandle: nym.pseudonym,
    peerIconIndex: iconIndex,
    peerColorHue: colorHue,
    isSelling: trade.role == rust_types.TradeRole.seller,
    lastMessage: last?.content,
    lastMessageIsOwn: last?.isMine ?? false,
    lastMessageAt: last?.createdAt.toInt() ?? 0,
    unreadCount: unreadCount,
  );
}

/// FutureProvider that converts the full trade list into [ChatRoomState]s.
///
/// Only trades with a known peer pubkey are included. Sorted newest-message first.
final chatRoomsFromTradesProvider =
    FutureProvider<List<ChatRoomState>>((ref) async {
  final trades = await ref.watch(rawTradesProvider.future);

  final rooms = <ChatRoomState>[];
  for (final trade in trades) {
    final room = await tradeInfoToChatRoom(trade);
    if (room != null) rooms.add(room);
  }

  rooms.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
  return rooms;
});

/// Stream provider that emits new [rust_types.ChatMessage]s for a given trade.
///
/// Used by [ChatRoomScreen] to update its local list in real-time without
/// polling.
final incomingMessageProvider =
    StreamProvider.autoDispose.family<rust_types.ChatMessage, String>(
  (ref, tradeId) async* {
    final stream = await messages_api.onNewMessage(tradeId: tradeId);
    while (true) {
      final msg = await stream.next();
      if (msg == null) break;
      yield msg;
    }
  },
);

/// FutureProvider that loads the full message history for a trade once.
///
/// [ChatRoomScreen] seeds its local state from this, then appends live
/// updates via [incomingMessageProvider].
final messageHistoryProvider =
    FutureProvider.autoDispose.family<List<rust_types.ChatMessage>, String>(
  (ref, tradeId) => messages_api.getMessages(tradeId: tradeId),
);
