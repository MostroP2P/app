import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/account/widgets/funds_at_risk_dialog.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/src/rust/api/types.dart';

Future<void> _pump(WidgetTester tester, List<FundsAtRisk> risks) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: FundsAtRiskDialog(risks: risks)),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a Cashu balance says only these words bring it back', (
    tester,
  ) async {
    // The wallet's proof store opens only under this identity: replacing it
    // strands the ecash unless the words are kept.
    await _pump(tester, [
      FundsAtRisk(
        orderId: '',
        reason: FundsAtRiskReason.cashuWalletBalance,
        amountSats: BigInt.from(2100),
      ),
    ]);

    expect(find.text('Ecash in the Cashu wallet'), findsOneWidget);
    expect(find.text("Only this user's words bring it back"), findsOneWidget);
    expect(find.textContaining('2,100'), findsOneWidget);
    expect(find.textContaining('Order'), findsNothing);
  });

  testWidgets('open Cashu invoices are named, paid or not', (tester) async {
    // Invoices not minted yet live only in this identity's proof store: one
    // paid while the app was closed reads unpaid until its mint is asked.
    await _pump(tester, [
      const FundsAtRisk(
        orderId: '',
        reason: FundsAtRiskReason.cashuPendingInvoices,
        amountSats: null,
      ),
    ]);

    expect(find.text('Cashu invoices that may have been paid'), findsOneWidget);
    expect(find.text("Only this user's words bring it back"), findsOneWidget);
    expect(find.textContaining('Order'), findsNothing);
    // None known paid yet: no figure to show.
    expect(find.textContaining(RegExp(r'\d')), findsNothing);
  });

  testWidgets('the sats known paid are shown with the invoices', (
    tester,
  ) async {
    await _pump(tester, [
      FundsAtRisk(
        orderId: '',
        reason: FundsAtRiskReason.cashuPendingInvoices,
        amountSats: BigInt.from(210),
      ),
    ]);

    expect(find.textContaining('210'), findsOneWidget);
  });
}
