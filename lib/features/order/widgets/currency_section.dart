import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/create_order_palette.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';

/// Provider for the currently selected fiat code in the create-order form.
final selectedFiatCodeProvider = StateProvider<String>((_) => 'USD');

/// The selected currency's catalogue entry, or null while the asset loads or
/// for a code the catalogue does not know.
final selectedFiatCurrencyProvider = Provider<FiatCurrency?>((ref) {
  final code = ref.watch(selectedFiatCodeProvider);
  final currencies = ref.watch(fiatCurrenciesProvider).valueOrNull;
  if (currencies == null) return null;
  for (final currency in currencies) {
    if (currency.code == code) return currency;
  }
  return null;
});

/// Opens the searchable currency picker and writes the choice to
/// [selectedFiatCodeProvider].
void showCurrencyPicker(BuildContext context, WidgetRef ref) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => _CurrencyPickerDialog(
      selected: ref.read(selectedFiatCodeProvider),
      onSelect: (code) {
        ref.read(selectedFiatCodeProvider.notifier).state = code;
        Navigator.pop(dialogContext);
      },
    ),
  );
}

/// Flag + code + chevron, sitting inline at the right of the single-amount
/// field (5b). Shares the field's underline.
class CurrencyInlineSelector extends ConsumerWidget {
  const CurrencyInlineSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(selectedFiatCodeProvider);
    final flag = ref.watch(currencyFlagsProvider)[code] ?? '';
    final palette = OrderBookPalette.of(context);

    return InkWell(
      onTap: () => showCurrencyPicker(context, ref),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(flag, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Text(
              code,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.limeInk,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 13, color: palette.sortLabel),
          ],
        ),
      ),
    ).withAutomationId(AutomationIds.orderCreateCurrency);
  }
}

/// Flag + code + currency name + chevron on its own inset row (5a).
class CurrencyRowSelector extends ConsumerWidget {
  const CurrencyRowSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(selectedFiatCodeProvider);
    final currency = ref.watch(selectedFiatCurrencyProvider);
    final palette = OrderBookPalette.of(context);
    final create = CreateOrderPalette.of(context);

    return Material(
      color: create.inset,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => showCurrencyPicker(context, ref),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Text(currency?.flag ?? '', style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 8),
              Text(
                code,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.limeInk,
                ),
              ),
              if (currency != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currency.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: palette.textTertiary,
                    ),
                  ),
                ),
              ] else
                const Spacer(),
              Icon(Icons.expand_more, size: 13, color: palette.sortLabel),
            ],
          ),
        ),
      ),
    ).withAutomationId(AutomationIds.orderCreateCurrency);
  }
}

/// Watches the catalogue rather than snapshotting it, so a picker opened
/// while `assets/data/fiat.json` is still loading fills in once it lands.
class _CurrencyPickerDialog extends ConsumerStatefulWidget {
  const _CurrencyPickerDialog({
    required this.selected,
    required this.onSelect,
  });

  final String selected;
  final ValueChanged<String> onSelect;

  @override
  ConsumerState<_CurrencyPickerDialog> createState() =>
      _CurrencyPickerDialogState();
}

class _CurrencyPickerDialogState extends ConsumerState<_CurrencyPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final currencies = ref.watch(fiatCurrenciesProvider);
    final loaded = currencies.valueOrNull ?? const <FiatCurrency>[];
    final filtered = loaded.where((c) {
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
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context).searchCurrenciesHint,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v),
            ).withAutomationId(AutomationIds.orderCreateCurrencySearch),
          ),
          SizedBox(
            height: 300,
            child: currencies.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
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
                ).withAutomationId(
                  AutomationIds.orderCreateCurrencyOption(c.code),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
