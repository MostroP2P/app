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
/// Every state the field can reach is set here — it is never disabled, so
/// there is no disabled border: whatever it left out would come from the
/// theme, which still paints v1's filled underline (DS-CMP-19).
class PasteField extends StatelessWidget {
  const PasteField({
    super.key,
    required this.controller,
    required this.hint,
    this.errorText,
    this.onChanged,
    this.onEditingComplete,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;

  /// Shown under the field, which turns its border to the error ink.
  final String? errorText;
  final ValueChanged<String>? onChanged;

  /// Called on the keyboard's done action ([TextInputAction.done]). Given
  /// one, the field keeps its focus unless the callback moves it: an Enter
  /// that submits nothing leaves the user where they were typing.
  final VoidCallback? onEditingComplete;
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
      enableIMEPersonalizedLearning: false,
      // A multi-line field would otherwise give a phone keyboard a newline
      // key, and one stray Enter breaks the token or URI.
      textInputAction: TextInputAction.done,
      // A token or URI runs to hundreds of characters: the box looks
      // multi-line before anything is in it, as the invoice field does.
      minLines: 3,
      maxLines: 5,
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
      onEditingComplete: onEditingComplete,
    );
  }
}
