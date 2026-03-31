import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Shimmer skeleton shown while the order book is loading.
///
/// Renders 5 placeholder cards per DESIGN_SYSTEM.md §9.1.
/// Colors: baseColor #1E2230, highlightColor #2A2D35.
class OrderListSkeleton extends StatelessWidget {
  const OrderListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: AppLocalizations.of(context).loadingOrders,
      child: Shimmer.fromColors(
        baseColor: const Color(0xFF1E2230),
        highlightColor: const Color(0xFF2A2D35),
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm,
          ),
          itemCount: 5,
          itemBuilder: (_, __) => const _SkeletonCard(),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  static const double _height = 100;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _height,
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    );
  }
}
