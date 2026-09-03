import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';

import '../../support/fake_orders.dart';
import '../../support/provider_harness.dart';

/// Let the stream event reach the provider and its dependents.
Future<void> settle() =>
    Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  group('orderByIdProvider', () {
    test('resolves an order by id and null for an unknown one', () async {
      final container = createContainer(overrides: [
        orderBookProvider.overrideWith(
          (ref) => Stream.value([fakeOrder(id: 'a'), fakeOrder(id: 'b')]),
        ),
      ]);
      container.listen(orderBookProvider, (_, __) {});
      await container.read(orderBookProvider.future);

      expect(container.read(orderByIdProvider('a'))?.id, 'a');
      expect(container.read(orderByIdProvider('missing')), isNull);
    });

    test('does not rebuild a screen whose order did not change', () async {
      final book = StreamController<List<OrderItem>>();
      addTearDown(book.close);

      final container = createContainer(overrides: [
        orderBookProvider.overrideWith((ref) => book.stream),
      ]);

      var rebuilds = 0;
      container.listen(orderByIdProvider('a'), (_, __) => rebuilds++);

      book.add([fakeOrder(id: 'a', premium: 1), fakeOrder(id: 'b', premium: 1)]);
      await settle();
      expect(rebuilds, 1, reason: 'the first value is a change');

      // A different order moves. Watching one order must not repaint the
      // screens watching the others — the whole point of the index.
      book.add([fakeOrder(id: 'a', premium: 1), fakeOrder(id: 'b', premium: 9)]);
      await settle();
      expect(rebuilds, 1, reason: 'order a is untouched');

      // Its own order moving must still come through.
      book.add([fakeOrder(id: 'a', premium: 5), fakeOrder(id: 'b', premium: 9)]);
      await settle();
      expect(rebuilds, 2, reason: 'order a changed');
    });
  });
}
