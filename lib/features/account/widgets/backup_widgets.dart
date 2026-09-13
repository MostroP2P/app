import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/backup_palette.dart';
import 'package:mostro/features/account/models/backup_rules.dart';
import 'package:mostro/shared/widgets/redesign_app_bar.dart';

/// Pieces shared by Account (15a/15b) and the backup flow (16a–16d) of
/// `design_handoff_cuenta_respaldo`.

/// How long `Copy` shows a check after copying.
const Duration backupCopyFeedback = Duration(milliseconds: 1200);

/// A column that fills the viewport so [footer] sits at the bottom, and
/// scrolls instead of shrinking text when a translation does not fit.
/// [centered] also centres [blocks] vertically (16d).
class BackupFillViewport extends StatelessWidget {
  const BackupFillViewport({
    super.key,
    required this.blocks,
    this.footer,
    this.gap = 12,
    this.centered = false,
  });

  /// The content, [gap] apart.
  final List<Widget> blocks;
  final Widget? footer;
  final double gap;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder:
          (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              redesignSidePadding,
              0,
              redesignSidePadding,
              redesignSidePadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: math.max(
                  0,
                  constraints.maxHeight - redesignSidePadding,
                ),
              ),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (centered) const Spacer(),
                    for (var i = 0; i < blocks.length; i++) ...[
                      if (i > 0) SizedBox(height: gap),
                      blocks[i],
                    ],
                    if (footer != null || centered) const Spacer(),
                    if (footer != null) ...[SizedBox(height: gap), footer!],
                  ],
                ),
              ),
            ),
          ),
    );
  }
}

/// The 12 words in a 2 × 6 grid. A null [words] shows 12 masked cells (15b);
/// [large] is the roomier grid of 16a.
class BackupWordGrid extends StatelessWidget {
  const BackupWordGrid({super.key, required this.words, this.large = false});

  final List<String>? words;
  final bool large;

  static const _gap = 6.0;
  static const _maskedCount = 12;

  @override
  Widget build(BuildContext context) {
    final count = words?.length ?? _maskedCount;
    final rows = (count + 1) ~/ 2;
    return Column(
      children: [
        for (var r = 0; r < rows; r++) ...[
          if (r > 0) const SizedBox(height: _gap),
          Row(
            children: [
              for (var c = 0; c < 2; c++) ...[
                if (c > 0) const SizedBox(width: _gap),
                Expanded(
                  child:
                      r * 2 + c < count
                          ? _WordCell(
                            index: r * 2 + c,
                            word: words?[r * 2 + c],
                            large: large,
                          )
                          : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _WordCell extends StatelessWidget {
  const _WordCell({
    required this.index,
    required this.word,
    required this.large,
  });

  final int index;

  /// Null while masked.
  final String? word;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);
    final size = large ? 14.0 : 13.0;
    final masked = word == null;
    final value = Text(
      word ?? backupWordMask,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: AppFonts.figures,
        fontSize: size,
        fontWeight: FontWeight.w500,
        letterSpacing: size * (masked ? 0.12 : 0.01),
        color: masked ? pal.muted : book.textStrong,
      ),
    );
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: large ? 11 : 10,
        vertical: large ? 9 : 7,
      ),
      decoration: BoxDecoration(
        color: pal.cell,
        borderRadius: BorderRadius.circular(large ? 11 : 10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            backupWordNumber(index),
            style: TextStyle(
              fontFamily: AppFonts.figures,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: pal.wordIndex,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(child: masked ? ExcludeSemantics(child: value) : value),
        ],
      ),
    );
  }
}

/// The lime action of every step: padding 15, radius 16, 14/700. A null
/// [onPressed] greys it out; [loading] keeps the lime and shows a spinner.
class BackupPrimaryButton extends StatelessWidget {
  const BackupPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.leading,
    this.trailing,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? leading;
  final IconData? trailing;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final pal = BackupPalette.of(context);
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: book.lime,
        foregroundColor: book.onLime,
        disabledBackgroundColor: loading ? book.lime : pal.disabledFill,
        disabledForegroundColor: loading ? book.onLime : pal.muted,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        minimumSize: const Size(0, 50),
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontFamily: AppFonts.ui,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      child:
          loading
              // The spinner replaces the label on screen, not for assistive
              // technology: the button keeps its name while it is busy.
              ? Semantics(
                label: label,
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: book.onLime,
                  ),
                ),
              )
              : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (leading != null) ...[
                    Icon(leading, size: 16),
                    const SizedBox(width: 8),
                  ],
                  Flexible(child: Text(label, textAlign: TextAlign.center)),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    Icon(trailing, size: 16),
                  ],
                ],
              ),
    );
  }
}

/// Three segments under the app bar; every segment up to [step] (0-based) is
/// lit.
class BackupProgressBar extends StatelessWidget {
  const BackupProgressBar({super.key, required this.step});

  final int step;

  static const segments = 3;

  @override
  Widget build(BuildContext context) {
    final pal = BackupPalette.of(context);
    return Row(
      children: [
        for (var i = 0; i < segments; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: i <= step ? pal.accent : pal.progressTrack,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
