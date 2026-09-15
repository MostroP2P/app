import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/notifications/models/notification_model.dart';

// Platform-specific imports — the data directory only exists off web.
import 'package:path/path.dart' as p;
import 'package:mostro/core/storage/app_data_dir.dart'
    if (dart.library.html) 'package:mostro/core/storage/app_data_dir_web.dart';
import 'package:sembast/sembast.dart';
import 'package:mostro/features/notifications/providers/sembast_factory_io.dart'
    if (dart.library.html) 'package:mostro/features/notifications/providers/sembast_factory_web.dart';

// ── Sembast persistence store ─────────────────────────────────────────────────

class SembastNotificationsStore {
  SembastNotificationsStore({DatabaseFactory? factory, String? path})
    : _factoryOverride = factory,
      _pathOverride = path;

  static const _dbName = 'notifications.db';

  /// The int-keyed store this feature shipped with.
  static const _legacyStoreName = 'notifications';

  /// Records keyed by notification id. A separate store name, not a re-typed
  /// view of the old one: the two must not share physical records, or
  /// migrating out of the old shape would delete what it just wrote.
  static const _storeName = 'notifications_v2';

  /// Test seam: when set, bypasses platform factory/path resolution (e.g. an
  /// in-memory Sembast factory for restart/replay tests).
  final DatabaseFactory? _factoryOverride;
  final String? _pathOverride;

  Database? _db;
  Completer<Database>? _opening;

  /// Keyed by notification id. Before this, the store used auto-incrementing
  /// integer keys and every write looked its record up with a `Finder` — a
  /// full-store scan per save, and O(n) scans for an O(n) bulk update.
  final _store = StoreRef<String, Map<String, Object?>>(_storeName);

