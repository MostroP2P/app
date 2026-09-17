import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:mostro/core/app_routes.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/features/notifications/services/event_cards.dart';
import 'package:mostro/src/rust/api/types.dart';

List<NotificationModel> snapshot(NotificationsNotifier n) {
  late List<NotificationModel> result;
  n.addListener((s) => result = s)();
  return result;
}

class HeldLoadStore extends SembastNotificationsStore {
  HeldLoadStore() : super(factory: newDatabaseFactoryMemory());
  final release = Completer<void>();
  @override
  Future<List<NotificationModel>> loadAll() async {
    await release.future;
    return super.loadAll();
  }
}

void main() {
  test('opening chat during identity lookup leaves no unread card', () async {
    final n = NotificationsNotifier(
      store: SembastNotificationsStore(factory: newDatabaseFactoryMemory()),
    );
    await n.loadInitialData();
    String? location;
    final identityRead = Completer<DateTime?>();
    final cards = EventCards(
      notifications: () => n,
      isEnabled: (_) => true,
      identityCreatedAt: () => identityRead.future,
      currentLocation: () => location,
    );
    final pending = cards.onChatMessage(
      const ChatMessage(
        id: 'm1',
        tradeId: 'order-1',
        senderPubkey: 'peer',
        content: 'hi',
        messageType: MessageType.peer,
        isMine: false,
        isRead: false,
        hasAttachment: false,
        createdAt: 1000,
      ),
    );
    location = AppRoute.chatRoomPath('order-1');
    await n.markAsRead('chat-order-1');
    // Leaving before the event finishes must not undo the read intent.
    location = null;
    identityRead.complete(null);
    await pending;
    expect(snapshot(n).where((card) => !card.isRead), isEmpty);
  });

  test(
    'opening chat before notification hydration preserves mark-read',
    () async {
      final store = HeldLoadStore();
      await store.save(
        NotificationModel.chatMessages(
          tradeId: 'order-1',
          fromSolver: false,
          count: 2,
          at: DateTime.fromMillisecondsSinceEpoch(1000000),
        ),
      );
      final n = NotificationsNotifier(store: store);
      final load = n.loadInitialData();
      await n.markAsRead('chat-order-1');
      store.release.complete();
      await load;
      expect(snapshot(n).single.isRead, isTrue);
    },
  );
  test(
    'concurrent mark-read and chat fold keep disk and UI consistent',
    () async {
      final store = SembastNotificationsStore(
        factory: newDatabaseFactoryMemory(),
      );
      final n = NotificationsNotifier(store: store);
      await n.loadInitialData();
      NotificationModel fold(NotificationModel? existing) =>
          NotificationModel.chatMessages(
            tradeId: 'order-1',
            fromSolver: false,
            count: (existing?.chatUnreadCount ?? 0) + 1,
            at: DateTime.fromMillisecondsSinceEpoch(1000000),
          );
      await n.addChatMessage(
        messageId: 'm1',
        cardId: 'chat-order-1',
        fold: fold,
      );
      final pending = n.addChatMessage(
        messageId: 'm2',
        cardId: 'chat-order-1',
        fold: fold,
      );
      await n.markAsRead('chat-order-1');
      await pending;
      final ui = snapshot(n).single;
      final disk = (await store.loadAll()).single;
      expect(disk.chatUnreadCount, 2);
      expect(ui.isRead, isTrue);
      expect(disk.chatUnreadCount, ui.chatUnreadCount);
      expect(disk.isRead, ui.isRead);
    },
  );
  test('a failed write retries and does not poison later mutations', () async {
    final store = FailingChatStore();
    final notifier = NotificationsNotifier(store: store);
    NotificationModel fold(NotificationModel? existing) =>
        NotificationModel.chatMessages(
          tradeId: 'order-1',
          fromSolver: false,
          count: (existing?.chatUnreadCount ?? 0) + 1,
          at: DateTime.utc(2026),
        );
    await notifier.addChatMessage(
      messageId: 'm1',
      cardId: 'chat-order-1',
      fold: fold,
    );
    expect(notifier.hasProcessedChatMessage('m1'), isFalse);
    expect(await store.isProcessed('msg:m1'), isFalse);
    await notifier.addChatMessage(
      messageId: 'm1',
      cardId: 'chat-order-1',
      fold: fold,
    );
    await notifier.addChatMessage(
      messageId: 'm1',
      cardId: 'chat-order-1',
      fold: fold,
    );
    expect(snapshot(notifier).single.chatUnreadCount, 1);
    expect(await store.isProcessed('msg:m1'), isTrue);
  });

  test(
    'storeless message replay is deduplicated after clearing the card',
    () async {
      final notifier = NotificationsNotifier();
      NotificationModel fold(NotificationModel? existing) =>
          NotificationModel.chatMessages(
            tradeId: 'order-1',
            fromSolver: false,
            count: (existing?.chatUnreadCount ?? 0) + 1,
            at: DateTime.utc(2026),
          );
      await notifier.addChatMessage(
        messageId: 'm1',
        cardId: 'chat-order-1',
        fold: fold,
      );
      await notifier.addChatMessage(
        messageId: 'm1',
        cardId: 'chat-order-1',
        fold: fold,
      );
      expect(snapshot(notifier).single.chatUnreadCount, 1);
      await notifier.deleteAll();
      await notifier.addChatMessage(
        messageId: 'm1',
        cardId: 'chat-order-1',
        fold: fold,
      );
      expect(snapshot(notifier), isEmpty);
    },
  );

  test('mark-all and delete execute after a pending chat fold', () async {
    for (final delete in [false, true]) {
      final store = SembastNotificationsStore(
        factory: newDatabaseFactoryMemory(),
      );
      final notifier = NotificationsNotifier(store: store);
      final pending = notifier.addChatMessage(
        messageId: 'm1',
        cardId: 'chat-order-1',
        fold:
            (_) => NotificationModel.chatMessages(
              tradeId: 'order-1',
              fromSolver: false,
              count: 1,
              at: DateTime.utc(2026),
            ),
      );
      if (delete) {
        await notifier.deleteAll();
      } else {
        await notifier.markAllAsRead();
      }
      await pending;
      if (delete) {
        expect(snapshot(notifier), isEmpty);
        expect(await store.loadAll(), isEmpty);
      } else {
        expect(snapshot(notifier).single.isRead, isTrue);
        expect((await store.loadAll()).single.isRead, isTrue);
      }
    }
  });
}

class FailingChatStore extends SembastNotificationsStore {
  FailingChatStore() : super(factory: newDatabaseFactoryMemory());
  bool fail = true;

  @override
  Future<NotificationModel?> saveChatMessage({
    required String messageId,
    required String cardId,
    required NotificationModel? Function(NotificationModel? existing) fold,
  }) {
    if (fail) {
      fail = false;
      throw StateError('injected chat write failure');
    }
    return super.saveChatMessage(
      messageId: messageId,
      cardId: cardId,
      fold: fold,
    );
  }
}
