import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;

void main() {
  group('orderStatusToFilter', () {
    test('maps every protocol status to its bucket', () {
      const expected = {
        OrderStatus.pending: TradeStatusFilter.pending,
        OrderStatus.waitingBuyerInvoice: TradeStatusFilter.waitingInvoice,
        OrderStatus.waitingPayment: TradeStatusFilter.waitingPayment,
        OrderStatus.waitingTakerBond: TradeStatusFilter.waitingPayment,
        OrderStatus.waitingMakerBond: TradeStatusFilter.waitingPayment,
        OrderStatus.active: TradeStatusFilter.active,
        OrderStatus.inProgress: TradeStatusFilter.active,
        OrderStatus.fiatSent: TradeStatusFilter.fiatSent,
        OrderStatus.settledHoldInvoice: TradeStatusFilter.payoutPending,
        OrderStatus.success: TradeStatusFilter.success,
        OrderStatus.settledByAdmin: TradeStatusFilter.success,
        OrderStatus.completedByAdmin: TradeStatusFilter.success,
        OrderStatus.canceled: TradeStatusFilter.canceled,
        OrderStatus.expired: TradeStatusFilter.canceled,
        OrderStatus.cooperativelyCanceled: TradeStatusFilter.canceled,
        OrderStatus.canceledByAdmin: TradeStatusFilter.canceled,
        OrderStatus.dispute: TradeStatusFilter.dispute,
      };

      // Guards against an unmapped status silently slipping through.
      expect(expected.length, OrderStatus.values.length);
      expected.forEach((status, bucket) {
        expect(orderStatusToFilter(status), bucket, reason: '$status');
      });
    });
  });
}
