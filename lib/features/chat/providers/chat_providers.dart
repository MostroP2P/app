import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  });

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

  ChatRoomState copyWith({
    String? orderId,
    String? peerPubkey,
    String? peerHandle,
    int? peerIconIndex,
    int? peerColorHue,
    bool? isSelling,
    String? lastMessage,
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
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageIsOwn: lastMessageIsOwn ?? this.lastMessageIsOwn,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

// ── ChatRoomsNotifier ─────────────────────────────────────────────────────────

/// Manages the list of active chat rooms.
///
/// Only includes sessions that have a peer pubkey AND at least one message.
/// Currently returns an empty list; will be wired to the Rust bridge in a
/// later phase.
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
/// Kept in memory for Phase 10; SharedPreferences persistence is Phase 10+.
final chatReadStatusProvider =
    StateProvider<Map<String, int>>((_) => const {});
