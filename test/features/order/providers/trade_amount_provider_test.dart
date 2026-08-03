import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';
import '../../../support/provider_harness.dart';

const _orderId = 'order-1';

/// The coarse public listing, whose `amountSats` is the full order figure
/// rather than this taker's calculated share.
OrderInfo _publicOrder({int? amountSats}) => OrderInfo(
      id: _orderId,
      kind: OrderKind.sell,
      status: OrderStatus.pending,
      fiatAmount: 100,
      fiatCode: 'USD',
      paymentMethod: 'Wire',
      premium: 0,
      creatorPubkey: 'maker',
      createdAt: 0,
      isMine: false,
      amountSats: amountSats == null ? null : BigInt.from(amountSats),
      rating: 0,
      totalReviews: 0,
      daysActive: 0,
    );

void main() {
  group('tradeAmountProvider', () {
    test('does not emit the public amount while a trade row exists without one',
        () async {
      var getOrderCalls = 0;
      final container = createContainer(overrides: [
        bridgeListTradesProvider.overrideWithValue(
          () async => [fakeTrade(orderId: _orderId)], // amountSats still null
        ),
        bridgeGetOrderProvider.overrideWithValue((_) async {
          getOrderCalls++;
          return _publicOrder(amountSats: 10000);
        }),
      ]);

      container.listen(tradeAmountProvider(_orderId), (_, __) {});
      final first = await container.read(tradeAmountProvider(_orderId).future);

      expect(first, isNull,
          reason: 'the coarse listing figure would size the invoice wrongly');
      expect(getOrderCalls, 0,
          reason: 'a persisted trade row is authoritative; do not ask the book');
    });

    test('emits the per-role amount once the trade row carries it', () async {
      final container = createContainer(overrides: [
        bridgeListTradesProvider.overrideWithValue(
          () async => [fakeTrade(orderId: _orderId, amountSats: 9526)],
        ),
        bridgeGetOrderProvider
            .overrideWithValue((_) async => _publicOrder(amountSats: 10000)),
      ]);

      container.listen(tradeAmountProvider(_orderId), (_, __) {});

      expect(
        await container.read(tradeAmountProvider(_orderId).future),
        BigInt.from(9526),
      );
    });

    test('falls back to the book only when we follow no trade', () async {
      final container = createContainer(overrides: [
        bridgeListTradesProvider.overrideWithValue(() async => []),
        bridgeGetOrderProvider
            .overrideWithValue((_) async => _publicOrder(amountSats: 10000)),
      ]);

      container.listen(tradeAmountProvider(_orderId), (_, __) {});

      expect(
        await container.read(tradeAmountProvider(_orderId).future),
        BigInt.from(10000),
      );
    });
  });

  group('tradeStatusProvider', () {
    test('prefers the trade row over the coarse public bucket', () async {
      final container = createContainer(overrides: [
        bridgeListTradesProvider.overrideWithValue(
          () async => [
            fakeTrade(orderId: _orderId, status: OrderStatus.waitingTakerBond),
          ],
        ),
        // The daemon publishes WaitingTakerBond as the coarse `pending`.
        bridgeGetOrderProvider.overrideWithValue((_) async => _publicOrder()),
      ]);

      container.listen(tradeStatusProvider(_orderId), (_, __) {});

      expect(
        await container.read(tradeStatusProvider(_orderId).future),
        OrderStatus.waitingTakerBond,
      );
    });

    test('falls back to the book when no trade row exists', () async {
      final container = createContainer(overrides: [
        bridgeListTradesProvider.overrideWithValue(() async => []),
        bridgeGetOrderProvider.overrideWithValue((_) async => _publicOrder()),
      ]);

      container.listen(tradeStatusProvider(_orderId), (_, __) {});

      expect(
        await container.read(tradeStatusProvider(_orderId).future),
        OrderStatus.pending,
      );
    });
  });
}
