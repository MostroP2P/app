import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/features/settings/screens/nwc_wallet_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';
import 'package:mostro/src/rust/frb_generated.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../support/provider_harness.dart';

class _NoWallet extends NwcNotifier {}

/// The core's `connect_wallet`, failing with whatever the test says.
class _FailingApi implements RustLibApi {
  String message = '';

  @override
  Future<NwcWalletInfo> crateApiNwcConnectWallet({required String nwcUri}) =>
      Future.error(AnyhowException(message));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _uri =
    'nostr+walletconnect://'
    '0000000000000000000000000000000000000000000000000000000000000004'
    '?relay=ws://localhost:9'
    '&secret=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  final api = _FailingApi();
  setUpAll(() => RustLib.initMock(api: api));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // What the user reads for each label the core puts in front of the error.
  final cases = <(String, String Function(AppLocalizations))>[
    ('InvalidNwcUri: invalid URI', (l) => l.nwcConnectionFailedMessage),
    (
      'Unsupported: NWC is not supported on web',
      (l) => l.nwcUnsupportedOnWebMessage,
    ),
    (
      'WalletRejected: no wallet [UNAUTHORIZED]',
      (l) => l.nwcWalletRejectedMessage,
    ),
    (
      'WalletUnsupported: get_info [NOT_IMPLEMENTED]',
      (l) => l.nwcWalletUnsupportedMessage,
    ),
    ('WalletError: busy [RATE_LIMITED]', (l) => l.nwcWalletErrorMessage),
    (
      'ConnectionFailed: NWC timeout: no response',
      (l) => l.nwcWalletUnreachableMessage,
    ),
  ];

  for (final (error, expected) in cases) {
    testWidgets('"$error" shows its own message', (tester) async {
      api.message = error;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: createContainer(
            overrides: [nwcProvider.overrideWith((ref) => _NoWallet())],
          ),
          child: MaterialApp(
            theme: buildLightTheme(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const NwcWalletScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NwcWalletScreen)),
      );

      await tester.enterText(find.byType(TextField), _uri);
      await tester.pump();
      await tester.tap(find.text(l10n.connectButtonLabel));
      await tester.pumpAndSettle();

      expect(find.text(expected(l10n)), findsOneWidget);
    });
  }
}
