import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Dispute models ────────────────────────────────────────────────────────────

/// Dispute lifecycle status, matching the Rust `DisputeStatus` enum.
enum DisputeStatus { open, inReview, resolved }

/// Dispute resolution outcome.
enum DisputeResolution { fundsToMe, fundsToCounterparty, cooperativeCancel }

/// Dart-side chat message for dispute/admin chat.
@immutable
class DisputeMessage {
  const DisputeMessage({
    required this.id,
    required this.content,
    required this.isMine,
    required this.isAdmin,
    required this.createdAt,
    this.nostrEventId,
  });

  final String id;
  final String content;
  final bool isMine;
  final bool isAdmin;
  final int createdAt;
  final String? nostrEventId;

  bool get isSystem => !isMine && !isAdmin;
}

/// Dart-side immutable model for one dispute.
@immutable
class DisputeItem {
  const DisputeItem({
    required this.id,
    required this.tradeId,
    required this.status,
    required this.initiatedByMe,
    required this.openedAt,
    this.reason,
    this.adminPubkey,
    this.resolution,
    this.resolvedAt,
    this.isRead = false,
    this.peerHandle,
    this.peerIconIndex = 0,
    this.peerColorHue = 180,
    this.isSelling = false,
  })  : assert(peerIconIndex >= 0 && peerIconIndex <= 36),
        assert(peerColorHue >= 0 && peerColorHue <= 359);

  final String id;
  final String tradeId;
  final DisputeStatus status;
  final bool initiatedByMe;
  final int openedAt;
  final String? reason;
  final String? adminPubkey;
  final DisputeResolution? resolution;
  final int? resolvedAt;
  final bool isRead;

  // Peer identity (populated from session when available).
  final String? peerHandle;
  final int peerIconIndex;
  final int peerColorHue;

  /// true → "Dispute with Seller"; false → "Dispute with Buyer".
  final bool isSelling;

  DisputeItem copyWith({
    DisputeStatus? status,
    bool? initiatedByMe,
    int? openedAt,
    String? reason,
    String? adminPubkey,
    DisputeResolution? resolution,
    int? resolvedAt,
    bool? isRead,
    String? peerHandle,
    int? peerIconIndex,
    int? peerColorHue,
    bool? isSelling,
  }) {
    return DisputeItem(
      id: id,
      tradeId: tradeId,
      status: status ?? this.status,
      initiatedByMe: initiatedByMe ?? this.initiatedByMe,
      openedAt: openedAt ?? this.openedAt,
      reason: reason ?? this.reason,
      adminPubkey: adminPubkey ?? this.adminPubkey,
      resolution: resolution ?? this.resolution,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      isRead: isRead ?? this.isRead,
      peerHandle: peerHandle ?? this.peerHandle,
      peerIconIndex: peerIconIndex ?? this.peerIconIndex,
      peerColorHue: peerColorHue ?? this.peerColorHue,
      isSelling: isSelling ?? this.isSelling,
    );
  }

  /// Human-readable description shown in list items.
  String get description {
    if (status == DisputeStatus.resolved) {
      return switch (resolution) {
        DisputeResolution.fundsToMe => 'Dispute resolved in your favour',
        DisputeResolution.fundsToCounterparty =>
          "Dispute resolved in counterparty's favour",
        DisputeResolution.cooperativeCancel => 'Order cancelled cooperatively',
        null => 'Dispute resolved',
      };
    }
    return initiatedByMe ? 'You opened this dispute' : 'Counterpart opened this dispute';
  }
}

// ── DisputeNotifier ───────────────────────────────────────────────────────────

class DisputeNotifier extends StateNotifier<List<DisputeItem>> {
  DisputeNotifier() : super(const []);

  /// Upsert a dispute (insert or update by id).
  void upsert(DisputeItem dispute) {
    final idx = state.indexWhere((d) => d.id == dispute.id);
    if (idx >= 0) {
      final updated = [...state];
      updated[idx] = dispute;
      state = updated;
    } else {
      state = [...state, dispute];
    }
  }

  /// Mark a dispute as read.
  void markRead(String disputeId) {
    state = [
      for (final d in state)
        if (d.id == disputeId) d.copyWith(isRead: true) else d,
    ];
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// Source-of-truth list of disputes.
///
/// Empty until bridge events are integrated (Phase 12+).
final disputeNotifierProvider =
    StateNotifierProvider<DisputeNotifier, List<DisputeItem>>(
  (_) => DisputeNotifier(),
);

/// All disputes sorted newest-first.
///
/// Drives [DisputesList] and the Chat screen Disputes tab.
///
/// Returns [AsyncValue.data] even though [disputeNotifierProvider] is
/// synchronous. This provides a uniform `AsyncValue`-based API surface for
/// consumers and allows easy future migration when the source becomes
/// asynchronous (e.g. backed by a Rust bridge stream).
final userDisputeDataProvider = Provider<AsyncValue<List<DisputeItem>>>((ref) {
  final disputes = ref.watch(disputeNotifierProvider);
  final sorted = [...disputes]
    ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
  return AsyncValue.data(sorted);
});

/// Total unread dispute count for the Chat screen Disputes tab badge.
final disputeUnreadCountProvider = Provider<int>((ref) {
  final disputes = ref.watch(disputeNotifierProvider);
  return disputes.where((d) => !d.isRead).length;
});

/// Look up a single dispute by its ID.
final disputeByIdProvider =
    Provider.family<DisputeItem?, String>((ref, id) {
  return ref.watch(disputeNotifierProvider).where((d) => d.id == id).firstOrNull;
});

/// Look up a dispute by its associated trade ID.
///
/// Used by [TradeDetailScreen] to resolve the correct `disputeId` before
/// navigating to [DisputeChatScreen].
final disputeByTradeIdProvider =
    Provider.family<DisputeItem?, String>((ref, tradeId) {
  return ref
      .watch(disputeNotifierProvider)
      .where((d) => d.tradeId == tradeId)
      .firstOrNull;
});
