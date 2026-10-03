import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/cashu/providers/cashu_wallet_provider.dart';
import 'package:mostro/features/cashu/screens/cashu_wallet_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/input_source_action.dart';
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/provider_harness.dart';

/// Stands in for the Rust bridge. Every method the screen can reach is
/// overridden — an un-overridden one would call into Rust and hang the test
/// rather than fail it.
class _FakeController extends CashuWalletController {
  const _FakeController({
    this.connectError,
    this.createTokenError,
    this.token = 'cashuBtesttoken',
    this.received,
  });

  final Object? connectError;
  final Object? createTokenError;
  final String token;

  /// Every token handed to [receiveToken], when the test wants to see them.
  final List<String>? received;

  @override
  Future<CashuWalletStatus> connect() async {
    if (connectError != null) throw connectError!;
    return _status(connected: true, balance: 0);
  }

  @override
  Future<BigInt> receiveToken(String encoded) async {
    received?.add(encoded);
    return BigInt.zero;
  }

  @override
  Future<String> createToken(BigInt amountSats) async {
    if (createTokenError != null) throw createTokenError!;
    return token;
  }

  @override
  Future<void> sweepSpentProofs() async {}
}

/// `balance: null` models an unreadable balance, which the screen must not
/// render as zero.
CashuWalletStatus _status({required bool connected, required int? balance}) {
  return CashuWalletStatus(
    connected: connected,
    mintUrl: connected ? 'https://mint.example.com' : null,
    balanceSats: balance == null ? null : BigInt.from(balance),
    missingCapabilities: const [],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required CashuWalletStatus status,
  CashuWalletController controller = const _FakeController(),
  Locale locale = const Locale('en'),
}) async {
  final container = createContainer(
    overrides: [
      cashuWalletProvider.overrideWith((ref) => Stream.value(status)),
      cashuWalletControllerProvider.overrideWithValue(controller),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CashuWalletScreen(),
      ),
    ),
  );

  // One frame to build, one for the stream and the post-frame connect.
  await tester.pump();
  await tester.pump();
}

const _scannerMethods = MethodChannel(
  'dev.steenbakker.mobile_scanner/scanner/method',
);
const _scannerEvents = MethodChannel(
  'dev.steenbakker.mobile_scanner/scanner/event',
);
const _scannerOrientation = MethodChannel(
  'dev.steenbakker.mobile_scanner/scanner/deviceOrientation',
);

/// Answers mobile_scanner's channels the way Android does when the user
/// refuses the camera permission, so the scanner falls back to its paste form.
void _denyCameraPermission(WidgetTester tester) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_scannerMethods, (call) async {
    switch (call.method) {
      case 'state':
        return 2; // MobileScannerAuthorizationState.denied
      case 'request':
        return false;
    }
    return null;
  });
  messenger.setMockMethodCallHandler(_scannerEvents, (_) async => null);
  messenger.setMockMethodCallHandler(_scannerOrientation, (_) async => null);
  addTearDown(() {
    messenger.setMockMethodCallHandler(_scannerMethods, null);
    messenger.setMockMethodCallHandler(_scannerEvents, null);
    messenger.setMockMethodCallHandler(_scannerOrientation, null);
  });
}

/// Makes `Clipboard.getData` return [text].
void _mockClipboard(WidgetTester tester, String? text) {
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') {
      return text == null ? null : {'text': text};
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
}

Future<void> _openReceive(WidgetTester tester) async {
  await tester.tap(find.text('Receive'));
  await tester.pumpAndSettle();
}

/// The Receive button of the dialog, not the screen's own.
FilledButton _dialogReceive(WidgetTester tester) => tester.widget(
  find.descendant(
    of: find.byType(MostroDialog),
    matching: find.widgetWithText(FilledButton, 'Receive'),
  ),
);

Future<void> _tapDialogReceive(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(MostroDialog),
      matching: find.widgetWithText(FilledButton, 'Receive'),
    ),
  );
  await tester.pumpAndSettle();
}

InputSourceAction _source(WidgetTester tester, String label) =>
    tester.widget(find.widgetWithText(InputSourceAction, label));

