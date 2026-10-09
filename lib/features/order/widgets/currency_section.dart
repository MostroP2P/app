import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/create_order_palette.dart';
import 'package:mostro/features/about/providers/mostro_node_provider.dart';
import 'package:mostro/features/order/models/create_order_rules.dart';
import 'package:mostro/features/settings/providers/node_stats_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// The picker's boxed search field (DS-CMP-11).
const _kSearchFieldRadius = 14.0;

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

/// The fiat codes the active node accepts ([activeNodeCurrenciesProvider]),
/// or null when it sets no limit
/// (an empty list, which mostrod reads as "any currency"). Also null while
/// the cache is first read, for a node never seen, or when the read fails:
/// the form never waits on it, and the node still refuses a currency it does
/// not take. A previous node's list is dropped, not kept, while a new one
/// loads; a reread of the same node keeps its list until the read returns,
/// so a refused currency stays refused meanwhile.
final acceptedFiatCodesProvider = Provider.autoDispose<List<String>?>((ref) {
  // The live fetch of the node's info event (the form watches it for the
  // sats range) also writes the cache in Rust: reread it once it lands.
  ref.listen<AsyncValue<Object?>>(mostroNodeProvider, (_, next) {
    if (next.hasValue && !next.isLoading) {
      ref.invalidate(activeNodeCurrenciesProvider);
    }
  });
  final async = ref.watch(activeNodeCurrenciesProvider);
  // isReloading: the active node changed. A plain invalidate is isRefreshing.
  final codes = async.isReloading ? null : async.valueOrNull;
  return codes == null || codes.isEmpty ? null : codes;
});

/// Whether the user picked the form's currency in the picker. A picked
/// currency counts as input: the node's list never switches it away.
final fiatPickedByUserProvider = StateProvider<bool>((_) => false);

/// The currencies the picker offers: the catalogue narrowed to
/// [acceptedFiatCodesProvider], the whole catalogue when that is null.
final offeredFiatCurrenciesProvider =
    Provider.autoDispose<AsyncValue<List<FiatCurrency>>>((ref) {
      final accepted = ref.watch(acceptedFiatCodesProvider);
      return ref.watch(fiatCurrenciesProvider).whenData((catalogue) {
        final byCode = {for (final c in catalogue) c.code: c};
        return [
          for (final code in offeredFiatCodes(byCode.keys.toList(), accepted))
            byCode[code] ?? FiatCurrency(code: code, name: '', flag: ''),
        ];
      });
    });

/// Opens the searchable currency picker and writes the choice to
/// [selectedFiatCodeProvider].
void showCurrencyPicker(BuildContext context, WidgetRef ref) {
  showMostroDialog<void>(
    context: context,
    builder: (dialogContext) => _CurrencyPickerDialog(
      selected: ref.read(selectedFiatCodeProvider),
      onSelect: (code) {
        ref.read(selectedFiatCodeProvider.notifier).state = code;
        ref.read(fiatPickedByUserProvider.notifier).state = true;
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

    return _EditableValue(
      onTap: () => showCurrencyPicker(context, ref),
      hint: AppLocalizations.of(context).selectCurrencyDialogTitle,
      borderRadius: BorderRadius.circular(8),
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
          Icon(Icons.expand_more, size: 16, color: palette.sortLabel),
        ],
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
      child: _EditableValue(
        onTap: () => showCurrencyPicker(context, ref),
        hint: AppLocalizations.of(context).selectCurrencyDialogTitle,
        borderRadius: BorderRadius.circular(12),
        padding: const EdgeInsets.symmetric(horizontal: 12),
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
            Icon(Icons.expand_more, size: 16, color: palette.sortLabel),
          ],
        ),
      ),
    ).withAutomationId(AutomationIds.orderCreateCurrency);
  }
}

/// A value the user can change in place (DS-CMP-27): a button of at least
/// 48 × 48 dp whose [hint] names the change.
class _EditableValue extends StatelessWidget {
  const _EditableValue({
    required this.onTap,
    required this.hint,
    required this.borderRadius,
    required this.padding,
    required this.child,
  });

  final VoidCallback onTap;

  /// Names the change, e.g. "Select currency".
  final String hint;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Widget child;

  static const double _minTarget = 48;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      hint: hint,
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: _minTarget,
            minHeight: _minTarget,
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Watches the offered list rather than snapshotting it, so a picker opened
/// while `assets/data/fiat.json` or the node's info event is still loading
/// fills in once it lands.
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
    final palette = OrderBookPalette.of(context);
    final currencies = ref.watch(offeredFiatCurrenciesProvider);
    final loaded = currencies.valueOrNull ?? const <FiatCurrency>[];
    final filtered = loaded.where((c) {
      if (_query.isEmpty) return true;
      final q = _query.toLowerCase();
      return c.code.toLowerCase().contains(q) ||
          c.name.toLowerCase().contains(q);
    }).toList();
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kSearchFieldRadius),
      borderSide: BorderSide(color: palette.border),
    );
    // The field opens focused, so the focus has to show (DS-COL-7).
    final focusBorder = border.copyWith(
      borderSide: BorderSide(color: palette.limeText),
    );

    return MostroDialog(
      title: AppLocalizations.of(context).selectCurrencyDialogTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(fontSize: 14, color: palette.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: palette.inset,
              border: border,
              enabledBorder: border,
              focusedBorder: focusBorder,
              hintText: AppLocalizations.of(context).searchCurrenciesHint,
              hintStyle: TextStyle(fontSize: 13, color: palette.textFaint),
              prefixIcon: Icon(
                Icons.search,
                size: 16,
                color: palette.textTertiary,
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ).withAutomationId(AutomationIds.orderCreateCurrencySearch),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 300,
            child: currencies.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Text(
                          AppLocalizations.of(context).noCurrenciesFoundMessage,
                          style: TextStyle(color: palette.textTertiary),
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (_, i) {
                          final c = filtered[i];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Text(
                              c.flag,
                              style: const TextStyle(fontSize: 19),
                            ),
                            title: Text(c.code),
                            // A code the node accepts but the catalogue
                            // does not name has no subtitle.
                            subtitle:
                                c.name.isEmpty
                                    ? null
                                    : Text(
                                      c.name,
                                      style: TextStyle(
                                        color: palette.textTertiary,
                                        fontSize: 12,
                                      ),
                                    ),
                            selected: c.code == widget.selected,
                            selectedColor: palette.limeText,
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
