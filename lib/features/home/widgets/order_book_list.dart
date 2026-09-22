import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';
import 'package:mostro/features/home/widgets/order_list_item.dart';

/// The order book's rows — one column as a list, two or three as a grid.
///
/// Lifted out of `HomeScreen` so the list's keyed reorder, and the grid's
/// keys without one, can be tested against the delegates the app actually
/// builds.
/// Inline in the screen the only reachable test is a replica of the list,
/// which would keep passing after the real one regressed.
class OrderBookList extends StatelessWidget {
  const OrderBookList({
    super.key,
    required this.orders,
    required this.currencyFlags,
    required this.reasons,
    required this.columns,
    required this.onOrderTap,
  });

  /// Already filtered and sorted — newest first by default, which is what
  /// makes an arriving order shift every row below it.
  final List<OrderItem> orders;
  final Map<String, String> currencyFlags;
  final Map<String, OrderReason> reasons;
  final int columns;
  final void Function(String orderId) onOrderTap;

  /// Handoff 4b: 18 at the sides, cards straight under the filter row, and
  /// enough bottom clearance for the last card to scroll out from under the
  /// create-order button. Shared with the loading skeleton.
  static const listPadding = EdgeInsets.fromLTRB(18, 0, 18, 96);

  static const double _gap = 12;

  @override
  Widget build(BuildContext context) {
    if (columns == 1) {
      // Where each order sits right now, so a row that moved can be found at
      // its new index. A `ValueKey` alone does not do this: a lazy sliver
      // compares the new widget at index *i* against the old element at *i*,
      // and two different keys fail `Widget.canUpdate`, so the element is torn
      // down and a fresh one inflated — strictly worse than no key at all. The
      // index callback is what lets the framework move the element instead,
      // and it is also what keeps the card's `InkWell` splash with its own
      // order rather than with the position it used to occupy.
      //
      // Built on first lookup and discarded with this build: the framework
      // asks only for the keys it currently holds (the visible rows and the
      // cache extent), and a linear scan per key would be O(rows × orders).
      Map<String, int>? indexById;
      int? indexOfKey(Key key) {
        if (key is! ValueKey<String>) return null;
        indexById ??= {for (var i = 0; i < orders.length; i++) orders[i].id: i};
        return indexById![key.value];
      }

      return ListView.separated(
        padding: listPadding,
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: _gap),
        // `separated` builds one child per item *and* one per separator, so a
        // child index is twice its item index — hence the doubling, which is
        // the whole reason Flutter later replaced this parameter with
        // `findItemIndexCallback` (item indices, no arithmetic). That
        // replacement does not exist in the 3.38.2 this repo pins in
        // `ci.yml`, so it can only be adopted when that pin moves. The ignore
        // is for newer local SDKs, where the parameter already warns; on 3.38.2
        // there is nothing to ignore.
        // ignore: deprecated_member_use
        findChildIndexCallback: (key) {
          final index = indexOfKey(key);
          return index == null ? null : index * 2;
        },
        itemBuilder: (context, index) => _card(orders[index]),
      );
    }

    // Masonry, not a fixed-extent grid: a card's height depends on its
    // content and the text scale (wrapping chips, two lines of payment
    // methods), so a fixed tile ratio overflows on long localized copy or
    // large text.
    //
    // The cards are keyed here as well, but the grid does not move them by
    // key: `SliverMasonryGrid` cannot lay out a child moved by
    // `findChildIndexCallback` (#453, flutter_staggered_grid_view 0.7.0).
    // Once an order that had left the book comes back, `performLayout` hits a
    // null layout offset and throws on every frame, blanking the whole grid
    // until a later update lays it out again.
    //
    // The key still earns its place without the callback, for correctness
    // rather than cost: a card whose order moved fails `Widget.canUpdate`, so
    // it is torn down instead of being reused for whatever order landed at
    // its index. A press, hover or focus in progress is cancelled rather than
    // carried over to an order the user never picked — the book shifts on its
    // own as relays deliver, and this is the layout desktop, web and tablets
    // get. The cost is a re-inflate instead of a rebuild per shifted card.
    //
    // TODO(#453): give the delegate the index callback again once the package
    // lays out children moved by it. The regression group in
    // `order_book_list_reorder_test.dart` says whether a version does.
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: listPadding,
          sliver: SliverMasonryGrid(
            gridDelegate: SliverSimpleGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
            ),
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
            delegate: SliverChildBuilderDelegate(
              (context, index) => _card(orders[index]),
              childCount: orders.length,
            ),
          ),
        ),
      ],
    );
  }

  /// Keyed by order id: in the list, where the index callback can find the
  /// key again, an arriving order moves the rows below it instead of leaving
  /// each element with a different order's content; in the grid, where
  /// nothing moves by key, the key is what keeps an element from being reused
  /// for another order.
  Widget _card(OrderItem order) => OrderListItem(
    key: ValueKey(order.id),
    order: order,
    currencyFlags: currencyFlags,
    reason: reasons[order.id],
    onTap: () => onOrderTap(order.id),
  );
}
