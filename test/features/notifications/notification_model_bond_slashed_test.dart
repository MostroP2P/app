import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:mostro/features/notifications/models/notification_model.dart';
import 'package:mostro/features/notifications/providers/notifications_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('NotificationModel.bondSlashed — stored data is locale-independent', () {
    test('stores stable keys and raw values, not localized labels', () {
      final n = NotificationModel.bondSlashed(
        id: 'evt-1',
        orderId: 'order-1',
        amountSats: 1000,
        disputeCause: false,
      );

      expect(n.type, NotificationType.bondSlashed);
      expect(n.id, 'evt-1');
      expect(n.orderId, 'order-1');
      expect(n.title, isEmpty);
      expect(n.message, isEmpty);
      expect(n.detail?['bondAmountSats'], '1000');
      expect(n.detail?['cause'], 'timeout');
    });

    test('dispute cause is stored as a stable marker', () {
      final n = NotificationModel.bondSlashed(
        id: 'evt-2',
        orderId: 'order-2',
        amountSats: 500,
        disputeCause: true,
      );
      expect(n.detail?['cause'], 'dispute');
    });

    test('optional fiat and payment method use stable keys', () {
      final n = NotificationModel.bondSlashed(
        id: 'evt-3',
        orderId: 'order-3',
        amountSats: 250,
        disputeCause: false,
        fiatCode: 'USD',
        fiatAmount: 20,
        paymentMethod: 'SEPA',
      );
      expect(n.detail?['fiatCode'], 'USD');
      expect(n.detail?['fiatAmount'], '20');
      expect(n.detail?['paymentMethod'], 'SEPA');
    });

    test('optional fields are omitted when absent', () {
      final n = NotificationModel.bondSlashed(
        id: 'evt-4',
        orderId: 'order-4',
        amountSats: 250,
        disputeCause: false,
      );
      expect(n.detail?.containsKey('fiatCode'), isFalse);
      expect(n.detail?.containsKey('paymentMethod'), isFalse);
    });
  });

  group('NotificationModel.bondSlashed — localized at render time', () {
    test('timeout notice resolves localized title, message and detail', () {
      final n = NotificationModel.bondSlashed(
        id: 'evt-1',
        orderId: 'order-1',
        amountSats: 1000,
        disputeCause: false,
      );

      expect(n.resolvedTitle(l10n), 'Bond slashed');
      expect(n.resolvedMessage(l10n), contains('waiting-state timeout'));
      expect(n.resolvedMessage(l10n), contains('order status is unchanged'));

      final detail = n.resolvedDetail(l10n);
      expect(detail['Cause'], 'Waiting-state timeout');
      expect(detail['Bond amount'], '1000 sats');
      expect(detail['Order'], 'order-1');
    });

    test('dispute notice resolves the dispute copy', () {
      final n = NotificationModel.bondSlashed(
        id: 'evt-2',
        orderId: 'order-2',
        amountSats: 500,
        disputeCause: true,
      );

      expect(n.resolvedMessage(l10n), contains('dispute resolution'));
      expect(n.resolvedDetail(l10n)['Cause'], 'Dispute resolution');
    });

    test('resolved detail includes fiat and payment method when present', () {
      final n = NotificationModel.bondSlashed(
        id: 'evt-3',
        orderId: 'order-3',
        amountSats: 250,
        disputeCause: false,
        fiatCode: 'USD',
        fiatAmount: 20,
        paymentMethod: 'SEPA',
      );

      final detail = n.resolvedDetail(l10n);
      expect(detail['Fiat'], '20 USD');
      expect(detail['Payment method'], 'SEPA');
    });
  });

  group('NotificationModel.bondSlashed — one record per slash across restart',
      () {
    // The daemon replays stored gift-wrap history on reconnect/restart, so the
    // same slash can arrive more than once. Keyed on the source event id and
    // recorded through addIfNew, it must yield exactly one persisted, visible
    // notification that preserves the user's read/delete state across restarts.
    NotificationModel slashFor(String eventId) => NotificationModel.bondSlashed(
          id: eventId,
          orderId: 'order-1',
          amountSats: 1000,
          disputeCause: true,
        );

    // Reads current notifier state without the deprecated debugState getter.
    List<NotificationModel> stateOf(NotificationsNotifier n) {
      late List<NotificationModel> snapshot;
      n.addListener((s) => snapshot = s)();
      return snapshot;
    }

    NotificationsNotifier notifierOver(DatabaseFactory factory, String path) =>
        NotificationsNotifier(
          store: SembastNotificationsStore(factory: factory, path: path),
        );

    test('replay keeps a single visible notification', () async {
      final notifier = notifierOver(newDatabaseFactoryMemory(), 'n.db');
      await notifier.loadInitialData();

      await notifier.addIfNew(slashFor('evt-1'));
      await notifier.addIfNew(slashFor('evt-1')); // replay, same id

      expect(stateOf(notifier).length, 1);
      expect(stateOf(notifier).single.id, 'evt-1');
    });

    test('cause survives restart; post-restart replay stays deduplicated',
        () async {
      final factory = newDatabaseFactoryMemory();
      const path = 'n.db';

      final n1 = notifierOver(factory, path);
      await n1.loadInitialData();
      await n1.addIfNew(slashFor('evt-1'));

      // Restart over the same persisted database.
      final n2 = notifierOver(factory, path);
      await n2.loadInitialData();

      expect(stateOf(n2).length, 1);
      final restored = stateOf(n2).single;
      expect(restored.detail?['cause'], 'dispute');
      expect(restored.resolvedMessage(l10n), contains('dispute resolution'));

      await n2.addIfNew(slashFor('evt-1')); // replay after restart
      expect(stateOf(n2).length, 1);
    });

    test('delayed hydration does not drop a concurrent live add', () async {
      final factory = newDatabaseFactoryMemory();
      const path = 'n.db';

      // A record persisted by a previous session.
      final seed = SembastNotificationsStore(factory: factory, path: path);
      final persisted = slashFor('evt-persisted');
      await seed.save(persisted);
      await seed.markProcessed(persisted.id);

      // New session: hydration is in flight while a live event is added.
      final notifier = notifierOver(factory, path);
      final hydration = notifier.loadInitialData();
      await notifier.addIfNew(slashFor('evt-live'));
      await hydration;

      final ids = stateOf(notifier).map((n) => n.id).toSet();
      expect(ids, {'evt-live', 'evt-persisted'});
    });

    test('read state survives restart and replay', () async {
      final factory = newDatabaseFactoryMemory();
      const path = 'n.db';

      final n1 = notifierOver(factory, path);
      await n1.loadInitialData();
      await n1.addIfNew(slashFor('evt-1'));
      await n1.markAsRead('evt-1');

      // Restart, then the same event replays.
      final n2 = notifierOver(factory, path);
      await n2.loadInitialData();
      await n2.addIfNew(slashFor('evt-1'));

      expect(stateOf(n2).length, 1);
      expect(stateOf(n2).single.isRead, isTrue);
    });

    test('a failed write leaves neither the record nor its marker', () async {
      final factory = newDatabaseFactoryMemory();
      const path = 'n.db';
      final store = SembastNotificationsStore(factory: factory, path: path);
      final notifier = NotificationsNotifier(store: store);
      await notifier.loadInitialData();

      // The record write throws after the marker was written in the same
      // transaction, so the whole commit must roll back.
      await notifier.addIfNew(_FailingNotification(slashFor('evt-1')));

      expect(await store.loadAll(), isEmpty);
      expect(await store.isProcessed('evt-1'), isFalse);
      expect(stateOf(notifier), isEmpty);

      // Still unprocessed, so the next replay records it normally.
      await notifier.addIfNew(slashFor('evt-1'));
      expect(stateOf(notifier).length, 1);
      expect(await store.isProcessed('evt-1'), isTrue);
      expect((await store.loadAll()).length, 1);
    });

    test('deleted notice is not resurrected by restart and replay', () async {
      final factory = newDatabaseFactoryMemory();
      const path = 'n.db';

      final n1 = notifierOver(factory, path);
      await n1.loadInitialData();
      await n1.addIfNew(slashFor('evt-1'));
      await n1.delete('evt-1');

      // Restart, then the daemon replays the deleted slash.
      final n2 = notifierOver(factory, path);
      await n2.loadInitialData();
      await n2.addIfNew(slashFor('evt-1'));

      expect(stateOf(n2), isEmpty);
    });
  });
}

/// Fails when serialized, to inject a write failure inside the store's
/// record-plus-marker transaction.
class _FailingNotification extends NotificationModel {
  _FailingNotification(NotificationModel base)
      : super(
          id: base.id,
          type: base.type,
          title: base.title,
          message: base.message,
          timestamp: base.timestamp,
          orderId: base.orderId,
          detail: base.detail,
        );

  @override
  Map<String, dynamic> toJson() => throw StateError('injected write failure');
}
