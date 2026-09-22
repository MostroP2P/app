import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
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

class _RangeAmountDialogState extends State<_RangeAmountDialog> {
  final _controller = TextEditingController();
  String? _error;

  double? get _parsed => double.tryParse(_controller.text);

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
        ).amountRangeError(_fmt(widget.min), _fmt(widget.max));
      } else {
        _error = null;
      }
    });
  }

  static String _fmt(double v) {
    return v == v.truncateToDouble() ? v.toInt().toString() : v.toString();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>();
    final green = colors?.mostroGreen ?? const Color(0xFF8CC63F);
    final l10n = AppLocalizations.of(context);

    return MostroDialog(
      title: l10n.enterAmountTitle,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            cursorColor: green,
            style: Theme.of(context).textTheme.headlineMedium,
            decoration: InputDecoration(
              hintText: '0',
              suffixText: widget.currencyCode,
              errorText: _error,
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: green, width: 2),
              ),
            ),
            onChanged: (_) => _validate(),
          ).withAutomationId(AutomationIds.orderTakeAmount),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.minMaxRangeLabel(
              _fmt(widget.min),
              _fmt(widget.max),
              widget.currencyCode,
            ),
            style: TextStyle(color: colors?.textSubtle, fontSize: 12),
          ),
        ],
      ),
      secondary: ModalAction(
        label: l10n.cancel,
        onPressed: () => Navigator.pop(context),
      ),
      primary: ModalAction(
        label: l10n.submitButton,
        onPressed: _isValid ? () => Navigator.pop(context, _parsed) : null,
        automationId: AutomationIds.orderTakeAmountConfirm,
      ),
    );
  }
}
