import 'package:mostro/core/app_routes.dart';
import 'package:mostro/src/rust/api/types.dart';

/// Pure rules of opening a `mostro:` order link — no widgets, no providers.
/// The link's format and the lookup of its order live in Rust
/// (`rust/src/nostr/order_link.rs`).

/// The scheme a node writes into an order's `source` tag.
const orderLinkScheme = 'mostro';

/// Whether [raw] is meant for this app: a `mostro:` link, in any case. Whether
/// it is a *valid* one is the core's to say.
bool isOrderLink(String raw) =>
    raw.trim().toLowerCase().startsWith('$orderLinkScheme:');

/// Why an order link did not lead to an order.
enum OrderLinkFailure {
  /// The link cannot be read: not an order link, or part of it is missing.
  invalidLink,

  /// No relay answered with the order.
  notFound,

  /// The order exists, but can no longer be taken and the user has no part
  /// in it.
  unavailable,

  /// Changing to the order's node failed.
  nodeChangeFailed,

  /// The trades could not be read, so whether a node change would leave one
  /// behind is unknown.
  tradesUnreadable,
}

/// The failure a `resolveOrderLink` error stands for. The core reports
/// `InvalidOrderLink` and `OrderLinkNotFound` markers; anything else (the
/// bridge, the relays) is as good as not found, and as worth retrying.
OrderLinkFailure orderLinkFailureOf(Object error) =>
    error.toString().contains('InvalidOrderLink')
        ? OrderLinkFailure.invalidLink
        : OrderLinkFailure.notFound;

/// Where an order link leads once its order was found on the active node, or
/// `null` when it leads nowhere ([OrderLinkFailure.unavailable]).
///
/// A participant goes to their trade, where the take screen would send them
/// anyway (#268), and a pending order to the take screen of its side: taking a
/// sell order is buying.
String? orderLinkDestination(OrderInfo order, {required bool participates}) {
  if (participates) return AppRoute.tradeDetailPath(order.id);
  if (order.status != OrderStatus.pending) return null;
  return switch (order.kind) {
    OrderKind.sell => AppRoute.takeSellPath(order.id),
    OrderKind.buy => AppRoute.takeBuyPath(order.id),
  };
}
