import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:mostro/features/notifications/models/notification_model.dart';

// Platform-specific imports — path_provider is only needed on non-web.
import 'package:path_provider/path_provider.dart'
    if (dart.library.html) 'dart:html';
import 'package:sembast/sembast_io.dart';
import 'package:sembast/sembast_memory.dart' show databaseFactoryMemory;

// ── Sembast persistence store ─────────────────────────────────────────────────

class SembastNotificationsStore {
  static const _dbName = 'notifications.db';
  static const _storeName = 'notifications';

  Database? _db;
  Completer<Database>? _opening;
  final _store = intMapStoreFactory.store(_storeName);

  Future<Database> _open() async {
    if (_db != null) return _db!;
    if (_opening != null) return _opening!.future;

    _opening = Completer<Database>();
    try {
      final Database db;
      if (kIsWeb) {
        // TODO(web-push): Replace databaseFactoryMemory with databaseFactoryWeb
        // once sembast_web is added to pubspec.yaml. Without this, web users
        // lose all notifications on page reload (notificationsProviderWithDb
        // regresses to in-memory-only behavior).  Fix: add sembast_web, switch
        // to databaseFactoryWeb, remove the sembast_memory import.
        debugPrint(
          '[notifications] WARNING: Using in-memory DB on web — '
          'notifications will not persist across reloads. '
          'Add sembast_web to pubspec.yaml to fix.',
        );
        db = await databaseFactoryMemory.openDatabase(_dbName);
      } else {
        final dir = await getApplicationDocumentsDirectory();
        final path = '${dir.path}/$_dbName';
        db = await databaseFactoryIo.openDatabase(path);
      }
      _db = db;
      _opening!.complete(db);
      return db;
    } catch (e, st) {
      _opening!.completeError(e, st);
      _opening = null;
      rethrow;
    }
  }

  Future<List<NotificationModel>> loadAll() async {
    final db = await _open();
    final records = await _store.find(db);
    return records
        .map((r) => NotificationModel.fromJson(Map<String, dynamic>.from(r.value)))
        .toList();
  }

  /// Upsert: updates existing record by id, inserts if not found.
  Future<void> save(NotificationModel notification) async {
    final db = await _open();
    final json = Map<String, dynamic>.from(notification.toJson())
      ..removeWhere((_, v) => v == null);
    final finder = Finder(filter: Filter.equals('id', notification.id));
    final existing = await _store.findFirst(db, finder: finder);
    if (existing != null) {
      await _store.update(db, json, finder: finder);
    } else {
      await _store.add(db, json);
    }
  }

  Future<void> deleteRecord(String id) async {
    final db = await _open();
    await _store.delete(db, finder: Finder(filter: Filter.equals('id', id)));
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
    final notifier = NotificationsNotifier(store: store);
    notifier.loadInitialData();
    return notifier;
  },
);

/// Count of unread notifications (in-memory provider).
final unreadNotificationCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).where((n) => !n.isRead).length,
);

/// Count of unread notifications (DB-backed provider).
final unreadNotificationCountProviderWithDb = Provider<int>(
  (ref) => ref.watch(notificationsProviderWithDb).where((n) => !n.isRead).length,
);

// ── Notifier ──────────────────────────────────────────────────────────────────

class NotificationsNotifier extends StateNotifier<List<NotificationModel>> {
  NotificationsNotifier({this.store}) : super([]);

  final SembastNotificationsStore? store;

  /// Load persisted notifications into state. Called once on construction
  /// when a [store] is provided.
  Future<void> loadInitialData() async {
    if (store == null) return;
    try {
      final notifications = await store!.loadAll();
      state = notifications;
    } catch (e) {
      debugPrint('NotificationsNotifier: failed to load from Sembast: $e');
    }
  }

  Future<void> add(NotificationModel notification) async {
    state = [notification, ...state];
    try {
      await store?.save(notification);
    } catch (e) {
      debugPrint('NotificationsNotifier: failed to persist add: $e');
    }
  }

  Future<void> markAsRead(String id) async {
    state = [
      for (final n in state)
        if (n.id == id) n.copyWith(isRead: true) else n,
    ];
    try {
      final updated = state.firstWhere((n) => n.id == id);
      await store?.save(updated);
    } catch (e) {
      debugPrint('NotificationsNotifier: failed to persist markAsRead: $e');
    }
  }

  void markAllAsRead() {
    state = [for (final n in state) n.copyWith(isRead: true)];
    // Persist each updated record; fire-and-forget is acceptable for bulk
    // read-status updates since ordering doesn't matter here.
    for (final n in state) {
      store?.save(n).catchError((Object e) {
        debugPrint('NotificationsNotifier: failed to persist markAllAsRead: $e');
      });
    }
  }

  Future<void> delete(String id) async {
    state = state.where((n) => n.id != id).toList();
    try {
      await store?.deleteRecord(id);
    } catch (e) {
      debugPrint('NotificationsNotifier: failed to persist delete: $e');
    }
  }

  Future<void> deleteAll() async {
    state = [];
    try {
      await store?.deleteAll();
    } catch (e) {
      debugPrint('NotificationsNotifier: failed to persist deleteAll: $e');
    }
  }

  // ── Bridge stubs ────────────────────────────────────────────────────────────

  /// Called from bridge listener for on_trade_updated events.
  void onTradeUpdated(String orderId, String status) {
    final notification = NotificationModel(
      id: const Uuid().v4(),
      type: NotificationType.tradeUpdate,
      title: 'Trade updated',
      message: 'Order $orderId status changed to $status.',
      timestamp: DateTime.now(),
      orderId: orderId,
      detail: {'Order': orderId, 'Status': status},
    );
    add(notification);
  }

  /// Called from bridge listener for on_new_message events.
  void onNewMessage(String orderId) {
    final notification = NotificationModel(
      id: const Uuid().v4(),
      type: NotificationType.message,
      title: 'New message',
      message: 'You have a new message for order $orderId.',
      timestamp: DateTime.now(),
      orderId: orderId,
      detail: {'Order': orderId},
    );
    add(notification);
  }
}