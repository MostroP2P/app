import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/invoice_palette.dart';

const _kRadius = 14.0;

const _kTextStyle = TextStyle(
  fontFamily: AppFonts.figures,
  fontSize: 13,
  fontWeight: FontWeight.w500,
  height: 1.45,
);

/// The boxed field a pasted value goes in — a Cashu token, a wallet URI, an
/// invoice (DS-CMP-11), on the invoice field's tokens.
///
/// Every state of the decoration is set here: whatever it left out would come
/// from the theme, which still paints v1's filled underline (DS-CMP-19).
class PasteField extends StatelessWidget {
  const PasteField({
    super.key,
    required this.controller,
    required this.hint,
    this.errorText,
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;

  /// Shown under the field, which turns its border to the error ink.
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = InvoicePalette.of(context);
    OutlineInputBorder outline(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(_kRadius),
      borderSide: BorderSide(color: color),
    );

    return TextField(
      controller: controller,
      autofocus: autofocus,
      autocorrect: false,
      enableSuggestions: false,
      minLines: 1,
      maxLines: 4,
      cursorColor: book.lime,
      style: _kTextStyle.copyWith(color: book.textPrimary),
      decoration: InputDecoration(
        filled: true,
        fillColor: pal.textareaFill,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: outline(pal.cardBorder),
        enabledBorder: outline(pal.cardBorder),
        focusedBorder: outline(pal.fieldFocusBorder),
        errorBorder: outline(pal.errorInk),
        focusedErrorBorder: outline(pal.errorInk),
        hintText: hint,
        hintStyle: _kTextStyle.copyWith(color: pal.placeholder),
        errorText: errorText,
        errorMaxLines: 2,
        errorStyle: TextStyle(fontSize: 12, color: pal.errorInk),
      ),
      onChanged: onChanged,
    );
  }
}
