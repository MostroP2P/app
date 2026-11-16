import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/utils/insert_at_cursor.dart';

void main() {
  group('insertAtCursor (#938)', () {
    test('puts the text at the cursor and the cursor after it', () {
      const value = TextEditingValue(
        text: 'hi there',
        selection: TextSelection.collapsed(offset: 2),
      );

      final next = insertAtCursor(value, '😀');

      expect(next.text, 'hi😀 there');
      expect(next.selection, const TextSelection.collapsed(offset: 4));
    });

    test('replaces the selected text', () {
      const value = TextEditingValue(
        text: 'hi there',
        selection: TextSelection(baseOffset: 3, extentOffset: 8),
      );

      final next = insertAtCursor(value, '👋');

      expect(next.text, 'hi 👋');
      expect(next.selection, const TextSelection.collapsed(offset: 5));
    });

    test('appends when the field has no cursor yet', () {
      const value = TextEditingValue(text: 'ok');

      final next = insertAtCursor(value, '👍');

      expect(next.text, 'ok👍');
      expect(next.selection, const TextSelection.collapsed(offset: 4));
    });

    test('fills an empty field', () {
      final next = insertAtCursor(TextEditingValue.empty, '🙂');

      expect(next.text, '🙂');
      expect(next.selection, const TextSelection.collapsed(offset: 2));
    });

    test('leaves the value it was given untouched', () {
      const value = TextEditingValue(
        text: 'a',
        selection: TextSelection.collapsed(offset: 1),
      );

      insertAtCursor(value, '😀');

      expect(value.text, 'a');
    });
  });
}
