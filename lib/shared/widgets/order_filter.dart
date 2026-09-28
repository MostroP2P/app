import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';

/// Commonly traded currencies shown first in the filter. The full list
/// comes from the fiatCurrenciesProvider (assets/data/fiat.json).
const _topCurrencies = ['ARS', 'USD', 'EUR', 'BRL', 'MXN', 'COP', 'CLP', 'VES'];

/// Available payment methods for the filter chip selector.
const _paymentMethods = [
  'Mercado Pago',
  'Bank Transfer',
  'Pix',
  'Zelle',
  'Wise',
  'SEPA',
  'Revolut',
  'Cash',
];

/// Shows the order filter dialog. Reads/writes the individual filter providers.
Future<void> showOrderFilterDialog(BuildContext context) {
  return showMostroDialog<void>(
    context: context,
    builder: (_) => const _OrderFilterDialog(),
  );
}

class _OrderFilterDialog extends ConsumerWidget {
  const _OrderFilterDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);

    final filters = ref.watch(orderFiltersProvider);
    final notifier = ref.read(orderFiltersProvider.notifier);
    final selectedCurrencies = filters.currencies;
    final selectedMethods = filters.paymentMethods;
    final allCurrencies = ref.watch(availableCurrencyCodesProvider);
    // Selected values first-class, catalogued or not: the filters outlive
    // the app version that stored them (#575), and a value the dialog does
    // not show is one the user cannot deselect.
    final currencies = _withSelected(
      allCurrencies.isNotEmpty ? allCurrencies : _topCurrencies,
      selectedCurrencies,
    );
    final methods = _withSelected(_paymentMethods, selectedMethods);
    final ratingRange = filters.rating;
    final premiumRange = filters.premium;
    final l10n = AppLocalizations.of(context);

    return MostroDialog(
      title: l10n.filtersDialogTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Currency chips
          Text(l10n.currencyLabel, style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children:
                currencies.map((code) {
                  final selected = selectedCurrencies.contains(code);
                  return FilterChip(
                    label: Text(code),
                    selected: selected,
                    selectedColor: green.withValues(alpha: 0.2),
                    checkmarkColor: green,
                    onSelected: (on) {
                      final current = ref.read(orderFiltersProvider);
                      notifier.set(
                        current.copyWith(
                          currencies:
                              on
                                  ? [...current.currencies, code]
                                  : current.currencies
                                      .where((c) => c != code)
                                      .toList(),
                        ),
                      );
                    },
                  );
                }).toList(),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Payment method chips
          Text(l10n.paymentMethodLabel, style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children:
                methods.map((method) {
                  final selected = selectedMethods.contains(method);
                  return FilterChip(
                    label: Text(method, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    selectedColor: green.withValues(alpha: 0.2),
                    checkmarkColor: green,
                    onSelected: (on) {
                      final current = ref.read(orderFiltersProvider);
                      notifier.set(
                        current.copyWith(
                          paymentMethods:
                              on
                                  ? [...current.paymentMethods, method]
                                  : current.paymentMethods
                                      .where((m) => m != method)
                                      .toList(),
                        ),
                      );
                    },
                  );
                }).toList(),
          ),
          const SizedBox(height: AppSpacing.lg),

          // Rating range slider
          Text(l10n.ratingLabel, style: theme.textTheme.labelLarge),
          RangeSlider(
            values: RangeValues(ratingRange.min, ratingRange.max),
            min: 0,
            max: 5,
            divisions: 10,
            activeColor: green,
            labels: RangeLabels(
              ratingRange.min.toStringAsFixed(1),
              ratingRange.max.toStringAsFixed(1),
            ),
            // Every frame of a drag applies; only where it comes to rest is
            // written to disk.
            onChanged:
                (v) => notifier.set(
                  ref
                      .read(orderFiltersProvider)
                      .copyWith(rating: (min: v.start, max: v.end)),
                  persist: false,
                ),
            onChangeEnd:
                (v) => notifier.set(
                  ref
                      .read(orderFiltersProvider)
                      .copyWith(rating: (min: v.start, max: v.end)),
                ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Premium range slider
          Text(l10n.premiumSectionLabel, style: theme.textTheme.labelLarge),
          RangeSlider(
            values: RangeValues(premiumRange.min, premiumRange.max),
            min: -10,
            max: 10,
            divisions: 20,
            activeColor: green,
            labels: RangeLabels(
              '${premiumRange.min.toStringAsFixed(0)}%',
              '${premiumRange.max.toStringAsFixed(0)}%',
            ),
            onChanged:
                (v) => notifier.set(
                  ref
                      .read(orderFiltersProvider)
                      .copyWith(premium: (min: v.start, max: v.end)),
                  persist: false,
                ),
            onChangeEnd:
                (v) => notifier.set(
                  ref
                      .read(orderFiltersProvider)
                      .copyWith(premium: (min: v.start, max: v.end)),
                ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
      // Resetting is neither the answer nor the way out — it reads as a link,
      // the way it did in the header before this shared shape existed.
      links: [
        ModalLink(
          label: l10n.resetButton,
          onPressed: notifier.clear,
        ),
      ],
      primary: ModalAction(
        label: l10n.applyButton,
        onPressed: () => Navigator.pop(context),
      ),
    );
  }
}

/// [catalogue], then whatever of [selected] it does not list, in the order
/// they were picked.
List<String> _withSelected(List<String> catalogue, List<String> selected) {
  final listed = catalogue.toSet();
  return [...catalogue, ...selected.where((v) => !listed.contains(v))];
}
