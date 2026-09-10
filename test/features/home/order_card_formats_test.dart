import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/widgets/order_list_item.dart';

void main() {
  group('OrderCardFormats', () {
    test('reuses one set of formatters per locale', () {
      // The card needs four formatters, so building them per row per rebuild
      // is the most repeated allocation in a list of thousands of orders —
      // which is the saving here, construction being only ~1.2–1.5x the cost
      // of a format() call rather than the order of magnitude one might
      // assume.
      expect(
        identical(OrderCardFormats.of('es'), OrderCardFormats.of('es')),
        isTrue,
      );
    });

    test('keeps locales apart', () {
      final es = OrderCardFormats.of('es');
      final en = OrderCardFormats.of('en');

      expect(identical(es, en), isFalse);
      expect(es.decimal.format(1234), isNot(en.decimal.format(1234)));
    });

    test('formats the premium with an explicit sign', () {
      final formats = OrderCardFormats.of('en');

      expect(formats.premium.format(2.5), '+2.5');
      expect(formats.premium.format(-2.5), '-2.5');
    });
  });
}
