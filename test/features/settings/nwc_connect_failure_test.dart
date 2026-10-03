import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/features/settings/nwc_connect_failure.dart';

void main() {
  group('classifyNwcConnectError', () {
    test('the web stub is unsupported, not a bad URI', () {
      expect(
        classifyNwcConnectError(
          'AnyhowException(Unsupported: NWC is not supported on web)',
        ),
        NwcConnectFailure.unsupported,
      );
    });

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
}
