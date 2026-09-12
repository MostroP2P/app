import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/rate/providers/rating_providers.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/features/trades/providers/trade_rows_provider.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/shared/providers/peer_nym_provider.dart';
import 'package:mostro/src/rust/api/types.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/fake_trades.dart';
import '../../../support/provider_harness.dart';

/// A container whose trades are [trades], each live status taken from
/// [live] (falling back to the persisted one), nobody rated, and every
/// counterparty named `peer`.
ProviderContainer _container(
  List<TradeInfo> trades, {
  Map<String, OrderStatus> live = const {},
}) => createContainer(
  overrides: [
    rawTradesProvider.overrideWith((ref) async => trades),
    for (final t in trades)
      tradeStatusProvider(
        t.order.id,
      ).overrideWith((ref) => Stream.value(live[t.order.id] ?? t.order.status)),
    for (final t in trades)
      tradeRatingProvider(t.order.id).overrideWith((ref) async => null),
    for (final t in trades)
      peerNymProvider(t.counterpartyPubkey).overrideWith(
        (ref) async =>
            const NymIdentity(pseudonym: 'peer', iconIndex: 0, colorHue: 0),
      ),
  ],
);

Future<List<TradeRow>> _rows(ProviderContainer container) async {
  // Subscribe first, as a screen would: the live status and the pseudonym
  // are only fetched once something listens to the rows.
  container.listen(tradeRowsProvider, (_, __) {});
  await container.read(rawTradesProvider.future);
  await pumpEventQueue();
  return container.read(tradeRowsProvider).value!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('tradeRowsProvider', () {
    test('the live status wins over the persisted one', () async {
      final c = _container(
        [fakeTrade(id: 'a', status: OrderStatus.waitingPayment)],
        live: {'order-a': OrderStatus.active},
      );
      final row = (await _rows(c)).single;
      expect(row.status, OrderStatus.active);
      // The fixture is a buyer: active means the fiat is theirs to send.
      expect(row.state.verb, TradeRowVerb.sendPayment);
    });

    test('a terminal trade keeps its persisted status', () async {
      final c = _container(
        [fakeTrade(id: 'a', status: OrderStatus.canceled)],
        live: {'order-a': OrderStatus.active},
      );
      expect((await _rows(c)).single.status, OrderStatus.canceled);
    });

    test('a durable rating marker closes a successful trade', () async {
      final rated = fakeTrade(id: 'a', status: OrderStatus.success);
      final c = _container([
        TradeInfo(
          id: rated.id,
          order: rated.order,
          role: rated.role,
          counterpartyPubkey: rated.counterpartyPubkey,
          currentStep: rated.currentStep,
          tradeKeyIndex: rated.tradeKeyIndex,
          startedAt: rated.startedAt,
          ratedAt: 2000,
        ),
      ]);
      expect((await _rows(c)).single.state.group, TradeGroup.closed);
    });

    test('names the counterparty once its key is known', () async {
      final c = _container([fakeTrade(id: 'a')]);
      expect((await _rows(c)).single.peerHandle, 'peer');
    });
  });

  group('needsActionCountProvider', () {
    test('counts only the trades whose next step is the user\'s', () async {
      final c = _container([
        fakeTrade(id: 'buyer-active', status: OrderStatus.active),
        fakeTrade(
          id: 'seller-active',
          status: OrderStatus.active,
          role: TradeRole.seller,
        ),
        fakeTrade(id: 'done', status: OrderStatus.canceled),
      ]);
      await _rows(c);
      expect(c.read(needsActionCountProvider), 1);
      // The tab badge is the same figure.
      expect(c.read(orderBookNotificationCountProvider), 1);
    });

    test('ignores the list filter', () async {
      final c = _container([
        fakeTrade(id: 'buyer-active', status: OrderStatus.active),
      ]);
      await _rows(c);
      await c
          .read(tradeListFilterProvider.notifier)
          .select(TradeListFilter.cancelled);
      expect(c.read(needsActionCountProvider), 1);
    });
  });

  group('groupedTradeRowsProvider', () {
    test('applies the filter before grouping', () async {
      final c = _container([
        fakeTrade(id: 'active', status: OrderStatus.active, startedAt: 5),
        fakeTrade(id: 'gone', status: OrderStatus.canceled, startedAt: 9),
      ]);
      await _rows(c);
      await c
          .read(tradeListFilterProvider.notifier)
          .select(TradeListFilter.cancelled);

      final groups = c.read(groupedTradeRowsProvider).value!;
      expect(groups.map((g) => g.group), [TradeGroup.closed]);
      expect(groups.single.rows.single.orderId, 'order-gone');
    });
  });

  group('TradeListFilterNotifier', () {
    test('restores the filter chosen in an earlier session', () async {
      SharedPreferences.setMockInitialValues({
        kTradeListFilterKey: TradeListFilter.completed.name,
      });
      final notifier = TradeListFilterNotifier();
      await pumpEventQueue();
      expect(notifier.state, TradeListFilter.completed);
    });

    test('persists a pick', () async {
      final notifier = TradeListFilterNotifier();
      await notifier.select(TradeListFilter.active);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kTradeListFilterKey), 'active');
    });

    test('a pick made while loading is not overwritten by the load', () async {
      SharedPreferences.setMockInitialValues({
        kTradeListFilterKey: TradeListFilter.completed.name,
      });
      final disk = Completer<SharedPreferences>();
      final notifier = TradeListFilterNotifier(prefs: () => disk.future);

      final saved = notifier.select(TradeListFilter.active);
      disk.complete(await SharedPreferences.getInstance());
      await saved;
      await pumpEventQueue();

      expect(notifier.state, TradeListFilter.active);
    });
  });

  group('needsActionIdsProvider', () {
    test(
      'null until the trades load, then the ids that need the user',
      () async {
        final c = _container([
          fakeTrade(id: 'buyer-active', status: OrderStatus.active),
          fakeTrade(id: 'done', status: OrderStatus.canceled),
        ]);
        expect(c.read(needsActionIdsProvider), isNull);
        await _rows(c);
        expect(c.read(needsActionIdsProvider), {'order-buyer-active'});
      },
    );
  });
}
