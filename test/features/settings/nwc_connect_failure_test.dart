import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/nwc_connect_failure.dart';

void main() {
  group('classifyNwcConnectError', () {
    test('only the leading label counts, not the wallet\'s own message', () {
      expect(
        classifyNwcConnectError(
          'AnyhowException(ConnectionFailed: NWC get_info error: Unsupported: get_info [OTHER])',
        ),
        NwcConnectFailure.unreachable,
      );
    });

    test('a URI that does not parse is the one case that blames the URI', () {
      expect(
        classifyNwcConnectError(
          'AnyhowException(InvalidNwcUri: invalid NWC URI scheme)',
        ),
        NwcConnectFailure.invalidUri,
      );
    });

    test('a wallet that answers with an error rejected the connection', () {
      expect(
        classifyNwcConnectError(
          'AnyhowException(WalletRejected: no wallet connected [UNAUTHORIZED])',
        ),
        NwcConnectFailure.rejected,
      );
    });

    test('a wallet without get_info is a wallet problem, not a retry', () {
      expect(
        classifyNwcConnectError(
          'AnyhowException(WalletUnsupported: get_info [NOT_IMPLEMENTED])',
        ),
        NwcConnectFailure.walletUnsupported,
      );
    });

    test('any other wallet answer is a wallet error, worth a retry', () {
      expect(
        classifyNwcConnectError(
          'AnyhowException(WalletError: busy [RATE_LIMITED])',
        ),
        NwcConnectFailure.walletError,
      );
    });

    test('a wallet that does not answer is unreachable', () {
      expect(
        classifyNwcConnectError(
          'AnyhowException(ConnectionFailed: NWC timeout: no response received from wallet within 30s)',
        ),
        NwcConnectFailure.unreachable,
      );
    });

    test('an unlabelled error never blames the URI', () {
      expect(
        classifyNwcConnectError(StateError('bridge gone')),
        NwcConnectFailure.unreachable,
      );
    });
  });

  group('relaysBlockedByPage', () {
    final https = Uri.parse('https://mostro.network/app/');
    const pk =
        'b889ff5b1513b641e2a139f661a661364979c5beee91842f8f0ef42ab558e9d4';
    String uri(List<String> relays) =>
        'nostr+walletconnect://$pk?${relays.map((r) => 'relay=${Uri.encodeComponent(r)}').join('&')}&secret=00';

    test('only ws:// relays on an https page are blocked', () {
      expect(
        relaysBlockedByPage(uri(['ws://umbrel.local:4848']), https),
        isTrue,
      );
    });

    test('one wss:// relay is enough to try', () {
      expect(
        relaysBlockedByPage(
          uri(['ws://umbrel.local:4848', 'wss://relay.getalby.com/v1']),
          https,
        ),
        isFalse,
      );
    });

    test('the machine itself and a plain http page are not blocked', () {
      expect(relaysBlockedByPage(uri(['ws://localhost:7777']), https), isFalse);
      expect(
        relaysBlockedByPage(
          uri(['ws://umbrel.local:4848']),
          Uri.parse('http://127.0.0.1:8765/app/'),
        ),
        isFalse,
      );
    });
  });
}
