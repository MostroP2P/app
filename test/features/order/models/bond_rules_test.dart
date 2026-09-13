import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/models/bond_rules.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/src/rust/api/types.dart'
    show BondInfo, BondRole, BondState, OrderKind, TradeRole, TradeUpdateReason;

void main() {
  BondInfo bond(BondRole role) => BondInfo(
    role: role,
    amountSats: BigInt.from(1000),
    invoice: 'lnbc1x',
    state: BondState.requested,
    requestedAt: intToPlatformInt64(1),
    expiresAt: null,
    lockedAt: null,
  );

  group('bondIsMakers', () {
    test('reads the bond role, and ownership when there is no bond', () {
      expect(bondIsMakers(bond(BondRole.maker), isMine: true), isTrue);
      expect(bondIsMakers(bond(BondRole.taker), isMine: false), isFalse);
      expect(bondIsMakers(null, isMine: true), isTrue);
      expect(bondIsMakers(null, isMine: false), isFalse);
    });
  });

  group('bondPayerIsBuying', () {
    test('a maker takes their own side, a taker the other', () {
      expect(bondPayerIsBuying(OrderKind.buy, maker: true), isTrue);
      expect(bondPayerIsBuying(OrderKind.sell, maker: true), isFalse);
      expect(bondPayerIsBuying(OrderKind.sell, maker: false), isTrue);
      expect(bondPayerIsBuying(OrderKind.buy, maker: false), isFalse);
    });
  });

  group('bondCountdownEnd', () {
    test('a taker counts the bolt11 alone', () {
      expect(
        bondCountdownEnd(
          invoiceExpiresAt: 900,
          orderExpiresAt: 500,
          maker: false,
        ),
        900,
      );
      expect(
        bondCountdownEnd(
          invoiceExpiresAt: null,
          orderExpiresAt: 500,
          maker: false,
        ),
        isNull,
      );
    });
    test('a maker counts the earlier of the bolt11 and the order', () {
      expect(
        bondCountdownEnd(
          invoiceExpiresAt: 900,
          orderExpiresAt: 500,
          maker: true,
        ),
        500,
      );
      expect(
        bondCountdownEnd(
          invoiceExpiresAt: 400,
          orderExpiresAt: 500,
          maker: true,
        ),
        400,
      );
      expect(
        bondCountdownEnd(
          invoiceExpiresAt: null,
          orderExpiresAt: 500,
          maker: true,
        ),
        500,
      );
      expect(
        bondCountdownEnd(
          invoiceExpiresAt: null,
          orderExpiresAt: null,
          maker: true,
        ),
        isNull,
      );
    });
  });

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

  group('bondWarnsTimeout', () {
    test('follows the node policy once known', () {
      expect(bondWarnsTimeout(true), isTrue);
      expect(bondWarnsTimeout(false), isFalse);
    });
    test('warns while the policy is unknown', () {
      expect(bondWarnsTimeout(null), isTrue);
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
      // Finite as a fraction, infinite once scaled: omitted, not a throw.
      expect(bondSharePercent(1e308), isNull);
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
