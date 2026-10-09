import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/chat/models/info_panel_rules.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart'
    show TradeChipKind;
import 'package:mostro/features/trades/providers/trades_providers.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_orders.dart';
import '../../../support/fake_trades.dart';

void main() {
  group('TradePanelFacts.of', () {
    test('is null until the row or the book entry is known', () {
      expect(TradePanelFacts.of(null, null), isNull);
    });

    test('takes the row first: the slice a take priced out of a range', () {
      final facts =
          TradePanelFacts.of(
            fakeTrade(fiatAmount: 150, fiatAmountMin: 100, fiatAmountMax: 500),
            fakeOrder(fiatAmountMin: 100, fiatAmountMax: 500),
          )!;

      expect(facts.fiatAmount, 150);
      expect(facts.hasFiat, isTrue);
    });

    test('fills sats and payment method from the book when the row lacks '
        'them', () {
      final facts =
          TradePanelFacts.of(
            fakeTrade(amountSats: BigInt.zero, paymentMethod: ' '),
            fakeOrder(amountSats: BigInt.from(1117), paymentMethod: 'SEPA'),
          )!;

      expect(facts.sats, 1117);
      expect(facts.paymentMethod, 'SEPA');
    });

    test('leaves unknown figures null rather than a placeholder', () {
      final facts =
          TradePanelFacts.of(
            fakeTrade(
              amountSats: BigInt.zero,
              paymentMethod: '',
              fiatAmount: 0,
            ),
            null,
          )!;

      expect(facts.sats, isNull);
      expect(facts.paymentMethod, isNull);
      expect(facts.hasFiat, isFalse);
    });

    test('falls back to the book entry without a row', () {
      final order = fakeOrder(fiatAmount: 1225, fiatCode: 'ARS');
      final facts = TradePanelFacts.of(null, order)!;

      expect(facts.fiatAmount, 1225);
      expect(facts.fiatCode, 'ARS');
      expect(facts.createdAt, order.createdAt);
    });
  });

  group('tradePanelStatus', () {
    test('is the header\'s: the live status over the resolved order', () {
      expect(
        tradePanelStatus(
          live: OrderStatus.success,
          order: fakeOrder(status: OrderStatus.active),
          trade: fakeTrade(status: OrderStatus.active),
        ),
        OrderStatus.success,
      );
      expect(
        tradePanelStatus(
          live: null,
          order: fakeOrder(status: OrderStatus.fiatSent),
          trade: fakeTrade(status: OrderStatus.active),
        ),
        OrderStatus.fiatSent,
      );
    });

    test('falls back to the row, then to nothing', () {
      expect(
        tradePanelStatus(
          live: null,
          order: null,
          trade: fakeTrade(status: OrderStatus.dispute),
        ),
        OrderStatus.dispute,
      );
      expect(tradePanelStatus(live: null, order: null, trade: null), isNull);
    });
  });

  test('tradePanelChipKind keeps the trades list\'s colour meanings', () {
    expect(tradePanelChipKind(TradeStatusFilter.active), TradeChipKind.waiting);
    expect(
      tradePanelChipKind(TradeStatusFilter.fiatSent),
      TradeChipKind.waiting,
    );
    expect(tradePanelChipKind(TradeStatusFilter.success), TradeChipKind.done);
    expect(tradePanelChipKind(TradeStatusFilter.canceled), TradeChipKind.done);
    expect(
      tradePanelChipKind(TradeStatusFilter.dispute),
      TradeChipKind.dispute,
    );
  });

  group('peerReputation', () {
    test('a maker gets the taker\'s snapshot', () {
      final reputation = peerReputation(
        fakeTrade(isMine: true, peerRating: 4.4, peerReviews: 4, peerDays: 9),
        fakeOrder(isMine: true, rating: 5, tradeCount: 99),
      );

      expect(reputation, (rating: 4.4, reviews: 4, days: 9));
    });

    test('a taker gets the maker\'s rating tag from the order', () {
      final reputation = peerReputation(
        fakeTrade(),
        fakeOrder(rating: 4.8, tradeCount: 12, daysActive: 186),
      );

      expect(reputation, (rating: 4.8, reviews: 12, days: 186));
    });

    test('a maker without a snapshot gets none, never their own rating', () {
      expect(
        peerReputation(
          fakeTrade(isMine: true),
          fakeOrder(isMine: true, rating: 5, tradeCount: 99),
        ),
        isNull,
      );
    });

    test('nothing is known before the order resolves', () {
      expect(peerReputation(fakeTrade(), null), isNull);
      expect(peerReputation(null, null), isNull);
    });
  });
}
