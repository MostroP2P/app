import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// Portuguese puts 0 and 1 in the same plural category, so a `=1{1 ordem}`
/// case alone would read "1 ordem" for zero. Every count in app_pt.arb
/// therefore carries its own `=0` case, in the plural Brazilian Portuguese
/// uses for zero: "0 ordens", never "0 ordem".
void main() {
  late AppLocalizations pt;

  setUpAll(() async {
    pt = await AppLocalizations.delegate.load(const Locale('pt'));
  });

  test('zero takes the plural, one the singular', () {
    expect(pt.ordersCount(0), '0 ordens');
    expect(pt.ordersCount(1), '1 ordem');
    expect(pt.ordersCount(3), '3 ordens');
    expect(pt.reputationTradesCount(0), '0 operações');
    expect(pt.reputationTradesCount(1), '1 operação');
    expect(pt.reputationTradesCount(2), '2 operações');
  });

  test('every plural in app_pt.arb has its own =0 case', () {
    final raw =
        jsonDecode(File('lib/l10n/app_pt.arb').readAsStringSync())
            as Map<String, dynamic>;
    final plural = RegExp(r'\{\s*\w+\s*,\s*plural\s*,');
    final zero = RegExp(r'=0\s*\{');
    final missing = [
      for (final MapEntry(:key, :value) in raw.entries)
        if (!key.startsWith('@') &&
            value is String &&
            plural.allMatches(value).length > zero.allMatches(value).length)
          key,
    ];
    expect(missing, isEmpty);
  });
}
