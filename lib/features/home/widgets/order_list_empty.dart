import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Empty order book: the faded mascot, a title, and one line that says why.
///
/// It blames the filters — and offers to clear them — only when they are
/// what hides the orders: when the tab has none at all, clearing the filters
/// would change nothing, so it says the generic line instead.
class OrderListEmpty extends ConsumerWidget {
  const OrderListEmpty({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final isFiltered = ref.watch(hasActiveOrderFiltersProvider);
    final tabHasOrders = ref.watch(tabHasOrdersProvider);
    final hiddenByFilters = isFiltered && tabHasOrders;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/mostro_mascot.webp',
              height: 64,
              opacity: const AlwaysStoppedAnimation(0.4),
              excludeFromSemantics: true,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.noOrdersAvailable,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: pal.textBody,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hiddenByFilters
                  ? l10n.ordersEmptyFilteredHint
                  : l10n.ordersEmptyHint,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: pal.textSecondary),
            ),
            if (hiddenByFilters) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => clearOrderFilters(ref),
                style: TextButton.styleFrom(foregroundColor: pal.limeText),
                child: Text(l10n.clearFiltersButton),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
