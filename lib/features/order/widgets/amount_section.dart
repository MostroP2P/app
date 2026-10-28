import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/order/providers/order_side_provider.dart';
import 'package:mostro/features/order/widgets/currency_section.dart';
import 'package:mostro/features/order/widgets/price_section.dart';
import 'package:mostro/features/order/widgets/underline_amount_field.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/btc_pegged.dart';
import 'package:mostro/shared/widgets/pill_segmented.dart';

/// The locale's thousands and decimal separators.
typedef AmountSymbols = ({String group, String decimal});

/// "How much you sell / buy" card: `Single | Range` control, the amount
/// field(s) with the currency selector, and the quick-amount chips (5b).
///
/// The text controllers belong to the screen, which also owns validation and
/// the preview; this widget only lays them out.
class AmountSection extends ConsumerWidget {
  const AmountSection({
    super.key,
    required this.amountController,
    required this.minController,
    required this.maxController,
    required this.symbols,
    required this.fiatFormat,
    required this.quickAmounts,
    required this.onChanged,
    required this.onRangeChanged,
    this.canRange = true,
    this.hasError = false,
  });

  final TextEditingController amountController;
  final TextEditingController minController;
  final TextEditingController maxController;
  final AmountSymbols symbols;

  /// Grouped fiat formatter of the current locale, for the quick chips.
  final NumberFormat fiatFormat;

  /// Chip values, or empty to show none.
  final List<int> quickAmounts;

  /// Any amount text changed (typed or chip-filled).
  final VoidCallback onChanged;
  final ValueChanged<bool> onRangeChanged;

  /// Whether a range order can be written: a range is priced at market, so
  /// it is locked out while Market is ([marketLockedCodeProvider]).
  final bool canRange;

  /// Paints the amount underline(s) coral: the amount is what the validation
  /// message in the preview bar refers to.
  final bool hasError;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final side = ref.watch(orderSideProvider);
    final isRange = ref.watch(isRangeOrderProvider);
    // A BTC-pegged code is entered in sats, which are whole: they are what
    // goes on the wire as the order's amount (#907).
    final inSats = isBtcPeggedCode(ref.watch(selectedFiatCodeProvider));
    // Moving between a fiat and a BTC-pegged code changes the unit of what is
    // typed (whole units or sats): 12.5 USD would become 12 sats, 100000 sats
    // 100,000 USD. Clear it rather than reread it in the new unit.
    ref.listen<String>(selectedFiatCodeProvider, (previous, next) {
      if (previous == null ||
          isBtcPeggedCode(previous) == isBtcPeggedCode(next)) {
        return;
      }
      amountController.clear();
      minController.clear();
      maxController.clear();
      onChanged();
    });
    final formatters = [
      ThousandsInputFormatter(
        groupSeparator: symbols.group,
        decimalSeparator: symbols.decimal,
        allowDecimals: !inSats,
      ),
    ];
    final satsUnit = inSats ? _SatsUnit(l10n.satsUnitLabel) : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                side == OrderType.sell
                    ? l10n.amountSectionSell
                    : l10n.amountSectionBuy,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: palette.textStrong,
                ),
              ),
            ),
            const SizedBox(width: 8),
            PillSegmented<bool>(
              size: PillSegmentedSize.small,
              selected: isRange,
              segments: [
                PillSegment(
                  value: false,
                  label: l10n.amountModeSingle,
                  automationId: AutomationIds.orderCreateAmountSingle,
                ),
                PillSegment(
                  value: true,
                  label: l10n.amountModeRange,
                  automationId: AutomationIds.orderCreateAmountRange,
                  enabled: canRange,
                ),
              ],
              onSelected: onRangeChanged,
            ).withAutomationId(AutomationIds.orderCreateRange, merge: false),
          ],
        ),
        const SizedBox(height: 12),
        if (isRange) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: UnderlineAmountField(
                  controller: minController,
                  label: l10n.amountMinLabel,
                  hintText: '0',
                  valueFontSize: 19,
                  hasError: hasError,
                  inputFormatters: formatters,
                  trailing: satsUnit,
                  onChanged: (_) => onChanged(),
                ).withAutomationId(AutomationIds.orderCreateFiatMin),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: Text(
                  '–',
                  style: TextStyle(
                    fontFamily: AppFonts.figures,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: palette.textFaint,
                  ),
                ),
              ),
              Expanded(
                child: UnderlineAmountField(
                  controller: maxController,
                  label: l10n.amountMaxLabel,
                  hintText: '0',
                  valueFontSize: 19,
                  hasError: hasError,
                  inputFormatters: formatters,
                  trailing: satsUnit,
                  onChanged: (_) => onChanged(),
                ).withAutomationId(AutomationIds.orderCreateFiatMax),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const CurrencyRowSelector(),
        ] else ...[
          // The identifier names the field alone; the inline currency
          // selector inside the row keeps its own.
          UnderlineAmountField(
            controller: amountController,
            hintText: '0',
            hasError: hasError,
            inputFormatters: formatters,
            trailing:
                satsUnit == null
                    ? const CurrencyInlineSelector()
                    : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        satsUnit,
                        const SizedBox(width: 8),
                        const CurrencyInlineSelector(),
                      ],
                    ),
            onChanged: (_) => onChanged(),
            automationId: AutomationIds.orderCreateFiatAmount,
          ),
          if (quickAmounts.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final amount in quickAmounts)
                  _QuickAmountChip(
                    label: fiatFormat.format(amount),
                    onTap: () {
                      amountController.text = fiatFormat.format(amount);
                      onChanged();
                    },
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

/// The `sats` beside an amount field for a BTC-pegged code, whose amount is
/// typed in sats (#907).
class _SatsUnit extends StatelessWidget {
  const _SatsUnit(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: palette.textMuted,
      ),
    );
  }
}

/// A round amount that fills the field when tapped; not a state of its own.
class _QuickAmountChip extends StatelessWidget {
  const _QuickAmountChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = OrderBookPalette.of(context);

    return Material(
      color: palette.chipFill,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: AppFonts.figures,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
