import 'package:flutter/material.dart';

import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/home/providers/order_reason_provider.dart';
import 'package:mostro/features/home/widgets/order_list_item.dart';

/// The order book's rows — one column as a list, two or three as a grid.
///
/// Lifted out of `HomeScreen` so the keyed-reorder behaviour below can be
/// tested against the delegates the app actually builds. Inline in the screen
/// the only reachable test is a replica of the list, which would keep passing
/// after the real one regressed.
class OrderBookList extends StatelessWidget {
  const OrderBookList({
    super.key,
    required this.orders,
    required this.currencyFlags,
    required this.reasons,
    required this.columns,
    required this.onOrderTap,
  });

  /// Already filtered and sorted — newest first, which is what makes an
  /// arriving order shift every row below it.
  final List<OrderItem> orders;
  final Map<String, String> currencyFlags;
  final Map<String, OrderReason> reasons;
  final int columns;
  final void Function(String orderId) onOrderTap;

  /// Mock list: 8px top, 16px sides, 90px bottom clearance, 12px card gap.
  static const _listPadding = EdgeInsets.fromLTRB(16, 8, 16, 90);

  @override
  Widget build(BuildContext context) {
    // Where each order sits right now, so a row that moved can be found at its
    // new index. A `ValueKey` alone does not do this: a lazy sliver compares
    // the new widget at index *i* against the old element at *i*, and two
    // different keys fail `Widget.canUpdate`, so the element is torn down and a
    // fresh one inflated — strictly worse than no key at all. The index
    // callback is what lets the framework move the element instead, and it is
    // also what keeps the card's `InkWell` splash with its own order rather
    // than with the position it used to occupy.
    //
    // Built on first lookup and discarded with this build: the framework asks
    // only for the keys it currently holds (the visible rows and the cache
    // extent), and a linear scan per key would be O(rows × orders).
    Map<String, int>? indexById;
    int? indexOfKey(Key key) {
      if (key is! ValueKey<String>) return null;
      indexById ??= {
        for (var i = 0; i < orders.length; i++) orders[i].id: i,
      };
      return indexById![key.value];
    }

    if (columns == 1) {
      return ListView.separated(
        padding: _listPadding,
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
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

    return GridView.builder(
      padding: _listPadding,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: orders.length,
      findChildIndexCallback: indexOfKey,
      itemBuilder: (context, index) => _card(orders[index]),
    );
  }

  Widget _card(OrderItem order) => OrderListItem(
    // Keyed by order id so an arriving order moves the rows below it instead
    // of leaving each element with a different order's content — see
    // `indexOfKey`, without which the key is a pessimisation.
    key: ValueKey(order.id),
    order: order,
    currencyFlags: currencyFlags,
    reason: reasons[order.id],
    onTap: () => onOrderTap(order.id),
  );
}
