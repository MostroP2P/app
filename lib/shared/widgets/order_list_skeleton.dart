import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Shimmer skeleton shown while the order book is loading.
///
/// Renders 5 placeholder cards matching the redesigned order card's
/// [OrderBookPalette] surfaces, radius, and list spacing in both themes.
class OrderListSkeleton extends StatelessWidget {
  const OrderListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = OrderBookPalette.of(context);
    return Semantics(
      label: AppLocalizations.of(context).loadingOrders,
      child: Shimmer.fromColors(
        // Card tone over the lighter list well, pulsing toward the inner
        // panel tone — matches how a loaded card sits on [bgWell].
        baseColor: pal.bgCard,
        highlightColor: pal.bgElevated,
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          itemCount: 5,
          itemBuilder: (_, __) => const _SkeletonCard(),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  /// Approximate height of a rendered order card.
  static const double _height = 172;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _height,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
    );
  }
}
