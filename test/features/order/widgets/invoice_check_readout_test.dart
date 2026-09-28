import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';
import 'package:mostro/features/order/widgets/invoice_widgets.dart';

/// `invoice.check` is the readout Mortsom asserts the app's own verdict on
/// (`docs/automation-contract.md`). The unit rules live in
/// `invoice_rules_test.dart`; what matters here is that the word survives the
/// trip to the semantics node the accessibility bridge exposes — the row
/// wraps its content in a `Semantics(liveRegion: true)` of its own, and a
/// merge that took the visible sentence instead would hand automation
/// translated copy.
void main() {
  Future<void> pumpRow(WidgetTester tester, InvoiceCheck check,
      {required String sentence}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: invoiceCheckRow(check: check, sentence: sentence),
        ),
      ),
    );
  }

  testWidgets('a refused invoice reads its word, not its sentence',
      (tester) async {
    // The sentence is Spanish on purpose: a harness reading the label must
    // get `expires-too-soon` whatever locale the app is in.
    await pumpRow(
      tester,
      const InvoiceCheckError(
        InvoiceProblem.expiresTooSoon,
        minRemainingSecs: 300,
      ),
      sentence: 'La factura vence en menos de 5 minutos',
    );

    expect(
      tester.getSemantics(find.byType(InvoiceValidationRow)),
      isSemantics(
        identifier: AutomationIds.invoiceCheck,
        label: 'expires-too-soon',
      ),
    );
  });

  testWidgets('an accepted invoice reads valid', (tester) async {
    await pumpRow(
      tester,
      const InvoiceCheckValid(250),
      sentence: 'Factura válida por 250 sats',
    );

    expect(
      tester.getSemantics(find.byType(InvoiceValidationRow)),
      isSemantics(identifier: AutomationIds.invoiceCheck, label: 'valid'),
    );
  });
}
