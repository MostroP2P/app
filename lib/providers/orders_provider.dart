/// Orders provider stub.
///
/// Phase 4 T040 replaces this with a real implementation backed by
/// rust/src/api/orders.rs.
library orders_provider;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Placeholder order info.  Phase 4 replaces with full OrderInfo from types.
class OrderInfo {
  const OrderInfo({required this.id});

  final String id;
}

class OrdersNotifier extends AsyncNotifier<List<OrderInfo>> {
  @override
  Future<List<OrderInfo>> build() async {
    // Phase 4: subscribe to Rust orders stream and cache results.
    return [];
  }
}

final ordersProvider =
    AsyncNotifierProvider<OrdersNotifier, List<OrderInfo>>(
  OrdersNotifier.new,
);
