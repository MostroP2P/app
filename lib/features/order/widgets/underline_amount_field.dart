import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/create_order_palette.dart';

/// Groups the integer part of a typed number with the locale's thousands
/// separator as the user types (`25000` → `25.000` in `es`), keeps at most
/// one decimal separator and two decimals, and drops everything else. Only
/// the locale's own decimal separator counts as one: a pasted `25.000` in
/// `es` is twenty-five thousand, not twenty-five. A leading separator gets a
/// zero (`,5` → `0,5`); with [allowDecimals] off, everything from the
/// separator on is dropped.
///
/// The field therefore always shows the amount the way the order book prints
/// it; `canonicalAmount` strips the grouping again before the value is used.
class ThousandsInputFormatter extends TextInputFormatter {
  const ThousandsInputFormatter({
    required this.groupSeparator,
    required this.decimalSeparator,
    this.allowDecimals = true,
  });

  final String groupSeparator;
  final String decimalSeparator;
  final bool allowDecimals;

  static const _maxDecimals = 2;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    if (raw.isEmpty) return newValue;

    final digitsOnly = StringBuffer();
    var seenDecimal = false;
    var decimals = 0;
    for (final rune in raw.runes) {
      final char = String.fromCharCode(rune);
      if (RegExp(r'\d').hasMatch(char)) {
        if (seenDecimal) {
          if (decimals >= _maxDecimals) continue;
          decimals++;
        }
        digitsOnly.write(char);
      } else if (char == decimalSeparator && !seenDecimal) {
        // An integer-only field ends at the separator: `5000,5` is 5 000,
        // never 50 005.
        if (!allowDecimals) break;
        seenDecimal = true;
        // `,5` means 0,5 — keep the intent instead of turning it into 5.
        if (digitsOnly.isEmpty) digitsOnly.write('0');
        digitsOnly.write(decimalSeparator);
      }
    }

    final text = digitsOnly.toString();
    final parts = text.split(decimalSeparator);
    final integer = parts.first.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final grouped = _group(integer);
    final formatted =
        parts.length > 1 ? '$grouped$decimalSeparator${parts[1]}' : grouped;

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _group(String digits) {
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(groupSeparator);
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}

/// Amount field of the create-order form: an optional uppercase label, a
/// Manrope figure over a hairline underline that turns lime (1.5px) on focus
/// and coral on error, and an optional trailing widget (currency selector,
/// `sats` suffix) that shares the underline.
class UnderlineAmountField extends StatefulWidget {
  const UnderlineAmountField({
    super.key,
    required this.controller,
    this.label,
    this.hintText,
    this.trailing,
    this.valueFontSize = 22,
    this.hasError = false,
    this.autofocus = false,
    this.keyboardType = const TextInputType.numberWithOptions(decimal: true),
    this.inputFormatters = const [],
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
  });

  final TextEditingController controller;

  /// Shown above the value, uppercased with wide tracking (`MINIMUM`).
  final String? label;
  final String? hintText;
  final Widget? trailing;

  /// 22 for the single amount and the sats figure, 19 for a range end.
  final double valueFontSize;
  final bool hasError;
  final bool autofocus;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  @override
  State<UnderlineAmountField> createState() => _UnderlineAmountFieldState();
}

class _UnderlineAmountFieldState extends State<UnderlineAmountField> {
  late FocusNode _focusNode;
  bool _ownsFocusNode = false;

  @override
  void initState() {
    super.initState();
    _adoptFocusNode();
  }

  @override
  void didUpdateWidget(covariant UnderlineAmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _disposeFocusNode();
      _adoptFocusNode();
    }
  }

  void _adoptFocusNode() {
    _focusNode = widget.focusNode ?? FocusNode();
    _ownsFocusNode = widget.focusNode == null;
    _focusNode.addListener(_onFocusChanged);
  }

  void _disposeFocusNode() {
    _focusNode.removeListener(_onFocusChanged);
    if (_ownsFocusNode) _focusNode.dispose();
  }

  @override
  void dispose() {
    _disposeFocusNode();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final palette = CreateOrderPalette.of(context);
    final book = OrderBookPalette.of(context);
    final focused = _focusNode.hasFocus;

    final Color underline;
    final double underlineWidth;
    if (widget.hasError) {
      underline = palette.error;
      underlineWidth = 1.5;
    } else if (focused) {
      underline = palette.fieldUnderlineFocus;
      underlineWidth = 1.5;
    } else {
      underline = palette.fieldUnderline;
      underlineWidth = 1;
    }

    final label = widget.label;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          AnimatedDefaultTextStyle(
            duration: kThemeChangeDuration,
            // AnimatedDefaultTextStyle replaces the inherited style rather
            // than merging it, so the family must be spelled out.
            style: TextStyle(
              fontFamily: AppFonts.ui,
              fontSize: 10,
              letterSpacing: 0.6,
              fontWeight: FontWeight.w500,
              color: widget.hasError
                  ? palette.error
                  : focused
                      ? palette.fieldLabelFocus
                      : palette.fieldLabel,
            ),
            child: Text(label.toUpperCase()),
          ),
          const SizedBox(height: 5),
        ],
        AnimatedContainer(
          duration: kThemeChangeDuration,
          // The hairline is padded so the 1.5px focus state does not nudge
          // the row.
          padding: EdgeInsets.only(bottom: 8 - (underlineWidth - 1)),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: underline, width: underlineWidth),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.controller,
                  focusNode: _focusNode,
                  autofocus: widget.autofocus,
                  keyboardType: widget.keyboardType,
                  inputFormatters: widget.inputFormatters,
                  textInputAction: widget.textInputAction,
                  cursorColor: palette.fieldUnderlineFocus,
                  style: TextStyle(
                    fontFamily: AppFonts.figures,
                    fontSize: widget.valueFontSize,
                    fontWeight: FontWeight.w600,
                    color: book.textPrimary,
                    height: 1.2,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: widget.hintText,
                    hintStyle: TextStyle(
                      fontFamily: AppFonts.figures,
                      fontSize: widget.valueFontSize,
                      fontWeight: FontWeight.w600,
                      color: book.textFaint,
                    ),
                  ),
                  onChanged: widget.onChanged,
                  onSubmitted: widget.onSubmitted,
                ),
              ),
              if (widget.trailing != null) ...[
                const SizedBox(width: 10),
                widget.trailing!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
