import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/disputes.dart' as disputes_api;
import 'package:mostro/src/rust/api/types.dart' as rust_types;

// ── Dispute models ────────────────────────────────────────────────────────────

/// Dispute lifecycle status, matching the Rust `DisputeStatus` enum.
enum DisputeStatus { open, inReview, resolved }

/// Dispute resolution outcome.
/// Absolute outcome of a resolved dispute.
///
/// Named from the perspective of the trade roles, not the viewing party,
/// so both buyer and seller can interpret the same value correctly.
enum DisputeResolution {
  /// Admin settled the dispute — sats released to the buyer.
  fundsToBuyer,

  /// Admin canceled the order — sats returned to the seller.
  fundsToSeller,

  cooperativeCancel,
}

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
  }) : assert(peerIconIndex >= 0 && peerIconIndex <= 36),
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
}

// ── DisputeNotifier ───────────────────────────────────────────────────────────

class DisputeNotifier extends StateNotifier<List<DisputeItem>> {
  DisputeNotifier() : super(const []);

  /// Upsert a dispute (insert or update by id).
  ///
  /// When updating an existing entry the current [DisputeItem.isRead] state is
  /// preserved so that bridge-driven refreshes do not accidentally reset the
  /// in-memory read flag that the UI manages via [markRead].
  void upsert(DisputeItem dispute) {
    final idx = state.indexWhere((d) => d.id == dispute.id);
    if (idx >= 0) {
      final updated = [...state];
      // Preserve the UI-managed read flag across server-driven updates.
      updated[idx] = dispute.copyWith(isRead: state[idx].isRead);
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
final disputeByIdProvider = Provider.family<DisputeItem?, String>((ref, id) {
  return ref
      .watch(disputeNotifierProvider)
      .where((d) => d.id == id)
      .firstOrNull;
});

/// Look up a dispute by its associated trade ID.
///
/// Used by [TradeDetailScreen] to resolve the correct `disputeId` before
/// navigating to [DisputeChatScreen].
final disputeByTradeIdProvider = Provider.family<DisputeItem?, String>((
  ref,
  tradeId,
) {
  return ref
      .watch(disputeNotifierProvider)
      .where((d) => d.tradeId == tradeId)
      .firstOrNull;
});

// ── Hydration (resume) ────────────────────────────────────────────────────────

/// The bridge's dispute record, as the list shows it. The peer's handle and
/// side are the row's own concern (they come from the trade, not the
/// dispute) and stay whatever the UI already set.
DisputeItem disputeItemFromRust(rust_types.Dispute dispute) => DisputeItem(
  id: dispute.id,
  tradeId: dispute.tradeId,
  status: switch (dispute.status) {
    rust_types.DisputeStatus.open => DisputeStatus.open,
    rust_types.DisputeStatus.inReview => DisputeStatus.inReview,
    rust_types.DisputeStatus.resolved => DisputeStatus.resolved,
  },
  initiatedByMe: dispute.initiatedByMe,
  openedAt: platformInt64ToInt(dispute.openedAt),
  reason: dispute.reason,
  adminPubkey: dispute.adminPubkey,
  resolution: switch (dispute.resolution) {
    null => null,
    rust_types.DisputeResolution.fundsToBuyer => DisputeResolution.fundsToBuyer,
    rust_types.DisputeResolution.fundsToSeller =>
      DisputeResolution.fundsToSeller,
    rust_types.DisputeResolution.cooperativeCancel =>
      DisputeResolution.cooperativeCancel,
  },
  resolvedAt:
      dispute.resolvedAt == null
          ? null
          : platformInt64ToInt(dispute.resolvedAt),
  isRead: dispute.isRead,
);

/// Trade statuses under which the bridge cannot hold a dispute: the trade
/// ended without one. Everything else is queried, because a dispute's record
/// and the row's status are written by different arms — `admin-took-dispute`
/// creates an `InReview` dispute without touching the status, so the row can
/// still read `active`, `fiatSent` or `inProgress` while a dispute exists.
const _undisputableStatuses = {
  rust_types.OrderStatus.success,
  rust_types.OrderStatus.canceled,
  rust_types.OrderStatus.expired,
  rust_types.OrderStatus.cooperativelyCanceled,
};

/// Re-read every dispute the bridge knows for the trades that can own one
/// and upsert it: the read flag the UI manages survives (`upsert` keeps it),
/// and a dispute opened by the peer while the process was suspended appears
/// without a restart — the shape of the v1 bug this exists to prevent
/// (MostroP2P/mobile#675). Assumes the trade list was hydrated first.
Future<void> hydrateDisputes(
  ProviderContainer container, {
  Future<rust_types.Dispute?> Function({required String tradeId})? getDispute,
}) async {
  final lookup = getDispute ?? disputes_api.getDispute;
  final trades = await container.read(rawTradesProvider.future);
  final notifier = container.read(disputeNotifierProvider.notifier);
  for (final trade in trades) {
    if (_undisputableStatuses.contains(trade.order.status)) continue;
    final rust_types.Dispute? dispute;
    try {
      dispute = await lookup(tradeId: trade.order.id);
    } catch (e) {
      debugPrint(
        '[disputes] hydrate: getDispute(${trade.order.id}) failed: $e',
      );
      continue;
    }
    if (dispute != null) notifier.upsert(disputeItemFromRust(dispute));
  }
}
