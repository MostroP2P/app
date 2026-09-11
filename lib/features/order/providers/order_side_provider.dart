import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/features/home/providers/home_order_providers.dart';

/// Which side the order being created is on. Seeded from the order book's
/// create button and switchable on the screen with the `Buy BTC | Sell BTC`
/// control, so the premium block, the card titles and the preview follow it.
final orderSideProvider = StateProvider<OrderType>((_) => OrderType.sell);
