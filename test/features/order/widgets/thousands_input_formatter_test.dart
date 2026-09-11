import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/widgets/underline_amount_field.dart';

String _format(ThousandsInputFormatter f, String typed) =>
    f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: typed)).text;

void main() {
  const es = ThousandsInputFormatter(groupSeparator: '.', decimalSeparator: ',');
  const en = ThousandsInputFormatter(groupSeparator: ',', decimalSeparator: '.');
  const ints = ThousandsInputFormatter(
    groupSeparator: '.',
    decimalSeparator: ',',
    allowDecimals: false,
  );

  group('ThousandsInputFormatter', () {
    test('groups the integer part with the locale separator', () {
      expect(_format(es, '25000'), '25.000');
      expect(_format(en, '1234567'), '1,234,567');
    });

    test('regroups text that already carries separators', () {
      expect(_format(es, '2.50.0'), '2.500');
      expect(_format(en, '1,2345'), '12,345');
    });

    test('only the locale decimal separator is a decimal', () {
      expect(_format(es, '1000,5'), '1.000,5');
      expect(_format(en, '1000.5'), '1,000.5');
      // The other locale's decimal mark is this locale's group mark: a pasted
      // grouped figure keeps its magnitude.
      expect(_format(es, '25.000'), '25.000');
      expect(_format(en, '25,000'), '25,000');
    });

    test('keeps one decimal separator and at most two decimals', () {
      expect(_format(es, '1,2,3'), '1,23');
      expect(_format(en, '1.23456'), '1.23');
    });

    test('drops letters and leading zeros', () {
      expect(_format(en, 'a1b2'), '12');
      expect(_format(en, '007'), '7');
      expect(_format(en, '0'), '0');
    });

    test('ignores decimals when they are not allowed', () {
      expect(_format(ints, '5000,5'), '50.005');
    });

    test('moves the caret to the end of the regrouped text', () {
      final value = es.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '25000'),
      );
      expect(value.selection.baseOffset, 6);
    });
  });
}
