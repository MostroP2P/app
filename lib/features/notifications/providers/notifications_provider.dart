import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart';

import 'package:mostro/features/notifications/models/notification_model.dart';

// ── Sembast persistence store ─────────────────────────────────────────────────

class SembastNotificationsStore {
  static const _dbName = 'notifications.db';
  static const _storeName = 'notifications';

  Database? _db;
  final _store = intMapStoreFactory.store(_storeName);

  Future<Database> _open() async {
    if (_db != null) return _db!;
    if (kIsWeb) {
      // TODO(web-push): Replace with databaseFactoryWeb once sembast_web is
      // added to pubspec.yaml. Using in-memory factory as a placeholder.
      _db = await databaseFactoryMemory.openDatabase(_dbName);
    } else {
      final dir = await getApplicationDocumentsDirectory();
      final path = '${dir.path}/$_dbName';
      _db = await databaseFactoryIo.openDatabase(path);
    }
    return _db!;
  }

  Future<List<NotificationModel>> loadAll() async {
    final db = await _open();
    final records = await _store.find(db);
    return records
        .map(
          (r) => NotificationModel.fromJson(
            Map<String, dynamic>.from(r.value),
          ),
        )
        .toList();
  }

  Future<void> save(NotificationModel notification) async {
    final db = await _open();
    final json = notification.toJson()
      ..removeWhere((_, v) => v == null);
    await _store.add(db, Map<String, dynamic>.from(json));
  }

  Future<void> deleteRecord(String id) async {
    final db = await _open();
    final finder = Finder(filter: Filter.equals('id', id));
    await _store.delete(db, finder: finder);
  }

  Future<void> deleteAll() async {
    final db = await _open();
    await _store.delete(db);
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final sembastNotificationsStoreProvider = Provider<SembastNotificationsStore>(
  (ref) => SembastNotificationsStore(),
);

/// In-memory list of all app notifications (backward-compat, no persistence).
///
/// Prefer [notificationsProviderWithDb] for new code.
final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, List<NotificationModel>>(
  (ref) => NotificationsNotifier(),
);

/// Notifications provider backed by Sembast persistence.
final notificationsProviderWithDb =
    StateNotifierProvider<NotificationsNotifier, List<NotificationModel>>(
  (ref) {
    final store = ref.watch(sembastNotificationsStoreProvider);
    return NotificationsNotifier(store: store);
  },
);

/// Count of unread notifications.
final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref.watch(notificationsProvider).where((n) => !n.isRead).length;
});

// ── Notifier ──────────────────────────────────────────────────────────────────

class NotificationsNotifier extends StateNotifier<List<NotificationModel>> {
  NotificationsNotifier({this.store}) : super([]);

  final SembastNotificationsStore? store;

  void add(NotificationModel notification) {
    state = [notification, ...state];
    store?.save(notification);
  }

  void markAsRead(String id) {
    state = [
      for (final n in state)
        if (n.id == id) n.copyWith(isRead: true) else n,
    ];
  }

  void markAllAsRead() {
    state = [for (final n in state) n.copyWith(isRead: true)];
  }

  void delete(String id) {
    state = state.where((n) => n.id != id).toList();
    store?.deleteRecord(id);
  }

  void deleteAll() {
    state = [];
    store?.deleteAll();
  }

  // ── Bridge stubs ────────────────────────────────────────────────────────────

  /// TODO(bridge): Call from bridge listener for on_trade_updated events.
  void onTradeUpdated(String orderId, String status) {}

  /// TODO(bridge): Call from bridge listener for on_new_message events.
  void onNewMessage(String orderId) {}
}
