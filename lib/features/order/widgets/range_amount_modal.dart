import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/create_order_palette.dart';
import 'package:mostro/features/order/widgets/underline_amount_field.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';

/// Shows a modal dialog for entering an amount within a range.
///
/// Returns the selected amount, or `null` if cancelled.
Future<double?> showRangeAmountModal({
  required BuildContext context,
  required double min,
  required double max,
  required String currencyCode,
}) {
  return showMostroDialog<double>(
    context: context,
    builder:
        (dialogContext) =>
            _RangeAmountDialog(min: min, max: max, currencyCode: currencyCode),
  );
}

class _RangeAmountDialog extends StatefulWidget {
  const _RangeAmountDialog({
    required this.min,
    required this.max,
    required this.currencyCode,
  });

  final double min;
  final double max;
  final String currencyCode;

  @override
  State<_RangeAmountDialog> createState() => _RangeAmountDialogState();
}

/// The amount is typed, shown and bounded the way the take-order card prints
/// the range: grouped by the locale (`25.000` in `es`), so the dialog never
/// reads `2000 – 998000` under a card that says `2.000 – 998.000` (#720).
class _RangeAmountDialogState extends State<_RangeAmountDialog> {
  final _controller = TextEditingController();
  String? _error;

  String get _locale => Localizations.localeOf(context).toString();

  NumberFormat get _fiat => NumberFormat('#,##0.##', _locale);

  /// The typed amount without the grouping the field adds, or null while the
  /// field is empty. Whole units only: the take sends it as an integer. Zero
  /// parses, so it gets the range error like any other value under [min].
  double? get _parsed {
    final digits = _controller.text.replaceAll(_fiat.symbols.GROUP_SEP, '');
    return int.tryParse(digits)?.toDouble();
  }

  bool get _isValid {
    final v = _parsed;
    return v != null && v >= widget.min && v <= widget.max;
  }

  void _validate() {
    final v = _parsed;
    setState(() {
      if (v == null) {
        _error = null; // don't show error while typing
      } else if (v < widget.min || v > widget.max) {
        _error = AppLocalizations.of(
          context,
        ).amountRangeError(_fiat.format(widget.min), _fiat.format(widget.max));
      } else {
        _error = null;
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final palette = CreateOrderPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final symbols = _fiat.symbols;
    final error = _error;

    return MostroDialog(
      title: l10n.enterAmountTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          UnderlineAmountField(
            controller: _controller,
            autofocus: true,
            hintText: '0',
            hasError: error != null,
            keyboardType: TextInputType.number,
            inputFormatters: [
              ThousandsInputFormatter(
                groupSeparator: symbols.GROUP_SEP,
                decimalSeparator: symbols.DECIMAL_SEP,
                allowDecimals: false,
              ),
            ],
            trailing: Text(
              widget.currencyCode,
              style: TextStyle(
                fontFamily: AppFonts.figures,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: book.textTertiary,
              ),
            ),
            onChanged: (_) => _validate(),
            automationId: AutomationIds.orderTakeAmount,
          ),
          if (error != null) ...[
            const SizedBox(height: 6),
            Text(error, style: TextStyle(fontSize: 12, color: palette.error)),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.minMaxRangeLabel(
              _fiat.format(widget.min),
              _fiat.format(widget.max),
              widget.currencyCode,
            ),
            style: TextStyle(fontSize: 12, color: book.textTertiary),
          ),
        ],
      ),
      secondary: ModalAction(
        label: l10n.cancel,
        onPressed: () => Navigator.pop(context),
      ),
      primary: ModalAction(
        label: l10n.rangeAmountTakeAction,
        onPressed: _isValid ? () => Navigator.pop(context, _parsed) : null,
        automationId: AutomationIds.orderTakeAmountConfirm,
      ),
    );
  }
}
