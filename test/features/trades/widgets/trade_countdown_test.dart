import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/trades/widgets/trade_countdown.dart';

/// The handoff's clock rules: h:mm from an hour up, mm:ss below, colour by
/// urgency, and a repaint cadence that follows the displayed precision.
void main() {
  group('formatTradeCountdown', () {
    test('an hour or more reads h:mm, never with seconds', () {
      expect(
        formatTradeCountdown(
          const Duration(hours: 23, minutes: 57, seconds: 48),
        ),
        '23:57',
      );
      expect(formatTradeCountdown(const Duration(hours: 1)), '1:00');
      expect(
        formatTradeCountdown(const Duration(hours: 1, minutes: 5)),
        '1:05',
      );
    });

    test('under an hour reads mm:ss', () {
      expect(
        formatTradeCountdown(const Duration(minutes: 12, seconds: 40)),
        '12:40',
      );
      expect(
        formatTradeCountdown(const Duration(minutes: 59, seconds: 59)),
        '59:59',
      );
      expect(formatTradeCountdown(const Duration(seconds: 7)), '00:07');
    });

    test('zero and negative read 00:00', () {
      expect(formatTradeCountdown(Duration.zero), '00:00');
      expect(formatTradeCountdown(const Duration(seconds: -5)), '00:00');
    });
  });

  group('countdownTier', () {
    test(
      'calm from an hour, under-hour below it, urgent under five minutes',
      () {
        expect(countdownTier(const Duration(hours: 1)), CountdownTier.calm);
        expect(
          countdownTier(const Duration(minutes: 59, seconds: 59)),
          CountdownTier.underHour,
        );
        expect(
          countdownTier(const Duration(minutes: 5)),
          CountdownTier.underHour,
        );
        expect(
          countdownTier(const Duration(minutes: 4, seconds: 59)),
          CountdownTier.urgent,
        );
      },
    );
  });

  group('nextCountdownTick', () {
    test('ticks every second under an hour', () {
      expect(
        nextCountdownTick(const Duration(minutes: 30)),
        const Duration(seconds: 1),
      );
    });

    test('ticks on the minute from an hour up', () {
      expect(
        nextCountdownTick(const Duration(hours: 2, seconds: 17)),
        const Duration(seconds: 17),
      );
      expect(
        nextCountdownTick(const Duration(hours: 2)),
        const Duration(seconds: 60),
      );
    });

    test('lands exactly on the switch to mm:ss', () {
      const remaining = Duration(hours: 1, seconds: 3);
      expect(
        formatTradeCountdown(remaining - nextCountdownTick(remaining)),
        '1:00',
      );
      // At exactly one hour the clock is about to switch to mm:ss, so the
      // next repaint is one second away, not a minute.
      expect(
        nextCountdownTick(const Duration(hours: 1)),
        const Duration(seconds: 1),
      );
      expect(
        formatTradeCountdown(
          const Duration(hours: 1) -
              nextCountdownTick(const Duration(hours: 1)),
        ),
        '59:59',
      );
    });
  });
}
