import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A `MaterialApp.builder` that renders the app at [scale] times the text
/// size, as the system setting would.
TransitionBuilder textScaleBuilder(double scale) =>
    (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    );

/// Whether [paragraph] broke a word across two lines.
bool breaksAWord(RenderParagraph paragraph) {
  final text = paragraph.text.toPlainText();
  for (final word in RegExp(r'\S+').allMatches(text)) {
    final tops =
        paragraph
            .getBoxesForSelection(
              TextSelection(baseOffset: word.start, extentOffset: word.end),
            )
            .map((box) => box.top)
            .toSet();
    if (tops.length > 1) return true;
  }
  return false;
}
