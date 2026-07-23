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
    // same slash can arrive more than once. Keyed on the source event id, it
    // must yield exactly one persisted, visible notification whose cause
    // survives a restart.
    NotificationModel slashFor(String eventId) => NotificationModel.bondSlashed(
          id: eventId,
          orderId: 'order-1',
          amountSats: 1000,
          disputeCause: true,
        );

    test('replay keeps a single visible notification (in-memory dedup)',
        () async {
      final store = SembastNotificationsStore(
        factory: newDatabaseFactoryMemory(),
        path: 'n.db',
      );
      final notifier = NotificationsNotifier(store: store);
      await notifier.loadInitialData();

      var latest = const <NotificationModel>[];
      final removeListener = notifier.addListener((s) => latest = s);

      await notifier.add(slashFor('gift-wrap-evt-1'));
      await notifier.add(slashFor('gift-wrap-evt-1')); // replay, same id

      expect(latest.length, 1);
      expect(latest.single.id, 'gift-wrap-evt-1');
      removeListener();
    });

    test('persisted cause survives restart; replay stays deduplicated',
        () async {
      final factory = newDatabaseFactoryMemory();
      const path = 'n.db';

      // First session: live delivery plus a same-event replay.
      final store1 = SembastNotificationsStore(factory: factory, path: path);
      await store1.save(slashFor('gift-wrap-evt-1'));
      await store1.save(slashFor('gift-wrap-evt-1'));
      expect((await store1.loadAll()).length, 1);

      // Restart: a fresh store over the same persisted database.
      final store2 = SembastNotificationsStore(factory: factory, path: path);
      final restored = await store2.loadAll();
      expect(restored.length, 1);
      expect(restored.single.id, 'gift-wrap-evt-1');
      expect(restored.single.detail?['cause'], 'dispute');
      expect(
        restored.single.resolvedMessage(l10n),
        contains('dispute resolution'),
      );

      // A post-restart replay of the same event still yields one record.
      await store2.save(slashFor('gift-wrap-evt-1'));
      expect((await store2.loadAll()).length, 1);
    });
  });
}
