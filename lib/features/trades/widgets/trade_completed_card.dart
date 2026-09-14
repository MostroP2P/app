import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/trade_palette.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// The closing card of a completed trade (8e): a lime check, the amount, and
/// either the rating the user gave or the five stars to give one. The check
/// and the title already say it — no `DONE` chip, no thank-you line.
class TradeCompletedCard extends StatelessWidget {
  const TradeCompletedCard({
    super.key,
    required this.amount,
    this.paymentMethod,
    this.ratedAlias,
    this.ratedScore,
    this.selectedRating,
    this.onRatingChanged,
    this.statusReadout,
  });

  /// `9.999 ARS`, or null while the order is unknown.
  final String? amount;
  final String? paymentMethod;

  /// The rating already sent, when there is one.
  final String? ratedAlias;
  final int? ratedScore;

  /// The star picker, when the user has yet to rate; [selectedRating] is 0
  /// until a star is tapped.
  final int? selectedRating;
  final ValueChanged<int>? onRatingChanged;

  /// Machine name of the status for the `order.status` readout, attached to
  /// the title row so the stars below keep their own semantics.
  final String? statusReadout;

  Widget _readout(Widget child) =>
      statusReadout == null
          ? child
          : child.withAutomationId(
            AutomationIds.orderStatus,
            label: statusReadout,
          );

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final trade = TradePalette.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: book.surface,
        border: Border.all(color: trade.stepBorderActive),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _readout(
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: trade.doneBg,
                    border: Border.all(color: trade.doneBorder),
                  ),
                  child: Icon(Icons.check, size: 17, color: book.limeText),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.tradeCompletedTitle,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w600,
                      color: book.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (amount != null) ...[
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: amount,
                    style: TextStyle(
                      fontFamily: AppFonts.figures,
                      fontSize: 26,
                      fontWeight: FontWeight.w600,
                      color: book.textPrimary,
                    ),
                  ),
                  if (paymentMethod != null)
                    TextSpan(
                      text: ' · $paymentMethod',
                      style: TextStyle(fontSize: 12, color: book.textTertiary),
                    ),
                ],
              ),
            ),
          ],
          if (onRatingChanged != null) ...[
            const SizedBox(height: 12),
            _RatingStars(
              selected: selectedRating ?? 0,
              onChanged: onRatingChanged!,
            ),
          ] else if (ratedScore != null) ...[
            const SizedBox(height: 12),
            _RatedRow(alias: ratedAlias ?? '', score: ratedScore!),
          ],
        ],
      ),
    );
  }
}

class _RatedRow extends StatelessWidget {
  const _RatedRow({required this.alias, required this.score});

  final String alias;
  final int score;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);
    final sentence = l10n.tradeRatedCounterpart(alias, '$score');
    final base = TextStyle(fontSize: 12, color: book.textSecondary);
    final aliasStyle = base.copyWith(
      color: book.textStrong,
      fontWeight: FontWeight.w500,
    );
    final scoreStyle = base.copyWith(
      fontFamily: AppFonts.figures,
      fontWeight: FontWeight.w600,
      color: book.textStrong,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: book.inset,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.star_rounded, size: 13, color: book.yellow),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              _emphasise(sentence, {alias: aliasStyle, '$score': scoreStyle}),
              style: base,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps each key of [parts] found in [sentence] in its style, so the
/// translation decides the word order and the code the emphasis.
TextSpan _emphasise(String sentence, Map<String, TextStyle> parts) {
  final keys = parts.keys.where((k) => k.isNotEmpty).toList();
  if (keys.isEmpty) return TextSpan(text: sentence);
  final pattern = RegExp(keys.map(RegExp.escape).join('|'));
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in pattern.allMatches(sentence)) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: sentence.substring(cursor, match.start)));
    }
    spans.add(TextSpan(text: match.group(0), style: parts[match.group(0)]));
    cursor = match.end;
  }
  if (cursor < sentence.length) {
    spans.add(TextSpan(text: sentence.substring(cursor)));
  }
  return TextSpan(children: spans);
}

/// Five tappable stars, 22dp, yellow once picked. Carries the same
/// automation ids as the rating screen (`trade.rate.star.<n>`).
class _RatingStars extends StatelessWidget {
  const _RatingStars({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final l10n = AppLocalizations.of(context);

    return Row(
      children: [
        for (var star = 1; star <= 5; star++) ...[
          if (star > 1) const SizedBox(width: 8),
          Semantics(
            button: true,
            selected: star <= selected,
            label: l10n.selectStarTooltip(star),
            child: InkResponse(
              onTap: () => onChanged(star),
              radius: 20,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(
                  star <= selected
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded,
                  size: 22,
                  color: star <= selected ? book.yellow : book.starEmpty,
                ),
              ),
            ),
          ).withAutomationId(AutomationIds.tradeRateStar(star)),
        ],
      ],
    );
  }
}
