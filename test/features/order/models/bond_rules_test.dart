import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/models/bond_rules.dart';
import 'package:mostro/src/rust/api/types.dart'
    show OrderKind, TradeRole, TradeUpdateReason;

void main() {
  group('bondFiatEquivalent', () {
    test('converts sats at a fiat-per-BTC rate', () {
      expect(
        bondFiatEquivalent(sats: 1648, rate: 125000000),
        closeTo(2060, 0.01),
      );
    });
    test('is null without a usable rate or amount', () {
      expect(bondFiatEquivalent(sats: 1648, rate: null), isNull);
      expect(bondFiatEquivalent(sats: 1648, rate: 0), isNull);
      expect(bondFiatEquivalent(sats: 1648, rate: double.nan), isNull);
      expect(bondFiatEquivalent(sats: 0, rate: 1000), isNull);
    });
  });

  group('bondSharePercent', () {
    test('renders the node fraction as a percentage without a trailing .0', () {
      expect(bondSharePercent(0.02), '2');
      expect(bondSharePercent(0.015), '1.5');
      expect(bondSharePercent(0.0), '0');
    });
    test('is null when the node advertises none', () {
      expect(bondSharePercent(null), isNull);
      expect(bondSharePercent(-0.1), isNull);
      expect(bondSharePercent(double.infinity), isNull);
    });
  });

  group('formatBondFiat', () {
    test('rounds to whole units with the locale grouping and the code', () {
      expect(formatBondFiat('en', 2060.4, 'ARS'), '2,060 ARS');
    });
  });

  test('the taker of a sell order buys, of a buy order sells', () {
    expect(takerIsBuying(OrderKind.sell), isTrue);
    expect(takerIsBuying(OrderKind.buy), isFalse);
    expect(bondIsFollowedByEscrow(TradeRole.seller), isTrue);
    expect(bondIsFollowedByEscrow(TradeRole.buyer), isFalse);
  });

  test('the cancel copy follows the cause the core attached', () {
    expect(
      bondCancelCopy(TradeUpdateReason.bondLostRace),
      BondCancelCopy.lostRace,
    );
    expect(
      bondCancelCopy(TradeUpdateReason.makerCanceled),
      BondCancelCopy.makerCanceled,
    );
    expect(bondCancelCopy(TradeUpdateReason.userCanceled), BondCancelCopy.own);
    expect(
      bondCancelCopy(TradeUpdateReason.bondExpired),
      BondCancelCopy.neutral,
    );
    expect(bondCancelCopy(null), BondCancelCopy.neutral);
  });

  test('the explainer opens the first time and then as last left', () {
    expect(bondExplainerOpens(stored: null), isTrue);
    expect(bondExplainerOpens(stored: false), isFalse);
    expect(bondExplainerOpens(stored: true), isTrue);
  });
}
