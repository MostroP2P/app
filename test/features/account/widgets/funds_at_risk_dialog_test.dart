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
}
