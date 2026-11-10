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
    late List<Map<String, dynamic>> catalogue;
    setUpAll(() {
      shipped = jsonDecode(
        File('assets/data/payment_methods.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      catalogue =
          (jsonDecode(File('assets/data/fiat.json').readAsStringSync())
                  as List<dynamic>)
              .cast<Map<String, dynamic>>();
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

    test('the Cuban USD cards are offered in USD, not in CUP or MLC', () {
      // Tarjeta Clásica and Tarjeta Tropical hold dollars: neither takes
      // pesos or MLC, which is a separate denomination.
      const cards = ['Tarjeta Clásica', 'Tarjeta Tropical'];
      final usd = (shipped['USD'] as List).cast<String>();
      for (final card in cards) {
        expect(usd, contains(card));
        expect((shipped['CUP'] as List).cast<String>(), isNot(contains(card)));
        expect((shipped['MLC'] as List).cast<String>(), isNot(contains(card)));
      }
    });

    test('every currency with its own methods can be picked', () {
      // A code missing from fiat.json is never offered, so its methods are
      // never seen (MLC had both, and only the methods shipped).
      final codes = catalogue.map((c) => c['code'] as String).toSet();
      expect(
        shipped.keys.where((k) => k != 'default' && !codes.contains(k)),
        isEmpty,
      );
    });

    test('every stablecoin has its own methods, each naming the network', () {
      // A coin sent on the wrong network can be lost, so a stablecoin never
      // falls back to the fiat `default` list, and every method says which
      // chain the coin travels on: "USDT (Tron)" (#884).
      final coins = [
        for (final c in catalogue)
          if (c['peg'] != null) c['code'] as String,
      ];
      expect(coins, isNotEmpty);
      for (final code in coins) {
        expect(shipped.keys, contains(code), reason: '$code has no methods');
        final methods = (shipped[code] as List).cast<String>();
        expect(methods, isNotEmpty, reason: code);
        expect(
          methods,
          everyElement(
            matches(RegExp('^${RegExp.escape(code)} \\([^()]+\\)\$')),
          ),
          reason: code,
        );
      }
    });

    test('bitcoin on other networks names its one network (#907)', () {
      // The code already names the network, so each has one method, written
      // `<CODE> (<Network>)` as the protocol book's page asks.
      const methods = {
        'BTC': ['BTC (On-chain)'],
        'LBTC': ['LBTC (Liquid)'],
        'RBTC': ['RBTC (Rootstock)'],
      };
      methods.forEach((code, expected) {
        expect((shipped[code] as List).cast<String>(), expected, reason: code);
      });
    });

    test('each coin is offered on the networks of #884', () {
      // The order is the picker's, not part of the contract.
      const networks = {
        'DOC': ['Rootstock'],
        'USDC': ['Ethereum', 'Base', 'Solana', 'Polygon'],
        'USDT': ['Tron', 'Ethereum', 'Polygon', 'Solana', 'Liquid'],
      };
      networks.forEach((code, chains) {
        expect(
          (shipped[code] as List).cast<String>(),
          unorderedEquals([for (final chain in chains) '$code ($chain)']),
          reason: code,
        );
      });
    });
  });
}
