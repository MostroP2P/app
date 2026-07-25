import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/cashu/providers/cashu_wallet_provider.dart';
import 'package:mostro/features/cashu/screens/lock_escrow_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/provider_harness.dart';

/// Stands in for the Rust bridge so nothing reaches a mint or a relay.
class _FakeEscrow extends CashuEscrowController {
  const _FakeEscrow({this.quoteResult, this.quoteError, this.lockError});

  final CashuEscrowQuote? quoteResult;
  final Object? quoteError;
  final Object? lockError;

  @override
  Future<CashuEscrowQuote> quote(String orderId) async {
    if (quoteError != null) throw quoteError!;
    return quoteResult!;
  }

  @override
  Future<CashuEscrowQuote> lock(String orderId) async {
    if (lockError != null) throw lockError!;
    return quoteResult!;
  }
}

class _FakeWallet extends CashuWalletController {
  const _FakeWallet();

  @override
  Future<CashuWalletStatus> connect() async => CashuWalletStatus(
        connected: true,
        mintUrl: 'https://mint.example.com',
        balanceSats: BigInt.from(100000),
        missingCapabilities: const [],
      );
}

CashuEscrowQuote _quote({required int balance}) => CashuEscrowQuote(
      orderId: 'order-1',
      amountSats: BigInt.from(10000),
      feeSats: BigInt.from(60),
      totalSats: BigInt.from(10060),
      balanceSats: BigInt.from(balance),
      mintUrl: 'https://mint.example.com',
      locktimeDays: 15,
    );

Future<void> _pump(
  WidgetTester tester, {
  required CashuEscrowController escrow,
}) async {
  final container = createContainer(overrides: [
    cashuEscrowControllerProvider.overrideWithValue(escrow),
    cashuWalletControllerProvider.overrideWithValue(const _FakeWallet()),
  ]);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LockEscrowScreen(orderId: 'order-1'),
      ),
    ),
  );

  await tester.pump();
  await tester.pump();
}

void main() {
  group('LockEscrowScreen', () {
    testWidgets('shows what will be locked before anything is committed',
        (tester) async {
      await _pump(
        tester,
        escrow: _FakeEscrow(quoteResult: _quote(balance: 100000)),
      );

      // Escrow, fee and total are all stated: the fee is a separate token and
      // its size is not obvious from the order.
      expect(find.text('10000 Satoshis'), findsOneWidget);
      expect(find.text('60 Satoshis'), findsOneWidget);
      expect(find.text('10060 Satoshis'), findsOneWidget);
      expect(find.text('Lock escrow'), findsOneWidget);
    });

    testWidgets('a short balance offers funding instead of a failure',
        (tester) async {
      // The most common seller error must not surface as a mint-side message.
      await _pump(
        tester,
        escrow: _FakeEscrow(quoteResult: _quote(balance: 100)),
      );

      expect(find.text('Fund your wallet'), findsOneWidget);
      expect(find.text('Lock escrow'), findsNothing);
    });

    testWidgets('a missing escrow request is explained, not shown as a marker',
        (tester) async {
      await _pump(
        tester,
        escrow: const _FakeEscrow(
          quoteError: 'CashuEscrowRequestMissing: nothing stored',
        ),
      );

      expect(find.textContaining('no escrow request yet'), findsOneWidget);
      expect(find.textContaining('CashuEscrowRequestMissing'), findsNothing);
    });

    testWidgets('a failure before the mint swap offers no retry',
        (tester) async {
      // Nothing moved, so offering "retry sending" would misdescribe what
      // happened.
      await _pump(
        tester,
        escrow: _FakeEscrow(
          quoteResult: _quote(balance: 100000),
          lockError: 'CashuWrongTradeKey: order expects abc',
        ),
      );

      await tester.tap(find.text('Lock escrow'));
      await tester.pumpAndSettle();

      expect(find.text('Retry sending'), findsNothing);
      expect(find.textContaining('does not hold the key'), findsOneWidget);
    });

    testWidgets('a failure after the mint swap offers a safe retry',
        (tester) async {
      // The funds are locked and the token is persisted; the daemon's handler
      // is idempotent, so retrying is the only way out of a lost publish.
      await _pump(
        tester,
        escrow: _FakeEscrow(
          quoteResult: _quote(balance: 100000),
          lockError: 'relay publish failed',
        ),
      );

      await tester.tap(find.text('Lock escrow'));
      await tester.pumpAndSettle();

      expect(find.text('Retry sending'), findsOneWidget);
      expect(
        find.textContaining('locked but the node has not confirmed'),
        findsOneWidget,
      );
    });
  });
}
