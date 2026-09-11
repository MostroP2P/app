import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/order/models/order_detail_rules.dart';

void main() {
  group('shortOrderId', () {
    test('keeps the head and the tail of a long id', () {
      // Arrange
      const id = '09150348-1a2b-4c3d-8e9f-0a1b2c3d99b5';

      // Act
      final short = shortOrderId(id);

      // Assert — the tail is what people compare when verifying.
      expect(short, '09150348…99b5');
    });

    test('leaves a short id untouched', () {
      expect(shortOrderId('abc123'), 'abc123');
      expect(shortOrderId('0915034899b5'), '0915034899b5');
    });
  });

  group('formatRemaining', () {
    test('shows h:mm above an hour, never seconds', () {
      expect(
        formatRemaining(const Duration(hours: 23, minutes: 12, seconds: 40)),
        '23:12',
      );
      expect(formatRemaining(const Duration(hours: 1)), '1:00');
    });

    test('shows mm:ss under an hour', () {
      expect(
        formatRemaining(const Duration(minutes: 12, seconds: 40)),
        '12:40',
      );
      expect(formatRemaining(const Duration(seconds: 5)), '00:05');
    });

    test('clamps a negative duration to zero', () {
      expect(formatRemaining(const Duration(seconds: -3)), '00:00');
    });
  });

  group('countdownTick', () {
    test('ticks every minute above an hour and every second under it', () {
      expect(
        countdownTick(const Duration(hours: 2)),
        const Duration(minutes: 1),
      );
      expect(
        countdownTick(const Duration(minutes: 59, seconds: 59)),
        const Duration(seconds: 1),
      );
    });
  });

  group('countdownTone', () {
    test('is calm above an hour, warning under it, urgent under five', () {
      expect(
        countdownTone(const Duration(hours: 1, seconds: 1)),
        CountdownTone.calm,
      );
      expect(countdownTone(const Duration(minutes: 30)), CountdownTone.warning);
      expect(
        countdownTone(const Duration(minutes: 4, seconds: 59)),
        CountdownTone.urgent,
      );
      expect(countdownTone(Duration.zero), CountdownTone.urgent);
    });
  });

  group('orderLifeProgress', () {
    final created = DateTime.utc(2026, 1, 1, 12);
    final expires = created.add(const Duration(hours: 24));

    test('is the elapsed share of the order lifetime', () {
      expect(
        orderLifeProgress(
          createdAt: created,
          expiresAt: expires,
          now: created.add(const Duration(hours: 6)),
        ),
        closeTo(0.25, 1e-9),
      );
    });

    test('clamps to [0, 1] and is 0 without an expiry', () {
      expect(
        orderLifeProgress(
          createdAt: created,
          expiresAt: expires,
          now: expires.add(const Duration(hours: 1)),
        ),
        1,
      );
      expect(
        orderLifeProgress(createdAt: created, expiresAt: null, now: created),
        0,
      );
    });
  });

  group('estimateSats', () {
    test('divides fiat by the premium-adjusted price', () {
      // 1 000 ARS at 100 000 000 ARS/BTC, no premium → 1 000 sats.
      expect(estimateSats(fiat: 1000, rate: 100000000, premium: 0), 1000);
      // +25 % premium → 800 sats.
      expect(estimateSats(fiat: 1000, rate: 100000000, premium: 25), 800);
    });

    test('rounds to whole sats', () {
      expect(estimateSats(fiat: 1000, rate: 118765432, premium: 0), 842);
    });

    test('is null without a usable rate', () {
      expect(estimateSats(fiat: 1000, rate: null, premium: 0), isNull);
      expect(estimateSats(fiat: 1000, rate: 0, premium: 0), isNull);
      expect(estimateSats(fiat: 1000, rate: 100, premium: -100), isNull);
    });
  });

  group('paymentMethodsSummary', () {
    test('joins up to two methods', () {
      final summary = paymentMethodsSummary('Mercado Pago, Transferencia');
      expect(summary.shown, ['Mercado Pago', 'Transferencia']);
      expect(summary.hidden, 0);
    });

    test('keeps one and counts the rest beyond two', () {
      final summary = paymentMethodsSummary('Mercado Pago, Brubank, Uala');
      expect(summary.shown, ['Mercado Pago']);
      expect(summary.hidden, 2);
      expect(summary.all, ['Mercado Pago', 'Brubank', 'Uala']);
    });

    test('drops blanks', () {
      expect(paymentMethodsSummary(' Cash ,, ').shown, ['Cash']);
    });
  });

  group('takerPremiumFavour', () {
    test('favours the taker buying below market or selling above it', () {
      expect(takerPremiumFavour(kind: 'sell', premium: -2), PremiumSide.good);
      expect(takerPremiumFavour(kind: 'buy', premium: 2), PremiumSide.good);
    });

    test('is against the taker buying above market or selling below it', () {
      expect(takerPremiumFavour(kind: 'sell', premium: 2), PremiumSide.bad);
      expect(takerPremiumFavour(kind: 'buy', premium: -2), PremiumSide.bad);
    });

    test('is neutral at zero', () {
      expect(takerPremiumFavour(kind: 'sell', premium: 0), PremiumSide.zero);
    });
  });
}
