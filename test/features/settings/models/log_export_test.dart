import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/models/log_export.dart';

void main() {
  group('sanitizeForShare', () {
    test('redacts a bearer token but keeps the header name', () {
      expect(
        sanitizeForShare('Authorization: Bearer abc.def.ghi'),
        'Authorization: Bearer [REDACTED_AUTH]',
      );
    });

    test('redacts key-value secrets with either separator', () {
      expect(sanitizeForShare('token=hunter2'), 'token=[REDACTED_SECRET]');
      expect(
        sanitizeForShare('api_key: hunter2'),
        'api_key: [REDACTED_SECRET]',
      );
    });

    test('redacts a quoted secret whole, spaces included', () {
      expect(
        sanitizeForShare('password="correct horse battery staple" next'),
        'password=[REDACTED_SECRET] next',
      );
      expect(
        sanitizeForShare("secret: 'two words'"),
        'secret: [REDACTED_SECRET]',
      );
    });

    test('redacts long hex runs and Bech32 keys', () {
      expect(
        sanitizeForShare('order ${'a' * 64} taken'),
        'order [REDACTED_KEY] taken',
      );
      expect(
        sanitizeForShare('from npub1qqqqqqqqqq'),
        'from [REDACTED_KEY]',
      );
    });

    test('leaves ordinary prose untouched', () {
      const line = 'relay wss://relay.damus.io connected in 240 ms';
      expect(sanitizeForShare(line), line);
    });
  });

  group('formatLogTimestamp', () {
    // Fixed instants so the test does not depend on when it runs; both are
    // converted to local time, which is what the screen shows.
    final today = DateTime(2026, 9, 12, 14, 32, 7);
    final yesterday = DateTime(2026, 9, 11, 9, 5, 0);

    int unix(DateTime dt) => dt.millisecondsSinceEpoch ~/ 1000;

    test('shows the time alone for an entry from today', () {
      expect(formatLogTimestamp(unix(today), now: today), '14:32:07');
    });

    test('prefixes the date for an older entry', () {
      expect(
        formatLogTimestamp(unix(yesterday), now: today),
        '2026-09-11 09:05:00',
      );
    });
  });
}
