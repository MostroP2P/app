import 'dart:async';

import 'package:clock/clock.dart';
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
import 'package:mostro/shared/widgets/mostro_modal.dart';
import 'package:mostro/shared/widgets/mostro_qr.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/provider_harness.dart';
import '../../../support/qr_finders.dart';

/// Stands in for the Rust bridge. Every method the screen can reach is
/// overridden — an un-overridden one would call into Rust and hang the test
/// rather than fail it.
class _FakeController extends CashuWalletController {
  _FakeController({
    this.connectError,
    this.createTokenError,
    this.token = 'cashuBtesttoken',
    List<CashuMeltQuote>? quotes,
    List<Object>? meltOutcomes,
    this.mintQuoteError,
    this.invoiceLifetime,
    this.mintInvoice = _invoice,
    List<Object>? claimOutcomes,
  }) : quotes = quotes ?? [],
       meltOutcomes = meltOutcomes ?? [],
       claimOutcomes = claimOutcomes ?? [];

  final Object? connectError;
  final Object? createTokenError;
  final String token;

  /// The quotes [meltQuote] answers with, in order.
  final List<CashuMeltQuote> quotes;

  /// What each [melt] does, in order: a [CashuMeltResult] is returned, a
  /// `Future<CashuMeltResult>` is awaited (a payment still running), anything
  /// else is thrown.
  final List<Object> meltOutcomes;

  /// Every invoice handed to [meltQuote].
  final List<String> quoted = [];

  /// What [mintQuote] throws, when set.
  final Object? mintQuoteError;

  /// How long the invoice [mintQuote] gives can be paid; none when null.
  final Duration? invoiceLifetime;

  /// The invoice [mintQuote] gives.
  final String mintInvoice;

  /// What each [claimMintQuote] does, in order: a [CashuMintQuoteState] is
  /// returned, anything else is thrown. Once used up, it keeps waiting.
  final List<Object> claimOutcomes;

  /// Every amount handed to [mintQuote].
  final List<BigInt> mintQuoted = [];

  /// Every quote id handed to [claimMintQuote].
  final List<String> claims = [];

  /// Every (quote id, confirmed total) handed to [melt].
  final List<(String, BigInt)> melts = [];

  /// Every token handed to [receiveToken].
  final List<String> received = [];

  /// Every mint a connect asked for, `null` for "the usual one".
  final List<String?> connects = [];

  @override
  Future<CashuWalletStatus> connect({String? mintUrl}) async {
    connects.add(mintUrl);
    // The open-time connect fails as configured; a mint the user chose binds.
    if (mintUrl == null && connectError != null) throw connectError!;
    return _status(connected: true, balance: 0);
  }

  @override
  Future<BigInt> receiveToken(String encoded) async {
    received.add(encoded);
    return BigInt.zero;
  }

  @override
  Future<String> createToken(BigInt amountSats) async {
    if (createTokenError != null) throw createTokenError!;
    return token;
  }

  @override
  Future<void> sweepSpentProofs() async {}

  @override
  Future<CashuMeltQuote> meltQuote(String invoice) async {
    quoted.add(invoice);
    return quotes.removeAt(0);
  }

  @override
  Future<CashuMintQuote> mintQuote(BigInt amountSats) async {
    mintQuoted.add(amountSats);
    if (mintQuoteError != null) throw mintQuoteError!;
    return CashuMintQuote(
      quoteId: 'mq1',
      invoice: mintInvoice,
      amountSats: amountSats,
      expiresAt: switch (invoiceLifetime) {
        final lifetime? => BigInt.from(
          clock.now().add(lifetime).millisecondsSinceEpoch ~/ 1000,
        ),
        null => BigInt.zero,
      },
    );
  }

  @override
  Future<CashuMintQuoteState> claimMintQuote(String quoteId) async {
    claims.add(quoteId);
    if (claimOutcomes.isEmpty) return const CashuMintQuoteState.waiting();
    final outcome = claimOutcomes.removeAt(0);
    if (outcome is CashuMintQuoteState) return outcome;
    throw outcome;
  }

  @override
  Future<CashuMeltResult> melt(String quoteId, BigInt maxTotalSats) async {
    melts.add((quoteId, maxTotalSats));
    final outcome = meltOutcomes.removeAt(0);
    if (outcome is CashuMeltResult) return outcome;
    if (outcome is Future<CashuMeltResult>) return outcome;
    throw outcome;
  }
}

/// A quote for a 100 sat invoice: [reserve] in routing reserve, [input] in
/// input fees, and their sum on top as the most the payment can take.
CashuMeltQuote _quote(String id, {int reserve = 2, int input = 1}) =>
    CashuMeltQuote(
      quoteId: id,
      amountSats: BigInt.from(100),
      feeReserveSats: BigInt.from(reserve),
      inputFeeSats: BigInt.from(input),
      maxTotalSats: BigInt.from(100 + reserve + input),
    );

const _invoice = 'lnbc1000n1pinvoice';

