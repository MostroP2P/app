import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:sembast/sembast_memory.dart';

NotificationModel _note(String id, {bool isRead = false}) => NotificationModel(
      id: id,
      type: NotificationType.system,
      title: 'title-$id',
      message: 'message-$id',
      timestamp: DateTime.utc(2026, 1, 1),
      isRead: isRead,
    );

void main() {
  late DatabaseFactory factory;
  late String path;
  var dbCounter = 0;

  setUp(() {
    // MemoryFs, not plain memory: a plain in-memory database is discarded on
    // close, so the migration test could never reopen what it wrote.
    factory = databaseFactoryMemoryFs;
    path = 'notifications-test-${dbCounter++}.db';
  });

  SembastNotificationsStore openStore() =>
      SembastNotificationsStore(factory: factory, path: path);

  test('saving the same id twice leaves one record', () async {
    final store = openStore();

    await store.save(_note('a'));
    await store.save(_note('a', isRead: true));

    final all = await store.loadAll();
    expect(all, hasLength(1));
    expect(all.single.isRead, isTrue);
  });

  test('deleting by id removes only that record', () async {
    final store = openStore();
    await store.save(_note('a'));
    await store.save(_note('b'));

    await store.deleteRecord('a');

    expect((await store.loadAll()).map((n) => n.id), ['b']);
  });

  test('saveAll marks a whole batch read in one commit', () async {
    final store = openStore();
    for (final id in ['a', 'b', 'c']) {
      await store.save(_note(id));
    }

    await store.saveAll([
      for (final n in await store.loadAll()) n.copyWith(isRead: true),
    ]);

    final all = await store.loadAll();
    expect(all, hasLength(3));
    expect(all.every((n) => n.isRead), isTrue);
  });

  /// Records written before the store was keyed by id live under
  /// auto-incrementing integer keys. Reading those with a String-keyed
  /// `StoreRef` throws, so without a migration a user upgrading would lose
  /// their notification history — or crash on open.
  test('adopts records left by the previously int-keyed store', () async {
    final db = await factory.openDatabase(path);
    final legacy = intMapStoreFactory.store('notifications');
    await legacy.add(db, {
      'id': 'legacy-1',
      'type': 'system',
      'title': 'from before',
      'message': 'still here',
      'timestamp': DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      'isRead': false,
    });
    await db.close();

    final all = await openStore().loadAll();

    expect(all.map((n) => n.id), ['legacy-1']);
    expect(all.single.title, 'from before');
  });
}
