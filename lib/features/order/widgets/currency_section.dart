import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';

/// Provider for the currently selected fiat code in the create-order form.
final selectedFiatCodeProvider = StateProvider<String>((_) => 'USD');

/// Tappable currency selector — shows selected code + flag, opens picker.
class CurrencySection extends ConsumerWidget {
  const CurrencySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedCode = ref.watch(selectedFiatCodeProvider);
    final flags = ref.watch(currencyFlagsProvider);
    final flag = flags[selectedCode] ?? '';
    final colors = Theme.of(context).extension<AppColors>();
    final inputBg = colors?.backgroundInput ?? const Color(0xFF252A3A);
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);

    return GestureDetector(
      onTap: () => _showCurrencyDialog(context, ref),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: inputBg,
          borderRadius: BorderRadius.circular(AppRadius.input),
        ),
        child: Row(
          children: [
            Text(
              '$flag $selectedCode',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: green,
              ),
            ),
            const Spacer(),
            Icon(Icons.arrow_drop_down, color: colors?.textSecondary),
          ],
        ),
      ),
    );
  }

  void _showCurrencyDialog(BuildContext context, WidgetRef ref) {
    final currencies = ref.read(fiatCurrenciesProvider);
    final list = currencies.maybeWhen(
      data: (d) => d,
      orElse: () => <FiatCurrency>[],
    );

    showDialog<void>(
      context: context,
      builder: (dialogContext) => _CurrencyPickerDialog(
        currencies: list,
        selected: ref.read(selectedFiatCodeProvider),
        onSelect: (code) {
          ref.read(selectedFiatCodeProvider.notifier).state = code;
          Navigator.pop(dialogContext);
        },
      ),
    );
  }
}

class _CurrencyPickerDialog extends StatefulWidget {
  const _CurrencyPickerDialog({
    required this.currencies,
    required this.selected,
    required this.onSelect,
  });

  final List<FiatCurrency> currencies;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  State<_CurrencyPickerDialog> createState() => _CurrencyPickerDialogState();
}

class _CurrencyPickerDialogState extends State<_CurrencyPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final filtered = widget.currencies.where((c) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return c.code.toLowerCase().contains(q) ||
          c.name.toLowerCase().contains(q);
    }).toList();

    return Dialog(
      backgroundColor: colors?.backgroundCard,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search currency...',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 300,
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final c = filtered[i];
                final isSelected = c.code == widget.selected;
                return ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 20)),
                  title: Text(c.code),
                  subtitle: Text(
                    c.name,
                    style: TextStyle(color: colors?.textSubtle, fontSize: 12),
                  ),
                  selected: isSelected,
                  selectedColor: colors?.mostroGreen,
                  onTap: () => widget.onSelect(c.code),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
