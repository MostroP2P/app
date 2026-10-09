import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mostro/core/about_palette.dart';
import 'package:mostro/core/app_theme.dart';
import 'package:mostro/features/about/models/about_rules.dart';
import 'package:mostro/features/settings/providers/mostro_nodes_provider.dart'
    show truncatePubkey;

/// Building blocks shared by About (12a) and Technical data (12b) of
/// `design_handoff_acerca_de`.

const double aboutSidePadding = 18;
const double aboutBlockGap = 10;
const double aboutCardRadius = 18;

/// An About card's border, which also insets what the card holds.
const double aboutCardBorder = 1;

/// How far an About card's content sits from its border, on each side.
const double aboutCardInset = 14;

/// Minimum hit target of a copy icon, however small the icon draws.
const double aboutMinTapTarget = 44;

/// How long a copy icon stays a check after copying.
const Duration copyFeedbackDuration = Duration(milliseconds: 1200);

// ── Layout ────────────────────────────────────────────────────────────────────

/// A column that fills the viewport so [footer] sits at the bottom, and
/// scrolls instead of shrinking text when a translation does not fit.
class AboutFillViewport extends StatelessWidget {
  const AboutFillViewport({super.key, required this.children, this.footer});

  final List<Widget> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder:
          (context, constraints) => AboutContentWidth(
            width: constraints.maxWidth - 2 * aboutSidePadding,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                aboutSidePadding,
                0,
                aboutSidePadding,
                aboutSidePadding,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(
                    0,
                    constraints.maxHeight - aboutSidePadding,
                  ),
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0) const SizedBox(height: aboutBlockGap),
                        children[i],
                      ],
                      if (footer != null) ...[
                        const Spacer(),
                        const SizedBox(height: aboutBlockGap),
                        footer!,
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
    );
  }
}

/// The width of [AboutFillViewport]'s column: the space the screen's
/// SafeArea leaves, less the side padding. Published for the layouts that
/// size themselves by measuring text, which cannot use a `LayoutBuilder`
/// under the column's intrinsic height.
class AboutContentWidth extends InheritedWidget {
  const AboutContentWidth({
    super.key,
    required this.width,
    required super.child,
  });

  final double width;

  static double of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<AboutContentWidth>();
    assert(scope != null, 'No AboutFillViewport above this widget');
    return scope!.width;
  }

  @override
  bool updateShouldNotify(AboutContentWidth oldWidget) =>
      width != oldWidget.width;
}

/// `APPLICATION`, `MOSTRO`… above a card.
class AboutGroupHeader extends StatelessWidget {
  const AboutGroupHeader(this.title, {super.key, this.topPadding = 4});

  final String title;
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(2, topPadding, 2, 0),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: AboutPalette.of(context).groupHeader,
          ),
        ),
      ),
    );
  }
}

class AboutCard extends StatelessWidget {
  const AboutCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: aboutCardInset,
      vertical: 1,
    ),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: BorderRadius.circular(aboutCardRadius),
        border: Border.all(color: book.border, width: aboutCardBorder),
      ),
      child: child,
    );
  }
}

/// Rows of a card, a hairline under every row but the last.
class AboutRowList extends StatelessWidget {
  const AboutRowList({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final divider = BorderSide(color: AboutPalette.of(context).rowDivider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++)
          i == rows.length - 1
              ? rows[i]
              : DecoratedBox(
                decoration: BoxDecoration(border: Border(bottom: divider)),
                child: rows[i],
              ),
      ],
    );
  }
}

// ── Facts ─────────────────────────────────────────────────────────────────────

/// One figure of a node card: a short [label] over its [value], with an
/// optional [unit] beside the value (`sats`).
@immutable
class AboutFact {
  const AboutFact(this.label, this.value, {this.unit});

  final String label;
  final String value;
  final String? unit;
}

/// [facts] in rows of cells of one height: three to a row, or two, or one
/// per line, whichever is the most that lets every label read whole and every
/// value keep its size with no word split. A value may break between words
/// (`ARS, EUR,` / `USD`), never inside one (`10.000.000`, `0,6 %`, whose
/// space is a non-breaking one), and is never shrunk to fit. A unit is one
/// piece: beside the value, or whole on the line below.
///
/// The grid is as wide as [AboutContentWidth] less [inset] on each side: the
/// borders and paddings between the page's column and the grid.
class AboutFactGrid extends StatelessWidget {
  const AboutFactGrid({super.key, required this.facts, this.inset = 0});

  final List<AboutFact> facts;
  final double inset;

  static const _gap = 8.0;

