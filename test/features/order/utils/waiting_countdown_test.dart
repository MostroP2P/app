import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/utils/waiting_countdown.dart';
import 'package:mostro/src/rust/api/types.dart';

void main() {
  group('waitingCountdownDeadline', () {
    test('pending counts to the pending expiry; ring spans creation to expiry',
        () {
      // 24 h window: created at epoch 1000, expires at 1000 + 86400.
      const createdAt = 1000;
      final expiresAt =
          DateTime.fromMillisecondsSinceEpoch((createdAt + 86400) * 1000);
      final r = waitingCountdownDeadline(
        status: OrderStatus.pending,
        pendingExpiresAt: expiresAt,
        pendingCreatedAtEpoch: createdAt,
        expirationSeconds: 900,
      );
      expect(r, isNotNull);
      expect(r!.deadlineEpochSeconds, createdAt + 86400);
      // The ring spans the whole pending window, not the waiting window (#306).
      expect(r.totalWindowSeconds, 86400);
    });

    test('pending ring falls back to the window when no createdAt is given', () {
      final r = waitingCountdownDeadline(
        status: OrderStatus.pending,
        pendingExpiresAt: DateTime.fromMillisecondsSinceEpoch(2000 * 1000),
        pendingCreatedAtEpoch: null,
        expirationSeconds: 900,
      );
      expect(r, isNotNull);
      expect(r!.deadlineEpochSeconds, 2000);
      expect(r.totalWindowSeconds, 900);
    });

    test('pending with no expiry yields no countdown', () {
      final r = waitingCountdownDeadline(
        status: OrderStatus.pending,
        pendingExpiresAt: null,
        expirationSeconds: 900,
      );
      expect(r, isNull);
    });

    test('waiting state counts to the persisted timeout_at', () {
      for (final status in [
        OrderStatus.waitingBuyerInvoice,
        OrderStatus.waitingPayment,
      ]) {
        final r = waitingCountdownDeadline(
          status: status,
          timeoutAtEpoch: 5000,
          expirationSeconds: 900,
        );
        expect(r, isNotNull, reason: '$status');
        expect(r!.deadlineEpochSeconds, 5000, reason: '$status');
        expect(r.totalWindowSeconds, 900, reason: '$status');
      }
    });

    test(
        'a waiting order with no timeout_at yields no countdown, not a past '
        'deadline (#306: no startedAt fallback)', () {
      // startedAt is order-creation time; for a maker whose order sat in the
      // book before being taken, anchoring on it produced a deadline already in
      // the past — a countdown born at zero. With no timeout_at the helper now
      // returns null rather than a bogus deadline.
      for (final status in [
        OrderStatus.waitingBuyerInvoice,
        OrderStatus.waitingPayment,
      ]) {
        final r = waitingCountdownDeadline(
          status: status,
          timeoutAtEpoch: null,
          expirationSeconds: 900,
        );
        expect(r, isNull, reason: '$status');
      }
    });

    test('non-countdown states produce no countdown', () {
      for (final status in [
        OrderStatus.active,
        OrderStatus.fiatSent,
        OrderStatus.success,
        OrderStatus.canceled,
        null,
      ]) {
        final r = waitingCountdownDeadline(
          status: status,
          pendingExpiresAt: DateTime.fromMillisecondsSinceEpoch(2000 * 1000),
          timeoutAtEpoch: 5000,
          expirationSeconds: 900,
        );
        expect(r, isNull, reason: '$status');
      }
    });

    test('the resolved deadline is stable across repeated resolutions '
        '(#270 regression: no now-drift)', () {
      // The helper is pure: given the same inputs it returns the same deadline,
      // so the ticking per-second rebuild never slides the target forward.
      CountdownDeadline? resolve() => waitingCountdownDeadline(
            status: OrderStatus.waitingPayment,
            timeoutAtEpoch: 5000,
            expirationSeconds: 900,
          );
      final first = resolve();
      final second = resolve();
      final third = resolve();
      expect(first!.deadlineEpochSeconds, 5000);
      expect(second!.deadlineEpochSeconds, first.deadlineEpochSeconds);
      expect(third!.deadlineEpochSeconds, first.deadlineEpochSeconds);
    });
  });
}
