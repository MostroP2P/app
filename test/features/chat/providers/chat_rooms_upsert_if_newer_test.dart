import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';

ChatRoomState _room({
  String id = 'o1',
  int at = 100,
  String? last = 'hola',
  int unread = 0,
}) => ChatRoomState(
  orderId: id,
  peerPubkey: 'peer',
  peerHandle: 'used-jaguar',
  peerIconIndex: 0,
  peerColorHue: 0,
  isSelling: true,
  lastMessage: last,
  lastMessageAt: at,
  unreadCount: unread,
);

void main() {
  group('ChatRoomsNotifier.upsertIfNewer', () {
    test('a room the list does not have is added', () {
      final notifier = ChatRoomsNotifier();

      notifier.upsertIfNewer(_room());

      expect(notifier.state.single.orderId, 'o1');
    });

    test('a snapshot older than the live room leaves it alone', () {
      // A message folded in while the snapshot was being built.
      final notifier =
          ChatRoomsNotifier()
            ..setRooms([_room(at: 200, last: 'nuevo', unread: 1)]);

      notifier.upsertIfNewer(_room(at: 100, last: 'hola'));

      final room = notifier.state.single;
      expect(room.lastMessage, 'nuevo');
      expect(room.lastMessageAt, 200);
      expect(room.unreadCount, 1);
    });

    test('a snapshot at or past the live room replaces it', () {
      final notifier = ChatRoomsNotifier()..setRooms([_room(at: 100)]);

      notifier.upsertIfNewer(_room(at: 100, last: 'same time, re-read'));
      expect(notifier.state.single.lastMessage, 'same time, re-read');

      notifier.upsertIfNewer(_room(at: 300, last: 'later'));
      expect(notifier.state.single.lastMessage, 'later');
    });
  });
}
