import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/chat/providers/chat_providers.dart';
import 'package:mostro/src/rust/api/types.dart';

ChatRoomState _room({int at = 100, String? last = 'hola', int unread = 0}) =>
    ChatRoomState(
      orderId: 'o1',
      peerPubkey: 'peer',
      peerHandle: 'used-jaguar',
      peerIconIndex: 0,
      peerColorHue: 0,
      isSelling: true,
      lastMessage: last,
      lastMessageAt: at,
      unreadCount: unread,
    );

ChatMessage _msg({
  String id = 'm',
  String content = 'nuevo',
  int at = 200,
  bool isMine = false,
  bool isRead = false,
  MessageType type = MessageType.peer,
}) => ChatMessage(
  id: id,
  tradeId: 'o1',
  senderPubkey: 'peer',
  content: content,
  messageType: type,
  isMine: isMine,
  isRead: isRead,
  hasAttachment: false,
  createdAt: at,
);

ChatRoomState _foldInto(ChatRoomState room, ChatMessage msg) {
  final notifier = ChatRoomsNotifier()..setRooms([room]);
  notifier.foldIncoming('o1', msg);
  return notifier.state.single;
}

void main() {
  group('ChatRoomsNotifier.foldIncoming', () {
    test('a counterparty message updates the preview and raises the count', () {
      final room = _foldInto(_room(unread: 1), _msg());
      expect(room.lastMessage, 'nuevo');
      expect(room.lastMessageAt, 200);
      expect(room.lastMessageIsOwn, isFalse);
      expect(room.unreadCount, 2);
    });

    test('an own or already-read message does not raise the count', () {
      expect(_foldInto(_room(), _msg(isMine: true)).unreadCount, 0);
      expect(_foldInto(_room(), _msg(isRead: true)).unreadCount, 0);
      expect(_foldInto(_room(), _msg(isMine: true)).lastMessageIsOwn, isTrue);
    });

    test('dispute traffic on the same order is not a peer message', () {
      final room = _foldInto(_room(), _msg(type: MessageType.admin));
      expect(room.lastMessage, 'hola');
      expect(room.unreadCount, 0);
    });

    test('the message the open room already folded in counts once', () {
      final notifier = ChatRoomsNotifier()..setRooms([_room()]);
      notifier.foldIncoming('o1', _msg());
      notifier.foldIncoming('o1', _msg());
      expect(notifier.state.single.unreadCount, 1);
    });

    test('an older message does not replace a newer preview', () {
      final room = _foldInto(_room(at: 300), _msg(at: 200));
      expect(room.lastMessage, 'hola');
      expect(room.unreadCount, 0);
    });
  });
}
