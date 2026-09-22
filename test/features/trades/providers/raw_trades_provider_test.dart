import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/trades_list_fixtures.dart';

/// Longer than the provider's coalescing window, so a burst has settled.
const _settle = Duration(milliseconds: 400);

void main() {
  late StreamController<TradeTouch> touches;
  late StreamController<TradeUpdate> updates;
  late List<TradeInfo> stored;
  late int reads;
  late ProviderContainer container;

  setUp(() {
    touches = StreamController<TradeTouch>.broadcast();
    updates = StreamController<TradeUpdate>.broadcast();
    stored = [];
    reads = 0;
    container = ProviderContainer(
      overrides: [
        tradeTouchProvider.overrideWith((ref) => touches.stream),
        tradeUpdatesProvider.overrideWith((ref) => updates.stream),
        tradeListReaderProvider.overrideWithValue(() async {
          reads++;
          return List.of(stored);
        }),
      ],
    );
    // What the Trades screen does: keep the list watched.
    container.listen(rawTradesProvider, (_, __) {});
  });

  tearDown(() async {
    container.dispose();
    await touches.close();
    await updates.close();
  });

  // After an import, the history replay rebuilds the old trades and files
  // them with `touch_trade` only — never a TradeUpdate, which would raise a
  // notice for every past transition. The list used to hear TradeUpdates
  // alone, so the imported user's trades showed only after a restart.
  test('a row written with only a touch reaches the list', () async {
    expect(await container.read(rawTradesProvider.future), isEmpty);

    stored = [listTrade(id: 'history', status: OrderStatus.success)];
    touches.add(const TradeTouch(orderId: 'history'));
    await Future<void>.delayed(_settle);

    final trades = await container.read(rawTradesProvider.future);
    expect(trades.map((t) => t.id), ['history']);
  });

  test('a resync touch re-reads the list', () async {
    expect(await container.read(rawTradesProvider.future), isEmpty);

    stored = [listTrade(id: 'history', status: OrderStatus.success)];
    touches.add(const TradeTouch());
    await Future<void>.delayed(_settle);

    expect(await container.read(rawTradesProvider.future), hasLength(1));
  });

  test('a burst of touches costs one read, not one per touch', () async {
    await container.read(rawTradesProvider.future);
    final before = reads;

    for (var i = 0; i < 20; i++) {
      touches.add(TradeTouch(orderId: 'o$i'));
    }
    await Future<void>.delayed(_settle);
    await container.read(rawTradesProvider.future);

    expect(reads - before, 1);
  });
}