  /// The most cells to a row, at most three, whose width holds every label,
  /// the widest word of every value and every unit whole, as the cells draw
  /// them.
  int _perRow(BuildContext context, double width) {
    final painter = TextPainter(
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
      maxLines: 1,
    );
    var widest = 0.0;
    void measure(String text, TextStyle style) {
      painter
        ..text = TextSpan(text: text, style: style)
        ..layout();
      widest = math.max(widest, painter.width);
    }

    final labelStyle = _AboutFactCell.labelStyle(context);
    final valueStyle = _AboutFactCell.valueStyle(context);
    final unitStyle = _AboutFactCell.unitStyle(context);
    for (final fact in facts) {
      measure(fact.label, labelStyle);
      for (final word in fact.value.split(' ')) {
        measure(word, valueStyle);
      }
      final unit = fact.unit;
      if (unit != null) measure(_AboutFactCell.unbroken(unit), unitStyle);
    }
    painter.dispose();
    for (var perRow = 3; perRow > 1; perRow--) {
      final cell =
          (width - _gap * (perRow - 1)) / perRow -
          _AboutFactCell.horizontalPadding * 2;
      if (widest <= cell) return perRow;
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    final perRow = _perRow(context, AboutContentWidth.of(context) - 2 * inset);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var start = 0; start < facts.length; start += perRow) ...[
          if (start > 0) const SizedBox(height: _gap),
          // One height for the row when a value or unit takes a second line.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = start; i < start + perRow; i++) ...[
                  if (i > start) const SizedBox(width: _gap),
                  Expanded(
                    child:
                        i < facts.length
                            ? _AboutFactCell(facts[i])
                            : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AboutFactCell extends StatelessWidget {
  const _AboutFactCell(this.fact);

  final AboutFact fact;

  static const horizontalPadding = 10.0;

  /// [style] as a [Text] here resolves it: over the inherited
  /// [DefaultTextStyle], in bold when the platform asks for bold text. The
  /// grid measures with the same style the cell draws.
  static TextStyle _resolved(BuildContext context, TextStyle style) {
    final resolved = DefaultTextStyle.of(context).style.merge(style);
    return MediaQuery.boldTextOf(context)
        ? resolved.merge(const TextStyle(fontWeight: FontWeight.bold))
        : resolved;
  }

  static TextStyle labelStyle(BuildContext context) => _resolved(
    context,
    TextStyle(fontSize: 10, color: OrderBookPalette.of(context).textSecondary),
  );

  static TextStyle valueStyle(BuildContext context) => _resolved(
    context,
    TextStyle(
      fontFamily: AppFonts.figures,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: OrderBookPalette.of(context).textStrong,
    ),
  );

  static TextStyle unitStyle(BuildContext context) => _resolved(
    context,
    TextStyle(fontSize: 11, color: OrderBookPalette.of(context).textSecondary),
  );

  /// [unit] with non-breaking spaces, so a line never splits it
  /// (`min. 1,000 sats`).
  static String unbroken(String unit) => unit.replaceAll(' ', '\u00A0');

  @override
  Widget build(BuildContext context) {
    final unit = fact.unit;
    // One node per cell, so a screen reader reads its label, value and unit
    // together rather than the grid row by row (DS-A11Y-3).
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: AboutPalette.of(context).cell,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fact.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: labelStyle(context),
            ),
            const SizedBox(height: 4),
            // One paragraph, so the unit sits on the figure's baseline when
            // both fit (DS-CMP-23), and the space before it is where the line
            // breaks otherwise.
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: fact.value, style: valueStyle(context)),
                  if (unit != null)
                    TextSpan(
                      text: ' ${unbroken(unit)}',
                      style: unitStyle(context),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Rows ──────────────────────────────────────────────────────────────────────

enum AboutRowTrailing {
  /// Opens outside the app.
  external,

  /// Stays in the app.
  chevron,
}

/// A 12a row: label, value flush right, and where the tap leads.
class AboutNavRow extends StatelessWidget {
  const AboutNavRow({
    super.key,
    required this.label,
    required this.value,
    required this.trailing,
    required this.onTap,
    this.icon,
    this.valueIsFigure = false,
  });

  final String label;
  final String value;
  final AboutRowTrailing trailing;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool valueIsFigure;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = AboutPalette.of(context);
    return Semantics(
      button: trailing == AboutRowTrailing.chevron,
      link: trailing == AboutRowTrailing.external,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: pal.icon),
                const SizedBox(width: 11),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: book.textStrong,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Text(
                value,
                style: TextStyle(
                  fontFamily: valueIsFigure ? AppFonts.figures : null,
                  fontSize: 12,
                  fontWeight: valueIsFigure ? FontWeight.w500 : null,
                  color: book.textMuted,
                ),
              ),
              const SizedBox(width: 11),
              trailing == AboutRowTrailing.external
                  ? Icon(
                    Icons.open_in_new_rounded,
                    size: 14,
                    color: pal.chevron,
                  )
                  : Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: pal.chevron,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A 12b row, shaped by [TechRow.style].
class TechRowTile extends StatelessWidget {
  const TechRowTile(
    this.row, {
    super.key,
    required this.copyTooltip,
    required this.copiedLabel,
  });

  final TechRow row;
  final String copyTooltip;
  final String copiedLabel;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = AboutPalette.of(context);
    final strongValue = TextStyle(
      fontFamily: row.style == TechValueStyle.text ? null : AppFonts.figures,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: book.textStrong,
    );

    switch (row.style) {
      case TechValueStyle.key:
      case TechValueStyle.wrapped:
        final isKey = row.style == TechValueStyle.key;
        final valueStyle = strongValue.copyWith(fontWeight: FontWeight.w500);
        return Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      style: TextStyle(fontSize: 11, color: book.textSecondary),
                    ),
                    const SizedBox(height: 2),
                    // Screen readers get the whole key, never the `…` form.
                    isKey
                        ? Semantics(
                          label: row.value,
                          excludeSemantics: true,
                          child: Text(
                            truncatePubkey(row.value),
                            maxLines: 1,
                            style: valueStyle,
                          ),
                        )
                        : Text(row.value, style: valueStyle),
                  ],
                ),
              ),
            ),
            if (isKey)
              CopyIconButton(
                text: row.value,
                size: 15,
                color: pal.icon,
                tooltip: copyTooltip,
                copiedLabel: copiedLabel,
              ),
          ],
        );
      case TechValueStyle.text:
      case TechValueStyle.figure:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                flex: 3,
                child: Text(
                  row.label,
                  style: TextStyle(fontSize: 12, color: book.textMuted),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                flex: 2,
                child: Text(
                  row.value,
                  textAlign: TextAlign.end,
                  style: strongValue,
                ),
              ),
            ],
          ),
        );
    }
  }
}

