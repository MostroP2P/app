import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:mostro/core/app_routes.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/cashu/providers/cashu_wallet_provider.dart';
import 'package:mostro/features/cashu/screens/lock_escrow_screen.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/provider_harness.dart';

/// Stands in for the Rust bridge so nothing reaches a mint or a relay. It
/// keeps the one fact the screen must take from the core rather than guess:
/// whether an escrow is recorded (`pendingSubmission`) — which a failed lock
/// may or may not have left behind.
class _FakeEscrow extends CashuEscrowController {
  _FakeEscrow({
    required this.balance,
    this.fee = 0,
    this.quoteError,
    this.lockError,
    this.lockRecords = false,
  });

  int balance;
  final int fee;

  /// When set, the next quote waits on it: lets a test finish a newer quote
  /// before an older one.
  Completer<void>? hold;
  final Object? quoteError;
  final Object? lockError;

  /// Whether a failing lock got as far as recording an escrow.
  final bool lockRecords;
  bool pending = false;
  int quotes = 0;

  CashuEscrowQuote _current() => CashuEscrowQuote(
    orderId: 'order-1',
    amountSats: BigInt.from(10000),
    feeSats: BigInt.from(fee),
    totalSats: BigInt.from(10000 + fee),
    balanceSats: BigInt.from(balance),
    mintUrl: 'https://mint.example.com',
    locktimeDays: 15,
    pendingSubmission: pending,
  );

  @override
  Future<CashuEscrowQuote> quote(String orderId) async {
    quotes++;
    if (quoteError != null) throw quoteError!;
    // Read now, returned later: a held call reports the balance it saw.
    final seen = _current();
    final gate = hold;
    if (gate != null) {
      hold = null;
      await gate.future;
    }
    return seen;
  }

  @override
  Future<void> lock(String orderId) async {
    if (lockError != null) {
      if (lockRecords) pending = true;
      throw lockError!;
    }
  }
}

class _FakeWallet extends CashuWalletController {
  const _FakeWallet();

  @override
  Future<CashuWalletStatus> connect({String? mintUrl}) async => CashuWalletStatus(
    connected: true,
    mintUrl: 'https://mint.example.com',
    balanceSats: BigInt.from(100000),
    missingCapabilities: const [],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeEscrow escrow,
  Stream<CashuWalletStatus>? walletChanges,
}) async {
  final container = createContainer(
    overrides: [
      cashuEscrowControllerProvider.overrideWithValue(escrow),
      cashuWalletControllerProvider.overrideWithValue(const _FakeWallet()),
      cashuWalletProvider.overrideWith(
        (ref) => walletChanges ?? const Stream<CashuWalletStatus>.empty(),
      ),
    ],
  );

  // A real router: the funding round trip is a push and a pop.
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const LockEscrowScreen(orderId: 'order-1'),
      ),
      GoRoute(
        path: AppRoute.cashuWallet,
        builder:
            (context, _) => Scaffold(
              body: TextButton(
                onPressed: () {
                  escrow.balance = 100000;
                  context.pop();
                },
                child: const Text('funded'),
              ),
            ),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildDarkTheme(),
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );

  await tester.pump();
  await tester.pump();
}

