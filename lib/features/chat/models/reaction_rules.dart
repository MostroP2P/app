import 'package:mostro/src/rust/api/types.dart' as rust_types;

/// The reaction [msg] shows, or null. The core keeps one per party, an empty
/// one standing for a withdrawn reaction, and only the party who did not
/// write a message can react to it — so there is at most one to show: the
/// user's on the counterpart's message, the counterpart's on the user's.
String? shownReaction(rust_types.ChatMessage msg) {
  for (final reaction in msg.reactions) {
    if (reaction.emoji.isNotEmpty) return reaction.emoji;
  }
  return null;
}

/// Whether [next] may replace [current], two copies of one message: not
/// when its reactions are older. A reply to an earlier send can land after
/// the update of a later one, and must not bring the earlier reaction back.
///
/// Ordered as the core settles reactions: the newest `createdAt` wins, and
/// within one second the lowest event id.
bool reactionsNotOlder(
  rust_types.ChatMessage next,
  rust_types.ChatMessage current,
) {
  final a = _newest(next);
  final b = _newest(current);
  if (a.at != b.at) return a.at > b.at;
  if (a.id == null || b.id == null) return true;
  return a.id!.compareTo(b.id!) <= 0;
}

/// The reaction that settles [msg]'s state: the newest, and of those the
/// one with the lowest id. Null id when it has none.
({int at, String? id}) _newest(rust_types.ChatMessage msg) {
  var at = 0;
  String? id;
  for (final reaction in msg.reactions) {
    final when = reaction.createdAt.toInt();
    final lower = id == null || reaction.eventId.compareTo(id) < 0;
    if (when > at || (when == at && lower)) {
      at = when;
      id = reaction.eventId;
    }
  }
  return (at: at, id: id);
}

/// Whether two emojis are the same reaction. A picker may hand over ❤ where
/// the menu offered ❤️: they differ only by the emoji presentation selector.
bool sameReaction(String a, String? b) => b != null && _bare(a) == _bare(b);

String _bare(String emoji) => emoji.replaceAll('\u{FE0F}', '');
