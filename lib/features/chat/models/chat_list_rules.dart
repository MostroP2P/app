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
  /// there, but its conversation is over — Rust keeps a send to a finished
  /// trade local, so a live composer would mislead the sender.
  factory ChatRowState.of({OrderStatus? status, TradeRowState? trade}) {
    if (status != null && isTradeFinished(status)) {
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
