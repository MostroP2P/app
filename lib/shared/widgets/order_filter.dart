import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';

/// Available currencies for the filter chip selector.
const _currencies = ['ARS', 'USD', 'EUR', 'BRL', 'MXN', 'COP', 'CLP', 'VES'];

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
  return showDialog<void>(
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
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);

    final selectedCurrencies = ref.watch(currencyFilterProvider);
    final selectedMethods = ref.watch(paymentMethodFilterProvider);
    final ratingRange = ref.watch(ratingFilterProvider);
    final premiumRange = ref.watch(premiumRangeFilterProvider);

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Filters', style: theme.textTheme.headlineSmall),
                  TextButton(
                    onPressed: () {
                      ref.read(currencyFilterProvider.notifier).state = [];
                      ref.read(paymentMethodFilterProvider.notifier).state = [];
                      ref.read(ratingFilterProvider.notifier).state =
                          (min: 0.0, max: 5.0);
                      ref.read(premiumRangeFilterProvider.notifier).state =
                          (min: -10.0, max: 10.0);
                    },
                    child: Text('Reset', style: TextStyle(color: green)),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Currency chips
              Text('Currency', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: _currencies.map((code) {
                  final selected = selectedCurrencies.contains(code);
                  return FilterChip(
                    label: Text(code),
                    selected: selected,
                    selectedColor: green.withValues(alpha: 0.2),
                    checkmarkColor: green,
                    onSelected: (on) {
                      final current =
                          ref.read(currencyFilterProvider.notifier).state;
                      ref.read(currencyFilterProvider.notifier).state = on
                          ? [...current, code]
                          : current.where((c) => c != code).toList();
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Payment method chips
              Text('Payment Method', style: theme.textTheme.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: _paymentMethods.map((method) {
                  final selected = selectedMethods.contains(method);
                  return FilterChip(
                    label: Text(method, style: const TextStyle(fontSize: 12)),
                    selected: selected,
                    selectedColor: green.withValues(alpha: 0.2),
                    checkmarkColor: green,
                    onSelected: (on) {
                      final current =
                          ref.read(paymentMethodFilterProvider.notifier).state;
                      ref.read(paymentMethodFilterProvider.notifier).state = on
                          ? [...current, method]
                          : current.where((m) => m != method).toList();
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Rating range slider
              Text('Rating', style: theme.textTheme.labelLarge),
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
                onChanged: (v) {
                  ref.read(ratingFilterProvider.notifier).state =
                      (min: v.start, max: v.end);
                },
              ),
              const SizedBox(height: AppSpacing.md),

              // Premium range slider
              Text('Premium', style: theme.textTheme.labelLarge),
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
                onChanged: (v) {
                  ref.read(premiumRangeFilterProvider.notifier).state =
                      (min: v.start, max: v.end);
                },
              ),
              const SizedBox(height: AppSpacing.lg),

              // Close button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.button),
                    ),
                  ),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
