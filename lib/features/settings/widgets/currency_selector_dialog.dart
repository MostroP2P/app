import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/settings_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/fiat_currencies.dart';
import 'package:mostro/shared/widgets/currency_group_header.dart';
import 'package:mostro/shared/widgets/currency_mark.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';

/// The search field's box (DS-CMP-11), as the create-order picker's.
const _kSearchFieldRadius = 14.0;

/// Full-screen picker of the default currency (Settings). Reads the same
/// catalogue as the create-order picker, through [fiatCurrenciesProvider],
/// so the two never disagree on an entry.
class CurrencySelectorDialog extends ConsumerStatefulWidget {
  const CurrencySelectorDialog({super.key});

  @override
  ConsumerState<CurrencySelectorDialog> createState() =>
      _CurrencySelectorDialogState();
}

class _CurrencySelectorDialogState
    extends ConsumerState<CurrencySelectorDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearch);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearch() {
    setState(() => _query = _searchController.text.toLowerCase());
  }

  void _select(FiatCurrency entry) {
    ref.read(settingsProvider.notifier).setDefaultFiatCode(entry.code);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final catalogue = ref.watch(fiatCurrenciesProvider);
    final filtered = (catalogue.valueOrNull ?? const <FiatCurrency>[]).where(
      (e) =>
          _query.isEmpty ||
          e.code.toLowerCase().contains(_query) ||
          e.name.toLowerCase().contains(_query),
    );
    final rows = currencyPickerRows(filtered);
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kSearchFieldRadius),
      borderSide: BorderSide(color: book.border),
    );

    return Scaffold(
      backgroundColor: book.bg,
      appBar: redesignAppBar(
        context,
        title: l10n.selectCurrencyDialogTitle,
        onBack: () => Navigator.of(context).pop(),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              controller: _searchController,
              autocorrect: false,
              enableSuggestions: false,
              style: TextStyle(fontSize: 14, color: book.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: book.inset,
                border: border,
                enabledBorder: border,
                // The focus has to show (DS-COL-7).
                focusedBorder: border.copyWith(
                  borderSide: BorderSide(color: book.limeText),
                ),
                hintText: l10n.searchCurrenciesHint,
                hintStyle: TextStyle(fontSize: 13, color: book.textFaint),
                prefixIcon: Icon(
                  Icons.search,
                  size: 16,
                  color: book.textTertiary,
                ),
              ),
            ),
          ),
          Expanded(
            child:
                catalogue.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : rows.isEmpty
                    ? Center(
                      child: Text(
                        l10n.noCurrenciesFoundMessage,
                        style: TextStyle(
                          fontSize: 14,
                          color: book.textTertiary,
                        ),
                      ),
                    )
                    : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        if (row is StablecoinsHeaderRow) {
                          return const StablecoinsGroupHeader(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                          );
                        }
                        if (row is BitcoinNetworksHeaderRow) {
                          return const BitcoinNetworksGroupHeader(
                            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                          );
                        }
                        final entry = (row as CurrencyRow).currency;
                        return ListTile(
                          leading: CurrencyMark(code: entry.code, size: 22),
                          title: Text(
                            '${entry.code} — ${entry.name}',
                            style: TextStyle(
                              fontSize: 15,
                              color: book.textPrimary,
                            ),
                          ),
                          onTap: () => _select(entry),
                        );
                      },
                    ),
          ),
        ],
      ),
    );
  }
}

// ── Helper ────────────────────────────────────────────────────────────────────

/// Push the [CurrencySelectorDialog] as a full-screen route.
Future<void> showCurrencySelector(BuildContext context) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => const CurrencySelectorDialog(),
      fullscreenDialog: true,
    ),
  );
}
