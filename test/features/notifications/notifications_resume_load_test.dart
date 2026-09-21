import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:sembast/sembast_memory.dart';

NotificationModel _note(String id) => NotificationModel(
  id: id,
  type: NotificationType.system,
  title: 'title-$id',
  message: 'message-$id',
  timestamp: DateTime.utc(2026, 1, 1),
);

/// A store whose read can be held open, so a deletion can land between the
/// snapshot being taken and the merge publishing it — the resume race.
class _HeldStore extends SembastNotificationsStore {
  _HeldStore({required super.factory, required super.path});

  Completer<void>? hold;

  @override
  Future<List<NotificationModel>> loadAll() async {
    final gate = hold;
    if (gate != null) await gate.future;
    return super.loadAll();
  }
}

void main() {
  late _HeldStore store;
  late NotificationsNotifier notifier;

  setUp(() async {
    final factory = newDatabaseFactoryMemory();
    store = _HeldStore(
      factory: factory,
      path: 'resume-${DateTime.now().microsecondsSinceEpoch}.db',
    );
    notifier = NotificationsNotifier(store: store);
    await notifier.loadInitialData();
    await notifier.add(_note('a'));
    await notifier.add(_note('b'));
    expect(notifier.state.map((n) => n.id), unorderedEquals(['a', 'b']));
  });

  test(
    'a notice deleted while a resume load is reading stays deleted',
    () async {
      // Arrange — the load's snapshot is taken before the delete...
      store.hold = Completer<void>();
      final load = notifier.loadInitialData();
      await Future<void>.delayed(Duration.zero);

      // Act — ...the user deletes, then the snapshot returns.
      await notifier.delete('a');
      store.hold!.complete();
      await load;

      // Assert
      expect(notifier.state.map((n) => n.id), ['b']);
    },
  );

  test(
    'a clear-all while a resume load is reading wins over the snapshot',
    () async {
      store.hold = Completer<void>();
      final load = notifier.loadInitialData();
      await Future<void>.delayed(Duration.zero);

      await notifier.deleteAll();
      store.hold!.complete();
      await load;

      expect(notifier.state, isEmpty);
    },
  );

  test(
    'a notice added while a resume load is reading survives the merge',
    () async {
      store.hold = Completer<void>();
      final load = notifier.loadInitialData();
      await Future<void>.delayed(Duration.zero);

      await notifier.add(_note('c'));
      store.hold!.complete();
      await load;

      expect(notifier.state.map((n) => n.id), unorderedEquals(['a', 'b', 'c']));
    },
  );

  test(
    'a delete after the load finished is not remembered by the next load',
    () async {
      await notifier.delete('a');
      await notifier.loadInitialData();
      expect(notifier.state.map((n) => n.id), ['b']);

      // The next load starts clean: a fresh record with the deleted id is a
      // different notice and comes back.
      await notifier.add(_note('a'));
      await notifier.loadInitialData();
      expect(notifier.state.map((n) => n.id), unorderedEquals(['a', 'b']));
    },
  );
}
