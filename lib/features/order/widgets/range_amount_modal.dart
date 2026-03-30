import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';

/// Shows a modal dialog for entering an amount within a range.
///
/// Returns the selected amount, or `null` if cancelled.
Future<double?> showRangeAmountModal({
  required BuildContext context,
  required double min,
  required double max,
  required String currencyCode,
}) {
  return showDialog<double>(
    context: context,
    builder: (dialogContext) => _RangeAmountDialog(
      min: min,
      max: max,
      currencyCode: currencyCode,
    ),
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
        _error = 'Amount must be between '
            '${_fmt(widget.min)} and ${_fmt(widget.max)}';
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
    final cardBg = colors?.backgroundCard ?? const Color(0xFF1E2230);

    return Dialog(
      backgroundColor: cardBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter Amount',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: AppSpacing.lg),

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
            ),
            const SizedBox(height: AppSpacing.sm),

            Text(
              'Min: ${_fmt(widget.min)} – Max: ${_fmt(widget.max)} ${widget.currencyCode}',
              style: TextStyle(
                color: colors?.textSubtle,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors?.textSecondary,
                      side: BorderSide(
                        color: colors?.textSecondary ?? Colors.grey,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: _isValid
                        ? () => Navigator.pop(context, _parsed)
                        : null,
                    style: FilledButton.styleFrom(
                      backgroundColor: green,
                      foregroundColor: Colors.black,
                      disabledBackgroundColor: green.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.button),
                      ),
                    ),
                    child: const Text('Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
