import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mostro/src/rust/api/types.dart';

/// How long applied deltas wait before the list is handed to the UI.
///
/// A delta is one order, and a cold start or a refetch delivers thousands
/// back to back. Each emission costs every watcher a pass over the book —
/// the filter, the sort, the index — so emitting per delta would rebuild the
/// O(N²) start-up this pipeline exists to remove. Short enough to read as
/// immediate: three frames.
const orderBookFlushInterval = Duration(milliseconds: 50);

/// Where the order book comes from: the Rust bridge, or a script in tests.
abstract interface class OrderDeltaSource {
  /// Starts listening and returns the function that awaits the next delta
  /// (`null` once the stream has ended). Must be called **before**
  /// [snapshot], so no change can fall between the two.
  Future<Future<OrderDelta?> Function()> subscribe();

  /// The whole book and the revision it was read at.
  Future<OrderBookSnapshot> snapshot();
}

/// The Dart copy of the Rust order book, kept current from deltas.
///
/// [T] is what the UI shows for an order. An order is mapped once, when it
/// arrives or changes, and the same object is handed out until it changes
/// again — so a widget selecting one order sees nothing happen while the rest
/// of the book moves, and an event costs one mapping instead of one per order
/// in the book (docs/OPTIMIZATION_PLAN.md PR 3.3).
class OrderBookFeed<T> {
  OrderBookFeed(this._source, {required T Function(OrderInfo) map})
    : _map = map {
    unawaited(_run());
  }

  final OrderDeltaSource _source;
  final T Function(OrderInfo) _map;
  final _controller = StreamController<List<T>>.broadcast();
  final _byId = <String, T>{};

  /// Revision of the last change applied. A delta at or below it is already
  /// in [_byId] — it was inside the snapshot — and applying it could bring
  /// back an order removed since.
  int _revision = 0;

  /// Whether the UI has been given a list yet. Until then an empty book is
  /// not shown: it may only mean the relay has not answered, and "no orders"
  /// flashing before the orders arrive reads as a bug.
  bool _shown = false;
  bool _disposed = false;
  Timer? _flush;

  /// The book, as a list: at once when the first snapshot has orders, then
  /// at most once per [orderBookFlushInterval] while changes arrive.
  Stream<List<T>> get stream => _controller.stream;

  void dispose() {
    _disposed = true;
    _flush?.cancel();
    unawaited(_controller.close());
  }

  Future<void> _run() async {
    try {
      final next = await _source.subscribe();
      if (await _restart()) _emit();

      while (!_disposed) {
        final delta = await next();
        if (delta == null || _disposed) break;
        switch (delta) {
          case OrderDelta_Upserted(:final revision, :final order):
            if (revision <= _revision) continue;
            _revision = revision;
            _byId[order.id] = _map(order);
            _scheduleFlush();
          case OrderDelta_Removed(:final revision, :final orderId):
            if (revision <= _revision) continue;
            _revision = revision;
            if (_byId.remove(orderId) != null) _scheduleFlush();
          case OrderDelta_Resync():
            final wasShowing = _shown;
            final worthShowing = await _restart();
            if (wasShowing || worthShowing) _scheduleFlush();
          case OrderDelta_Loaded():
            // The relay confirmed the book: an empty one is really empty.
            if (!_shown) _scheduleFlush();
        }
      }
    } catch (e, st) {
      if (!_disposed) _controller.addError(e, st);
    }
    if (!_disposed) {
      _flush?.cancel();
      await _controller.close();
    }
  }

  /// Replace the copy with a fresh snapshot, and say whether it is worth
  /// showing on its own: it has orders, or the relay already confirmed the
  /// book — then an empty one is really empty. That second case is a feed
  /// created after the EOSE (Home re-created after a visit to another tab):
  /// the `loaded` delta is long gone and will not come again.
  Future<bool> _restart() async {
    final snapshot = await _source.snapshot();
    debugPrint(
      '[orderBook] snapshot: ${snapshot.orders.length} orders '
      'at revision ${snapshot.revision}',
    );
    _byId
      ..clear()
      ..addEntries(snapshot.orders.map((o) => MapEntry(o.id, _map(o))));
    _revision = snapshot.revision;
    return _byId.isNotEmpty || snapshot.loaded;
  }

  void _scheduleFlush() {
    _flush ??= Timer(orderBookFlushInterval, () {
      _flush = null;
      _emit();
    });
  }

  void _emit() {
    if (_disposed) return;
    _shown = true;
    _controller.add(List<T>.unmodifiable(_byId.values));
  }
}
