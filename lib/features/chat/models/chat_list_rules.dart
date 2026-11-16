import 'package:flutter/foundation.dart';

import 'package:mostro/features/trades/models/trade_status.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;

/// Pure rules of the chat list (handoff 11b). A conversation takes its group
/// and its avatar tint from the trade it belongs to — the same
/// [TradeRowState] the trades list uses — never from the chat itself.

enum ChatGroup { active, closed }

/// The avatar is tinted by state, not by a hash of the counterparty's key:
/// the saturated random circles suggested an identity that is not there.
enum ChatAvatarTone { yourTurn, waiting, closed }

@immutable
class ChatRowState {
  const ChatRowState({
    required this.group,
    required this.tone,
    this.isResolving = false,
  });

  final ChatGroup group;
  final ChatAvatarTone tone;

  /// The trade has not loaded yet, so whether the conversation is still open
  /// is unknown: the room holds the composer back until it is.
  final bool isResolving;

  /// While the trades load. Listed as open (so a live conversation does not
  /// jump to the closed group and back), but nothing can be sent yet.
  static const resolving = ChatRowState(
    group: ChatGroup.active,
    tone: ChatAvatarTone.waiting,
    isResolving: true,
  );

  /// The lime dot on the avatar: the trade is still open.
  bool get showsActiveDot => group == ChatGroup.active;

  /// A closed conversation still opens, with the composer replaced by a line
  /// saying the trade ended.
  bool get isReadOnly => group == ChatGroup.closed;

  /// Whether the room may show its composer: the trade is known and open.
  bool get canCompose => !isResolving && !isReadOnly;

  /// [status] and [trade] are null when the trades are known but this order
  /// is not among them (or they failed to load). That reads as open and
  /// waiting: a read error must not take the composer away from a live trade.
  /// While they are still loading, use [resolving] instead.
  ///
  /// Closure comes from the protocol status, not from the trades list's
  /// group: a successful trade not rated yet sits in `Requieren tu acción`
  /// there, but its conversation — like a cancelled one's — is over once its
  /// grace window ends
  /// ([chatGraceEndsAt], `now` in Unix seconds) — Rust gives the chat back
  /// then, so a live composer would mislead the sender.
  factory ChatRowState.of({
    OrderStatus? status,
    TradeRowState? trade,
    int? completedAt,
    int now = 0,
  }) {
    final graceEnd =
        status == null
            ? null
            : chatGraceEndsAt(status: status, completedAt: completedAt);
    final inGrace = graceEnd != null && now < graceEnd;
    if (status != null && isTradeFinished(status) && !inGrace) {
      return const ChatRowState(
        group: ChatGroup.closed,
        tone: ChatAvatarTone.closed,
      );
    }
    return ChatRowState(
      group: ChatGroup.active,
      tone:
          trade?.needsAction == true
              ? ChatAvatarTone.yourTurn
              : ChatAvatarTone.waiting,
    );
  }
}

/// How long the conversation of a trade that ended between its parties
/// stays open, in seconds (#642): after a success they thank each other and
/// announce their ratings, after a cooperative cancel they still have things
/// to settle. Mirrors Rust's `PEER_CHAT_GRACE_SECS`, which keeps the chat
/// subscribed for as long.
const kPeerChatGraceSeconds = 3600;

/// When an ended trade's conversation closes (Unix seconds): the end time
/// Rust recorded plus [kPeerChatGraceSeconds]. Rust records one only for a
/// `success` and for the cancel of a trade that was live. Null for any other
/// status, and for a trade that ended before the time was recorded — its
/// conversation is closed.
int? chatGraceEndsAt({required OrderStatus status, int? completedAt}) =>
    _endingsWithGrace.contains(status) && completedAt != null
        ? completedAt + kPeerChatGraceSeconds
        : null;

const _endingsWithGrace = {
  OrderStatus.success,
  OrderStatus.canceled,
  OrderStatus.cooperativelyCanceled,
};

/// Whether the trade has ended — completed (rated or not), settled by an
/// admin, cancelled or expired. A dispute is not an end.
bool isTradeFinished(OrderStatus status) => switch (tradeStatusFromOrderStatus(
  status,
)) {
  TradeStatus.pendingRating ||
  TradeStatus.completed ||
  TradeStatus.rated ||
  TradeStatus.cancelled => true,
  _ => false,
};

@immutable
class ChatRowGroup<T> {
  const ChatRowGroup(this.group, this.rows);

  final ChatGroup group;
  final List<T> rows;
}

/// `Operaciones activas` then `Cerradas`, each with the newest message first
/// — a conversation that just received one rises within its group. An empty
/// group is left out.
List<ChatRowGroup<T>> groupChatRows<T>(
  List<T> rows, {
  required ChatGroup Function(T) groupOf,
  required int Function(T) lastMessageAt,
}) => [
  for (final group in ChatGroup.values)
    if (rows.where((r) => groupOf(r) == group).toList() case final inGroup
        when inGroup.isNotEmpty)
      ChatRowGroup(
        group,
        inGroup..sort((a, b) => lastMessageAt(b).compareTo(lastMessageAt(a))),
      ),
];
