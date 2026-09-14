import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/invoice_palette.dart';
import 'package:mostro/features/order/models/invoice_rules.dart';

/// One of the three things that can happen to the bonded sats (handoff 14,
/// "fila de consecuencia"): the icon's shape and colour are the information,
/// and the bold part of the sentence says it in words so colour is never the
/// only carrier.
class BondConsequence {
  const BondConsequence({
    required this.icon,
    required this.color,
    required this.sentence,
    required this.boldPart,
  });

  final IconData icon;
  final Color color;

  /// The sentence with a placeholder where [boldPart] goes (an l10n message
  /// with one parameter).
  final String Function(String bold) sentence;
  final String boldPart;
}

/// A marker no translation contains, used to find where the bold part sits.
/// Not a space: every sentence has spaces of its own, and splitting on them
/// would drop the prose between the first and last word.
const kBondSplit = '\u0000';

/// `(before, after)` of [sentence] around its placeholder, the placeholder
/// resolved with [kBondSplit]. Exposed so the rich-text callers agree.
(String, String) bondSentenceParts(String Function(String) sentence) {
  final parts = sentence(kBondSplit).split(kBondSplit);
  return (parts.first, parts.length > 1 ? parts.sublist(1).join() : '');
}

/// The three consequence rows in one card (padding 14 / 3, radius 18,
/// hairline separators). Never a fourth: a justification is not a
/// consequence and lives in the explainer.
class BondConsequenceCard extends StatelessWidget {
  const BondConsequenceCard({super.key, required this.rows});

  final List<BondConsequence> rows;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final palette = InvoicePalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(height: 1, thickness: 1, color: palette.subtleBorder),
            _ConsequenceRow(row: rows[i]),
          ],
        ],
      ),
    );
  }
}

class _ConsequenceRow extends StatelessWidget {
  const _ConsequenceRow({required this.row});

  final BondConsequence row;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final (before, after) = bondSentenceParts(row.sentence);
    final body = TextStyle(fontSize: 12, height: 1.4, color: book.textBody);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(row.icon, size: 16, color: row.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: body,
                children: [
                  TextSpan(text: before),
                  TextSpan(
                    text: row.boldPart,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: row.color,
                    ),
                  ),
                  if (after.isNotEmpty) TextSpan(text: after),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The explainer accordion's header row: subtle when closed, lime when open
/// (handoff 14, "acordeón"). Hit target 44 dp.
class BondExplainerToggle extends StatelessWidget {
  const BondExplainerToggle({
    super.key,
    required this.label,
    required this.open,
    required this.onPressed,
  });

  final String label;
  final bool open;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final palette = InvoicePalette.of(context);
    final ink = open ? palette.validInk : book.textTertiary;
    final iconInk = open ? palette.validIcon : palette.icon;
    return Material(
      color: open ? palette.validFill : palette.subtleFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: open ? palette.validBorder : palette.subtleBorder,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: iconInk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: open ? FontWeight.w600 : FontWeight.w400,
                      color: ink,
                    ),
                  ),
                ),
                Icon(
                  open ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: open ? iconInk : book.textFaint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The explainer's body (14b): paragraphs and a link to the user docs.
class BondExplainerBody extends StatelessWidget {
  const BondExplainerBody({
    super.key,
    required this.paragraphs,
    required this.linkLabel,
    required this.onLink,
  });

  final List<InlineSpan> paragraphs;
  final String linkLabel;
  final VoidCallback onLink;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final palette = InvoicePalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 15),
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < paragraphs.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            Text.rich(
              paragraphs[i],
              style: TextStyle(
                fontSize: 12,
                height: 1.55,
                color: book.textBody,
              ),
            ),
          ],
          const SizedBox(height: 12),
          InkWell(
            onTap: onLink,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    linkLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: palette.validIcon,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new, size: 12, color: palette.validIcon),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 14b's compact amount row: the label and figure on the left, the amber
/// time pill on the right. The hero shrinks when the reader is reading, not
/// scanning.
class BondAmountRow extends StatelessWidget {
  const BondAmountRow({
    super.key,
    required this.label,
    required this.sats,
    required this.remaining,
    required this.hours,
    required this.unit,
  });

  final String label;
  final int sats;

  /// The localized `sats` unit label.
  final String unit;
  final Duration? remaining;
  final String Function(String hours, String minutes) hours;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final palette = InvoicePalette.of(context);
    final remaining = this.remaining;
    final urgent = remaining != null && isInvoiceCountdownUrgent(remaining);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: book.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: book.textTertiary),
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: formatInvoiceSats(sats),
                        style: TextStyle(
                          fontFamily: AppFonts.figures,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: book.textPrimary,
                        ),
                      ),
                      TextSpan(
                        text: ' $unit',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: book.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (remaining != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: urgent ? palette.errorFill : palette.timeFill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: urgent ? palette.errorBorder : palette.timeBorder,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule,
                    size: 13,
                    color: urgent ? palette.errorInk : palette.timeFigure,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    formatInvoiceCountdown(remaining, hours: hours),
                    style: TextStyle(
                      fontFamily: AppFonts.figures,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: urgent ? palette.errorInk : palette.timeFigure,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
