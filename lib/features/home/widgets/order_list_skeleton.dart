import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/widgets/order_book_list.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Shimmer skeleton shown while the order book is loading — never a centred
/// spinner.
///
/// Five placeholder cards with the order card's radius, height and list
/// spacing, in the card's inset tone pulsing one step lighter.
class OrderListSkeleton extends StatelessWidget {
  const OrderListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    return Semantics(
      label: AppLocalizations.of(context).loadingOrders,
      child: Shimmer.fromColors(
        baseColor: Color.alphaBlend(pal.inset, pal.bg),
        highlightColor: Color.alphaBlend(pal.chipBorder, pal.bg),
        period: const Duration(milliseconds: 1800),
        child: ListView.separated(
          padding: OrderBookList.listPadding,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 5,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, __) => const _SkeletonCard(),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  /// An order card with one line of payment methods at the default text
  /// scale.
  static const double _height = 190;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
    );
  }
}
