import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// The picker's boxed search field (DS-CMP-11).
const _kSearchFieldRadius = 14.0;

/// Opens the searchable currency picker over [currencies], with [selected]
/// marked. [onSelect] gets the picked code, then the picker closes. The
/// automation ids are the caller's, since each screen names its own.
void showCurrencyPickerDialog(
  BuildContext context, {
  required ProviderListenable<AsyncValue<List<FiatCurrency>>> currencies,
  required String? selected,
  required ValueChanged<String> onSelect,
  String? searchAutomationId,
  String Function(String code)? optionAutomationId,
}) {
  showMostroDialog<void>(
    context: context,
    builder: (dialogContext) => _CurrencyPickerDialog(
      currencies: currencies,
      selected: selected,
      onSelect: (code) {
        onSelect(code);
        Navigator.pop(dialogContext);
      },
      searchAutomationId: searchAutomationId,
      optionAutomationId: optionAutomationId,
    ),
  );
}

/// Watches [currencies] rather than snapshotting it, so a picker opened
/// while `assets/data/fiat.json` or the node's info event is still loading
/// fills in once it lands.
class _CurrencyPickerDialog extends ConsumerStatefulWidget {
  const _CurrencyPickerDialog({
    required this.currencies,
    required this.selected,
    required this.onSelect,
    this.searchAutomationId,
    this.optionAutomationId,
  });

  final ProviderListenable<AsyncValue<List<FiatCurrency>>> currencies;
  final String? selected;
  final ValueChanged<String> onSelect;
  final String? searchAutomationId;
  final String Function(String code)? optionAutomationId;

  @override
  ConsumerState<_CurrencyPickerDialog> createState() =>
      _CurrencyPickerDialogState();
}

class _CurrencyPickerDialogState extends ConsumerState<_CurrencyPickerDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    final currencies = ref.watch(widget.currencies);
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
    final search = TextField(
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
    );
    final searchId = widget.searchAutomationId;
    final optionId = widget.optionAutomationId;

    return MostroDialog(
      title: AppLocalizations.of(context).selectCurrencyDialogTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          searchId == null ? search : search.withAutomationId(searchId),
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
                          final option = ListTile(
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
                          );
                          return optionId == null
                              ? option
                              : option.withAutomationId(optionId(c.code));
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
