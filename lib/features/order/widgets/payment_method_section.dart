import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/order/providers/payment_methods_provider.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Selected payment methods for the create-order form.
final selectedPaymentMethodsProvider =
    StateProvider<List<String>>((_) => []);

/// Custom payment method text.
final customPaymentMethodProvider = StateProvider<String>((_) => '');

/// Multi-select payment methods + custom text field.
class PaymentMethodSection extends ConsumerStatefulWidget {
  const PaymentMethodSection({super.key});

  @override
  ConsumerState<PaymentMethodSection> createState() =>
      _PaymentMethodSectionState();
}

class _PaymentMethodSectionState extends ConsumerState<PaymentMethodSection> {
  late final TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    _customController = TextEditingController(
      text: ref.read(customPaymentMethodProvider),
    );
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final inputBg = colors?.backgroundInput ?? const Color(0xFF252A3A);
    // When the currency changes, drop any selected methods that are not valid
    // for the new currency (the custom free-text entry is left untouched).
    ref.listen<String>(selectedFiatCodeProvider, (_, next) {
      // Don't prune while the asset is still loading: the provider returns an
      // empty list during load, which would wipe every selection.
      if (!ref.read(paymentMethodsDataProvider).hasValue) return;
      final valid = ref.read(paymentMethodsForCurrencyProvider(next)).toSet();
      final current = ref.read(selectedPaymentMethodsProvider);
      final pruned = current.where(valid.contains).toList();
      if (pruned.length != current.length) {
        ref.read(selectedPaymentMethodsProvider.notifier).state = pruned;
      }
    });

    final selected = ref.watch(selectedPaymentMethodsProvider);
    final custom = ref.watch(customPaymentMethodProvider);
    final l10n = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.paymentMethodsLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.sm),

        // Selected chips
        if (selected.isNotEmpty) ...[
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: selected.map((method) {
              return Chip(
                label: Text(method, style: const TextStyle(fontSize: 12)),
                deleteIcon: const Icon(Icons.close, size: 14),
                onDeleted: () {
                  ref.read(selectedPaymentMethodsProvider.notifier).state =
                      selected.where((m) => m != method).toList();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],

        // Add method button
        GestureDetector(
          onTap: () => _showMethodPicker(context),
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: inputBg,
              borderRadius: BorderRadius.circular(AppRadius.input),
            ),
            child: Row(
              children: [
                Icon(Icons.add, size: 16, color: green),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  l10n.addPaymentMethod,
                  style: TextStyle(color: colors?.textSecondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Custom method text field. This is the free-text entry, so it is the
        // one an automated driver can fill with an arbitrary method.
        TextField(
          controller: _customController,
          decoration: InputDecoration(
            hintText: l10n.customPaymentMethodHint,
            filled: true,
            fillColor: inputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.input),
              borderSide: BorderSide.none,
            ),
          ),
          style: theme.textTheme.bodyMedium,
          onChanged: (v) =>
              ref.read(customPaymentMethodProvider.notifier).state = v,
        ).withAutomationId(AutomationIds.orderCreatePaymentMethod),

        if (custom.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              l10n.customMethodAppendedNote,
              style: TextStyle(
                color: colors?.textSubtle,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  void _showMethodPicker(BuildContext context) {
    final selected = ref.read(selectedPaymentMethodsProvider);

    final fiatCode = ref.read(selectedFiatCodeProvider);
    final methods = ref.read(paymentMethodsForCurrencyProvider(fiatCode));
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _MethodPickerDialog(
        selected: selected,
        methods: methods,
        onDone: (chosen) {
          ref.read(selectedPaymentMethodsProvider.notifier).state = chosen;
          Navigator.pop(dialogContext);
        },
      ),
    );
  }
}

class _MethodPickerDialog extends StatefulWidget {
  const _MethodPickerDialog({
    required this.selected,
    required this.methods,
    required this.onDone,
  });

  final List<String> selected;
  final List<String> methods;
  final ValueChanged<List<String>> onDone;

  @override
  State<_MethodPickerDialog> createState() => _MethodPickerDialogState();
}

class _MethodPickerDialogState extends State<_MethodPickerDialog> {
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.selected};
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);

    return Dialog(
      backgroundColor: colors?.backgroundCard,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).selectPaymentMethodsTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: widget.methods.map((method) {
                final isSelected = _selected.contains(method);
                return FilterChip(
                  label: Text(method, style: const TextStyle(fontSize: 12)),
                  selected: isSelected,
                  selectedColor: green.withValues(alpha: 0.2),
                  checkmarkColor: green,
                  onSelected: (on) {
                    setState(() {
                      if (on) {
                        _selected.add(method);
                      } else {
                        _selected.remove(method);
                      }
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => widget.onDone(_selected.toList()),
                style: FilledButton.styleFrom(
                  backgroundColor: green,
                  foregroundColor: Colors.black,
                ),
                child: Text(AppLocalizations.of(context).done),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