void main() {
  group('CashuWalletScreen receive', () {
    testWidgets(
      'receive offers the token field with paste and scan',
      (tester) async {
        await _pump(tester, status: _status(connected: true, balance: 0));

        await _openReceive(tester);

        expect(find.text('Receive a token'), findsOneWidget);
        expect(find.text('CASHU TOKEN'), findsOneWidget);
        // Empty, with a dimmed hint that goes once something is pasted.
        expect(find.text('Paste a Cashu token'), findsOneWidget);
        expect(_source(tester, 'Paste').onTap, isNotNull);
        expect(_source(tester, 'Scan QR').onTap, isNotNull);
        expect(find.text('Not available on this device'), findsNothing);
        // Nothing to redeem yet.
        expect(_dialogReceive(tester).onPressed, isNull);
        // No camera opens on its own.
        expect(find.byType(MobileScanner), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'a typed token is received trimmed',
      (tester) async {
        final received = <String>[];
        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          controller: _FakeController(received: received),
        );

        await _openReceive(tester);
        await tester.enterText(find.byType(TextField), '  cashuBtyped  ');
        await tester.pump();
        expect(received, isEmpty);

        await _tapDialogReceive(tester);

        expect(received, ['cashuBtyped']);
        expect(find.text('Received 0 sats'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'Paste fills the field and waits for Receive',
      (tester) async {
        final received = <String>[];
        _mockClipboard(tester, '  cashuBclipboard  ');
        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          controller: _FakeController(received: received),
        );

        await _openReceive(tester);
        await tester.tap(find.text('Paste'));
        await tester.pumpAndSettle();

        // The user sees what they pasted before it goes to the mint.
        expect(find.text('cashuBclipboard'), findsOneWidget);
        expect(received, isEmpty);

        await _tapDialogReceive(tester);

        expect(received, ['cashuBclipboard']);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'an empty clipboard says so under the field',
      (tester) async {
        final received = <String>[];
        _mockClipboard(tester, '   ');
        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          controller: _FakeController(received: received),
        );

        await _openReceive(tester);
        await tester.tap(find.text('Paste'));
        await tester.pumpAndSettle();

        expect(find.text('Clipboard is empty'), findsOneWidget);
        expect(_dialogReceive(tester).onPressed, isNull);
        expect(received, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'a scanned token is received without coming back to the dialog',
      (tester) async {
        final received = <String>[];
        _denyCameraPermission(tester);
        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          controller: _FakeController(received: received),
        );

        await _openReceive(tester);
        await tester.tap(find.text('Scan QR'));
        await tester.pumpAndSettle();

        // The camera is refused, so the scanner offers its paste form; what
        // it returns travels the same way a decoded QR does.
        expect(find.text('Scan QR Code'), findsOneWidget);
        await tester.enterText(find.byType(TextField), ' cashuBscanned ');
        await tester.tap(find.text('Submit'));
        await tester.pumpAndSettle();

        expect(received, ['cashuBscanned']);
        expect(find.byType(MostroDialog), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'without a camera scanning is offered disabled, with the reason',
      (tester) async {
        final received = <String>[];
        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          controller: _FakeController(received: received),
        );

        await _openReceive(tester);

        // Same dialog as on a phone, so the user learns why there is no
        // camera instead of wondering where scanning went.
        expect(_source(tester, 'Scan QR').onTap, isNull);
        expect(find.text('Not available on this device'), findsOneWidget);
        expect(find.byType(MobileScanner), findsNothing);

        await tester.enterText(find.byType(TextField), 'cashuBdesktop');
        await tester.pump();
        await _tapDialogReceive(tester);

        expect(received, ['cashuBdesktop']);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'Cancel closes the dialog without reaching the wallet',
      (tester) async {
        final received = <String>[];
        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          controller: _FakeController(received: received),
        );

        await _openReceive(tester);
        await tester.enterText(find.byType(TextField), 'cashuBkept');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(MostroDialog), findsNothing);
        expect(received, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });

  group('CashuWalletScreen', () {
    testWidgets('a connected wallet shows its balance and mint', (
      tester,
    ) async {
      await _pump(tester, status: _status(connected: true, balance: 1234));

      expect(find.text('1,234 Satoshis'), findsOneWidget);
      expect(find.text('Mint: https://mint.example.com'), findsOneWidget);
      expect(find.text('Not connected to a mint'), findsNothing);
    });

    testWidgets('the balance groups digits the way the reader\'s locale does', (
      tester,
    ) async {
      // Arrange / Act — German groups with a period. A hard-coded comma turns
      // 1.234.567 sats into a number a German reader parses as 1.234567.
      await _pump(
        tester,
        status: _status(connected: true, balance: 1234567),
        locale: const Locale('de'),
      );

      // Assert
      expect(find.textContaining('1.234.567'), findsOneWidget);
      expect(find.textContaining('1,234,567'), findsNothing);
    });

    testWidgets('a balance beyond double precision is shown exactly', (
      tester,
    ) async {
      // Arrange — 2^53 + 1, the first integer a double cannot represent.
      // Formatting through `num` would render this rounded, and a bearer-money
      // balance must never be approximate.
      final status = CashuWalletStatus(
        connected: true,
        mintUrl: 'https://mint.example.com',
        balanceSats: BigInt.parse('9007199254740993'),
        missingCapabilities: const [],
      );

      // Act
      await _pump(tester, status: status);

      // Assert
      expect(find.textContaining('9,007,199,254,740,993'), findsOneWidget);
    });

    testWidgets('a wallet that could not bind says so', (tester) async {
      await _pump(tester, status: _status(connected: false, balance: 0));

      expect(find.text('Not connected to a mint'), findsOneWidget);
      expect(find.text('0 Satoshis'), findsOneWidget);
    });

    testWidgets('an unreadable balance renders as unknown, never as zero', (
      tester,
    ) async {
      // Ecash is bearer money: showing "0 Satoshis" for a failed read is the
      // one number this screen must never invent.
      await _pump(tester, status: _status(connected: true, balance: null));

      expect(find.text('—'), findsOneWidget);
      expect(find.text('0 Satoshis'), findsNothing);
    });

    testWidgets('sending is disabled while the balance is unknown', (
      tester,
    ) async {
      await _pump(tester, status: _status(connected: true, balance: null));

      final send = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Send'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(send.onPressed, isNull);
    });

    testWidgets('an exported token stays retrievable until dismissed', (
      tester,
    ) async {
      // The dialog is not dismissible and the token survives it: losing the
      // only copy of a token loses the funds.
      await _pump(tester, status: _status(connected: true, balance: 100));

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '10');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('cashuBtesttoken'), findsOneWidget);

      // Close the dialog — the reminder and a way back to the token remain.
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Show it again'), findsOneWidget);

      await tester.tap(find.text('Show it again'));
      await tester.pumpAndSettle();
      expect(find.text('cashuBtesttoken'), findsOneWidget);
    });

    testWidgets('an amount above the balance is refused in the dialog', (
      tester,
    ) async {
      await _pump(tester, status: _status(connected: true, balance: 100));

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '101');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('You only have 100 sats.'), findsOneWidget);
      // Still open: the user corrects the amount instead of starting over.
      expect(find.text('Confirm'), findsOneWidget);
      expect(find.text('cashuBtesttoken'), findsNothing);
    });

    testWidgets('neither a stray tap nor back closes the token dialog', (
      tester,
    ) async {
      await _pump(tester, status: _status(connected: true, balance: 100));

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '10');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // Outside the dialog, on the barrier.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('cashuBtesttoken'), findsOneWidget);

      // The system back gesture / button.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('cashuBtesttoken'), findsOneWidget);
    });

    testWidgets("I've sent it clears the exported-token reminder", (
      tester,
    ) async {
      await _pump(tester, status: _status(connected: true, balance: 100));

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '10');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Show it again'), findsOneWidget);

      await tester.tap(find.text("I've sent it"));
      await tester.pumpAndSettle();

      expect(find.text('Show it again'), findsNothing);
      expect(find.text("I've sent it"), findsNothing);
    });

    testWidgets(
      'a token too large for a QR is shown as text, never as an error',
      (tester) async {
        // A cdk token from many small proofs runs to tens of KB; a QR holds
        // ~2.9 KB. The dialog must degrade to the copyable text, not paint
        // qr_flutter's exception on the one dialog showing the user's money.
        final huge = 'cashuB${'A' * 4096}';
        await _pump(
          tester,
          status: _status(connected: true, balance: 100),
          controller: _FakeController(token: huge),
        );

        await tester.tap(find.text('Send'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '10');
        await tester.tap(find.text('Confirm'));
        await tester.pumpAndSettle();

        expect(
          find.text('This token is too large for a QR code. Copy it instead.'),
          findsOneWidget,
        );
        expect(find.text(huge), findsOneWidget);
        expect(find.textContaining('QrInputTooLong'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a send that could not confirm its proofs back says so', (
      tester,
    ) async {
      // "Try again" is the wrong advice here: the wallet must sync first.
      // The marker is one main grew after this screen was written, so it
      // pins that the mapper kept up.
      await _pump(
        tester,
        status: _status(connected: true, balance: 100),
        controller: const _FakeController(
          createTokenError: 'CashuSendUnresolved: revoke failed',
        ),
      );

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '10');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Sync with the mint before trying again'),
        findsOneWidget,
      );
      expect(find.textContaining('CashuSendUnresolved'), findsNothing);
      // Nothing was exported, so there is no token to keep retrievable.
      expect(find.text('Show it again'), findsNothing);
    });

    testWidgets('sending is disabled with an empty wallet', (tester) async {
      // Nothing to send: offering the button would only produce a mint-side
      // failure the user cannot act on.
      await _pump(tester, status: _status(connected: true, balance: 0));

      final send = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Send'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(send.onPressed, isNull);
    });

    testWidgets('sending is enabled once there are funds', (tester) async {
      await _pump(tester, status: _status(connected: true, balance: 10));

      final send = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Send'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(send.onPressed, isNotNull);
    });

    testWidgets('a Rust marker is shown as a localized message, never raw', (
      tester,
    ) async {
      // The screen connects on its first frame; a Lightning node answers with
      // the gate marker.
      await _pump(
        tester,
        status: _status(connected: false, balance: 0),
        controller: const _FakeController(
          connectError: 'CashuNotEnabled: whatever Rust appended',
        ),
      );
      await tester.pump();

      expect(
        find.text('This Mostro node does not settle trades with Cashu.'),
        findsOneWidget,
      );
      expect(find.textContaining('CashuNotEnabled'), findsNothing);
    });

    testWidgets('an unrecognised failure falls back to the generic message', (
      tester,
    ) async {
      // A marker this build does not know must not leak an internal string.
      await _pump(
        tester,
        status: _status(connected: false, balance: 0),
        controller: const _FakeController(
          connectError: 'SomeFutureMarker: internal detail',
        ),
      );
      await tester.pump();

      expect(
        find.text('Something went wrong with the wallet. Please try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('SomeFutureMarker'), findsNothing);
    });

    testWidgets(
      'a marker is found inside the exception the bridge really throws',
      (tester) async {
        // Arrange — the other marker tests pass a bare String, whose toString()
        // starts with the marker. Production never does: the bridge throws an
        // `AnyhowException`, and its toString() wraps the message, so the marker
        // sits after `AnyhowException(` rather than at the start.
        //
        // This pins that shape. Narrowing the lookup to a leading token — a
        // tempting "fix" for the tail-matching the mapper does — would send every
        // marker to the generic message in the app while the String-based tests
        // above stayed green.
        await _pump(
          tester,
          status: _status(connected: false, balance: 0),
          controller: _FakeController(
            connectError: AnyhowException(
              'CashuNotEnabled: whatever Rust appended',
            ),
          ),
        );
        await tester.pump();

        // Assert
        expect(
          find.text('This Mostro node does not settle trades with Cashu.'),
          findsOneWidget,
        );
        expect(find.textContaining('AnyhowException'), findsNothing);
      },
    );
  });
}
