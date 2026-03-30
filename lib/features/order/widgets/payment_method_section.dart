import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';

/// Common payment methods available for selection.
const _commonMethods = [
  'Mercado Pago',
  'Bank Transfer',
  'Pix',
  'Zelle',
  'Wise',
  'SEPA',
  'Revolut',
  'Cash',
  'PayPal',
  'Nequi',
];

/// Selected payment methods for the create-order form.
final selectedPaymentMethodsProvider =
    StateProvider<List<String>>((_) => []);

/// Custom payment method text.
final customPaymentMethodProvider = StateProvider<String>((_) => '');

/// Multi-select payment methods + custom text field.
class PaymentMethodSection extends ConsumerWidget {
  const PaymentMethodSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final inputBg = colors?.backgroundInput ?? const Color(0xFF252A3A);
    final selected = ref.watch(selectedPaymentMethodsProvider);
    final custom = ref.watch(customPaymentMethodProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Payment Methods', style: theme.textTheme.labelLarge),
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
          onTap: () => _showMethodPicker(context, ref),
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
                  'Add payment method',
                  style: TextStyle(color: colors?.textSecondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),

        // Custom method text field
        TextField(
          decoration: InputDecoration(
            hintText: 'Custom payment method...',
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
        ),

        if (custom.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              'Custom method will be appended to selection',
              style: TextStyle(
                color: colors?.textSubtle,
                fontSize: 11,
              ),
            ),
          ),
      ],
    );
  }

  void _showMethodPicker(BuildContext context, WidgetRef ref) {
    final selected = ref.read(selectedPaymentMethodsProvider);

    showDialog<void>(
      context: context,
      builder: (_) => _MethodPickerDialog(
        selected: selected,
        onDone: (methods) {
          ref.read(selectedPaymentMethodsProvider.notifier).state = methods;
          Navigator.pop(context);
        },
      ),
    );
  }
}

class _MethodPickerDialog extends StatefulWidget {
  const _MethodPickerDialog({
    required this.selected,
    required this.onDone,
  });

  final List<String> selected;
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
              'Select Payment Methods',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: _commonMethods.map((method) {
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
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