void main() {
  group('LockEscrowScreen', () {
    testWidgets('shows what will be locked before anything is committed', (
      tester,
    ) async {
      await _pump(tester, escrow: _FakeEscrow(balance: 100000));

      expect(find.text('10000 Satoshis'), findsNWidgets(2));
      expect(find.text('Lock escrow'), findsOneWidget);
      // No fee token until the daemon collects one (TA-1f): no fee row.
      expect(find.text('Mostro fee'), findsNothing);
    });

    testWidgets('a fee, once charged, is stated before the lock', (
      tester,
    ) async {
      await _pump(tester, escrow: _FakeEscrow(balance: 100000, fee: 60));

      expect(find.text('Mostro fee'), findsOneWidget);
      expect(find.text('60 Satoshis'), findsOneWidget);
      expect(find.text('10060 Satoshis'), findsOneWidget);
    });

    testWidgets('a short balance offers funding instead of a failure', (
      tester,
    ) async {
      await _pump(tester, escrow: _FakeEscrow(balance: 100));

      expect(find.text('Fund your wallet'), findsOneWidget);
      expect(find.text('Lock escrow'), findsNothing);
    });

    testWidgets('coming back funded offers the lock', (tester) async {
      // ermeme on #238: the quote was read once, so a seller who funded the
      // wallet and came back was still told to fund it.
      final escrow = _FakeEscrow(balance: 100);
      await _pump(tester, escrow: escrow);

      await tester.tap(find.text('Fund your wallet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('funded'));
      await tester.pumpAndSettle();

      expect(find.text('Lock escrow'), findsOneWidget);
      expect(find.text('Fund your wallet'), findsNothing);
    });

    testWidgets('an older quote never replaces a newer one', (tester) async {
      // CodeRabbit on #238: a balance change and the funding route's return
      // can both reload; the one that started first may finish last.
      final escrow = _FakeEscrow(balance: 100);
      final wallet = StreamController<CashuWalletStatus>();
      addTearDown(wallet.close);
      await _pump(tester, escrow: escrow, walletChanges: wallet.stream);

      // A balance event starts a reload that reads the old balance and is
      // held back...
      final older = Completer<void>();
      escrow.hold = older;
      wallet.add(
        CashuWalletStatus(
          connected: true,
          mintUrl: 'https://mint.example.com',
          balanceSats: BigInt.from(100),
          missingCapabilities: const [],
        ),
      );
      await tester.pump();

      // ...while the reload after funding reads the new one and lands first.
      await tester.tap(find.text('Fund your wallet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('funded'));
      await tester.pumpAndSettle();
      expect(find.text('Lock escrow'), findsOneWidget);

      // The older one finishes last: it must not bring "fund your wallet"
      // back.
      older.complete();
      await tester.pumpAndSettle();

      expect(find.text('Lock escrow'), findsOneWidget);
      expect(find.text('Fund your wallet'), findsNothing);
    });

    testWidgets('a missing escrow request is explained, not shown as a marker', (
      tester,
    ) async {
      await _pump(
        tester,
        escrow: _FakeEscrow(
          balance: 100000,
          quoteError: 'CashuEscrowRequestMissing: nothing stored',
        ),
      );

      expect(find.textContaining('no escrow request yet'), findsOneWidget);
      expect(find.textContaining('CashuEscrowRequestMissing'), findsNothing);
    });

    testWidgets('a failure that recorded nothing offers no re-send', (
      tester,
    ) async {
      await _pump(
        tester,
        escrow: _FakeEscrow(
          balance: 100000,
          lockError: 'CashuWrongTradeKey: order expects abc',
        ),
      );

      await tester.tap(find.text('Lock escrow'));
      await tester.pumpAndSettle();

      expect(find.text('Retry sending'), findsNothing);
      expect(find.textContaining('does not hold the key'), findsOneWidget);
    });

    testWidgets('an unanswered submission re-sends the recorded escrow', (
      tester,
    ) async {
      // The core recorded the escrow before publishing; the next tap re-sends
      // that token, so the screen says so and the balance no longer matters.
      await _pump(
        tester,
        escrow: _FakeEscrow(
          balance: 100000,
          lockError: 'NoDaemonResponse',
          lockRecords: true,
        ),
      );

      await tester.tap(find.text('Lock escrow'));
      await tester.pumpAndSettle();

      expect(find.text('Retry sending'), findsOneWidget);
      expect(find.textContaining('has not answered yet'), findsOneWidget);
      expect(
        find.textContaining('locked but the node has not confirmed'),
        findsOneWidget,
      );
    });

    testWidgets('a token the node rejected for good says it was set aside', (
      tester,
    ) async {
      await _pump(
        tester,
        escrow: _FakeEscrow(
          balance: 100000,
          lockError: 'CashuEscrowRejected: InvalidCashuToken',
        ),
      );

      await tester.tap(find.text('Lock escrow'));
      await tester.pumpAndSettle();

      expect(find.textContaining('set aside'), findsOneWidget);
      // Retired, so the next attempt locks a new one.
      expect(find.text('Lock escrow'), findsOneWidget);
    });
  });
}
