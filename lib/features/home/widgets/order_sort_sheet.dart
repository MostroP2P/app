import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Shows the order-book sort picker; picking a criterion applies it and
/// closes the sheet.
Future<void> showOrderSortSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: OrderBookPalette.of(context).surface,
    builder: (_) => const _OrderSortSheet(),
  );
}

/// Name of [sort], shared by the sheet and the filter row's caption.
String orderSortLabel(AppLocalizations l10n, OrderSort sort) => switch (sort) {
  OrderSort.newest => l10n.sortNewest,
  OrderSort.bestPremium => l10n.sortBestPremium,
  OrderSort.bestReputation => l10n.sortBestReputation,
};

class _OrderSortSheet extends ConsumerWidget {
  const _OrderSortSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pal = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final current = ref.watch(orderSortProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                l10n.sortSheetTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: pal.textPrimary,
                ),
              ),
            ),
            for (final sort in OrderSort.values)
              _SortOption(
                label: orderSortLabel(l10n, sort),
                isSelected: sort == current,
                palette: pal,
                onTap: () {
                  ref.read(orderSortProvider.notifier).state = sort;
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _SortOption extends StatelessWidget {
  const _SortOption({
    required this.label,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final OrderBookPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      inMutuallyExclusiveGroup: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? palette.limeInk : palette.textBody,
                  ),
                ),
              ),
              if (isSelected)
                Icon(Icons.check_rounded, size: 20, color: palette.limeText),
            ],
          ),
        ),
      ),
    );
  }
}
