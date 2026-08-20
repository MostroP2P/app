import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/utils/waiting_countdown.dart';
import 'package:mostro/src/rust/api/types.dart';

void main() {
  group('waitingCountdownDeadline', () {
    test('pending counts to the pending expiry, window from expiration_seconds',
        () {
      final expiresAt = DateTime.fromMillisecondsSinceEpoch(2000 * 1000);
      final r = waitingCountdownDeadline(
        status: OrderStatus.pending,
        pendingExpiresAt: expiresAt,
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

    test('waiting state prefers the persisted timeout_at', () {
      for (final status in [
        OrderStatus.waitingBuyerInvoice,
        OrderStatus.waitingPayment,
      ]) {
        final r = waitingCountdownDeadline(
          status: status,
          timeoutAtEpoch: 5000,
          waitingSinceEpoch: 1000,
          expirationSeconds: 900,
        );
        expect(r, isNotNull, reason: '$status');
        expect(r!.deadlineEpochSeconds, 5000, reason: '$status');
        expect(r.totalWindowSeconds, 900, reason: '$status');
      }
    });

    test('waiting falls back to startedAt + window when timeout_at is absent',
        () {
      final r = waitingCountdownDeadline(
        status: OrderStatus.waitingPayment,
        timeoutAtEpoch: null,
        waitingSinceEpoch: 1000,
        expirationSeconds: 900,
      );
      expect(r, isNotNull);
      expect(r!.deadlineEpochSeconds, 1900); // 1000 + 900, not now-based
      expect(r.totalWindowSeconds, 900);
    });

    test('waiting fallback uses the 900 s default when the node omits '
        'expiration_seconds', () {
      final r = waitingCountdownDeadline(
        status: OrderStatus.waitingPayment,
        timeoutAtEpoch: null,
        waitingSinceEpoch: 1000,
        expirationSeconds: null,
      );
      expect(r, isNotNull);
      expect(r!.totalWindowSeconds, kWaitingCountdownFallbackSeconds);
      expect(r.deadlineEpochSeconds, 1000 + kWaitingCountdownFallbackSeconds);
    });

    test('waiting with neither timeout_at nor a start anchor yields no '
        'countdown', () {
      final r = waitingCountdownDeadline(
        status: OrderStatus.waitingBuyerInvoice,
        timeoutAtEpoch: null,
        waitingSinceEpoch: null,
        expirationSeconds: 900,
      );
      expect(r, isNull);
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
          waitingSinceEpoch: 1000,
          expirationSeconds: 900,
        );
        expect(r, isNull, reason: '$status');
      }
    });

    test('the fallback deadline is stable across repeated resolutions '
        '(#270 regression: no now-drift)', () {
      CountdownDeadline? resolve() => waitingCountdownDeadline(
            status: OrderStatus.waitingPayment,
            timeoutAtEpoch: null,
            waitingSinceEpoch: 1000,
            expirationSeconds: 900,
          );
      final first = resolve();
      final second = resolve();
      final third = resolve();
      expect(first!.deadlineEpochSeconds, 1900);
      expect(second!.deadlineEpochSeconds, first.deadlineEpochSeconds);
      expect(third!.deadlineEpochSeconds, first.deadlineEpochSeconds);
    });
  });
}
