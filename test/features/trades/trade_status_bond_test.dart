import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/trades/models/trade_status.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;

/// Phase 0 of `docs/ANTI_ABUSE_BOND.md`: the two bond statuses have a local
/// representation, and it is the one automation reads as `waiting-bond`.
void main() {
  test('both bond statuses map to waitingBond', () {
    expect(
      tradeStatusFromOrderStatus(OrderStatus.waitingTakerBond),
      TradeStatus.waitingBond,
    );
    expect(
      tradeStatusFromOrderStatus(OrderStatus.waitingMakerBond),
      TradeStatus.waitingBond,
    );
  });

  test('the machine name is the contract value', () {
    expect(TradeStatus.waitingBond.machineName, 'waiting-bond');
  });
}
