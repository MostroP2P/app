import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/providers/invoice_providers.dart';
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';

const _started = 1757678400;

Future<int?> _deadline({
  required TradeInfo? trade,
  required int? stepStart,
}) async {
  final container = ProviderContainer(
    overrides: [
      tradeInfoProvider.overrideWith((ref, id) async => trade),
      mostroNodeProvider.overrideWith((ref) async => null),
      invoiceStepStartLookupProvider.overrideWithValue((id) async => stepStart),
    ],
  );
  addTearDown(container.dispose);
  final sub = container.listen(invoiceDeadlineProvider('order-1'), (_, _) {});
  addTearDown(sub.close);
  return container.read(invoiceDeadlineProvider('order-1').future);
}

void main() {
  test('a recorded step start plus the node window is the deadline', () async {
    final deadline = await _deadline(
      trade: fakeTrade(isMine: true, startedAt: 1),
      stepStart: _started,
    );
    expect(deadline, _started + kDefaultInvoiceStepSeconds);
  });

  test(
    'a taker without a recorded step start counts from the take, not a fixed 900 s timeout',
    () async {
      // The taker's first reply is consumed by take_order before any status
      // cursor is written (PR #438 review).
      final deadline = await _deadline(
        trade: fakeTrade(isMine: false, startedAt: _started),
        stepStart: null,
      );
      expect(deadline, _started + kDefaultInvoiceStepSeconds);
    },
  );

  test('a maker without a recorded step start has no deadline', () async {
    // Their started_at is when the order was created, not when it was taken.
    final deadline = await _deadline(
      trade: fakeTrade(isMine: true, startedAt: _started),
      stepStart: null,
    );
    expect(deadline, isNull);
  });
}
