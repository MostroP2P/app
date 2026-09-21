import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';
import '../../../support/provider_harness.dart';

void main() {
  late StreamController<TradeTouch> touches;
  late ProviderContainer container;

  setUp(() => touches = StreamController<TradeTouch>.broadcast());
  tearDown(() => touches.close());

  /// Mounts [provider] and returns every value it emits. A test whose
  /// provider is still following when it ends disposes the container itself:
  /// the safety poll would otherwise be a pending timer when the binding
  /// checks its invariants.
  Future<List<T>> observe<T>(
    WidgetTester tester,
    ProviderListenable<AsyncValue<T>> provider,
    List<Override> overrides,
  ) async {
    container = createContainer(
      overrides: [
        tradeTouchProvider.overrideWith((ref) => touches.stream),
        ...overrides,
      ],
    );
    final observed = <T>[];
    container.listen<AsyncValue<T>>(provider, (_, next) {
      if (next.hasValue) observed.add(next.requireValue);
    }, fireImmediately: true);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const SizedBox()),
    );
    await tester.pump();
    return observed;
  }

  Future<void> ring(WidgetTester tester, String? orderId) async {
    touches.add(TradeTouch(orderId: orderId));
    await tester.pump();
    await tester.pump();
  }

  group('tradeStatusProvider', () {
    late OrderStatus current;
    late int lookups;

    setUp(() {
      current = OrderStatus.active;
      lookups = 0;
    });

    List<Override> lookup() => [
      tradeStatusLookupProvider.overrideWithValue((orderId) async {
        lookups++;
        return current;
      }),
    ];

    testWidgets('re-reads the status the moment its trade is touched', (
      tester,
    ) async {
      // Arrange
      final observed = await observe(
        tester,
        tradeStatusProvider('order-1'),
        lookup(),
      );
      expect(observed, [OrderStatus.active]);

      // Act: the daemon's fiat-sent lands; no poll interval elapses.
      current = OrderStatus.fiatSent;
      await ring(tester, 'order-1');

      // Assert
      expect(observed, [OrderStatus.active, OrderStatus.fiatSent]);
      container.dispose();
    });

    testWidgets('re-reads on each of two identical touches in a row', (
      tester,
    ) async {
      // Arrange: equal values must not be deduplicated away on the path here.
      await observe(tester, tradeStatusProvider('order-1'), lookup());
      final before = lookups;

      // Act
      await ring(tester, 'order-1');
      await ring(tester, 'order-1');

      // Assert
      expect(lookups, before + 2);
      container.dispose();
    });

    testWidgets('ignores a touch of another trade', (tester) async {
      // Arrange
      await observe(tester, tradeStatusProvider('order-1'), lookup());
      final before = lookups;

      // Act
      await ring(tester, 'order-2');

      // Assert
      expect(lookups, before);
      container.dispose();
    });

    testWidgets('re-reads on a resync, whatever trade it follows', (
      tester,
    ) async {
      // Arrange
      final observed = await observe(
        tester,
        tradeStatusProvider('order-1'),
        lookup(),
      );

      // Act: the stream fell behind and cannot say which touches it lost.
      current = OrderStatus.fiatSent;
      await ring(tester, null);

      // Assert
      expect(observed.last, OrderStatus.fiatSent);
      container.dispose();
    });

    testWidgets('is not re-read every two seconds any more', (tester) async {
      // Arrange
      await observe(tester, tradeStatusProvider('order-1'), lookup());
      final before = lookups;

      // Act
      await tester.pump(const Duration(seconds: 10));

      // Assert
      expect(lookups, before);
      container.dispose();
    });

    testWidgets(
      'still catches a change nothing announced, on the safety poll',
      (tester) async {
        // Arrange
        final observed = await observe(
          tester,
          tradeStatusProvider('order-1'),
          lookup(),
        );

        // Act
        current = OrderStatus.fiatSent;
        await tester.pump(tradeSafetyPollInterval);
        await tester.pump();

        // Assert
        expect(observed.last, OrderStatus.fiatSent);
        container.dispose();
      },
    );

    testWidgets('stops once the trade is over', (tester) async {
      // Arrange
      current = OrderStatus.success;
      await observe(tester, tradeStatusProvider('order-1'), lookup());
      final before = lookups;

      // Act
      await ring(tester, 'order-1');
      await tester.pump(tradeSafetyPollInterval);

      // Assert: no read, and no timer left for the binding to complain about.
      expect(lookups, before);
    });

    testWidgets('keeps following after escrow settles, until payout succeeds', (
      tester,
    ) async {
      // Arrange
      current = OrderStatus.settledHoldInvoice;
      final observed = await observe(
        tester,
        tradeStatusProvider('order-1'),
        lookup(),
      );

      // Act
      current = OrderStatus.success;
      await ring(tester, 'order-1');

      // Assert
      expect(observed, [OrderStatus.settledHoldInvoice, OrderStatus.success]);
    });
  });

  group('the invoice providers', () {
    late List<TradeInfo> trades;
    late int reads;

    setUp(() {
      trades = [fakeTrade(id: 't1')];
      reads = 0;
    });

    List<Override> reader() => [
      tradeListReaderProvider.overrideWithValue(() async {
        reads++;
        return trades;
      }),
    ];

    testWidgets('hand over the hold invoice the moment the row gets it', (
      tester,
    ) async {
      // Arrange
      final observed = await observe(
        tester,
        tradeHoldInvoiceProvider('order-t1'),
        reader(),
      );
      expect(observed, [null]);

      // Act
      trades = [fakeTrade(id: 't1', holdInvoice: 'lnbc1hold')];
      await ring(tester, 'order-t1');

      // Assert
      expect(observed, [null, 'lnbc1hold']);
    });

    testWidgets('no longer read the trades table twice a second', (
      tester,
    ) async {
      // Arrange
      await observe(tester, tradeInfoStreamProvider('order-t1'), reader());
      final before = reads;

      // Act
      await tester.pump(const Duration(seconds: 10));

      // Assert
      expect(reads, before);
      container.dispose();
    });

    testWidgets('give the full trade with the invoice, then stop', (
      tester,
    ) async {
      // Arrange
      final observed = await observe(
        tester,
        tradeInfoStreamProvider('order-t1'),
        reader(),
      );

      // Act
      trades = [
        fakeTrade(
          id: 't1',
          holdInvoice: 'lnbc1hold',
          amountSats: BigInt.from(5000),
        ),
      ];
      await ring(tester, 'order-t1');
      final before = reads;
      await ring(tester, 'order-t1');

      // Assert
      expect(observed.last?.holdInvoice, 'lnbc1hold');
      expect(observed.last?.order.amountSats, BigInt.from(5000));
      expect(reads, before);
    });

    testWidgets('survive a failed read and try again on the next touch', (
      tester,
    ) async {
      // Arrange
      var fail = true;
      final observed = await observe(
        tester,
        tradeHoldInvoiceProvider('order-t1'),
        [
          tradeListReaderProvider.overrideWithValue(() async {
            if (fail) throw StateError('bridge hiccup');
            return [fakeTrade(id: 't1', holdInvoice: 'lnbc1hold')];
          }),
        ],
      );

      // Act
      fail = false;
      await ring(tester, 'order-t1');

      // Assert
      expect(observed, ['lnbc1hold']);
    });
  });

  group('tradeAmountProvider', () {
    testWidgets('yields the amount the moment the order gets one', (
      tester,
    ) async {
      // Arrange
      BigInt? sats;
      final observed = await observe(tester, tradeAmountProvider('order-1'), [
        orderReaderProvider.overrideWithValue(
          (orderId) async => fakeTrade(id: '1', amountSats: sats).order,
        ),
      ]);
      expect(observed, [null]);

      // Act
      sats = BigInt.from(21000);
      await ring(tester, 'order-1');

      // Assert
      expect(observed, [null, BigInt.from(21000)]);
    });
  });
}
