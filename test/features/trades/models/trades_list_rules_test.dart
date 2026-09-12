import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/src/rust/api/types.dart' show OrderStatus;

TradeRowState _row(
  OrderStatus status, {
  bool isBuyer = true,
  bool ratedByMe = false,
  bool canRate = true,
}) => TradeRowState.of(
  status: status,
  isBuyer: isBuyer,
  ratedByMe: ratedByMe,
  canRate: canRate,
);

void main() {
  group('TradeRowState · requires your action', () {
    // Exactly the states where the trade screen shows a primary button
    // that moves the trade (handoff 8): the list promises what it keeps.
    for (final (status, isBuyer, verb) in [
      (OrderStatus.waitingBuyerInvoice, true, TradeRowVerb.addInvoice),
      (OrderStatus.waitingPayment, false, TradeRowVerb.payInvoice),
      (OrderStatus.active, true, TradeRowVerb.sendPayment),
      (OrderStatus.fiatSent, false, TradeRowVerb.releaseSats),
      (OrderStatus.success, true, TradeRowVerb.rate),
      (OrderStatus.success, false, TradeRowVerb.rate),
    ]) {
      test('$status as ${isBuyer ? 'buyer' : 'seller'} → ${verb.name}', () {
        final row = _row(status, isBuyer: isBuyer);
        expect(row.group, TradeGroup.needsAction);
        expect(row.verb, verb);
        expect(row.chip, TradeChipLabel.yourTurn);
        expect(row.chipKind, TradeChipKind.action);
      });
    }
  });

  group('TradeRowState · in progress', () {
    for (final (status, isBuyer, chip) in [
      (OrderStatus.pending, true, TradeChipLabel.published),
      (OrderStatus.waitingBuyerInvoice, false, TradeChipLabel.waitingInvoice),
      (OrderStatus.waitingPayment, true, TradeChipLabel.waitingPayment),
      (OrderStatus.inProgress, true, TradeChipLabel.inProgress),
      (OrderStatus.active, false, TradeChipLabel.waitingPayment),
      (OrderStatus.fiatSent, true, TradeChipLabel.waitingSats),
      (OrderStatus.settledHoldInvoice, true, TradeChipLabel.waitingSats),
    ]) {
      test('$status as ${isBuyer ? 'buyer' : 'seller'} → ${chip.name}', () {
        final row = _row(status, isBuyer: isBuyer);
        expect(row.group, TradeGroup.inProgress);
        expect(row.verb, TradeRowVerb.none);
        expect(row.chip, chip);
        expect(row.chipKind, TradeChipKind.waiting);
      });
    }

    test('a dispute stays in progress, in the dispute chip', () {
      // Viewing the dispute is navigation, not a step the user owes: until
      // the admin asks for something the model cannot tell, it would sit in
      // `Requieren tu acción` for its whole life.
      for (final isBuyer in [true, false]) {
        final row = _row(OrderStatus.dispute, isBuyer: isBuyer);
        expect(row.group, TradeGroup.inProgress);
        expect(row.verb, TradeRowVerb.none);
        expect(row.chipKind, TradeChipKind.dispute);
      }
    });
  });

  group('TradeRowState · closed', () {
    test('a rated success is completed', () {
      final row = _row(OrderStatus.success, ratedByMe: true);
      expect(row.group, TradeGroup.closed);
      expect(row.chip, TradeChipLabel.completed);
      expect(row.chipKind, TradeChipKind.done);
    });

    test('with no way to rate, a success is completed at once', () {
      final row = _row(OrderStatus.success, canRate: false);
      expect(row.group, TradeGroup.closed);
      expect(row.verb, TradeRowVerb.none);
    });

    test('an admin settlement counts as a success', () {
      expect(
        _row(OrderStatus.settledByAdmin, ratedByMe: true).chip,
        TradeChipLabel.completed,
      );
      expect(
        _row(OrderStatus.completedByAdmin, ratedByMe: true).chip,
        TradeChipLabel.completed,
      );
    });

    test('cancellations and expiry are told apart', () {
      for (final status in [
        OrderStatus.canceled,
        OrderStatus.cooperativelyCanceled,
        OrderStatus.canceledByAdmin,
      ]) {
        expect(_row(status).chip, TradeChipLabel.cancelled, reason: '$status');
        expect(_row(status).group, TradeGroup.closed);
      }
      expect(_row(OrderStatus.expired).chip, TradeChipLabel.expired);
    });
  });

  group('groupTradeRows', () {
    test('fixed order, empty groups skipped, newest activity first', () {
      final rows = [
        (id: 'closed-old', group: TradeGroup.closed, at: 1),
        (id: 'progress', group: TradeGroup.inProgress, at: 5),
        (id: 'action-old', group: TradeGroup.needsAction, at: 2),
        (id: 'action-new', group: TradeGroup.needsAction, at: 9),
      ];

      final grouped = groupTradeRows(
        rows,
        groupOf: (r) => r.group,
        activityOf: (r) => r.at,
      );

      expect(grouped.map((g) => g.group), [
        TradeGroup.needsAction,
        TradeGroup.inProgress,
        TradeGroup.closed,
      ]);
      expect(grouped.first.rows.map((r) => r.id), ['action-new', 'action-old']);

      final noClosed = groupTradeRows(
        rows.where((r) => r.group != TradeGroup.closed).toList(),
        groupOf: (r) => r.group,
        activityOf: (r) => r.at,
      );
      expect(noClosed.map((g) => g.group), [
        TradeGroup.needsAction,
        TradeGroup.inProgress,
      ]);
    });
  });

  group('TradeListFilter', () {
    test('matches by what the row became, not by raw status', () {
      final action = _row(OrderStatus.active);
      final completed = _row(OrderStatus.success, ratedByMe: true);
      final cancelled = _row(OrderStatus.canceled);
      final expired = _row(OrderStatus.expired);

      expect(TradeListFilter.all.matches(cancelled), isTrue);
      expect(TradeListFilter.active.matches(action), isTrue);
      expect(TradeListFilter.active.matches(completed), isFalse);
      expect(TradeListFilter.completed.matches(completed), isTrue);
      expect(TradeListFilter.completed.matches(action), isFalse);
      expect(TradeListFilter.cancelled.matches(cancelled), isTrue);
      expect(TradeListFilter.cancelled.matches(expired), isTrue);
    });

    test('round-trips through its stored name and survives junk', () {
      for (final f in TradeListFilter.values) {
        expect(TradeListFilter.fromStored(f.name), f);
      }
      expect(TradeListFilter.fromStored(null), TradeListFilter.all);
      expect(TradeListFilter.fromStored('nope'), TradeListFilter.all);
    });
  });

  group('satsFigure', () {
    test('the fixed amount is exact', () {
      final f = satsFigure(
        status: OrderStatus.active,
        amountSats: 6900,
        fiat: 10,
        rate: 1,
        premium: 0,
      );
      expect(f.kind, SatsFigureKind.exact);
      expect(f.sats, 6900);
    });

    test('with no fixed amount it is estimated from the rate', () {
      final f = satsFigure(
        status: OrderStatus.pending,
        amountSats: null,
        fiat: 100,
        rate: 100000000,
        premium: 0,
      );
      expect(f.kind, SatsFigureKind.estimate);
      expect(f.sats, 100);
    });

    test('cancelled, or nothing to estimate from, shows none', () {
      expect(
        satsFigure(
          status: OrderStatus.canceled,
          amountSats: 6900,
          fiat: 10,
          rate: 1,
          premium: 0,
        ).kind,
        SatsFigureKind.none,
      );
      expect(
        satsFigure(
          status: OrderStatus.pending,
          amountSats: 0,
          fiat: 10,
          rate: null,
          premium: 0,
        ).kind,
        SatsFigureKind.none,
      );
    });
  });

  group('relativeTime', () {
    final now = DateTime(2026, 9, 12, 15, 30); // a Saturday

    test('minutes and hours in the past', () {
      expect(
        relativeTime(now.subtract(const Duration(seconds: 20)), now: now),
        const RelativeTime.now(),
      );
      expect(
        relativeTime(now.subtract(const Duration(minutes: 7)), now: now),
        const RelativeTime.minutes(7),
      );
      expect(
        relativeTime(now.subtract(const Duration(hours: 13)), now: now),
        const RelativeTime.hours(13),
      );
    });

    test('yesterday by the calendar, weekday within a week, then a date', () {
      final lateYesterday = DateTime(2026, 9, 11, 23, 0);
      // 16 h ago but on the previous calendar day: the hour count wins, as
      // `hace 16 h` is the more precise of the two.
      expect(
        relativeTime(lateYesterday, now: now),
        const RelativeTime.hours(16),
      );
      expect(
        relativeTime(DateTime(2026, 9, 11, 9, 0), now: now),
        const RelativeTime.yesterday(),
      );
      final monday = DateTime(2026, 9, 7, 10, 0);
      expect(relativeTime(monday, now: now), RelativeTime.weekday(monday));
      final old = DateTime(2026, 9, 1, 10, 0);
      expect(relativeTime(old, now: now), RelativeTime.date(old));
    });
  });

  group('relativeTime across a clock change', () {
    test('the previous calendar day is yesterday whatever the offset', () {
      // 29 March 2026 is a spring-forward day in much of Europe: in such a
      // zone the local midnights around it are 23 h apart.
      final now = DateTime(2026, 3, 30, 9, 0);
      final then = DateTime(2026, 3, 29, 8, 0);
      expect(relativeTime(then, now: now), const RelativeTime.yesterday());
    });
  });

  group('paymentMethodLabel', () {
    test('one method as is, several as the first plus a count', () {
      expect(paymentMethodLabel('Mercado Pago'), 'Mercado Pago');
      expect(
        paymentMethodLabel('Mercado Pago, Transferencia, Efectivo'),
        'Mercado Pago +2',
      );
      expect(paymentMethodLabel('  '), '');
    });
  });

  group('formatFiatAmount', () {
    test('whole, decimal and range amounts use the locale separators', () {
      expect(
        formatFiatAmount(amount: 1250, min: null, max: null, locale: 'es'),
        '1.250',
      );
      expect(
        formatFiatAmount(amount: 55.5, min: null, max: null, locale: 'en'),
        '55.50',
      );
      expect(
        formatFiatAmount(amount: null, min: 100, max: 500, locale: 'es'),
        '100 – 500',
      );
      expect(
        formatFiatAmount(amount: null, min: null, max: null, locale: 'es'),
        '—',
      );
      expect(formatSatsCount(6900, 'es'), '6.900');
    });
  });
}
