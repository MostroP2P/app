import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/widgets/nwc_invoice_widget.dart';

/// With a wallet connected the buyer invoice is generated and submitted in
/// one action, so this widget is the only place the invoice exists in the UI.
/// What it exposes — and what it must refuse to expose after a failure — is
/// the whole of its contract.
void main() {
  const invoice = 'lnbc1000n1buyerinvoice';

  Future<void> pump(
    WidgetTester tester, {
    required Future<String> Function(int) generate,
    required ValueChanged<String> onConfirmed,
    required VoidCallback onFallback,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: NwcInvoiceWidget(
            amountSats: 1000,
            generateInvoice: generate,
            onInvoiceConfirmed: onConfirmed,
            onFallbackToManual: onFallback,
          ),
        ),
      ),
    );
  }

  testWidgets('exposes the submitted invoice while the send is still in flight',
      (tester) async {
    // The screen leaves only once the daemon answers, so the readout has to
    // survive the wait — that is the window automation reads it in.
    final sending = Completer<void>();
    var fellBack = false;

    await pump(
      tester,
      generate: (_) async => invoice,
      onConfirmed: (_) => sending.future,
      onFallback: () => fellBack = true,
    );
    await tester.pump();

    expect(
      tester.getSemantics(find.byType(NwcInvoiceWidget)),
      containsSemantics(
        identifier: AutomationIds.invoiceNwcText,
        label: invoice,
      ),
    );
    expect(fellBack, isFalse);

    sending.complete();
    await tester.pump();
  });

  testWidgets('falls back to the manual form when the wallet generates none',
      (tester) async {
    var fellBack = false;
    String? confirmed;

    await pump(
      tester,
      generate: (_) async => throw StateError('no wallet'),
      onConfirmed: (i) => confirmed = i,
      onFallback: () => fellBack = true,
    );
    await tester.pump();

    expect(fellBack, isTrue);
    expect(confirmed, isNull);
    expect(
      find.text(
        AppLocalizations.of(
          tester.element(find.byType(NwcInvoiceWidget)),
        ).unableToGenerateInvoice,
      ),
      findsOneWidget,
    );
  });

  testWidgets('reports the error rather than a submission that never happened',
      (tester) async {
    // Generating succeeded and submitting threw: nothing reached the daemon,
    // so a readout here would name an invoice no one is going to pay.
    var fellBack = false;

    await pump(
      tester,
      generate: (_) async => invoice,
      onConfirmed: (_) => throw StateError('send failed'),
      onFallback: () => fellBack = true,
    );
    await tester.pump();

    expect(fellBack, isTrue);
    expect(
      find.bySemanticsLabel(invoice),
      findsNothing,
      reason: 'a failed submission must not leave the invoice readable',
    );
    expect(
      find.text(
        AppLocalizations.of(
          tester.element(find.byType(NwcInvoiceWidget)),
        ).unableToGenerateInvoice,
      ),
      findsOneWidget,
    );
  });
}
