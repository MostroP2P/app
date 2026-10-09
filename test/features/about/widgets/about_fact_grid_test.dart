import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/widgets/about_widgets.dart';

import '../../../support/load_app_fonts.dart';

/// The six facts of 12a's node card, as a German node with a wide range
/// shows them. The sign and the hour unit follow a non-breaking space, as
/// `aboutFeeValue` and `aboutHoursShort` write them.
const _facts = [
  AboutFact('Mindestbetrag', '100.000', unit: 'Sats'),
  AboutFact('Höchstbetrag', '10.000.000', unit: 'Sats'),
  AboutFact('Gebühr', '0,6\u00A0%'),
  AboutFact('Einlage', '5\u00A0%'),
  AboutFact('Währungen', 'ARS, EUR, USD'),
  AboutFact('Ablauf', '24\u00A0h'),
];

/// The German card on a node whose deposit has a wide floor.
final _floored = [
  for (final fact in _facts)
    fact.label == 'Einlage'
        ? const AboutFact('Einlage', '1,5\u00A0%', unit: 'mind. 100.000 Sats')
        : fact,
];

/// The same card in English, at the widest figures a node sends.
const _wideEnglish = [
  AboutFact('Min order', '1,000,000', unit: 'sats'),
  AboutFact('Max order', '10,000,000', unit: 'sats'),
  AboutFact('Fee', '0.6%'),
  AboutFact('Deposit', '1.5%', unit: 'min. 10,000 sats'),
  AboutFact('Currencies', 'ARS, EUR +5'),
  AboutFact('Expiration', '24\u00A0h'),
];

/// The German card while the node has not answered.
final _loading = [for (final fact in _facts) AboutFact(fact.label, '—')];

/// Pumps the grid as 12a lays it out on a [screenWidth] phone: inside the
/// page's viewport and SafeArea, in a card with the node card's inset.
Future<void> _pump(
  WidgetTester tester, {
  required double screenWidth,
  List<AboutFact> facts = _facts,
  double textScale = 1,
  bool boldText = false,
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  tester.view.physicalSize = Size(screenWidth, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildDarkTheme(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(screenWidth, 1600),
          padding: padding,
          textScaler: TextScaler.linear(textScale),
          boldText: boldText,
        ),
        child: Scaffold(
          body: SafeArea(
            child: AboutFillViewport(
              children: [
                AboutCard(
                  padding: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: aboutCardInset,
                    ),
                    child: AboutFactGrid(
                      facts: facts,
                      inset: aboutCardBorder + aboutCardInset,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// How many cells share the first row.
int _firstRowCount(WidgetTester tester, List<AboutFact> facts) {
  final top = tester.getTopLeft(find.text(facts.first.label)).dy;
  return facts
      .where((fact) => tester.getTopLeft(find.text(fact.label)).dy == top)
      .length;
}

/// Lines [text]'s paragraph takes.
int _lines(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.text(text, findRichText: true).first,
  );
  final line = paragraph.getFullHeightForCaret(const TextPosition(offset: 0));
  return (paragraph.size.height / line).round();
}

/// What in the grid does not read whole: a label cut by its ellipsis, or a
/// piece of a value or unit (the text between two breaking spaces) that
/// spans two lines.
List<String> _broken(WidgetTester tester) => [
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.descendant(
      of: find.byType(AboutFactGrid),
      matching: find.byType(RichText),
    ),
  ))
    ..._brokenIn(paragraph),
];

List<String> _brokenIn(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  if (paragraph.didExceedMaxLines) return [text];
  final broken = <String>[];
  var start = 0;
  for (final piece in text.split(' ')) {
    final end = start + piece.length;
    final tops = {
      for (final box in paragraph.getBoxesForSelection(
        TextSelection(baseOffset: start, extentOffset: end),
      ))
        box.top.round(),
    };
    if (tops.length > 1) broken.add(piece);
    start = end + 1;
  }
  return broken;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('three to a row on a common phone', (tester) async {
    await _pump(tester, screenWidth: 393);

    expect(_firstRowCount(tester, _facts), 3);
    expect(_broken(tester), isEmpty);
  });

  testWidgets('a list wraps between its codes, at full size', (tester) async {
    await _pump(tester, screenWidth: 393);

    expect(_lines(tester, 'ARS, EUR, USD'), 2);
    expect(find.byType(FittedBox), findsNothing);
  });

  testWidgets('two to a row when a figure would split in three', (
    tester,
  ) async {
    await _pump(tester, screenWidth: 320);

    expect(_firstRowCount(tester, _facts), 2);
    expect(_broken(tester), isEmpty);
  });

  testWidgets('a floor goes whole: two to a row where it does not fit three', (
    tester,
  ) async {
    await _pump(tester, screenWidth: 393, facts: _floored);

    expect(_firstRowCount(tester, _floored), 2);
    expect(_broken(tester), isEmpty);
  });

  testWidgets('one per line at 2x on a 320 dp phone, nothing split', (
    tester,
  ) async {
    await _pump(tester, screenWidth: 320, textScale: 2);

    expect(tester.takeException(), isNull);
    expect(_firstRowCount(tester, _facts), 1);
    expect(_broken(tester), isEmpty);
  });

  testWidgets('no figure or unit splits and no label is cut, at any width', (
    tester,
  ) async {
    for (final scale in const [1.0, 1.15, 1.3]) {
      for (var width = 320.0; width <= 430; width++) {
        for (final facts in [_facts, _floored, _wideEnglish]) {
          await _pump(
            tester,
            screenWidth: width,
            textScale: scale,
            facts: facts,
          );
          expect(_broken(tester), isEmpty, reason: '$width dp at ${scale}x');
        }
      }
    }
  });

  testWidgets('bold text is measured bold', (tester) async {
    await _pump(tester, screenWidth: 360, facts: _wideEnglish, boldText: true);

    expect(_broken(tester), isEmpty);
  });

  testWidgets('the system insets narrow the grid', (tester) async {
    // Landscape split screen next to a 48 dp side navigation bar.
    await _pump(
      tester,
      screenWidth: 400,
      facts: _wideEnglish,
      padding: const EdgeInsets.only(right: 48),
    );

    expect(_broken(tester), isEmpty);
  });

  testWidgets('the labels read whole while the node loads', (tester) async {
    for (final width in const [320.0, 360.0, 393.0]) {
      await _pump(tester, screenWidth: width, facts: _loading);

      expect(_broken(tester), isEmpty, reason: '$width dp');
    }
  });

  testWidgets('a screen reader reads each cell whole', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, screenWidth: 360, facts: _wideEnglish);

    expect(
      tester.getSemantics(find.text('Max order')).label,
      'Max order\n10,000,000 sats',
    );
    expect(tester.getSemantics(find.text('Fee')).label, 'Fee\n0.6%');
    semantics.dispose();
  });
}