  /// The int-keyed shape this store used to have. Only read, and only once
  /// per database, by [_migrateLegacyRecords].
  final _legacyStore = intMapStoreFactory.store(_legacyStoreName);

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
        final dir = await appDataDirPath();
        db = await databaseFactoryIo.openDatabase(p.join(dir, _dbName));
      }
      await _migrateLegacyRecords(db);
      _db = db;
      _opening!.complete(db);
      return db;
    } catch (e, st) {
      _opening!.completeError(e, st);
      _opening = null;
      rethrow;
    }
  }

  /// Re-key records written by the previous int-keyed store.
  ///
  /// Reading an int-keyed record through a `StoreRef<String, ...>` throws, so
  /// without this an upgrade would either lose the user's notification history
  /// or fail on open. Runs inside one transaction and clears the old records,
  /// so it is a no-op from the second launch onwards.
  Future<void> _migrateLegacyRecords(Database db) async {
    final legacy = await _legacyStore.find(db);
    if (legacy.isEmpty) return;
    await db.transaction((txn) async {
      for (final record in legacy) {
        final value = Map<String, Object?>.from(record.value);
        final id = value['id'];
        if (id is String) {
          await _store.record(id).put(txn, value);
        }
      }
      await _legacyStore.delete(txn);
    });
  }

  Future<List<NotificationModel>> loadAll() async {
    final db = await _open();
    final records = await _store.find(db);
    return records
        .map(
          (r) => NotificationModel.fromJson(Map<String, dynamic>.from(r.value)),
        )
        .toList();
  }

  /// Upsert: updates existing record by id, inserts if not found.
  Future<void> save(NotificationModel notification) async {
    await _upsert(await _open(), notification);
  }

  /// Persist every notification in [notifications] in a single transaction.
  ///
  /// Bulk read-status updates used to fire one independent, un-awaited write
  /// per notification, each committing separately.
  Future<void> saveAll(List<NotificationModel> notifications) async {
    if (notifications.isEmpty) return;
    final db = await _open();
    await db.transaction((txn) async {
      for (final notification in notifications) {
        await _upsert(txn, notification);
      }
    });
  }

  Future<void> _upsert(
    DatabaseClient client,
    NotificationModel notification,
  ) async {
    final json = Map<String, Object?>.from(notification.toJson())
      ..removeWhere((_, v) => v == null);
    await _store.record(notification.id).put(client, json);
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
      final already =
          await _processed.record(notification.id).get(txn) ?? false;
      if (already) return false;
      await _processed.record(notification.id).put(txn, true);
      await _upsert(txn, notification);
      return true;
    });
  }

  /// Folds one chat message into its trade's card, exactly once per message.
  ///
  /// In one transaction: returns null when [messageId] was already counted;
  /// otherwise marks it, hands [fold] the card as stored (null when there is
  /// none, or the user deleted it) and writes what [fold] returns. A null
  /// result consumes a deliberately suppressed event without creating a card.
  /// The ledger is the same one [saveIfUnprocessed] uses, under a `msg:` prefix, so a
  /// message never counts twice even after its card was cleared.
  Future<NotificationModel?> saveChatMessage({
    required String messageId,
    required String cardId,
    required NotificationModel? Function(NotificationModel? existing) fold,
  }) async {
    final db = await _open();
    return db.transaction((txn) async {
      final ledgerKey = 'msg:$messageId';
      if (await _processed.record(ledgerKey).get(txn) ?? false) return null;
      await _processed.record(ledgerKey).put(txn, true);
      final raw = await _store.record(cardId).get(txn);
      final existing =
          raw == null
              ? null
              : NotificationModel.fromJson(Map<String, dynamic>.from(raw));
      final card = fold(existing);
      if (card != null) await _upsert(txn, card);
      return card;
    });
  }

  /// Read the latest stored card in the transaction, including when initial
  /// hydration has not populated the notifier yet. Never save a stale UI copy.
  Future<List<NotificationModel>> markRead({String? id}) async {
    final db = await _open();
    return db.transaction((txn) async {
      final records = await _store.find(
        txn,
        finder: id == null ? null : Finder(filter: Filter.byKey(id)),
      );
      final updated = <NotificationModel>[];
      for (final record in records) {
        final card = NotificationModel.fromJson(
          Map<String, dynamic>.from(record.value),
        ).copyWith(isRead: true);
        await _upsert(txn, card);
        updated.add(card);
      }
      return updated;
    });
  }

  Future<void> deleteRecord(String id) async {
    final db = await _open();
    await _store.record(id).delete(db);
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
    StateNotifierProvider<NotificationsNotifier, List<NotificationModel>>((
      ref,
    ) {
      final store = ref.watch(sembastNotificationsStoreProvider);
      final notifier = NotificationsNotifier(store: store);
      notifier.loadInitialData();
      return notifier;
    });

/// Count of unread notifications.
final unreadNotificationCountProvider = Provider<int>(
  (ref) => ref.watch(notificationsProvider).where((n) => !n.isRead).length,
);

// ── Notifier ──────────────────────────────────────────────────────────────────

class NotificationsNotifier extends StateNotifier<List<NotificationModel>> {
  NotificationsNotifier({this.store}) : super([]);

  final SembastNotificationsStore? store;

  // Commit and publish mutations in invocation order. Loads remain separate
  // and merge with committed state, so a slow hydration never blocks a read.
  Future<void> _mutationTail = Future<void>.value();
  final Set<String> _processedMessages = {};
  final Map<String, int> _readRevisions = {};
  int _readClock = 0;
  int _allReadRevision = 0;

  /// Capture before processing an event; a read during any await invalidates it.
  int readRevision(String cardId) {
    final revision = _readRevisions[cardId] ?? 0;
    return revision > _allReadRevision ? revision : _allReadRevision;
  }

  /// Avoid secure-storage reads and transactions for this session's replays.
  bool hasProcessedChatMessage(String messageId) =>
      _processedMessages.contains(messageId);

  Future<void> _mutate(Future<void> Function() operation) {
    final next = _mutationTail.then((_) async {
      if (mounted) await operation();
    });
    _mutationTail = next.catchError((Object e, StackTrace st) {
      debugPrint('NotificationsNotifier: mutation failed: $e\n$st');
    });
    return next;
  }

  /// Ids deleted while a load was reading the store. The snapshot the load
  /// returns still holds them, so the merge must not bring them back.
  final Set<String> _deletedDuringLoad = {};

  /// Loads in flight; deletions are only tracked while this is non-zero.
  int _loadsInFlight = 0;

  /// Set by [deleteAll] while a load is in flight: the whole snapshot that
  /// load returns predates the wipe and is discarded.
  bool _wipedDuringLoad = false;

  /// Load persisted notifications into state. Called once on construction
  /// when a [store] is provided, and again on every resume (the resync
  /// hydration, lib/core/lifecycle/resume_resync.dart).
  ///
  /// Merges the persisted snapshot with whatever is already in state, keyed by
  /// id, so a delayed load never drops (or overwrites with a stale copy) a
  /// notification added live while the load was in flight. Records added this
  /// session win on conflict. A record the user deleted while the load was
  /// reading is not resurrected: [delete] and [deleteAll] note the removal,
  /// and the merge skips it.
  Future<void> loadInitialData() async {
    if (store == null) return;
    _loadsInFlight++;
    try {
      final loaded = await store!.loadAll();
      if (!mounted || _wipedDuringLoad) return;
      final byId = {
        for (final n in loaded)
          if (!_deletedDuringLoad.contains(n.id)) n.id: n,
      };
      for (final n in state) {
        byId[n.id] = n;
      }
      state =
          byId.values.toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      debugPrint('NotificationsNotifier: failed to load from Sembast: $e');
    } finally {
      _loadsInFlight--;
      if (_loadsInFlight == 0) {
        _deletedDuringLoad.clear();
        _wipedDuringLoad = false;
      }
    }
  }

  /// Adds a locally-generated notification (unique id). Idempotent by id: a
  /// same-id entry is left untouched rather than replaced, so read state is
  /// never reset. For externally-sourced, replayable events use [addIfNew].
  Future<void> add(NotificationModel notification) => _mutate(() async {
    if (state.any((n) => n.id == notification.id)) return;
    state = [notification, ...state];
    try {
      await store?.save(notification);
    } catch (e) {
      debugPrint('NotificationsNotifier: failed to persist add: $e');
    }
  });

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
  Future<void> addIfNew(NotificationModel notification) => _mutate(() async {
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
    if (recorded && mounted) state = [notification, ...state];
  });

  Future<void> markAsRead(String id) {
    _readRevisions[id] = ++_readClock;
    return _markRead(id: id);
  }

  Future<void> markAllAsRead() {
    _allReadRevision = ++_readClock;
    return _markRead();
  }

  Future<void> _markRead({String? id}) => _mutate(() async {
    try {
      final updated =
          store == null
              ? [
                for (final n in state)
                  if (id == null || n.id == id) n.copyWith(isRead: true),
              ]
              : await store!.markRead(id: id);
      if (!mounted) return;
      final byId = {for (final n in state) n.id: n};
      for (final n in updated) {
        byId[n.id] = n;
      }
      state =
          byId.values.toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      debugPrint('NotificationsNotifier: failed to persist mark-read: $e');
    }
  });

  Future<void> delete(String id) => _mutate(() async {
    if (_loadsInFlight > 0) _deletedDuringLoad.add(id);
    state = state.where((n) => n.id != id).toList();
    try {
      await store?.deleteRecord(id);
    } catch (e) {
      debugPrint('NotificationsNotifier: failed to persist delete: $e');
    }
  });

  Future<void> deleteAll() => _mutate(() async {
    if (_loadsInFlight > 0) _wipedDuringLoad = true;
    state = [];
    try {
      await store?.deleteAll();
    } catch (e) {
      debugPrint('NotificationsNotifier: failed to persist deleteAll: $e');
    }
  });

  /// Records one chat message on its trade's card (see
  /// [SembastNotificationsStore.saveChatMessage]): the card moves to the top
  /// with what [fold] made of it, and a message already counted changes
  /// nothing. A failed write leaves state as it was, so a later delivery of
  /// the same message retries.
  Future<void> addChatMessage({
    required String messageId,
    required String cardId,
    required NotificationModel? Function(NotificationModel? existing) fold,
  }) => _mutate(() async {
    if (_processedMessages.contains(messageId)) return;
    final store = this.store;
    if (store == null) {
      final card = fold(state.where((n) => n.id == cardId).firstOrNull);
      _processedMessages.add(messageId);
      if (card != null) _putOnTop(card);
      return;
    }
    final NotificationModel? card;
    try {
      card = await store.saveChatMessage(
        messageId: messageId,
        cardId: cardId,
        fold: fold,
      );
    } catch (e) {
      debugPrint('NotificationsNotifier: failed to persist chat card: $e');
      return;
    }
    _processedMessages.add(messageId);
    if (card != null) _putOnTop(card);
  });

  void _putOnTop(NotificationModel card) {
    if (!mounted) return;
    // A new message brings a deleted card back on purpose; a load in flight
    // must not drop it again.
    _deletedDuringLoad.remove(card.id);
    state = [card, ...state.where((n) => n.id != card.id)];
  }
}

// ── Hydration (resume) ────────────────────────────────────────────────────────

/// Merge the persisted notifications back into state — the cold-start load,
/// which keeps whatever was added live. The cards themselves come from the
/// Rust streams the resync replays, deduplicated by `addIfNew`.
Future<void> hydrateNotifications(ProviderContainer container) =>
    container.read(notificationsProvider.notifier).loadInitialData();
