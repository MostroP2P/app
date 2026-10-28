import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/widgets/order_list_item.dart';

import '../../support/fake_orders.dart';

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

    group('BTC-pegged codes (#907)', () {
      test('read their sats in the asset unit', () {
        final formats = OrderCardFormats.of('en');

        expect(
          formats.amount(fakeOrder(fiatAmount: 100000, fiatCode: 'RBTC')),
          '0.001',
        );
        expect(
          formats.amount(
            fakeOrder(
              fiatAmountMin: 50000,
              fiatAmountMax: 200000,
              fiatCode: 'LBTC',
            ),
          ),
          '0.0005 – 0.002',
        );
        // Fiat is untouched.
        expect(formats.amount(fakeOrder(fiatAmount: 1250.5)), '1,250.5');
      });

      test(
        'a fixed-sats order stands for the premium its two figures imply',
        () {
          final formats = OrderCardFormats.of('en');
          // 99,000 Lightning sats for 100,000 sats of RBTC: 1% to the seller.
          final order = fakeOrder(
            fiatAmount: 100000,
            fiatCode: 'RBTC',
            amountSats: BigInt.from(99000),
          );

          expect(formats.impliedBtcPeggedPremium(order), closeTo(1.0, 1e-9));
          expect(
            formats.impliedBtcPeggedPremium(
              fakeOrder(
                fiatAmount: 100,
                fiatCode: 'EUR',
                amountSats: BigInt.from(163400),
              ),
            ),
            isNull,
          );
          expect(
            formats.impliedBtcPeggedPremium(
              fakeOrder(fiatAmount: 100000, fiatCode: 'RBTC'),
            ),
            isNull,
            reason: 'a market-price order has its own premium',
          );
        },
      );
    });

    group('fixedPricePerBtc', () {
      test('abbreviates the price per BTC of a fixed-sats order', () {
        final order = fakeOrder(
          fiatAmount: 100,
          fiatCode: 'EUR',
          amountSats: BigInt.from(163400),
        );

        expect(OrderCardFormats.of('en').fixedPricePerBtc(order), '61.2k');
        expect(OrderCardFormats.of('es').fixedPricePerBtc(order), '61,2k');
        expect(OrderCardFormats.of('de').fixedPricePerBtc(order), '61,2k');
      });

      test('keeps the order currency magnitude readable', () {
        final order = fakeOrder(
          fiatAmount: 1000000,
          fiatCode: 'ARS',
          amountSats: BigInt.from(892857),
        );

        expect(OrderCardFormats.of('en').fixedPricePerBtc(order), '112M');
        expect(OrderCardFormats.of('es').fixedPricePerBtc(order), '112M');
      });

      test('reads billions as B, the way a fiat figure is read', () {
        final order = fakeOrder(
          fiatAmount: 1000000,
          fiatCode: 'LBP',
          amountSats: BigInt.from(10000),
        );

        expect(OrderCardFormats.of('en').fixedPricePerBtc(order), '10B');
        expect(OrderCardFormats.of('es').fixedPricePerBtc(order), '10B');
      });

      test('is null for a market-price order', () {
        expect(OrderCardFormats.of('en').fixedPricePerBtc(fakeOrder()), isNull);
      });
    });
  });
}
