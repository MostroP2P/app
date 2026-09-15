import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/order/widgets/invoice_input_field.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// `design_handoff_campo_factura`: the empty field pulses until it first
/// gets focus or content, never under reduced motion; `Paste` only exists
/// when there is something to paste; the idle filled field cuts the invoice
/// and a long press shows it whole.
const _invoice =
    'lnbc1850n1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3'
    'zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7';

class _Harness {
  final controller = TextEditingController();
  final focus = FocusNode();
  var pastes = 0;
  var scans = 0;

  void dispose() {
    controller.dispose();
    focus.dispose();
  }
}

Future<_Harness> _pump(
  WidgetTester tester, {
  bool canPaste = true,
  bool reduceMotion = false,
  int? validSats,
  bool isAddress = false,
}) async {
  final h = _Harness();
  addTearDown(h.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder:
          (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reduceMotion),
            child: child!,
          ),
      home: Scaffold(
        body: Column(
          children: [
            InvoiceInputField(
              controller: h.controller,
              focusNode: h.focus,
              onChanged: () {},
              onPaste: canPaste ? () => h.pastes++ : null,
              onScan: () => h.scans++,
              validSats: validSats,
              isValid: validSats != null || isAddress,
              isAddress: isAddress,
            ),
            // Somewhere else to put the focus.
            const TextField(key: Key('other')),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  return h;
}

/// The field's outer border colour right now.
Color _border(WidgetTester tester) {
  final box = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(InvoiceInputField),
          matching: find.byType(Container),
        )
        .first,
  );
  return ((box.decoration! as BoxDecoration).border! as Border).top.color;
}

/// Whether the border moves over half a pulse. A focused text field blinks
/// its own cursor, so running animations cannot tell the pulse apart.
Future<bool> _pulsing(WidgetTester tester) async {
  final before = _border(tester);
  await tester.pump(const Duration(milliseconds: 600));
  return _border(tester) != before;
}

void main() {
  testWidgets('the empty field pulses and asks to paste', (tester) async {
    await _pump(tester);

    expect(await _pulsing(tester), isTrue);
    expect(find.text('PASTE YOUR INVOICE HERE'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
  });

  testWidgets('the pulse stops on focus and does not come back', (
    tester,
  ) async {
    final h = await _pump(tester);

    h.focus.requestFocus();
    await tester.pump();
    expect(await _pulsing(tester), isFalse);

    await tester.tap(find.byKey(const Key('other')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    expect(await _pulsing(tester), isFalse);
    // Still empty: the label keeps asking, without the pulse.
    expect(find.text('PASTE YOUR INVOICE HERE'), findsOneWidget);
  });

  testWidgets('reduced motion never pulses', (tester) async {
    await _pump(tester, reduceMotion: true);

    expect(tester.hasRunningAnimations, isFalse);
    expect(await _pulsing(tester), isFalse);
  });

  testWidgets('a valid address is labelled and announced as an address', (
    tester,
  ) async {
    final h = await _pump(tester, isAddress: true);
    final semantics = tester.ensureSemantics();

    h.controller.text = 'satoshi@example.com';
    await tester.pump();

    expect(find.text('LIGHTNING ADDRESS'), findsOneWidget);
    expect(find.text('LIGHTNING INVOICE'), findsNothing);
    expect(find.bySemanticsLabel('Lightning address'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('without anything to paste, scan takes the row', (tester) async {
    final h = await _pump(tester, canPaste: false);

    expect(find.text('Paste'), findsNothing);
    await tester.tap(find.text('Scan'));
    expect(h.scans, 1);
  });

  testWidgets('filled and idle: amount beside the label, replace, whole '
      'invoice on long press', (tester) async {
    final h = await _pump(tester, validSats: 1850);

    h.controller.text = _invoice;
    await tester.pump();

    expect(await _pulsing(tester), isFalse);
    expect(find.text('LIGHTNING INVOICE'), findsOneWidget);
    expect(find.text('1850 sats'), findsOneWidget);
    await tester.tap(find.text('Replace'));
    expect(h.pastes, 1);

    final cutFinder = find.byWidgetPredicate(
      (w) =>
          w is RichText && w.maxLines == 3 && w.text.toPlainText() == _invoice,
    );
    final cut = tester.widget<RichText>(cutFinder);
    expect(cut.overflow, TextOverflow.ellipsis);
    // The controller keeps the whole string; only the drawing is cut.
    expect(h.controller.text, _invoice);

    await tester.longPress(cutFinder);
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
  });
}
