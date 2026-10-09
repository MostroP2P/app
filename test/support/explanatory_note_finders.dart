import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asserts that [text] is rendered as the explanatory note DS-CMP-25
/// describes: inside a box at radius 12 with a hairline border and padding
/// 14 × 12, led by a 14-dp [icon], and never inside a widget matched by
/// [notInside] (the screen's action bar).
///
/// Reads the rendered widgets rather than a class name, so it holds for any
/// widget that draws the note this way.
void expectExplanatoryNote(
  WidgetTester tester,
  Finder text, {
  IconData icon = Icons.lock_outline,
  Finder? notInside,
}) {
  expect(text, findsOneWidget);
  final box = find.ancestor(
    of: text,
    matching: find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final decoration = w.decoration;
      return decoration is BoxDecoration &&
          decoration.borderRadius == BorderRadius.circular(12) &&
          decoration.border != null &&
          w.padding == const EdgeInsets.symmetric(horizontal: 14, vertical: 12);
    }),
  );
  expect(box, findsOneWidget, reason: 'the note is a 12-radius box, 14 × 12');
  final glyph = find.descendant(of: box, matching: find.byIcon(icon));
  expect(glyph, findsOneWidget, reason: 'the note leads with its icon');
  expect(tester.widget<Icon>(glyph).size, 14);
  if (notInside != null) {
    expect(
      find.ancestor(of: text, matching: notInside),
      findsNothing,
      reason: 'the note sits in the body, not in the action bar',
    );
  }
}
