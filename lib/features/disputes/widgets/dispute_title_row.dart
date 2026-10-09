import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Space between the title and the chip beside it.
const double _gapBeside = 8;

/// Space between the title and the chip under it.
const double _gapUnder = 6;

/// The dispute card's title with its status chip (#680): side by side, the
/// chip at its natural width on the end, when the title's longest word still
/// fits beside it; otherwise the chip goes under the title, so the title has
/// the whole row and no word of it is broken.
///
/// Decided by measuring both — the title's min-intrinsic width is its longest
/// word at the current text size, and the chip's max-intrinsic width its
/// natural one — so the normal-size look stays side by side, and a long
/// translation at 2x text on a narrow phone stacks.
class DisputeTitleRow extends MultiChildRenderObjectWidget {
  DisputeTitleRow({super.key, required Widget title, required Widget chip})
    : super(children: [title, chip]);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      RenderDisputeTitleRow(textDirection: Directionality.of(context));

  @override
  void updateRenderObject(
    BuildContext context,
    RenderDisputeTitleRow renderObject,
  ) {
    renderObject.textDirection = Directionality.of(context);
  }
}

class _TitleRowParentData extends ContainerBoxParentData<RenderBox> {}

/// The render object of [DisputeTitleRow].
class RenderDisputeTitleRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TitleRowParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TitleRowParentData> {
  RenderDisputeTitleRow({required TextDirection textDirection})
    : _textDirection = textDirection;

  TextDirection get textDirection => _textDirection;
  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (_textDirection == value) return;
    _textDirection = value;
    markNeedsLayout();
  }

  RenderBox get _title => firstChild!;
  RenderBox get _chip => childAfter(firstChild!)!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TitleRowParentData) {
      child.parentData = _TitleRowParentData();
    }
  }

  /// Whether the title's longest word fits beside the chip in [width].
  bool _fitsBeside(double width) =>
      _title.getMinIntrinsicWidth(double.infinity) +
          _gapBeside +
          _chip.getMaxIntrinsicWidth(double.infinity) <=
      width;

  @override
  double computeMinIntrinsicWidth(double height) => math.max(
    _title.getMinIntrinsicWidth(height),
    _chip.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _title.getMaxIntrinsicWidth(height) +
      _gapBeside +
      _chip.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => _heightFor(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _heightFor(width);

  double _heightFor(double width) {
    if (!width.isFinite) {
      return math.max(
        _title.getMaxIntrinsicHeight(width),
        _chip.getMaxIntrinsicHeight(width),
      );
    }
    final chipWidth = math.min(
      _chip.getMaxIntrinsicWidth(double.infinity),
      width,
    );
    if (_fitsBeside(width)) {
      return math.max(
        _title.getMaxIntrinsicHeight(width - chipWidth - _gapBeside),
        _chip.getMaxIntrinsicHeight(chipWidth),
      );
    }
    return _title.getMaxIntrinsicHeight(width) +
        _gapUnder +
        _chip.getMaxIntrinsicHeight(chipWidth);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final width = constraints.maxWidth;
    return constraints.constrain(Size(width, _heightFor(width)));
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final rtl = textDirection == TextDirection.rtl;
    final chipWidth = math.min(
      _chip.getMaxIntrinsicWidth(double.infinity),
      width,
    );
    final titleData = _title.parentData! as _TitleRowParentData;
    final chipData = _chip.parentData! as _TitleRowParentData;

    if (_fitsBeside(width)) {
      final titleWidth = width - chipWidth - _gapBeside;
      _title.layout(
        BoxConstraints.tightFor(width: titleWidth),
        parentUsesSize: true,
      );
      _chip.layout(BoxConstraints(maxWidth: chipWidth), parentUsesSize: true);
      titleData.offset = Offset(rtl ? width - titleWidth : 0, 0);
      chipData.offset = Offset(rtl ? 0 : width - _chip.size.width, 0);
      size = constraints.constrain(
        Size(width, math.max(_title.size.height, _chip.size.height)),
      );
      return;
    }

    _title.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    _chip.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    titleData.offset = Offset.zero;
    final chipTop = _title.size.height + _gapUnder;
    chipData.offset = Offset(rtl ? width - _chip.size.width : 0, chipTop);
    size = constraints.constrain(Size(width, chipTop + _chip.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
