import 'package:flutter/services.dart';

/// [value] with [text] put where the user is typing: in place of the
/// selection, or at the cursor, or at the end when the field never had one.
/// The cursor ends right after [text]. Returns a new value.
TextEditingValue insertAtCursor(TextEditingValue value, String text) {
  final selection = value.selection;
  final start = selection.isValid ? selection.start : value.text.length;
  final end = selection.isValid ? selection.end : value.text.length;
  return TextEditingValue(
    text: value.text.replaceRange(start, end, text),
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}
