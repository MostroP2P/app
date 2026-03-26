/// Trade provider stub.
///
/// Phase 5 T047 replaces this with a real implementation backed by
/// rust/src/api/trades.rs.
library trade_provider;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Placeholder trade info.
class TradeInfo {
  const TradeInfo({required this.id, required this.orderId});

  final String id;
  final String orderId;
}

class TradeNotifier extends AsyncNotifier<TradeInfo?> {
  @override
  Future<TradeInfo?> build() async {
    // Phase 5: load active trade from Rust.
    return null;
  }
}

final tradeProvider =
    AsyncNotifierProvider<TradeNotifier, TradeInfo?>(
  TradeNotifier.new,
);
