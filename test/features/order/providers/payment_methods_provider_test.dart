import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/providers/payment_methods_provider.dart';

/// In-memory data used to exercise the currency provider without touching
/// rootBundle (which isn't wired for plain unit tests).
const _fixture = <String, List<String>>{
  'ARS': ['Mercado Pago', 'CVU'],
  'default': ['Bank Transfer', 'Cash in person'],
};

ProviderContainer _containerWith(Map<String, List<String>> data) {
  final c = ProviderContainer(overrides: [
    paymentMethodsDataProvider.overrideWith((ref) async => data),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('paymentMethodsForCurrencyProvider', () {
    test('returns the currency-specific list for a known currency', () async {
      final c = _containerWith(_fixture);
      await c.read(paymentMethodsDataProvider.future);
      expect(c.read(paymentMethodsForCurrencyProvider('ARS')),
          ['Mercado Pago', 'CVU']);
    });

    test('falls back to the default list for an unknown currency', () async {
      final c = _containerWith(_fixture);
      await c.read(paymentMethodsDataProvider.future);
      expect(c.read(paymentMethodsForCurrencyProvider('XXX')),
          ['Bank Transfer', 'Cash in person']);
    });

    test('returns an empty list while the asset is still loading', () {
      final c = _containerWith(_fixture);
      // Not awaited: the future is still pending, so the provider must yield [].
      expect(c.read(paymentMethodsForCurrencyProvider('ARS')), isEmpty);
    });
  });

  group('shipped payment_methods.json contract', () {
    late Map<String, dynamic> shipped;
    setUpAll(() {
      shipped = jsonDecode(
        File('assets/data/payment_methods.json').readAsStringSync(),
      ) as Map<String, dynamic>;
    });

    test('ships a default fallback plus many currencies', () {
      expect(shipped.containsKey('default'), isTrue);
      expect(shipped.length, greaterThan(20));
    });

    test('known currencies carry their expected local methods', () {
      expect((shipped['ARS'] as List).cast<String>(), contains('Mercado Pago'));
      expect((shipped['MWK'] as List).cast<String>(), contains('Airtel Money'));
      expect((shipped['KES'] as List).cast<String>(), contains('M-PESA'));
    });
  });
}
