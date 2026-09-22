import 'package:flutter/widgets.dart';

import 'package:mostro/features/home/providers/home_order_providers.dart';

/// Slowest horizontal release, in logical pixels per second, that counts as a
/// swipe. Below it a drag was hesitant or diagonal and changes nothing.
const double minSideSwipeVelocity = 300;

/// How many times its vertical travel a swipe's horizontal travel must be
/// (about 27° off horizontal at most). Past that it is a diagonal gesture,
/// not a side switch.
const double minSideSwipeDominance = 2;

/// The side a swipe leads to from [current], or null when it leads nowhere.
///
/// [velocity] is the horizontal release speed and [travel] the finger's whole
/// movement on both axes. The swipe moves like the Buy | Sell tabs are laid
/// out: a swipe to the left (negative velocity) brings in the tab on the
/// right, Sell; a swipe to the right brings back Buy. Swiping past the last
/// tab, too slowly, or diagonally does nothing.
OrderType? sideAfterSwipe(OrderType current, double velocity, Offset travel) {
  if (velocity.abs() < minSideSwipeVelocity) return null;
  if (travel.dx.abs() < minSideSwipeDominance * travel.dy.abs()) return null;
  final next = velocity < 0 ? OrderType.sell : OrderType.buy;
  return next == current ? null : next;
}

/// Switches the order book between Buy and Sell on a horizontal swipe over
/// [child], so the thumb never has to reach the tabs at the top.
///
/// Only a horizontal drag is claimed: a vertical one still scrolls the list.
/// The horizontal recognizer reports movement on its own axis only, so the
/// finger's real travel is read from the pointer positions, which are not
/// projected, to tell a diagonal gesture from a swipe.
class SideSwipe extends StatefulWidget {
  const SideSwipe({
    super.key,
    required this.current,
    required this.onChanged,
    required this.child,
  });

  final OrderType current;
  final ValueChanged<OrderType> onChanged;
  final Widget child;

  @override
  State<SideSwipe> createState() => _SideSwipeState();
}

class _SideSwipeState extends State<SideSwipe> {
  Offset _start = Offset.zero;
  Offset _travel = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Swipes that start between cards count too.
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (details) {
        _start = details.globalPosition;
        _travel = Offset.zero;
      },
      onHorizontalDragUpdate: (details) {
        _travel = details.globalPosition - _start;
      },
      onHorizontalDragEnd: (details) {
        final next = sideAfterSwipe(
          widget.current,
          details.primaryVelocity ?? 0,
          _travel,
        );
        if (next != null) widget.onChanged(next);
      },
      child: widget.child,
    );
  }
}
