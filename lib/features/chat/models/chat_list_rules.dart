import 'package:flutter/foundation.dart';

import 'package:mostro/features/trades/models/trades_list_rules.dart';

/// Pure rules of the chat list (handoff 11b). A conversation takes its group
/// and its avatar tint from the trade it belongs to — the same
/// [TradeRowState] the trades list uses — never from the chat itself.

enum ChatGroup { active, closed }

/// The avatar is tinted by state, not by a hash of the counterparty's key:
/// the saturated random circles suggested an identity that is not there.
enum ChatAvatarTone { yourTurn, waiting, closed }

@immutable
class ChatRowState {
  const ChatRowState({required this.group, required this.tone});

  final ChatGroup group;
  final ChatAvatarTone tone;

  /// The lime dot on the avatar: the trade is still open.
  bool get showsActiveDot => group == ChatGroup.active;

  /// A closed conversation still opens, with the composer replaced by a line
  /// saying the trade ended.
  bool get isReadOnly => group == ChatGroup.closed;

  /// [trade] is null while the trade row has not loaded. That reads as open
  /// and waiting — never as closed, which would take the composer away from
  /// a live trade.
  factory ChatRowState.of(TradeRowState? trade) {
    if (trade == null) {
      return const ChatRowState(
        group: ChatGroup.active,
        tone: ChatAvatarTone.waiting,
      );
    }
    if (trade.group == TradeGroup.closed) {
      return const ChatRowState(
        group: ChatGroup.closed,
        tone: ChatAvatarTone.closed,
      );
    }
    return ChatRowState(
      group: ChatGroup.active,
      tone:
          trade.needsAction ? ChatAvatarTone.yourTurn : ChatAvatarTone.waiting,
    );
  }
}

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
