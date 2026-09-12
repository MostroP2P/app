import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/trades/models/trade_status.dart';
import 'package:mostro/features/trades/models/trade_view.dart';

/// Locks the handoff's state → mockup table (`design_handoff_operacion/`):
/// one lime button when the user acts, none when they wait; chat only once
/// the trade is active; dispute never before the escrow is locked (#203).
void main() {
  TradeView view(
    TradeStatus status, {
    required bool isBuyer,
    bool canRate = true,
  }) => TradeView.of(status: status, isBuyer: isBuyer, canRate: canRate);

  group('8a · waiting for the counterpart to lock the sats', () {
    test('buyer waits: amber chip, no chat, cancel alone at full width', () {
      final v = view(TradeStatus.waitingPayment, isBuyer: true);
      expect(v.step, 1);
      expect(v.chip, TradeChip.waiting);
      expect(v.showsChat, isFalse);
      expect(v.primary, TradePrimaryAction.none);
      expect(v.secondary, [TradeSecondaryAction.cancel]);
      expect(v.cancelIsFullWidth, isTrue);
      expect(v.timer, TradeTimerOwner.counterpart);
      expect(v.note, TradeTimerNote.expiresCancels);
    });

    test('the seller who must pay the hold invoice gets the lime action', () {
      final v = view(TradeStatus.waitingPayment, isBuyer: false);
      expect(v.chip, TradeChip.yourTurn);
      expect(v.primary, TradePrimaryAction.payHoldInvoice);
      expect(v.timer, TradeTimerOwner.user);
    });

    test('the buyer who must add an invoice gets the lime action', () {
      final v = view(TradeStatus.waitingInvoice, isBuyer: true);
      expect(v.chip, TradeChip.yourTurn);
      expect(v.primary, TradePrimaryAction.addInvoice);
      expect(v.showsChat, isFalse);
    });

    test('in-progress only offers cancel and no clock', () {
      final v = view(TradeStatus.inProgress, isBuyer: true);
      expect(v.primary, TradePrimaryAction.none);
      expect(v.secondary, [TradeSecondaryAction.cancel]);
      expect(v.showsTimer, isFalse);
    });
  });

  group('8b · active, waiting for the buyer to pay', () {
    test('seller: lime chip, chat, reputation, no primary', () {
      final v = view(TradeStatus.active, isBuyer: false);
      expect(v.step, 2);
      expect(v.chip, TradeChip.active);
      expect(v.showsChat, isTrue);
      expect(v.showsReputation, isTrue);
      expect(v.primary, TradePrimaryAction.none);
      expect(v.secondary, [
        TradeSecondaryAction.cancel,
        TradeSecondaryAction.dispute,
      ]);
      expect(v.cancelIsFullWidth, isFalse);
      expect(v.timer, TradeTimerOwner.counterpart);
      expect(v.note, TradeTimerNote.coordinateInChat);
    });
  });

  group('8c · your turn to send the fiat', () {
    test('buyer: your-turn chip and the fiat-sent action', () {
      final v = view(TradeStatus.active, isBuyer: true);
      expect(v.chip, TradeChip.yourTurn);
      expect(v.primary, TradePrimaryAction.fiatSent);
      expect(v.showsReputation, isTrue);
      expect(v.timer, TradeTimerOwner.user);
    });
  });

  group('8d · confirm receipt and release', () {
    test('seller: release action with the irreversibility warning', () {
      final v = view(TradeStatus.fiatSent, isBuyer: false);
      expect(v.step, 3);
      expect(v.chip, TradeChip.yourTurn);
      expect(v.primary, TradePrimaryAction.release);
      expect(v.showsReleaseWarning, isTrue);
      expect(v.showsReputation, isFalse);
      expect(v.showsChat, isTrue);
      expect(v.secondary, [
        TradeSecondaryAction.cancel,
        TradeSecondaryAction.dispute,
      ]);
    });

    test('buyer waits for the release without a warning', () {
      final v = view(TradeStatus.fiatSent, isBuyer: true);
      expect(v.chip, TradeChip.waiting);
      expect(v.primary, TradePrimaryAction.none);
      expect(v.showsReleaseWarning, isFalse);
      expect(v.timer, TradeTimerOwner.counterpart);
    });

    test('payout pending: nothing to do, no clock', () {
      final v = view(TradeStatus.payoutPending, isBuyer: false);
      expect(v.hasActions, isFalse);
      expect(v.showsTimer, isFalse);
      expect(v.showsChat, isTrue);
    });
  });

  group('8e · completed', () {
    test('unrated: inline rating with Close as a link, timeline at step 5', () {
      final v = view(TradeStatus.pendingRating, isBuyer: true);
      expect(v.isCompleted, isTrue);
      expect(v.step, kTradeStepCount - 1);
      expect(v.primary, TradePrimaryAction.sendRating);
      expect(v.showsCloseLink, isTrue);
      expect(v.showsChat, isFalse);
      expect(v.showsTimer, isFalse);
    });

    test('unrated in privacy mode: only Close', () {
      final v = view(TradeStatus.pendingRating, isBuyer: true, canRate: false);
      expect(v.primary, TradePrimaryAction.close);
      expect(v.showsCloseLink, isFalse);
    });

    test('rated: every step done and Close', () {
      final v = view(TradeStatus.rated, isBuyer: false);
      expect(v.step, kTradeStepCount);
      expect(v.primary, TradePrimaryAction.close);
      expect(v.secondary, isEmpty);
    });
  });

  group('outside the happy path', () {
    test('dispute: view it; only the seller may still release or cancel', () {
      final seller = view(TradeStatus.disputed, isBuyer: false);
      expect(seller.chip, TradeChip.dispute);
      expect(seller.primary, TradePrimaryAction.viewDispute);
      expect(seller.secondary, [
        TradeSecondaryAction.release,
        TradeSecondaryAction.cancel,
      ]);
      expect(seller.step, -1);

      final buyer = view(TradeStatus.disputed, isBuyer: true);
      expect(buyer.secondary, isEmpty);
    });

    test('cancelled: just Close, no timeline', () {
      final v = view(TradeStatus.cancelled, isBuyer: true);
      expect(v.primary, TradePrimaryAction.close);
      expect(v.step, -1);
      expect(v.isCompleted, isFalse);
    });

    test('loading: nothing at all', () {
      final v = view(TradeStatus.loading, isBuyer: true);
      expect(v.hasActions, isFalse);
      expect(v.chip, TradeChip.none);
    });

    test('pending order: cancel alone, the book clock', () {
      final v = view(TradeStatus.pending, isBuyer: false);
      expect(v.step, 0);
      expect(v.cancelIsFullWidth, isTrue);
      expect(v.timer, TradeTimerOwner.order);
      expect(v.note, TradeTimerNote.leavesBook);
    });
  });

  test('a dispute is never offered before the escrow is locked (#203)', () {
    for (final status in [
      TradeStatus.pending,
      TradeStatus.waitingInvoice,
      TradeStatus.waitingPayment,
      TradeStatus.inProgress,
    ]) {
      for (final isBuyer in [true, false]) {
        expect(
          view(status, isBuyer: isBuyer).secondary,
          isNot(contains(TradeSecondaryAction.dispute)),
          reason: '$status',
        );
      }
    }
  });
}
