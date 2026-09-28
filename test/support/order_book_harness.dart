import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'provider_harness.dart';

/// Overrides the order book to yield [orders], resolved so
/// [filteredOrdersProvider] can be read synchronously afterwards.
///
/// The filters persist (#575), so each book starts from an empty store:
/// otherwise one test's filters would narrow the next test's book.
Future<OrderBookHarness> bookWith(List<OrderItem> orders) async {
  SharedPreferences.setMockInitialValues({});
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

  /// Applies [filters] the way the dialog does.
  Future<void> filter(OrderFilters filters) =>
      container.read(orderFiltersProvider.notifier).set(filters);

  List<String> ids() =>
      container.read(filteredOrdersProvider).map((o) => o.id).toList();
}
