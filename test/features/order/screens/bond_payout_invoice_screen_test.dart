import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/order/providers/bond_providers.dart';
import 'package:mostro/features/order/screens/bond_payout_invoice_screen.dart';
import 'package:mostro/features/settings/providers/nwc_provider.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/platform_int64.dart';
import 'package:mostro/shared/widgets/nwc_invoice_widget.dart';
import 'package:mostro/src/rust/api/types.dart';

/// `now` for every test: 2026-09-13 12:00 UTC, as unix seconds.
const _now = 1789300800;

BondClaim _claim({
  BondClaimPhase phase = BondClaimPhase.pending,
  int deadlineAt = _now + 86400,
  String? submittedInvoice,
}) => BondClaim(
  orderId: 'order-1',
  nodePubkey: 'node-a',
  amountSats: BigInt.from(1500),
  slashedAt: intToPlatformInt64(_now - 3600),
  deadlineAt: intToPlatformInt64(deadlineAt),
  phase: phase,
  submittedInvoice: submittedInvoice,
  fiatCode: 'USD',
  fiatAmount: 100,
  paymentMethod: 'Wire',
  updatedAt: intToPlatformInt64(_now - 60),
);

Future<void> _pump(
  WidgetTester tester, {
  required BondClaim? claim,
  bool walletConnected = false,
  Future<void> Function(String, String)? submit,
  Future<String> Function(int)? generateInvoice,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        isWalletConnectedProvider.overrideWithValue(walletConnected),
        bondClaimProvider.overrideWith((ref, id) async => claim),
        bondClaimUpdatesProvider.overrideWith(
          (ref) => const Stream<BondClaimUpdate>.empty(),
        ),
        if (submit != null)
          submitBondPayoutInvoiceProvider.overrideWithValue(submit),
      ],
      child: MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BondPayoutInvoiceScreen(
          orderId: 'order-1',
          generateInvoice: generateInvoice,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Finder _byId(String id) =>
    find.byWidgetPredicate((w) => w is AutomationId && w.id == id);

String? _label(WidgetTester tester, String id) =>
    tester.widget<AutomationId>(_byId(id)).label;

void main() {
  final clockAt = Clock.fixed(
    DateTime.fromMillisecondsSinceEpoch(_now * 1000, isUtc: true),
  );

  testWidgets('a pending claim shows the share, the deadline and the form', (
    tester,
  ) async {
    await withClock(clockAt, () async {
      await _pump(tester, claim: _claim());
      expect(find.text('1500'), findsOneWidget);
      expect(_label(tester, AutomationIds.bondClaimAmount), '1500');
      expect(_label(tester, AutomationIds.bondClaimStatus), 'pending');
      expect(find.textContaining('Claim before'), findsOneWidget);
      expect(find.textContaining('forfeited in your favour'), findsOneWidget);
      expect(_byId(AutomationIds.bondClaimText), findsOneWidget);
      // Nothing typed: nothing to send.
      final button = tester.widget<AutomationId>(
        _byId(AutomationIds.bondClaimSubmit),
      );
      expect(button, isNotNull);
    });
  });

  testWidgets('a typed invoice goes through the submission seam', (
    tester,
  ) async {
    final sent = <String>[];
    await withClock(clockAt, () async {
      await _pump(
        tester,
        claim: _claim(),
        submit: (orderId, invoice) async => sent.add('$orderId:$invoice'),
      );
      await tester.enterText(find.byType(TextField), 'lnbc15u1claim');
      await tester.pump();
      await tester.ensureVisible(find.text('Send invoice'));
      await tester.tap(find.text('Send invoice'));
      await tester.pump();
      await tester.pump();
      expect(sent, ['order-1:lnbc15u1claim']);
      expect(find.text('Invoice sent to the node'), findsOneWidget);
    });
  });

  testWidgets('a refused submission keeps the form with the reason', (
    tester,
  ) async {
    await withClock(clockAt, () async {
      await _pump(
        tester,
        claim: _claim(),
        submit: (_, _) async => throw Exception('InvoiceAmountMismatch'),
      );
      await tester.enterText(find.byType(TextField), 'lnbc1wrong');
      await tester.pump();
      await tester.ensureVisible(find.text('Send invoice'));
      await tester.tap(find.text('Send invoice'));
      await tester.pump();
      await tester.pump();
      expect(
        find.text('The invoice must be for exactly the share shown.'),
        findsOneWidget,
      );
      expect(_byId(AutomationIds.bondClaimText), findsOneWidget);
    });
  });

  testWidgets('a connected wallet creates the invoice for the share', (
    tester,
  ) async {
    final sent = <String>[];
    await withClock(clockAt, () async {
      await _pump(
        tester,
        claim: _claim(),
        walletConnected: true,
        submit: (orderId, invoice) async => sent.add(invoice),
        // Never completes: the widget stays on its spinner, which is
        // enough to prove the branch.
        generateInvoice: (_) => Completer<String>().future,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(NwcInvoiceWidget), findsOneWidget);
      expect(_byId(AutomationIds.bondClaimText), findsNothing);
    });
  });

  testWidgets('a submitted claim waits, showing the invoice sent', (
    tester,
  ) async {
    await withClock(clockAt, () async {
      await _pump(
        tester,
        claim: _claim(
          phase: BondClaimPhase.submitted,
          submittedInvoice: 'lnbc15u1claim',
        ),
      );
      expect(find.text('Invoice sent'), findsOneWidget);
      expect(find.text('lnbc15u1claim'), findsOneWidget);
      expect(_label(tester, AutomationIds.bondClaimStatus), 'submitted');
      expect(find.byType(TextField), findsNothing);
    });
  });

  testWidgets('an acknowledged claim reads as a payout in progress', (
    tester,
  ) async {
    await withClock(clockAt, () async {
      await _pump(tester, claim: _claim(phase: BondClaimPhase.acknowledged));
      expect(find.text('Payout in progress'), findsOneWidget);
      expect(_label(tester, AutomationIds.bondClaimStatus), 'acknowledged');
    });
  });

  testWidgets('a paid claim reads as paid', (tester) async {
    await withClock(clockAt, () async {
      await _pump(tester, claim: _claim(phase: BondClaimPhase.completed));
      expect(find.text('Paid'), findsOneWidget);
      expect(find.textContaining('sats reached your wallet.'), findsOneWidget);
      expect(_label(tester, AutomationIds.bondClaimStatus), 'completed');
    });
  });

  testWidgets('a pending claim past its window reads as expired', (
    tester,
  ) async {
    await withClock(clockAt, () async {
      await _pump(tester, claim: _claim(deadlineAt: _now - 1));
      expect(find.text('The claim window ended'), findsOneWidget);
      expect(_label(tester, AutomationIds.bondClaimStatus), 'expired');
      expect(find.byType(TextField), findsNothing);
    });
  });

  testWidgets('no claim for the order says so', (tester) async {
    await _pump(tester, claim: null);
    expect(find.text('No claim found for this order.'), findsOneWidget);
  });
}