/// `balance: null` models an unreadable balance, which the screen must not
/// render as zero.
CashuWalletStatus _status({
  required bool connected,
  required int? balance,
  bool canSendLightning = false,
  bool canReceiveLightning = false,
  int receiving = 0,
}) {
  return CashuWalletStatus(
    connected: connected,
    mintUrl: connected ? 'https://mint.example.com' : null,
    balanceSats: balance == null ? null : BigInt.from(balance),
    missingCapabilities: const [],
    canSendLightning: canSendLightning,
    canReceiveLightning: canReceiveLightning,
    receivingSats: BigInt.from(receiving),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required CashuWalletStatus status,
  CashuWalletController? controller,
  Locale locale = const Locale('en'),
}) async {
  final container = createContainer(overrides: [
    cashuWalletProvider.overrideWith((ref) => Stream.value(status)),
    cashuWalletControllerProvider.overrideWithValue(
      controller ?? _FakeController(),
    ),
  ]);

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
Finder _dialogReceiveFinder() => find.descendant(
  of: find.byType(MostroDialog),
  matching: find.widgetWithText(FilledButton, 'Receive'),
);

FilledButton _dialogReceive(WidgetTester tester) =>
    tester.widget(_dialogReceiveFinder());

Future<void> _tapDialogReceive(WidgetTester tester) async {
  await tester.tap(_dialogReceiveFinder());
  await tester.pumpAndSettle();
}

/// One of the dialog's links (Paste, Scan QR).
TextButton _link(WidgetTester tester, String label) => tester.widget(
  find.descendant(
    of: find.byType(MostroDialog),
    matching: find.widgetWithText(TextButton, label),
  ),
);

void main() {
  group('CashuWalletScreen receive', () {
    testWidgets(
      'receive offers the token field, with Paste and Scan QR as links',
      (tester) async {
        await _pump(tester, status: _status(connected: true, balance: 0));

        await _openReceive(tester);

        expect(find.text('Receive a token'), findsOneWidget);
        expect(find.text('CASHU TOKEN'), findsOneWidget);
        // Empty, with a dimmed hint that goes once something is pasted.
        expect(find.text('Paste a Cashu token'), findsOneWidget);
        expect(_link(tester, 'Paste').onPressed, isNotNull);
        expect(_link(tester, 'Scan QR').onPressed, isNotNull);
        expect(find.byTooltip('Not available on this device'), findsNothing);
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
        final controller = _FakeController();
        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          controller: controller,
        );

        await _openReceive(tester);
        await tester.enterText(find.byType(TextField), '  cashuBtyped  ');
        await tester.pump();
        expect(controller.received, isEmpty);

        await _tapDialogReceive(tester);

        expect(controller.received, ['cashuBtyped']);
        expect(find.text('Received 0 sats'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    // On desktop the field has the focus and the token comes in with a paste
    // shortcut, so Enter is the keyboard's Receive (done, not a newline).
    testWidgets(
      'Enter receives a typed token',
      (tester) async {
        final controller = _FakeController();
        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          controller: controller,
        );

        await _openReceive(tester);
        await tester.enterText(find.byType(TextField), '  cashuBentered  ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(controller.received, ['cashuBentered']);
        expect(find.byType(MostroDialog), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'Enter on an empty field does nothing and keeps the focus',
      (tester) async {
        final controller = _FakeController();
        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          controller: controller,
        );

        await _openReceive(tester);
        await tester.enterText(find.byType(TextField), '   ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(controller.received, isEmpty);
        expect(find.byType(MostroDialog), findsOneWidget);
        // The field keeps the focus, so a paste shortcut still lands in it
        // without a click first.
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isTrue,
        );
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'Paste fills the field and waits for Receive',
      (tester) async {
        final controller = _FakeController();
        _mockClipboard(tester, '  cashuBclipboard  ');
        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          controller: controller,
        );

        await _openReceive(tester);
        await tester.tap(find.text('Paste'));
        await tester.pumpAndSettle();

        // The user sees what they pasted before it goes to the mint.
        expect(find.text('cashuBclipboard'), findsOneWidget);
        expect(controller.received, isEmpty);

        await _tapDialogReceive(tester);

        expect(controller.received, ['cashuBclipboard']);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'an empty clipboard says so under the field',
      (tester) async {
        final controller = _FakeController();
        _mockClipboard(tester, '   ');
        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          controller: controller,
        );

        await _openReceive(tester);
        await tester.tap(find.text('Paste'));
        await tester.pumpAndSettle();

        expect(find.text('Clipboard is empty'), findsOneWidget);
        expect(_dialogReceive(tester).onPressed, isNull);
        expect(controller.received, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'a scanned token is received without coming back to the dialog',
      (tester) async {
        final controller = _FakeController();
        _denyCameraPermission(tester);
        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          controller: controller,
        );

        await _openReceive(tester);
        await tester.tap(find.text('Scan QR'));
        await tester.pumpAndSettle();

        // The camera is refused, so the scanner offers its paste form; what
        // it returns travels the same way a decoded QR does.
        expect(find.text('Paste QR Code Content'), findsOneWidget);
        await tester.enterText(find.byType(TextField).last, ' cashuBscanned ');
        await tester.tap(find.text('Submit'));
        await tester.pumpAndSettle();

        expect(controller.received, ['cashuBscanned']);
        expect(find.byType(MostroDialog), findsNothing);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets(
      'without a camera scanning is offered disabled, with the reason',
      (tester) async {
        final controller = _FakeController();
        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          controller: controller,
        );

        await _openReceive(tester);

        // Same dialog as on a phone, so the user learns why there is no
        // camera instead of wondering where scanning went.
        expect(_link(tester, 'Scan QR').onPressed, isNull);
        expect(find.byType(MobileScanner), findsNothing);
        // The reason is a tooltip: hidden until asked for, then shown though
        // the link itself cannot be pressed.
        expect(find.text('Not available on this device'), findsNothing);
        await tester.longPress(find.byTooltip('Not available on this device'));
        await tester.pump();
        expect(find.text('Not available on this device'), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'cashuBdesktop');
        await tester.pump();
        await _tapDialogReceive(tester);

        expect(controller.received, ['cashuBdesktop']);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'Cancel closes the dialog without reaching the wallet',
      (tester) async {
        final controller = _FakeController();
        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          controller: controller,
        );

        await _openReceive(tester);
        await tester.enterText(find.byType(TextField), 'cashuBkept');
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(MostroDialog), findsNothing);
        expect(controller.received, isEmpty);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  });

  // DS-A11Y-4: the longest translation, doubled, on the narrowest phone —
  // with Scan QR enabled (Android) and disabled with its reason (Linux), and
  // with the keyboard up, as it is while the token is typed or pasted.
  for (final keyboard in [0.0, 280.0]) {
    testWidgets(
      'German at 2x on a 320 dp screen fits the Receive dialog, '
      'keyboard inset $keyboard',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1.0;
        tester.platformDispatcher.textScaleFactorTestValue = 2.0;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        await _pump(
          tester,
          status: _status(connected: true, balance: 0),
          locale: const Locale('de'),
        );
        // At 2x the screen runs past 640 dp, and Receive with it.
        await tester.ensureVisible(find.text('Empfangen'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Empfangen'));
        await tester.pumpAndSettle();
        // The keyboard rises once the dialog is open and its field in use.
        tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
        await tester.pumpAndSettle();

        expect(find.byType(MostroDialog), findsOneWidget);
        expect(tester.takeException(), isNull);
        // The dialog follows the keyboard: its Receive stays above it, where
        // the user can reach it, rather than fitting only by hiding under it.
        final receive = find.descendant(
          of: find.byType(MostroDialog),
          matching: find.widgetWithText(FilledButton, 'Empfangen'),
        );
        expect(
          tester.getRect(receive).bottom,
          lessThanOrEqualTo(640 - keyboard),
        );
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.linux,
      }),
    );
  }

  group('CashuWalletScreen', () {
    testWidgets('a connected wallet shows its balance and mint', (tester) async {
      await _pump(tester, status: _status(connected: true, balance: 1234));

      expect(find.text('1,234 Satoshis'), findsOneWidget);
      expect(find.text('Mint: https://mint.example.com'), findsOneWidget);
      expect(find.text('Not connected to a mint'), findsNothing);
    });

    testWidgets('the balance groups digits the way the reader\'s locale does',
        (tester) async {
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

    testWidgets('a balance beyond double precision is shown exactly',
        (tester) async {
      // Arrange — 2^53 + 1, the first integer a double cannot represent.
      // Formatting through `num` would render this rounded, and a bearer-money
      // balance must never be approximate.
      final status = CashuWalletStatus(
        connected: true,
        mintUrl: 'https://mint.example.com',
        balanceSats: BigInt.parse('9007199254740993'),
        missingCapabilities: const [],
        canSendLightning: false,
        canReceiveLightning: false,
        receivingSats: BigInt.zero,
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

    testWidgets('an unreadable balance renders as unknown, never as zero',
        (tester) async {
      // Ecash is bearer money: showing "0 Satoshis" for a failed read is the
      // one number this screen must never invent.
      await _pump(tester, status: _status(connected: true, balance: null));

      expect(find.text('—'), findsOneWidget);
      expect(find.text('0 Satoshis'), findsNothing);
    });

    testWidgets('sending is disabled while the balance is unknown',
        (tester) async {
      await _pump(tester, status: _status(connected: true, balance: null));

      final send = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Send'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(send.onPressed, isNull);
    });

    testWidgets('an exported token stays retrievable until dismissed',
        (tester) async {
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

    testWidgets('an amount above the balance is refused in the dialog',
        (tester) async {
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

    testWidgets('neither a stray tap nor back closes the token dialog',
        (tester) async {
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

    testWidgets("I've sent it clears the exported-token reminder",
        (tester) async {
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

    testWidgets('a token is a Mostro QR without a logo: it is no node\'s',
        (tester) async {
      await _pump(tester, status: _status(connected: true, balance: 100));

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '10');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      final qr = tester.widget<MostroQr>(find.byType(MostroQr));
      expect(qr.data, 'cashuBtesttoken');
      expect(qr.logo, isNull);
    });

    testWidgets('the token QR takes the width of the dialog', (tester) async {
      // Arrange — a phone's width.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await _pump(tester, status: _status(connected: true, balance: 100));

      // Act — send 10 sats, which opens the token.
      await tester.ensureVisible(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '10');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      // Assert
      expectQrTakesItsWidth(tester);
    });

    testWidgets('a token too large for a QR is shown as text, never as an error',
        (tester) async {
      // A cdk token from many small proofs runs to tens of KB; a QR holds
      // ~2.9 KB. The dialog must degrade to the copyable text, not paint
      // the encoder's exception on the one dialog showing the user's money.
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
    });

    testWidgets('a send that could not confirm its proofs back says so',
        (tester) async {
      // "Try again" is the wrong advice here: the wallet must sync first.
      // The marker is one main grew after this screen was written, so it
      // pins that the mapper kept up.
      await _pump(
        tester,
        status: _status(connected: true, balance: 100),
        controller: _FakeController(
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

    testWidgets('a Rust marker is shown as a localized message, never raw',
        (tester) async {
      // The screen connects on its first frame; a Lightning node answers with
      // the gate marker.
      await _pump(
        tester,
        status: _status(connected: false, balance: 0),
        controller: _FakeController(
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

    testWidgets('an unrecognised failure falls back to the generic message',
        (tester) async {
      // A marker this build does not know must not leak an internal string.
      await _pump(
        tester,
        status: _status(connected: false, balance: 0),
        controller: _FakeController(
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

    testWidgets('a marker is found inside the exception the bridge really throws',
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
          connectError: AnyhowException('CashuNotEnabled: whatever Rust appended'),
        ),
      );
      await tester.pump();

      // Assert
      expect(
        find.text('This Mostro node does not settle trades with Cashu.'),
        findsOneWidget,
      );
      expect(find.textContaining('AnyhowException'), findsNothing);
    });
  });

  group('CashuWalletScreen — the wallet\'s mint is the user\'s', () {
    testWidgets('with no mint set, the wallet asks for one instead of failing',
        (tester) async {
      // A Lightning node on a fresh install: nothing to bind to yet, which is
      // a state to explain, not an error to flash.
      await _pump(
        tester,
        status: _status(connected: false, balance: 0),
        controller: _FakeController(connectError: 'CashuNoMint'),
      );

      expect(
        find.text('No mint set. Set one, or receive a token to use its mint.'),
        findsOneWidget,
      );
      expect(find.text('Set mint'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('receiving stays available with no mint set', (tester) async {
      // The first token received names the mint the wallet binds to.
      await _pump(
        tester,
        status: _status(connected: false, balance: 0),
        controller: _FakeController(connectError: 'CashuNoMint'),
      );

      final receive = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Receive'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
      );
      expect(receive.onPressed, isNotNull);
    });

    testWidgets('a token received with no mint set clears the no-mint notice',
        (tester) async {
      // Arrange — the received token's mint is now the wallet's, so asking
      // for one would be wrong.
      await _pump(
        tester,
        status: _status(connected: false, balance: 0),
        controller: _FakeController(connectError: 'CashuNoMint'),
      );
      const notice =
          'No mint set. Set one, or receive a token to use its mint.';
      expect(find.text(notice), findsOneWidget);

      // Act
      await _openReceive(tester);
      await tester.enterText(find.byType(TextField), 'cashuBfirst');
      await tester.pump();
      await _tapDialogReceive(tester);

      // Assert
      expect(find.text(notice), findsNothing);
    });

    testWidgets('setting a mint connects the wallet to it', (tester) async {
      // Arrange
      final controller = _FakeController(connectError: 'CashuNoMint');
      await _pump(
        tester,
        status: _status(connected: false, balance: 0),
        controller: controller,
      );

      // Act
      await tester.tap(find.text('Set mint'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), ' https://mint.new.com ');
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      // Assert — the open-time connect, then the chosen mint, trimmed.
      expect(controller.connects, [null, 'https://mint.new.com']);
    });

    testWidgets(
      'without a camera the mint dialog offers Scan QR disabled, with the '
      'reason',
      (tester) async {
        await _pump(
          tester,
          status: _status(connected: false, balance: 0),
          controller: _FakeController(connectError: 'CashuNoMint'),
        );

        await tester.tap(find.text('Set mint'));
        await tester.pumpAndSettle();

        // The scanner would only be a second paste field over this one.
        expect(_link(tester, 'Scan QR').onPressed, isNull);
        expect(_link(tester, 'Paste').onPressed, isNotNull);
        await tester.longPress(find.byTooltip('Not available on this device'));
        await tester.pump();
        expect(find.text('Not available on this device'), findsOneWidget);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
      },
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
    );

    testWidgets(
      'with a camera the mint dialog scans into its field',
      (tester) async {
        _denyCameraPermission(tester);
        await _pump(
          tester,
          status: _status(connected: false, balance: 0),
          controller: _FakeController(connectError: 'CashuNoMint'),
        );

        await tester.tap(find.text('Set mint'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('Not available on this device'), findsNothing);
        await tester.tap(find.text('Scan QR'));
        await tester.pumpAndSettle();

        // The camera is refused, so the scanner offers its paste form.
        await tester.enterText(
          find.byType(TextField).last,
          ' https://mint.scanned.com ',
        );
        await tester.tap(find.text('Submit'));
        await tester.pumpAndSettle();

        expect(find.text('https://mint.scanned.com'), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );

    testWidgets('an empty mint URL is refused in the dialog', (tester) async {
      final controller = _FakeController(connectError: 'CashuNoMint');
      await _pump(
        tester,
        status: _status(connected: false, balance: 0),
        controller: controller,
      );

      await tester.tap(find.text('Set mint'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Connect'));
      await tester.pumpAndSettle();

      expect(controller.connects, [null]);
      expect(find.text('Connect'), findsOneWidget);
    });

    testWidgets('an empty connected wallet changes its mint without a warning',
        (tester) async {
      await _pump(tester, status: _status(connected: true, balance: 0));

      await tester.tap(find.text('Change mint'));
      await tester.pumpAndSettle();

      expect(find.text('Mint URL'), findsOneWidget);
      expect(find.text('Change mint?'), findsNothing);
    });

    testWidgets('a set mint that is not answering is named, and replacing it '
        'warns about its sats', (tester) async {
      // Arrange — the mint did not answer when the wallet opened; Rust still
      // names it and reads its 500 sats from disk.
      await _pump(
        tester,
        status: CashuWalletStatus(
          connected: false,
          mintUrl: 'https://mint.example.com',
          balanceSats: BigInt.from(500),
          missingCapabilities: const [],
          canSendLightning: false,
          canReceiveLightning: false,
          receivingSats: BigInt.zero,
        ),
        controller: _FakeController(connectError: 'CashuMintUnreachable'),
      );

      // Assert — named, offered for change rather than for setting.
      expect(find.text('Mint: https://mint.example.com'), findsOneWidget);
      expect(find.text('Not connected to a mint'), findsOneWidget);
      expect(find.text('Set mint'), findsNothing);

      // Act — replacing it warns where the sats stay.
      await tester.tap(find.text('Change mint'));
      await tester.pumpAndSettle();
      expect(find.text('Change mint?'), findsOneWidget);
    });

    testWidgets('the mint cannot change while the balance is unknown',
        (tester) async {
      // The warning that the balance stays at the old mint needs the balance.
      await _pump(tester, status: _status(connected: true, balance: null));

      final change = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Change mint'),
          matching: find.byType(TextButton),
        ),
      );
      expect(change.onPressed, isNull);
    });

    testWidgets('changing the mint with a balance says where the balance stays',
        (tester) async {
      // Arrange
      await _pump(tester, status: _status(connected: true, balance: 500));

      // Act
      await tester.tap(find.text('Change mint'));
      await tester.pumpAndSettle();

      // Assert — the sats are not lost, and the user is told where they are.
      expect(find.text('Change mint?'), findsOneWidget);
      expect(
        find.text(
          'Your 500 sats stay at https://mint.example.com. They come back '
          'when you connect to that mint again.',
        ),
        findsOneWidget,
      );

      // And going on opens the mint dialog.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Mint URL'), findsOneWidget);
    });
  });

  testWidgets('the mint dialogs fit a narrow screen at German and 2x text',
      (tester) async {
    // Arrange — the longest strings, the smallest width, the largest text.
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(
      tester,
      status: _status(connected: true, balance: 1234567),
      locale: const Locale('de'),
    );

    // Act / Assert — the balance warning, then the mint dialog behind it.
    await tester.tap(find.text('Mint wechseln'));
    await tester.pumpAndSettle();
    expect(find.text('Mint wechseln?'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Weiter'));
    await tester.pumpAndSettle();
    expect(find.text('Mint-URL'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // DS-A11Y-4: the token dialog draws the Mostro QR (#851).
  testWidgets('the token dialog fits a narrow screen at German and 2x text',
      (tester) async {
    // Arrange — the longest strings, the smallest width, the largest text.
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1.0;
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final de = await AppLocalizations.delegate.load(const Locale('de'));
    await _pump(
      tester,
      status: _status(connected: true, balance: 100),
      locale: const Locale('de'),
    );

    // Act — send 10 sats, which opens the token.
    await tester.ensureVisible(find.text(de.cashuSendButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text(de.cashuSendButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '10');
    await tester.tap(find.text(de.confirm));
    await tester.pumpAndSettle();

    // Assert — the QR, the token and both actions, with nothing overflowing.
    expect(tester.takeException(), isNull);
    expect(find.byType(MostroQr), findsOneWidget);
    expect(find.text('cashuBtesttoken'), findsOneWidget);
    for (final action in [de.cashuCopyToken, de.done]) {
      final button = find.descendant(
        of: find.byType(MostroDialog),
        matching: find.text(action),
      );
      await tester.ensureVisible(button);
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(800));
    }
  });

  group('CashuWalletScreen — send to Lightning (C3b-1)', () {
    /// A mint that melts, a wallet with funds, and Send → Lightning → the
    /// invoice → Continue: the confirmation is on screen.
    Future<void> openConfirmation(
      WidgetTester tester,
      _FakeController controller,
    ) async {
      await _pump(
        tester,
        status: _status(connected: true, balance: 1000, canSendLightning: true),
        controller: controller,
      );
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lightning'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  $_invoice ');
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    Future<void> pay(WidgetTester tester) async {
      await tester.tap(find.text('Pay'));
      await tester.pumpAndSettle();
    }

    testWidgets('a mint that cannot melt sends a token, as before', (
      tester,
    ) async {
      await _pump(tester, status: _status(connected: true, balance: 100));

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      // Straight to the amount: no choice, and no Lightning anywhere.
      expect(find.text('Amount in sats'), findsOneWidget);
      expect(find.text('Lightning'), findsNothing);
    });

    testWidgets('a mint that melts offers ecash or Lightning', (tester) async {
      await _pump(
        tester,
        status: _status(connected: true, balance: 100, canSendLightning: true),
      );

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      // A dialog, like the rest of the screen, with two rows of equal weight,
      // each with its icon — no primary button that would rank one option
      // over the other (DS-CMP-2); Cancel is the only button.
      expect(find.byType(MostroDialog), findsOneWidget);
      expect(find.text('Ecash'), findsOneWidget);
      expect(find.text('Lightning'), findsOneWidget);
      expect(find.byIcon(Icons.toll_outlined), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MostroDialog),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );
      expect(find.text('Cancel'), findsOneWidget);

      // Ecash is the token flow it always was.
      await tester.tap(find.text('Ecash'));
      await tester.pumpAndSettle();
      expect(find.text('Amount in sats'), findsOneWidget);
    });

    testWidgets('Continue waits for an invoice', (tester) async {
      final controller = _FakeController();
      await _pump(
        tester,
        status: _status(connected: true, balance: 100, canSendLightning: true),
        controller: controller,
      );

      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lightning'));
      await tester.pumpAndSettle();

      final continueButton = find.descendant(
        of: find.byType(MostroDialog),
        matching: find.widgetWithText(FilledButton, 'Continue'),
      );
      expect(tester.widget<FilledButton>(continueButton).onPressed, isNull);
      expect(controller.quoted, isEmpty);
    });

    testWidgets('the confirmation shows the amount, fees up to, and total', (
      tester,
    ) async {
      final controller = _FakeController(
        quotes: [_quote('q1', reserve: 2, input: 1)],
      );
      await openConfirmation(tester, controller);

      // The trimmed invoice went to Rust; the fees are reserve + input.
      expect(controller.quoted, [_invoice]);
      expect(find.text('Confirm payment'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('100 Satoshis'), findsOneWidget);
      expect(find.text('Fees, up to'), findsOneWidget);
      expect(find.text('3 Satoshis'), findsOneWidget);
      expect(find.text('Total, up to'), findsOneWidget);
      expect(find.text('103 Satoshis'), findsOneWidget);
      // Nothing is paid by looking.
      expect(controller.melts, isEmpty);
    });

    testWidgets('Cancel on the confirmation pays nothing', (tester) async {
      final controller = _FakeController(quotes: [_quote('q1')]);
      await openConfirmation(tester, controller);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(MostroDialog), findsNothing);
      expect(controller.melts, isEmpty);
    });

    testWidgets('a paid invoice reports the fee actually charged', (
      tester,
    ) async {
      final controller = _FakeController(
        quotes: [_quote('q1')],
        meltOutcomes: [
          CashuMeltResult.paid(
            amountSats: BigInt.from(100),
            feePaidSats: BigInt.one,
          ),
        ],
      );
      await openConfirmation(tester, controller);

      await pay(tester);

      // Paid with the total the user saw as the ceiling, and said so in the
      // dialog itself — amount, the fee actually charged, a check mark — until
      // the user closes it.
      expect(controller.melts, [('q1', BigInt.from(103))]);
      expect(find.text('Paid 100 sats'), findsOneWidget);
      expect(find.text('Fee: 1 sats'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.text('Confirm payment'), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(MostroDialog), findsNothing);
    });

    testWidgets('the confirmation stays open, busy, while the payment runs', (
      tester,
    ) async {
      final routing = Completer<CashuMeltResult>();
      final controller = _FakeController(
        quotes: [_quote('q1')],
        meltOutcomes: [routing.future],
      );
      await openConfirmation(tester, controller);

      await tester.tap(find.text('Pay'));
      await tester.pump();

      // Still on screen, Pay replaced by its spinner, and no way out: closing
      // would not stop the payment.
      expect(find.text('Confirm payment'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final cancel = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Cancel'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(cancel.onPressed, isNull);
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(find.text('Confirm payment'), findsOneWidget);

      routing.complete(
        CashuMeltResult.paid(
          amountSats: BigInt.from(100),
          feePaidSats: BigInt.one,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirm payment'), findsNothing);
      expect(find.text('Paid 100 sats'), findsOneWidget);
    });

    testWidgets('a payment that never answers ends as pending, with a way out', (
      tester,
    ) async {
      // A mint that ignores `respond-async` holds the request for as long as
      // the payment takes — a hold invoice, a stuck route — and nothing in the
      // bridge times it out.
      final routing = Completer<CashuMeltResult>();
      final controller = _FakeController(
        quotes: [_quote('q1')],
        meltOutcomes: [routing.future],
      );
      await openConfirmation(tester, controller);

      await tester.tap(find.text('Pay'));
      await tester.pump();

      // Rust waits up to 30 s on a payment the mint answered as pending, and
      // its answer is worth more than a guess: still busy then.
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Confirm payment'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Within a minute the dialog stops waiting: the outcome is not known,
      // which is what "pending" says, and Close lets the user out.
      await tester.pump(const Duration(seconds: 30));
      await tester.pump();
      expect(find.text('Payment in progress'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(MostroDialog), findsNothing);

      // The payment itself was never cancelled: when it ends, late and with
      // the dialog gone, nothing is shown and nothing breaks.
      routing.completeError(Exception('CashuMeltFailed: too late'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(MostroDialog), findsNothing);
      expect(controller.melts, hasLength(1));
    });

    testWidgets('a payment not yet settled says how to settle it', (
      tester,
    ) async {
      final controller = _FakeController(
        quotes: [_quote('q1')],
        meltOutcomes: [const CashuMeltResult.pending()],
      );
      await openConfirmation(tester, controller);

      await pay(tester);

      expect(find.text('Payment in progress'), findsOneWidget);
      // Not "still routing": a mint that did not answer reads as pending
      // too. And nothing syncs on its own, so it names the button that does.
      expect(
        find.text(
          "The outcome isn't confirmed yet. Those sats stay on hold; tap "
          '“Sync with mint” later to settle them.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    });

    testWidgets('how the payment ended is announced to a screen reader', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      try {
        for (final (outcome, title) in [
          (
            CashuMeltResult.paid(
              amountSats: BigInt.from(100),
              feePaidSats: BigInt.one,
            ),
            'Paid 100 sats',
          ),
          (const CashuMeltResult.pending(), 'Payment in progress'),
          (
            AnyhowException('CashuMeltFailed: payment Failed'),
            'Payment failed',
          ),
        ]) {
          final controller = _FakeController(
            quotes: [_quote('q1')],
            meltOutcomes: [outcome],
          );
          await openConfirmation(tester, controller);

          await pay(tester);

          // It replaces the confirmation in place: no route change says it.
          // Title and body are read as one message.
          final node = tester.getSemantics(find.text(title));
          expect(node, isSemantics(isLiveRegion: true), reason: title);
          expect(node.label, contains('\n'), reason: title);
          await tester.tap(find.text('Close'));
          await tester.pumpAndSettle();
        }
      } finally {
        semantics.dispose();
      }
    });

    test('the pending note names the Sync button as each locale labels it', () {
      for (final locale in AppLocalizations.supportedLocales) {
        final l10n = lookupAppLocalizations(locale);
        expect(
          l10n.cashuMeltPendingBody,
          contains(l10n.cashuSyncButton),
          reason: '$locale',
        );
      }
    });

    testWidgets('a failed payment says so in the dialog, with the reason', (
      tester,
    ) async {
      final controller = _FakeController(
        quotes: [_quote('q1')],
        meltOutcomes: [AnyhowException('CashuMeltFailed: payment Failed')],
      );
      await openConfirmation(tester, controller);

      await pay(tester);

      // Not a passing snackbar over a closed dialog: the outcome, its reason
      // in words, and Close.
      expect(find.text('Payment failed'), findsOneWidget);
      expect(
        find.text(
          'The payment did not go through. Nothing was paid; the sats are '
          'back in your balance.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.textContaining('payment Failed'), findsNothing);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(MostroDialog), findsNothing);
      // Asked once, never retried.
      expect(controller.melts, hasLength(1));
    });

    for (final stale in ['CashuMeltFeeChanged', 'CashuMeltQuoteExpired']) {
      testWidgets('$stale asks for a fresh quote and shows it, never pays '
          'the stale one', (tester) async {
        final controller = _FakeController(
          quotes: [_quote('q1'), _quote('q2', reserve: 5)],
          meltOutcomes: [
            AnyhowException('$stale: detail'),
            CashuMeltResult.paid(
              amountSats: BigInt.from(100),
              feePaidSats: BigInt.two,
            ),
          ],
        );
        await openConfirmation(tester, controller);

        await pay(tester);

        // A second quote, shown with its own total and a word on why.
        expect(controller.quoted, [_invoice, _invoice]);
        expect(
          find.text('The price changed. Check the new total before paying.'),
          findsOneWidget,
        );
        expect(find.text('106 Satoshis'), findsOneWidget);

        await pay(tester);

        expect(controller.melts, [
          ('q1', BigInt.from(103)),
          ('q2', BigInt.from(106)),
        ]);
        expect(find.text('Paid 100 sats'), findsOneWidget);
        expect(find.text('Fee: 2 sats'), findsOneWidget);
      });
    }

    testWidgets('a second stale quote is shown as an error, not retried', (
      tester,
    ) async {
      final controller = _FakeController(
        quotes: [_quote('q1'), _quote('q2')],
        meltOutcomes: [
          AnyhowException('CashuMeltFeeChanged: detail'),
          AnyhowException('CashuMeltFeeChanged: detail'),
        ],
      );
      await openConfirmation(tester, controller);

      await pay(tester);
      await pay(tester);

      expect(controller.quoted, hasLength(2));
      expect(find.byType(MostroDialog), findsNothing);
      expect(
        find.text(
          'The fees went up since you confirmed. Nothing was paid; start '
          'again.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a refused quote is a localized message, never raw', (
      tester,
    ) async {
      final controller = _FakeControllerQuoteError(
        AnyhowException('CashuInvoiceNoAmount'),
      );
      await _pump(
        tester,
        status: _status(connected: true, balance: 100, canSendLightning: true),
        controller: controller,
      );
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lightning'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), _invoice);
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This invoice has no amount. Ask for one that states how much to '
          'pay.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('CashuInvoiceNoAmount'), findsNothing);
    });

    // DS-A11Y-4: the longest translation, doubled, on the narrowest phone.
    testWidgets('the payment confirmation fits a narrow screen at German and '
        '2x text', (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final de = await AppLocalizations.delegate.load(const Locale('de'));
      await _pump(
        tester,
        status: _status(connected: true, balance: 1000, canSendLightning: true),
        controller: _FakeController(quotes: [_quote('q1')]),
        locale: const Locale('de'),
      );

      await tester.ensureVisible(find.text(de.cashuSendButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text(de.cashuSendButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(de.cashuSendLightningOption));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.enterText(find.byType(TextField), _invoice);
      await tester.pump();
      await tester.tap(find.text(de.continueButtonLabel));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final action in [de.cancel, de.cashuPayButton]) {
        final button = find.descendant(
          of: find.byType(MostroDialog),
          matching: find.text(action),
        );
        await tester.ensureVisible(button);
        expect(tester.getRect(button).bottom, lessThanOrEqualTo(800));
      }
    });
  });

  group('CashuWalletScreen — receive via Lightning (C3b-2)', () {
    /// A mint that issues against Lightning, and Receive → Lightning →
    /// [amount] → Confirm: the invoice is on screen. Pumped by hand: the
    /// dialog polls on a timer and spins, so nothing ever settles.
    Future<void> openInvoice(
      WidgetTester tester,
      _FakeController controller, {
      String amount = '1000',
    }) async {
      await _pump(
        tester,
        status: _status(connected: true, balance: 0, canReceiveLightning: true),
        controller: controller,
      );
      await tester.tap(find.text('Receive'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lightning'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), amount);
      await tester.pump();
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    /// One poll: the timer fires, and its answer lands.
    Future<void> poll(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('a mint that cannot issue receives a token, as before', (
      tester,
    ) async {
      await _pump(tester, status: _status(connected: true, balance: 0));

      await tester.tap(find.text('Receive'));
      await tester.pumpAndSettle();

      expect(find.text('Receive a token'), findsOneWidget);
      expect(find.text('Lightning'), findsNothing);
    });

    testWidgets('a mint that issues offers a token or Lightning', (
      tester,
    ) async {
      await _pump(
        tester,
        status: _status(connected: true, balance: 0, canReceiveLightning: true),
      );

      await tester.tap(find.text('Receive'));
      await tester.pumpAndSettle();

      // Rows of equal weight, no primary button (DS-CMP-2); Cancel only.
      expect(find.byType(MostroDialog), findsOneWidget);
      expect(find.text('Ecash token'), findsOneWidget);
      expect(find.text('Lightning'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(MostroDialog),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );

      // The token is the flow it always was.
      await tester.tap(find.text('Ecash token'));
      await tester.pumpAndSettle();
      expect(find.text('Receive a token'), findsOneWidget);
    });

    testWidgets('the invoice waits, then shows what was received', (
      tester,
    ) async {
      final controller = _FakeController(
        claimOutcomes: [
          const CashuMintQuoteState.waiting(),
          CashuMintQuoteState.issued(amountSats: BigInt.from(1000)),
        ],
      );
      await openInvoice(tester, controller);

      // The invoice for the amount asked, as a QR, and nothing claimed yet.
      expect(controller.mintQuoted, [BigInt.from(1000)]);
      expect(find.text('Pay this invoice'), findsOneWidget);
      expect(find.byType(MostroQr), findsOneWidget);
      expect(find.text('1,000 Satoshis'), findsOneWidget);
      expect(find.text('Waiting for the payment…'), findsOneWidget);
      expect(controller.claims, isEmpty);

      // Not paid yet: still the invoice.
      await poll(tester);
      expect(controller.claims, ['mq1']);
      expect(find.text('Pay this invoice'), findsOneWidget);

      // Paid: the outcome, in the same dialog, as a live region.
      await poll(tester);
      expect(find.text('Received 1,000 sats'), findsOneWidget);
      expect(find.byType(MostroQr), findsNothing);
      expect(
        tester.widget<MostroDialog>(find.byType(MostroDialog)).liveRegion,
        isTrue,
      );

      // No more polling once it ended.
      await tester.pump(const Duration(seconds: 10));
      expect(controller.claims, hasLength(2));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(MostroDialog), findsNothing);
    });

    testWidgets('an invoice that expires unpaid says so', (tester) async {
      final controller = _FakeController(
        claimOutcomes: [const CashuMintQuoteState.expired()],
      );
      await openInvoice(tester, controller);

      await poll(tester);

      expect(find.text('Invoice expired'), findsOneWidget);
      expect(find.byType(MostroQr), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('a failed check shows the reason, never the marker', (
      tester,
    ) async {
      final controller = _FakeController(
        claimOutcomes: [Exception('CashuMintQuoteUnknown')],
      );
      await openInvoice(tester, controller);

      await poll(tester);

      expect(find.text('Could not receive'), findsOneWidget);
      expect(
        find.text(
          'This invoice belongs to another mint. Switch back to that mint '
          'to receive it.',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('CashuMint'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('closing the invoice stops asking about it', (tester) async {
      final controller = _FakeController();
      await openInvoice(tester, controller);

      // Closing is allowed while it waits, and says nothing is lost.
      expect(
        find.text(
          'You can close this. If the invoice is paid later, the sats arrive '
          'the next time you open the app.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(MostroDialog), findsNothing);

      await tester.pump(const Duration(seconds: 10));
      expect(controller.claims, isEmpty);
    });

    testWidgets('a refused amount shows the mint\'s reason', (tester) async {
      final controller = _FakeController(
        mintQuoteError: Exception('CashuMintAmountOutOfRange: 1000 sat'),
      );
      await openInvoice(tester, controller);
      await tester.pumpAndSettle();

      expect(find.text('Pay this invoice'), findsNothing);
      expect(
        find.text('This mint does not issue invoices of that amount.'),
        findsOneWidget,
      );
    });

    // DS-CMP-21: the time left, labelled, ticking down — never the clock
    // time it ends at, which reads as minutes and seconds that never move.
    testWidgets('the invoice counts down the time left to pay it', (
      tester,
    ) async {
      final controller = _FakeController(
        invoiceLifetime: const Duration(minutes: 10),
      );
      await openInvoice(tester, controller);

      expect(find.text('Expires in'), findsOneWidget);
      final shown = RegExp(r'^\d\d:\d\d$');
      String figure() =>
          tester
              .widgetList<Text>(find.byType(Text))
              .map((text) => text.data ?? '')
              .firstWhere(shown.hasMatch);
      final first = figure();
      expect(first, anyOf('10:00', '09:59'));

      await tester.pump(const Duration(seconds: 2));
      expect(figure(), isNot(first), reason: 'the countdown did not move');

      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 500));
    });

    // DS-CMP-2: copying is what the user does while it waits; closing is
    // the way out, and loses nothing.
    testWidgets('Copy is the answer while the invoice waits, Close the way out', (
      tester,
    ) async {
      await openInvoice(tester, _FakeController());

      final dialog = find.byType(MostroDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(FilledButton, 'Copy'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: dialog,
          matching: find.widgetWithText(FilledButton, 'Close'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(MostroDialog), findsNothing);
    });

    testWidgets('an invoice too large for a QR is shown as text to copy', (
      tester,
    ) async {
      final huge = 'lnbcrt${'q' * 6000}';
      await openInvoice(tester, _FakeController(mintInvoice: huge));

      expect(tester.takeException(), isNull);
      expect(find.byType(MostroQr), findsNothing);
      expect(
        find.text('This invoice is too large for a QR code. Copy it instead.'),
        findsOneWidget,
      );
      expect(find.text(huge), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 500));
    });

    // DS-MOT-3: no looping spinner when the system asks for reduced motion.
    testWidgets('the waiting spinner stands still with animations off', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await openInvoice(tester, _FakeController());

      final dialog = find.byType(MostroDialog);
      expect(
        find.descendant(
          of: dialog,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.byIcon(Icons.schedule_rounded)),
        findsOneWidget,
      );
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 500));
    });

    // A clock ahead of the mint's runs out before the invoice does: 00:00
    // would read as dead an invoice that can still be paid. Only the mint
    // calls it expired; until then it waits, and keeps asking.
    testWidgets('a run-out countdown leaves the invoice waiting, not dead', (
      tester,
    ) async {
      final controller = _FakeController(
        invoiceLifetime: const Duration(seconds: 2),
      );
      await openInvoice(tester, controller);
      expect(find.text('Expires in'), findsOneWidget);

      await poll(tester);
      await poll(tester);

      expect(find.text('Expires in'), findsNothing);
      expect(find.text('00:00'), findsNothing);
      expect(find.text('Waiting for the payment…'), findsOneWidget);
      expect(controller.claims, hasLength(2), reason: 'it still asks');
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('an invoice with no expiry shows no countdown', (tester) async {
      await openInvoice(tester, _FakeController());

      expect(find.text('Expires in'), findsNothing);
      await tester.tap(find.text('Close'));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('sats paid and not minted yet show as receiving', (
      tester,
    ) async {
      await _pump(
        tester,
        status: _status(connected: true, balance: 500, receiving: 1500),
      );

      // Under the balance, never added to it.
      expect(find.text('500 Satoshis'), findsOneWidget);
      expect(find.text('Receiving 1,500 sats'), findsOneWidget);
    });

    testWidgets('nothing receiving shows no row', (tester) async {
      await _pump(tester, status: _status(connected: true, balance: 500));

      expect(find.textContaining('Receiving'), findsNothing);
    });

    // DS-A11Y-4: the longest translation, doubled, on the narrowest phone.
    testWidgets('the invoice fits a narrow screen at German and 2x text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final de = await AppLocalizations.delegate.load(const Locale('de'));
      await _pump(
        tester,
        status: _status(connected: true, balance: 0, canReceiveLightning: true),
        locale: const Locale('de'),
      );

      await tester.tap(find.text(de.cashuReceiveButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text(de.cashuReceiveLightningOption));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1000');
      await tester.pump();
      await tester.tap(find.text(de.confirm));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.takeException(), isNull);
      for (final action in [de.cashuCopyToken, de.closeButtonLabel]) {
        final button = find.descendant(
          of: find.byType(MostroDialog),
          matching: find.text(action),
        );
        await tester.ensureVisible(button);
        await tester.pump();
        expect(tester.getRect(button).bottom, lessThanOrEqualTo(800));
      }
      await tester.tap(find.text(de.closeButtonLabel));
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}

/// A wallet whose mint refuses to quote, with [error].
class _FakeControllerQuoteError extends _FakeController {
  _FakeControllerQuoteError(this.error);

  final Object error;

  @override
  Future<CashuMeltQuote> meltQuote(String invoice) async => throw error;
}
