import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/features/order/widgets/order_detail_cards.dart';

/// The amount a screen is about (DS-CMP-23): a sentence-case label over the
/// figure, its unit on the figure's baseline, left-aligned on a card. The
/// take-order screen, the invoice screens and the bond screens all build it,
/// so the step that shows an amount looks the same wherever it falls.
class HeroAmountCard extends StatelessWidget {
  const HeroAmountCard({
    super.key,
    required this.label,
    required this.figure,
    required this.unit,
    this.semanticsLabel,
    this.automationId,
    this.automationLabel,
    this.second,
    this.footer,
    this.child,
  });

  /// `You pay`, `To pay`: what the figure is, in sentence case.
  final String label;

  /// `1,000`, `500 – 2,500`, `252`.
  final String figure;

  /// `ARS`, `sats`.
  final String unit;

  /// Announces the figure and its unit as one label (`252 satoshis to pay`).
  final String? semanticsLabel;
  final String? automationId;
  final String? automationLabel;

  /// The amount traded for this one, stacked under a divider.
  final HeroAmountSecond? second;

  /// The context line closing the card ([HeroContextLine], or a line of
  /// the screen's own with a styled figure in it).
  final Widget? footer;

  /// A QR, under everything else in the same card.
  final Widget? child;

  static const double _full = 38;
  static const double _compact = 26;
  static const double _unitGap = 6;

  TextStyle _figureStyle(double size, Color color) => TextStyle(
    fontFamily: AppFonts.figures,
    fontSize: size,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.02 * size,
    height: 1.1,
    color: color,
  );

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final unitStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: book.textSecondary,
    );

    Widget row(double size) => Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(figure, style: _figureStyle(size, book.textPrimary)),
        ),
        const SizedBox(width: _unitGap),
        Text(unit, style: unitStyle),
      ],
    );

    // 38 when the figure and its unit fit on the card's line, else 26
    // (DS-CMP-23), chosen at layout from the row's intrinsic width: the
    // invoice screens lay the card out under an IntrinsicHeight, which a
    // LayoutBuilder cannot answer.
    Widget amount = _FitChoice(full: row(_full), compact: row(_compact));
    final announced = semanticsLabel;
    if (announced != null) {
      amount = Semantics(
        label: announced,
        excludeSemantics: true,
        child: amount,
      );
    }
    final id = automationId;
    if (id != null) {
      amount = amount.withAutomationId(id, label: automationLabel);
    }

    final next = second;
    return OrderDetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeroLabel(label),
          const SizedBox(height: 6),
          amount,
          if (next != null) ...[
            const SizedBox(height: 12),
            Divider(height: 1, thickness: 1, color: book.border),
            const SizedBox(height: 12),
            _HeroLabel(next.label),
            const SizedBox(height: 4),
            next.value,
          ],
          if (footer != null) ...[const SizedBox(height: 8), footer!],
          if (child != null) ...[
            const SizedBox(height: 14),
            Center(child: child),
          ],
        ],
      ),
    );
  }
}

/// The second amount of a hero: what the first is traded for.
class HeroAmountSecond {
  const HeroAmountSecond({required this.label, required this.value});

  /// `You receive`, in sentence case.
  final String label;

  /// Usually a [HeroSecondFigure].
  final Widget value;
}

/// `≈ 8,420 sats` under the first amount: [figure] at 19 in lime, the rest
/// of [sentence] (the unit, a `from`) at 13. The figure is found inside the
/// localized sentence, so each locale keeps its own word order.
class HeroSecondFigure extends StatelessWidget {
  const HeroSecondFigure({
    super.key,
    required this.sentence,
    required this.figure,
  });

  final String sentence;
  final String figure;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Text.rich(
      TextSpan(
        children: figureSpans(
          sentence,
          figure,
          TextStyle(
            fontFamily: AppFonts.figures,
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: book.limeInk,
          ),
        ),
      ),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: book.textSecondary,
      ),
    );
  }
}

/// A plain context line closing a hero: `≈ 312 ARS · Bitcoin Bolivia`.
class HeroContextLine extends StatelessWidget {
  const HeroContextLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        height: 1.5,
        color: OrderBookPalette.of(context).textSecondary,
      ),
    );
  }
}

/// Shows [full] when its natural width fits the line, else [compact]. The
/// choice is made at layout and answers intrinsic sizes, so it works under
/// an `IntrinsicHeight`. Only the chosen child is painted, hit-tested,
/// announced and found by test finders (as `IndexedStack` does).
class _FitChoice extends MultiChildRenderObjectWidget {
  _FitChoice({required Widget full, required Widget compact})
    : super(children: [full, compact]);

  @override
  _RenderFitChoice createRenderObject(BuildContext context) =>
      _RenderFitChoice();

  @override
  MultiChildRenderObjectElement createElement() => _FitChoiceElement(this);
}

class _FitChoiceElement extends MultiChildRenderObjectElement {
  _FitChoiceElement(super.widget);

  @override
  void debugVisitOnstageChildren(ElementVisitor visitor) {
    final chosen = (renderObject as _RenderFitChoice).chosen;
    if (children.length > chosen) visitor(children.elementAt(chosen));
  }
}

class _FitChoiceParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderFitChoice extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FitChoiceParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FitChoiceParentData> {
  /// 0 for the full figure, 1 for the compact one.
  int chosen = 0;

  RenderBox get _full => firstChild!;
  RenderBox get _compact => lastChild!;
  RenderBox get _shown => chosen == 0 ? _full : _compact;

  RenderBox _pick(double width) =>
      _full.getMaxIntrinsicWidth(double.infinity) <= width ? _full : _compact;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FitChoiceParentData) {
      child.parentData = _FitChoiceParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _compact.getMinIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _full.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) =>
      _pick(width).getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _pick(width).getMaxIntrinsicHeight(width);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _pick(constraints.maxWidth).getDryLayout(constraints);

  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => _pick(constraints.maxWidth).getDryBaseline(constraints, baseline);

  @override
  void performLayout() {
    chosen = identical(_pick(constraints.maxWidth), _full) ? 0 : 1;
    // Both are laid out so neither is left dirty; only the chosen one shows.
    _full.layout(constraints, parentUsesSize: chosen == 0);
    _compact.layout(constraints, parentUsesSize: chosen == 1);
    size = _shown.size;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      _shown.getDistanceToActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) =>
      context.paintChild(_shown, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      _shown.hitTest(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) =>
      visitor(_shown);
}

class _HeroLabel extends StatelessWidget {
  const _HeroLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: OrderBookPalette.of(context).textSecondary,
      ),
    );
  }
}
