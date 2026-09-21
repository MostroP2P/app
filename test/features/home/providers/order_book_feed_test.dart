import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/providers/order_book_feed.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';

/// A scripted bridge: the test decides what the snapshot holds and when each
/// delta arrives.
class _FakeSource implements OrderDeltaSource {
  _FakeSource({
    this.revision = 0,
    this.loaded = false,
    List<OrderInfo> orders = const [],
  }) : orders = List.of(orders);

  int revision;
  bool loaded;
  List<OrderInfo> orders;
  int snapshotReads = 0;
  bool subscribedBeforeFirstSnapshot = false;
  bool _subscribed = false;
  final _deltas = StreamController<OrderDelta>();

  void send(OrderDelta delta) => _deltas.add(delta);
  Future<void> end() => _deltas.close();

  @override
  Future<Future<OrderDelta?> Function()> subscribe() async {
    _subscribed = true;
    final queue = StreamIterator(_deltas.stream);
    return () async => await queue.moveNext() ? queue.current : null;
  }

  @override
  Future<OrderBookSnapshot> snapshot() async {
    if (snapshotReads == 0) subscribedBeforeFirstSnapshot = _subscribed;
    snapshotReads++;
    return OrderBookSnapshot(
      revision: revision,
      orders: List.of(orders),
      loaded: loaded,
    );
  }
}

OrderInfo _order(String id, {OrderStatus status = OrderStatus.pending}) =>
    fakeTrade(id: id, status: status).order;

void main() {
  late _FakeSource source;
  late OrderBookFeed<OrderInfo> feed;
  late List<List<OrderInfo>> emissions;
  late int mapped;

  /// Starts a feed over [source] whose "mapping" is the identity, counted.
  Future<void> start(WidgetTester tester) async {
    mapped = 0;
    emissions = [];
    feed = OrderBookFeed<OrderInfo>(
      source,
      map: (info) {
        mapped++;
        return info;
      },
    );
    feed.stream.listen(emissions.add);
    await tester.pump();
  }

  Future<void> flush(WidgetTester tester) async {
    await tester.pump(orderBookFlushInterval);
    await tester.pump();
  }

  List<String> ids(List<OrderInfo> orders) =>
      orders.map((o) => o.id).toList()..sort();

  tearDown(() => feed.dispose());

  testWidgets('subscribes before it reads the snapshot', (tester) async {
    // Arrange / Act
    source = _FakeSource();
    await start(tester);

    // Assert: the other order leaves a gap a change can fall into.
    expect(source.subscribedBeforeFirstSnapshot, isTrue);
  });

  testWidgets('shows a snapshot that has orders at once', (tester) async {
    // Arrange
    source = _FakeSource(revision: 7, orders: [_order('a'), _order('b')]);

    // Act
    await start(tester);

    // Assert
    expect(emissions, hasLength(1));
    expect(ids(emissions.single), ['order-a', 'order-b']);
  });

  testWidgets('stays silent on an empty book until the relay confirms it', (
    tester,
  ) async {
    // Arrange: an empty snapshot may only mean the relay has not answered.
    source = _FakeSource();
    await start(tester);
    expect(emissions, isEmpty);

    // Act
    source.send(const OrderDelta.loaded());
    await flush(tester);

    // Assert
    expect(emissions, [isEmpty]);
  });

  testWidgets('shows an empty book at once when the relay already confirmed '
      'it', (tester) async {
    // Arrange: Home re-created after a visit to another tab. The feed's EOSE
    // came long ago and will not come again.
    source = _FakeSource(revision: 3, loaded: true);

    // Act
    await start(tester);

    // Assert: no `loaded` delta was needed.
    expect(emissions, [isEmpty]);
  });

  testWidgets('a resync to an unconfirmed empty book shows nothing new '
      'until it is confirmed', (tester) async {
    // Arrange: nothing on screen yet, and a node switch clears the book.
    source = _FakeSource();
    await start(tester);

    // Act
    source.send(const OrderDelta.resync());
    await flush(tester);

    // Assert
    expect(emissions, isEmpty);
  });

  testWidgets('applies upserts and removals', (tester) async {
    // Arrange
    source = _FakeSource(revision: 1, orders: [_order('a')]);
    await start(tester);

    // Act
    source.send(OrderDelta.upserted(revision: 2, order: _order('b')));
    source.send(const OrderDelta.removed(revision: 3, orderId: 'order-a'));
    await flush(tester);

    // Assert
    expect(ids(emissions.last), ['order-b']);
  });

  testWidgets('skips a delta that is already inside the snapshot', (
    tester,
  ) async {
    // Arrange: subscribed first, so the removal of "gone" is heard although
    // the snapshot, read after it, no longer has the order — and a re-insert
    // that followed is in the snapshot already.
    source = _FakeSource(revision: 5, orders: [_order('gone')]);
    await start(tester);

    // Act
    source.send(const OrderDelta.removed(revision: 4, orderId: 'order-gone'));
    source.send(const OrderDelta.loaded());
    await flush(tester);

    // Assert
    expect(ids(emissions.last), ['order-gone']);
  });

  testWidgets('turns a burst of deltas into one emission', (tester) async {
    // Arrange
    source = _FakeSource(revision: 0, orders: [_order('seed')]);
    await start(tester);
    final before = emissions.length;

    // Act: a cold start against a busy node.
    for (var n = 1; n <= 300; n++) {
      source.send(OrderDelta.upserted(revision: n, order: _order('n$n')));
    }
    await flush(tester);

    // Assert
    expect(emissions.length, before + 1);
    expect(emissions.last, hasLength(301));
  });

  testWidgets('maps only the order that changed', (tester) async {
    // Arrange
    source = _FakeSource(revision: 1, orders: [_order('a'), _order('b')]);
    await start(tester);
    final untouched = emissions.last.firstWhere((o) => o.id == 'order-a');
    final mappedBefore = mapped;

    // Act
    source.send(
      OrderDelta.upserted(
        revision: 2,
        order: _order('b', status: OrderStatus.active),
      ),
    );
    await flush(tester);

    // Assert: one mapping, and the other order is the very same object, so
    // a screen selecting it sees no change at all.
    expect(mapped, mappedBefore + 1);
    expect(
      identical(emissions.last.firstWhere((o) => o.id == 'order-a'), untouched),
      isTrue,
    );
  });

  testWidgets('starts over from a fresh snapshot on a resync', (tester) async {
    // Arrange
    source = _FakeSource(revision: 1, orders: [_order('old-node')]);
    await start(tester);

    // Act: a node switch replaced the book.
    source
      ..revision = 9
      ..orders = [_order('new-node')];
    source.send(const OrderDelta.resync());
    await flush(tester);

    // Assert
    expect(source.snapshotReads, 2);
    expect(ids(emissions.last), ['order-new-node']);
  });

  testWidgets('a resync to an empty book empties the list', (tester) async {
    // Arrange
    source = _FakeSource(revision: 1, orders: [_order('old-node')]);
    await start(tester);

    // Act
    source
      ..revision = 2
      ..orders = [];
    source.send(const OrderDelta.resync());
    await flush(tester);

    // Assert: it was showing orders, so silence would leave them on screen.
    expect(emissions.last, isEmpty);
  });

  testWidgets('closes when the bridge stream ends', (tester) async {
    // Arrange
    source = _FakeSource(revision: 1, orders: [_order('a')]);
    await start(tester);
    var done = false;
    feed.stream.listen(null, onDone: () => done = true);

    // Act
    await source.end();
    await flush(tester);

    // Assert
    expect(done, isTrue);
  });
}
