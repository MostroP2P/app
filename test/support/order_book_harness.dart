import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';

import 'provider_harness.dart';

/// Overrides the order book to yield [orders], resolved so
/// [filteredOrdersProvider] can be read synchronously afterwards.
Future<OrderBookHarness> bookWith(List<OrderItem> orders) async {
  final container = createContainer(overrides: [
    orderBookProvider.overrideWith((ref) => Stream.value(orders)),
  ]);
  // Keep the autoDispose stream alive so it survives any later awaits.
  container.listen(orderBookProvider, (_, __) {});
  await container.read(orderBookProvider.future);
  return OrderBookHarness(container);
}

class OrderBookHarness {
  OrderBookHarness(this.container);

  final ProviderContainer container;

  void setTab(OrderType type) =>
      container.read(homeOrderTypeProvider.notifier).state = type;

  List<String> ids() =>
      container.read(filteredOrdersProvider).map((o) => o.id).toList();
}
