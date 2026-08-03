import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/providers/trade_state_provider.dart';
import 'package:mostro/features/order/screens/pay_bond_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/l10n/app_localizations_en.dart';
import 'package:mostro/src/rust/api/types.dart';

import '../../../support/fake_trades.dart';
import '../../../support/provider_harness.dart';

const _orderId = 'order-bond-1';

/// Advances past dialog/snackbar transitions without waiting for the frame
/// queue to drain: the waiting states render a `CircularProgressIndicator`,
/// whose endless animation makes `pumpAndSettle` time out.
Future<void> _settle(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 400));

/// Pushes [PayBondInvoiceScreen] on top of a start route, so the screen is
/// poppable and renders an AppBar back button — the state the back handling
/// has to cover. `cancelOrder` itself is not exercised: it reaches the Rust
/// bridge, which is uninitialised in widget tests (see
/// `test/features/trades/trade_detail_screen_test.dart`).
Future<void> _pumpBondScreen(
  WidgetTester tester, {
  bool walletConnected = false,
  String? bondInvoice = 'lnbc1bondinvoice',
  OrderStatus status = OrderStatus.waitingTakerBond,
}) async {
  final trade = fakeTrade(
    orderId: _orderId,
    status: status,
    bondInvoice: bondInvoice,
    bondAmountSats: 1000,
  );

  final container = createContainer(overrides: [
    tradeBondInfoProvider(_orderId).overrideWith((ref) => Stream.value(trade)),
    tradeStatusProvider(_orderId).overrideWith((ref) => Stream.value(status)),
    isWalletConnectedProvider.overrideWithValue(walletConnected),
  ]);

  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (_, __) => const Scaffold(body: Text('start-route')),
      ),
      GoRoute(
        path: '/bond',
        builder: (_, __) => const PayBondInvoiceScreen(orderId: _orderId),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildDarkTheme(),
        routerConfig: router,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();

  router.push('/bond');
  await tester.pump();
  await _settle(tester);
}

void main() {
  final l10n = AppLocalizationsEn();

  // Clipboard goes through the platform channel, which has no implementation
  // in widget tests; the copy button must resolve for the launch path to run.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('PayBondInvoiceScreen back handling with the bond unpaid', () {
    testWidgets('AppBar back opens the leave dialog instead of popping',
        (tester) async {
      await _pumpBondScreen(tester);

      await tester.tap(find.byType(BackButton));
      await _settle(tester);

      expect(find.text(l10n.leaveBondPaymentTitle), findsOneWidget);
      expect(find.text('start-route'), findsNothing,
          reason: 'the screen must not pop before the choice is made');
    });

    testWidgets('system back opens the leave dialog instead of popping',
        (tester) async {
      await _pumpBondScreen(tester);

      await tester.binding.handlePopRoute();
      await _settle(tester);

      expect(find.text(l10n.leaveBondPaymentTitle), findsOneWidget);
      expect(find.text('start-route'), findsNothing);
    });

    testWidgets('keep paying dismisses the dialog and stays put',
        (tester) async {
      await _pumpBondScreen(tester);
      await tester.tap(find.byType(BackButton));
      await _settle(tester);

      await tester.tap(find.text(l10n.keepPayingButton));
      await _settle(tester);

      expect(find.text(l10n.leaveBondPaymentTitle), findsNothing);
      expect(find.text(l10n.payBondInvoiceInstruction), findsOneWidget);
    });

    testWidgets('leave pops back without cancelling', (tester) async {
      await _pumpBondScreen(tester);
      await tester.tap(find.byType(BackButton));
      await _settle(tester);

      await tester.tap(find.text(l10n.leaveButton));
      await _settle(tester);

      expect(find.text('start-route'), findsOneWidget);
    });
  });

  group('PayBondInvoiceScreen payment-in-flight state', () {
    testWidgets('copying the invoice hides cancel and offers recovery',
        (tester) async {
      await _pumpBondScreen(tester);
      expect(find.text(l10n.cancel), findsOneWidget);

      await tester.tap(find.text(l10n.copyButtonLabel));
      await _settle(tester);

      expect(find.text(l10n.cancel), findsNothing,
          reason: 'cancelling could race a bond that is already settling');
      expect(find.text(l10n.bondPaymentNotPaidYet), findsOneWidget);
    });

    testWidgets('back offers leaving but never releasing while unresolved',
        (tester) async {
      await _pumpBondScreen(tester);
      await tester.tap(find.text(l10n.copyButtonLabel));
      await _settle(tester);

      // `true` means the route consumed the pop rather than letting it through.
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pump();
      await _settle(tester);

      expect(find.text('start-route'), findsNothing,
          reason: 'the pop goes through the policy, not straight out');
      expect(find.text(l10n.releaseOrderButton), findsNothing,
          reason: 'releasing could race a bond that is already settling');
      expect(find.text(l10n.leaveButton), findsOneWidget,
          reason: 'leaving sends nothing, so it must stay available');
    });

    testWidgets('keep waiting returns to the waiting state', (tester) async {
      await _pumpBondScreen(tester);
      await tester.tap(find.text(l10n.copyButtonLabel));
      await _settle(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await _settle(tester);

      await tester.tap(find.text(l10n.keepWaitingButton));
      await _settle(tester);
      await _settle(tester);

      expect(find.text(l10n.leaveBondPaymentWaitingContent), findsNothing);
      expect(find.text(l10n.bondPaymentNotPaidYet), findsOneWidget);
    });

    testWidgets('the recovery action restores the cancel button',
        (tester) async {
      await _pumpBondScreen(tester);
      await tester.tap(find.text(l10n.copyButtonLabel));
      await _settle(tester);

      await tester.tap(find.text(l10n.bondPaymentNotPaidYet));
      await _settle(tester);

      expect(find.text(l10n.cancel), findsOneWidget);
      expect(find.text(l10n.bondPaymentNotPaidYet), findsNothing);
    });
  });

  group('PayBondInvoiceScreen with an NWC wallet connected', () {
    testWidgets('the cancel button is reachable', (tester) async {
      await _pumpBondScreen(tester, walletConnected: true);

      expect(find.text(l10n.payWithWalletButton), findsOneWidget);
      expect(find.text(l10n.cancel), findsOneWidget,
          reason: 'an unpaid bond must be releasable from the NWC branch too');
    });

    testWidgets('back opens the leave dialog', (tester) async {
      await _pumpBondScreen(tester, walletConnected: true);

      await tester.binding.handlePopRoute();
      await _settle(tester);

      expect(find.text(l10n.leaveBondPaymentTitle), findsOneWidget);
    });
  });

  testWidgets('back is handled while still waiting for the bond invoice',
      (tester) async {
    await _pumpBondScreen(tester, bondInvoice: null);

    expect(find.text(l10n.tradeWaitingForBondInvoice), findsOneWidget);

    await tester.binding.handlePopRoute();
    await _settle(tester);

    expect(find.text(l10n.leaveBondPaymentTitle), findsOneWidget,
        reason: 'the waiting branch renders its own AppBar and must not bypass '
            'the policy either');
  });
}
