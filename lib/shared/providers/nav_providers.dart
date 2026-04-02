import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Currently active bottom-nav tab index (0 = Order Book, 1 = My Trades, 2 = Chat).
final bottomNavIndexProvider = StateProvider<int>((_) => 0);
