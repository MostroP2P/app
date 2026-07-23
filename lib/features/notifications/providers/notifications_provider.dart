import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:mostro/features/notifications/models/notification_model.dart';

// Platform-specific imports — path_provider is only needed on non-web.
import 'package:path_provider/path_provider.dart'
    if (dart.library.html) 'package:mostro/core/stubs/path_provider_stub.dart';
import 'package:sembast/sembast.dart';
import 'package:mostro/features/notifications/providers/sembast_factory_io.dart'
    if (dart.library.html) 'package:mostro/features/notifications/providers/sembast_factory_web.dart';

// ── Sembast persistence store ─────────────────────────────────────────────────

class SembastNotificationsStore {
  SembastNotificationsStore({DatabaseFactory? factory, String? path})
      : _factoryOverride = factory,
        _pathOverride = path;

  static const _dbName = 'notifications.db';
  static const _storeName = 'notifications';

  /// Test seam: when set, bypasses platform factory/path resolution (e.g. an
  /// in-memory Sembast factory for restart/replay tests).
  final DatabaseFactory? _factoryOverride;
  final String? _pathOverride;

  Database? _db;
  Completer<Database>? _opening;
  final _store = intMapStoreFactory.store(_storeName);

  /// Tombstone / processed-event ledger: ids of externally-sourced events that
  /// have already been handled. It survives deletion of the notification record,
  /// so a daemon history replay never resurrects a dismissed notice or resets
  /// the read state of a known one.
  final _processed = StoreRef<String, bool>('processed_events');

  Future<Database> _open() async {
    if (_db != null) return _db!;
    if (_opening != null) return _opening!.future;

    _opening = Completer<Database>();
    try {
      final Database db;
      if (_factoryOverride != null) {
        db = await _factoryOverride.openDatabase(_pathOverride ?? _dbName);
      } else if (kIsWeb) {
        db = await databaseFactoryWeb.openDatabase(_dbName);
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
    await _upsert(await _open(), notification);
  }

  Future<void> _upsert(DatabaseClient client, NotificationModel notification) async {
    final json = Map<String, dynamic>.from(notification.toJson())
      ..removeWhere((_, v) => v == null);
    final finder = Finder(filter: Filter.equals('id', notification.id));
    final existing = await _store.findFirst(client, finder: finder);
    if (existing != null) {
      await _store.update(client, json, finder: finder);
    } else {
      await _store.add(client, json);
    }
  }

  /// Records [notification] and marks its source event processed in a single
  /// transaction, so a crash or a failed write can never leave one side of the
  /// invariant behind — a record without its tombstone would let a later replay
  /// resurrect a notice the user deleted.
  ///
  /// Returns false when the event was already processed (nothing is written).
  /// Both writes commit atomically, so their order here is immaterial.
  Future<bool> saveIfUnprocessed(NotificationModel notification) async {
    final db = await _open();
    return db.transaction((txn) async {
      final already = await _processed.record(notification.id).get(txn) ?? false;
      if (already) return false;
      await _processed.record(notification.id).put(txn, true);
      await _upsert(txn, notification);
      return true;
    });
  }

  Future<void> deleteRecord(String id) async {
    final db = await _open();
    await _store.delete(db, finder: Finder(filter: Filter.equals('id', id)));
  }

  /// Clears the visible notification records but deliberately keeps the
  /// processed-event ledger, so cleared notices are not resurrected by a replay.
  Future<void> deleteAll() async {
    final db = await _open();
    await _store.delete(db);
  }

  Future<bool> isProcessed(String eventId) async {
    final db = await _open();
    return await _processed.record(eventId).get(db) ?? false;
  }

  Future<void> markProcessed(String eventId) async {
    final db = await _open();
    await _processed.record(eventId).put(db, true);
  }
}

// ── Providers ─────────────────────────────────────────────────────────────────

final sembastNotificationsStoreProvider = Provider<SembastNotificationsStore>(
  (ref) => SembastNotificationsStore(),
);

/// All app notifications, backed by Sembast persistence. Records survive
/// restarts and are keyed by a stable id; externally-sourced events go through
/// [NotificationsNotifier.addIfNew], so a daemon history replay yields exactly
/// one record and preserves the user's read/delete state. Single source of
/// truth for the list, the bell, and every producer (listeners and push path).
final notificationsProvider =
    StateNotifierProvider<NotificationsNotifier, List<NotificationModel>>(
  (ref) {
    final store = ref.watch(sembastNotificationsStoreProvider);
    final notifier = NotificationsNotifier(store: store);
    notifier.loadInitialData();
    return notifier;
  },
);

/// Count of unread notifications.
final unreadNotificationCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).where((n) => !n.isRead).length,
);

// ── Notifier ──────────────────────────────────────────────────────────────────

class NotificationsNotifier extends StateNotifier<List<NotificationModel>> {
  NotificationsNotifier({this.store}) : super([]);

  final SembastNotificationsStore? store;

  /// Load persisted notifications into state. Called once on construction
  /// when a [store] is provided.
  ///
  /// Merges the persisted snapshot with whatever is already in state, keyed by
  /// id, so a delayed load never drops (or overwrites with a stale copy) a
  /// notification added live while the load was in flight. Records added this
  /// session win on conflict.
  Future<void> loadInitialData() async {
    if (store == null) return;
    try {
      final loaded = await store!.loadAll();
      final byId = {for (final n in loaded) n.id: n};
      for (final n in state) {
        byId[n.id] = n;
      }
      state = byId.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      debugPrint('NotificationsNotifier: failed to load from Sembast: $e');
    }
  }

  /// Adds a locally-generated notification (unique id). Idempotent by id: a
  /// same-id entry is left untouched rather than replaced, so read state is
  /// never reset. For externally-sourced, replayable events use [addIfNew].
  Future<void> add(NotificationModel notification) async {
    if (state.any((n) => n.id == notification.id)) return;
    state = [notification, ...state];
    try {
      await store?.save(notification);
    } catch (e) {
      debugPrint('NotificationsNotifier: failed to persist add: $e');
    }
  }

  /// Adds an externally-sourced notification keyed by a stable source event id,
  /// exactly once. A replay of an already-processed id (even after the record
  /// was read or deleted) is a no-op, so user-managed state survives the
  /// daemon's history replay across restarts.
  ///
  /// The record and its processed marker are committed in one transaction and
  /// state is published only once that commit succeeds. A failed write leaves
  /// both the database and the state untouched, so the event stays unprocessed
  /// and the next replay retries it instead of the in-memory guard hiding a
  /// half-applied record.
  Future<void> addIfNew(NotificationModel notification) async {
    if (state.any((n) => n.id == notification.id)) return;
    final store = this.store;
    if (store == null) {
      state = [notification, ...state];
      return;
    }
    final bool recorded;
    try {
      recorded = await store.saveIfUnprocessed(notification);
    } catch (e) {
      debugPrint('NotificationsNotifier: failed to persist addIfNew: $e');
      return;
    }
    if (recorded) state = [notification, ...state];
  }

  Future<void> markAsRead(String id) async {
    state = [
      for (final n in state)
        if (n.id == id) n.copyWith(isRead: true) else n,
    ];
    final updated = state.where((n) => n.id == id).firstOrNull;
    if (updated == null) return;
    try {
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