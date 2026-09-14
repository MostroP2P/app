import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/models/settings_rows.dart';
import 'package:mostro/src/rust/api/types.dart'
    show RelayInfo, RelaySource, RelayStatus;

RelayInfo _relay({
  String url = 'wss://relay.example.com',
  bool isActive = true,
  RelayStatus status = RelayStatus.connected,
}) => RelayInfo(
  url: url,
  isActive: isActive,
  isDefault: true,
  source: RelaySource.default_,
  isBlacklisted: false,
  status: status,
);

void main() {
  group('relayHealth', () {
    test('reports connected only for an enabled, connected relay', () {
      expect(relayHealth(_relay()), RelayHealth.connected);
    });

    test('reports offline for a relay the user switched off', () {
      // Even while the pool still holds the connection: the row has to read
      // as off, or the toggle and the dot contradict each other.
      expect(
        relayHealth(_relay(isActive: false)),
        RelayHealth.offline,
      );
    });

    test('reports offline while connecting, disconnected or errored', () {
      for (final status in [
        RelayStatus.connecting,
        RelayStatus.disconnected,
        RelayStatus.error,
      ]) {
        expect(
          relayHealth(_relay(status: status)),
          RelayHealth.offline,
          reason: '$status',
        );
      }
    });
  });

  group('relayDisplayUrl', () {
    test('drops the scheme, which is the same on every row', () {
      expect(relayDisplayUrl('wss://relay.damus.io'), 'relay.damus.io');
      expect(relayDisplayUrl('ws://127.0.0.1:7000'), '127.0.0.1:7000');
    });

    test('leaves a URL with no scheme alone', () {
      expect(relayDisplayUrl('relay.damus.io'), 'relay.damus.io');
    });
  });

  group('RelayTally', () {
    test('counts only the relays the user enabled', () {
      final tally = RelayTally.of([
        _relay(url: 'wss://a'),
        _relay(url: 'wss://b', status: RelayStatus.error),
        // Switched off on purpose: not a relay that failed, so it is out of
        // the denominator too.
        _relay(url: 'wss://c', isActive: false),
      ]);

      expect(tally.connected, 1);
      expect(tally.total, 2);
    });

    test('is lime only when every enabled relay is connected', () {
      final all = RelayTally.of([_relay(url: 'wss://a'), _relay(url: 'wss://b')]);
      expect(all.allConnected, isTrue);
      expect(all.tone, SettingsValueTone.good);

      final some = RelayTally.of([
        _relay(url: 'wss://a'),
        _relay(url: 'wss://b', status: RelayStatus.disconnected),
      ]);
      expect(some.allConnected, isFalse);
      expect(some.tone, SettingsValueTone.warn);
    });

    test('an empty list is not "all connected"', () {
      final none = RelayTally.of(const []);
      expect(none.allConnected, isFalse);
      expect(none.tone, SettingsValueTone.warn);
    });

    test('flags fewer than two connected as critical', () {
      expect(RelayTally.of([_relay(url: 'wss://a')]).isCritical, isTrue);
      expect(
        RelayTally.of([_relay(url: 'wss://a'), _relay(url: 'wss://b')])
            .isCritical,
        isFalse,
      );
    });
  });

  group('logSubsystem', () {
    test('buckets a module path and a bridge tag alike', () {
      expect(logSubsystem('mostro::nostr::relays'), LogSubsystem.relays);
      expect(logSubsystem('relay'), LogSubsystem.relays);
      expect(logSubsystem('daemon-msg'), LogSubsystem.orders);
      expect(logSubsystem('mostro::mostro::orders'), LogSubsystem.orders);
      expect(logSubsystem('nwc'), LogSubsystem.payments);
      expect(logSubsystem('mostro::escrow::cashu'), LogSubsystem.payments);
    });

    test('matches case-insensitively', () {
      expect(logSubsystem('NWC'), LogSubsystem.payments);
    });

    test('returns null for a tag no chip covers', () {
      // Still reachable under `Todos` — an unmatched tag must not vanish.
      expect(logSubsystem('blog_probe'), isNull);
    });
  });
}