// ── Copy ──────────────────────────────────────────────────────────────────────

/// Copies [text] on tap and tells [builder] to show the copied state for
/// [copyFeedbackDuration].
class CopyFeedback extends StatefulWidget {
  const CopyFeedback({super.key, required this.text, required this.builder});

  final String text;
  final Widget Function(BuildContext context, bool copied, VoidCallback copy)
  builder;

  @override
  State<CopyFeedback> createState() => _CopyFeedbackState();
}

class _CopyFeedbackState extends State<CopyFeedback> {
  Timer? _reset;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    HapticFeedback.selectionClick();
    setState(() => _copied = true);
    _reset?.cancel();
    _reset = Timer(copyFeedbackDuration, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _copied, _copy);
}

/// A copy icon that turns into a lime check for a moment, with a 44 dp hit
/// target around however small it draws.
class CopyIconButton extends StatelessWidget {
  const CopyIconButton({
    super.key,
    required this.text,
    required this.size,
    required this.color,
    required this.tooltip,
    required this.copiedLabel,
  });

  final String text;
  final double size;
  final Color color;
  final String tooltip;
  final String copiedLabel;

  @override
  Widget build(BuildContext context) {
    final accent = AboutPalette.of(context).accent;
    return CopyFeedback(
      text: text,
      builder:
          (context, copied, copy) => Semantics(
            button: true,
            label: copied ? copiedLabel : tooltip,
            excludeSemantics: true,
            child: InkResponse(
              onTap: copy,
              radius: aboutMinTapTarget / 2,
              child: SizedBox.square(
                dimension: aboutMinTapTarget,
                child: Icon(
                  copied ? Icons.check_rounded : Icons.content_copy_rounded,
                  size: size,
                  color: copied ? accent : color,
                ),
              ),
            ),
          ),
    );
  }
}

/// `Copy all data` at the foot of 12b.
class CopyAllButton extends StatelessWidget {
  const CopyAllButton({
    super.key,
    required this.text,
    required this.label,
    required this.copiedLabel,
  });

  final String text;
  final String label;
  final String copiedLabel;

  @override
  Widget build(BuildContext context) {
    final pal = AboutPalette.of(context);
    final radius = BorderRadius.circular(16);
    return CopyFeedback(
      text: text,
      builder:
          (context, copied, copy) => Semantics(
            button: true,
            label: copied ? copiedLabel : label,
            excludeSemantics: true,
            child: Material(
              color: pal.actionFill,
              shape: RoundedRectangleBorder(
                borderRadius: radius,
                side: BorderSide(color: pal.actionBorder),
              ),
              child: InkWell(
                onTap: copy,
                borderRadius: radius,
                child: Padding(
                  padding: const EdgeInsets.all(13),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        copied
                            ? Icons.check_rounded
                            : Icons.content_copy_rounded,
                        size: 16,
                        color: pal.accent,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: pal.accent,
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
}

// ── Note ──────────────────────────────────────────────────────────────────────

/// The ⓘ footnote box that replaces the per-row tooltips.
class AboutNote extends StatelessWidget {
  const AboutNote(this.text, {super.key, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = AboutPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: pal.noteFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: pal.noteBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: pal.icon),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                height: 1.45,
                color: book.textSecondary,
              ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}
