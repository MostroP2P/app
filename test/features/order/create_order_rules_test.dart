import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/home/providers/home_order_providers.dart';
import 'package:mostro/features/about/models/mostro_instance.dart'
    show BondApplyTo, BondPolicy;
import 'package:mostro/features/order/models/create_order_rules.dart';

void main() {
  group('makerBondApplies', () {
    test('applies only to an enabled policy that bonds makers', () {
      expect(
        makerBondApplies(policy: BondPolicy.enabled, applyTo: BondApplyTo.make),
        isTrue,
      );
      expect(
        makerBondApplies(policy: BondPolicy.enabled, applyTo: BondApplyTo.both),
        isTrue,
      );
      expect(
        makerBondApplies(policy: BondPolicy.enabled, applyTo: BondApplyTo.take),
        isFalse,
      );
    });
    test('unknown, disabled or missing policy publishes as before', () {
      expect(
        makerBondApplies(
          policy: BondPolicy.disabled,
          applyTo: BondApplyTo.both,
        ),
        isFalse,
      );
      expect(
        makerBondApplies(policy: BondPolicy.unsupported, applyTo: null),
        isFalse,
      );
      expect(makerBondApplies(policy: null, applyTo: null), isFalse);
    });
  });

  group('premiumFavour (maker side)', () {
    test('selling above market favours the maker', () {
      expect(premiumFavour(OrderType.sell, 3), PremiumFavour.good);
    });

    test('selling below market plays against the maker', () {
      expect(premiumFavour(OrderType.sell, -3), PremiumFavour.bad);
    });

    test('buying below market favours the maker', () {
      expect(premiumFavour(OrderType.buy, -3), PremiumFavour.good);
    });

    test('buying above market plays against the maker', () {
      expect(premiumFavour(OrderType.buy, 3), PremiumFavour.bad);
    });

    test('zero is neutral on both sides', () {
      expect(premiumFavour(OrderType.buy, 0), PremiumFavour.zero);
      expect(premiumFavour(OrderType.sell, 0), PremiumFavour.zero);
    });

    test('switching side with a premium set inverts the colour', () {
      // Arrange
      const premium = 2.0;

      // Act
      final asSeller = premiumFavour(OrderType.sell, premium);
      final asBuyer = premiumFavour(OrderType.buy, premium);

      // Assert
      expect(asSeller, PremiumFavour.good);
      expect(asBuyer, PremiumFavour.bad);
    });
  });

  group('quickAmounts', () {
    test('USD keeps the base amounts', () {
      expect(quickAmounts(1), [10, 25, 50, 100]);
    });

    test('rounds a weak currency to round figures', () {
      // 1 USD ≈ 1450 ARS → 14 500 / 36 250 / 72 500 / 145 000 raw.
      expect(quickAmounts(1450), [10000, 25000, 50000, 100000]);
    });

    test('rounds a strong currency without collapsing to nothing', () {
      // 1 USD ≈ 0.92 EUR → 9.2 / 23 / 46 / 92 raw.
      expect(quickAmounts(0.92), [10, 25, 50, 100]);
    });

    test('drops duplicates and gives up below two distinct chips', () {
      // 1 USD ≈ 0.31 KWD → 3.1 / 7.75 / 15.5 / 31.
      expect(quickAmounts(0.31), [3, 10, 20, 25]);
      // Rate so small every candidate is under one unit.
      expect(quickAmounts(0.001), isEmpty);
    });

    test('returns nothing without a usable rate', () {
      expect(quickAmounts(null), isEmpty);
      expect(quickAmounts(0), isEmpty);
      expect(quickAmounts(-5), isEmpty);
      expect(quickAmounts(double.nan), isEmpty);
      expect(quickAmounts(double.infinity), isEmpty);
    });
  });

  group('canonicalAmount', () {
    String? es(String text) =>
        canonicalAmount(text, groupSeparator: '.', decimalSeparator: ',');
    String? en(String text) =>
        canonicalAmount(text, groupSeparator: ',', decimalSeparator: '.');

    test('strips the group separator of the locale', () {
      expect(es('25.000'), '25000');
      expect(en('25,000'), '25000');
    });

    test('normalises the decimal separator to a dot', () {
      expect(es('1.000,50'), '1000.50');
      expect(en('1,000.50'), '1000.50');
    });

    test('accepts a plain number and trims whitespace', () {
      expect(en(' 42 '), '42');
    });

    test('rejects empty, non-numeric, zero, negative and special doubles', () {
      expect(en(''), isNull);
      expect(en('abc'), isNull);
      expect(en('0'), isNull);
      expect(en('-5'), isNull);
      expect(en('Infinity'), isNull);
      expect(en('NaN'), isNull);
      expect(en('1e5'), isNull);
    });
  });

  group('preview markup', () {
    test('recovers each role from a filled-in template', () {
      // Arrange
      final amount = markPreview('5.000 ARS', PreviewRole.amount);
      final premium = markPreview('+3%', PreviewRole.premium);
      final duration = markPreview('24 h', PreviewRole.duration);
      final sentence = 'Vendes BTC por $amount a mercado $premium · $duration';

      // Act
      final fragments = previewFragments(sentence);

      // Assert
      expect(fragments, const [
        PreviewFragment('Vendes BTC por ', PreviewRole.text),
        PreviewFragment('5.000 ARS', PreviewRole.amount),
        PreviewFragment(' a mercado ', PreviewRole.text),
        PreviewFragment('+3%', PreviewRole.premium),
        PreviewFragment(' · ', PreviewRole.text),
        PreviewFragment('24 h', PreviewRole.duration),
      ]);
    });

    test('a sentence without markers is one plain fragment', () {
      expect(previewFragments('hello'), const [
        PreviewFragment('hello', PreviewRole.text),
      ]);
    });

    test('tells sats apart from amount even when the figures match', () {
      final sentence =
          '${markPreview('5.000 sats', PreviewRole.sats)} por '
          '${markPreview('5.000 ARS', PreviewRole.amount)}';
      final roles = previewFragments(sentence).map((f) => f.role).toList();
      expect(roles, [PreviewRole.sats, PreviewRole.text, PreviewRole.amount]);
    });
  });
}
