import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The default payment methods used when a currency has no specific list.
const _fallbackMethods = <String>['Bank Transfer', 'Cash in person'];

/// Loads the currency → payment-methods map from the bundled asset once.
final paymentMethodsDataProvider =
    FutureProvider<Map<String, List<String>>>((ref) async {
  final raw =
      await rootBundle.loadString('assets/data/payment_methods.json');
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  return decoded.map(
    (code, methods) => MapEntry(
      code,
      (methods as List<dynamic>).cast<String>(),
    ),
  );
});

/// The suggested payment methods for [currencyCode], falling back to the
/// `default` list (and then a hardcoded fallback) for unknown currencies.
///
/// Returns an empty list while the asset is still loading so the section can
/// render its custom field without flashing placeholder chips.
final paymentMethodsForCurrencyProvider =
    Provider.family<List<String>, String>((ref, currencyCode) {
  final data = ref.watch(paymentMethodsDataProvider);
  return data.maybeWhen(
    data: (map) =>
        map[currencyCode] ?? map['default'] ?? _fallbackMethods,
    orElse: () => const <String>[],
  );
});
