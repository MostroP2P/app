import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/shared/utils/countdown.dart';

void main() {
  group('formatCountdown', () {
    String hours(String h, String m) => '$h Std. $m';

    test('reads mm:ss under an hour', () {
      expect(
        formatCountdown(const Duration(minutes: 14, seconds: 38), hours: hours),
        '14:38',
      );
      expect(
        formatCountdown(const Duration(seconds: 5), hours: hours),
        '00:05',
      );
    });

    test('reads the localized h mm from an hour up', () {
      expect(
        formatCountdown(const Duration(hours: 1, minutes: 5), hours: hours),
        '1 Std. 05',
      );
      expect(
        formatCountdown(const Duration(hours: 1), hours: hours),
        '1 Std. 00',
      );
    });

    test('never goes below zero', () {
      expect(
        formatCountdown(const Duration(seconds: -3), hours: hours),
        '00:00',
      );
    });
  });

  group('countdownTick', () {
    test('ticks every second up to an hour', () {
      expect(
        countdownTick(const Duration(minutes: 10)),
        const Duration(seconds: 1),
      );
      expect(
        countdownTick(const Duration(hours: 1)),
        const Duration(seconds: 1),
      );
    });

    test('lands on the next displayed value above an hour', () {
      // 2:00:15 still reads 2 h 00 at +15 s; it turns 1 h 59 at +16 s.
      expect(
        countdownTick(const Duration(hours: 2, seconds: 15)),
        const Duration(seconds: 16),
      );
      // 2:00:00 turns 1 h 59 one second later, not a minute later.
      expect(
        countdownTick(const Duration(hours: 2)),
        const Duration(seconds: 1),
      );
    });
  });

  group('countdownTone', () {
    test('is calm from an hour up', () {
      expect(countdownTone(const Duration(hours: 1)), CountdownTone.calm);
    });

    test('warns under an hour', () {
      expect(
        countdownTone(const Duration(minutes: 59, seconds: 59)),
        CountdownTone.warning,
      );
      expect(countdownTone(const Duration(minutes: 5)), CountdownTone.warning);
    });

    test('turns urgent under five minutes', () {
      expect(
        countdownTone(const Duration(minutes: 4, seconds: 59)),
        CountdownTone.urgent,
      );
      expect(countdownTone(Duration.zero), CountdownTone.urgent);
    });

    test('in a window of 15 minutes or less, turns urgent under one', () {
      const window = Duration(minutes: 15);
      expect(
        countdownTone(const Duration(minutes: 4), window: window),
        CountdownTone.warning,
      );
      expect(
        countdownTone(const Duration(seconds: 60), window: window),
        CountdownTone.warning,
      );
      expect(
        countdownTone(const Duration(seconds: 59), window: window),
        CountdownTone.urgent,
      );
    });

    test('a longer window keeps the five-minute threshold', () {
      expect(
        countdownTone(
          const Duration(minutes: 4),
          window: const Duration(minutes: 16),
        ),
        CountdownTone.urgent,
      );
    });
  });
}
