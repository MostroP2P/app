import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/trades/models/trade_status.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;

/// The status each side of a trade sees (#586).
void main() {
  test(
    'after the release the seller rates, the buyer waits for the payout',
    () {
      expect(
        tradeStatusFor(OrderStatus.settledHoldInvoice, isBuyer: false),
        TradeStatus.pendingRating,
      );
      expect(
        tradeStatusFor(OrderStatus.settledHoldInvoice, isBuyer: true),
        TradeStatus.payoutPending,
      );
    },
  );

  test('every other status reads the same from both sides', () {
    for (final status in OrderStatus.values) {
      if (status == OrderStatus.settledHoldInvoice) continue;
      expect(
        tradeStatusFor(status, isBuyer: false),
        tradeStatusFromOrderStatus(status),
        reason: '$status as seller',
      );
      expect(
        tradeStatusFor(status, isBuyer: true),
        tradeStatusFromOrderStatus(status),
        reason: '$status as buyer',
      );
    }
  });
}
