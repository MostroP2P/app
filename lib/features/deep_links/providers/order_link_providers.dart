import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/src/rust/api/order_link.dart' as order_link_api;

/// Finds the order behind a `mostro:` link through the core; injectable so the
/// order link screen's outcomes can be tested without Rust.
final orderLinkResolverProvider =
    Provider<Future<order_link_api.OrderLinkTarget> Function(String link)>(
      (ref) => (link) => order_link_api.resolveOrderLink(link: link),
    );
