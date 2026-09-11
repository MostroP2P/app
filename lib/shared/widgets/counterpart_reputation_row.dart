import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/trade_palette.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// One-row counterpart reputation: the grade on the avatar, the role, and
/// `2 trades · 1 day on Mostro`. Shared by the trade screen (8b, 8c) and the
/// take-order detail, so both render identically.
///
/// A counterpart nobody has rated shows `New` in place of the grade. That is
/// the raw wire fact: a brand-new user and a full-privacy taker are
/// indistinguishable, and the row does not pretend otherwise.
class CounterpartReputationRow extends StatelessWidget {
  const CounterpartReputationRow({
    super.key,
    required this.rating,
    required this.reviews,
    required this.days,
    required this.counterpartIsBuyer,
  });

  final double rating;
  final int reviews;
  final int days;
  final bool counterpartIsBuyer;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final trade = TradePalette.of(context);
    final l10n = AppLocalizations.of(context);
    final isNew = reviews == 0;

    final summary = TextStyle(fontSize: 11, color: book.textSecondary);
    final figure = summary.copyWith(
      color: book.textBody,
      fontWeight: FontWeight.w500,
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: book.surface,
        border: Border.all(color: book.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isNew ? trade.avatarNewBg : trade.avatarBg,
              border: Border.all(
                color: isNew ? book.border : trade.avatarBorder,
              ),
            ),
            child:
                isNew
                    ? Text(
                      l10n.reputationNew,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: book.textNew,
                      ),
                    )
                    : Text(
                      rating.toStringAsFixed(1),
                      style: TextStyle(
                        fontFamily: AppFonts.figures,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: book.limeInk,
                      ),
                    ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 12,
                      color: isNew ? book.starEmpty : book.yellow,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      counterpartIsBuyer
                          ? l10n.tradeRoleBuyer
                          : l10n.tradeRoleSeller,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: book.textStrong,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      ...highlightFigures(
                        l10n.reputationTradesCount(reviews),
                        figure,
                      ),
                      const TextSpan(text: ' · '),
                      ...highlightFigures(
                        l10n.reputationDaysOnMostro(days),
                        figure,
                      ),
                    ],
                  ),
                  style: summary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

final _digits = RegExp(r'\d[\d.,]*');

/// Splits [text] so every run of digits gets [figureStyle] while the rest
/// inherits — how a localized sentence keeps its numbers emphasised without
/// the translation knowing where they fall.
List<InlineSpan> highlightFigures(String text, TextStyle figureStyle) {
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in _digits.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    spans.add(TextSpan(text: match.group(0), style: figureStyle));
    cursor = match.end;
  }
  if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
  return spans;
}
