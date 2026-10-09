import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/trade_palette.dart';
import 'package:mostro/l10n/app_localizations.dart';
import 'package:mostro/shared/utils/countdown.dart';
import 'package:mostro/shared/widgets/countdown_urgency_announcer.dart';

/// The countdown of the step block: label + time, a progress bar that fills
/// with the elapsed share of the window, and an optional note. Formatted and
/// toned by the shared countdown (DS-CMP-21); [total] is its window.
class TradeCountdown extends StatelessWidget {
  const TradeCountdown({
    super.key,
    required this.remaining,
    required this.total,
    required this.label,
    required this.isWaiting,
    this.note,
  });

  final Duration remaining;

  /// The whole window, so the bar can show how much of it has elapsed.
  final Duration total;

  /// `You have` / `They have`.
  final String label;

  /// Yellow while the user waits on the counterpart, lime while they act.
  final bool isWaiting;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final trade = TradePalette.of(context);
    final l10n = AppLocalizations.of(context);
    final tone = countdownTone(remaining, window: total);
    final color = switch (tone) {
      CountdownTone.urgent => trade.timerUrgent,
      CountdownTone.warning => trade.timerWait,
      CountdownTone.calm => isWaiting ? trade.timerWait : trade.timerActive,
    };
    final elapsed =
        total > Duration.zero
            ? (1 - remaining.inSeconds / total.inSeconds).clamp(0.0, 1.0)
            : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 11, color: book.textTertiary),
              ),
            ),
            CountdownUrgencyAnnouncer(
              urgent: tone == CountdownTone.urgent,
              message:
                  '$label '
                  '${formatCountdown(remaining, hours: l10n.invoiceCountdownHours)}',
              child: Text(
                formatCountdown(remaining, hours: l10n.invoiceCountdownHours),
                style: TextStyle(
                  fontFamily: AppFonts.figures,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: elapsed,
            minHeight: 3,
            color: color,
            backgroundColor: trade.trackBg,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 8),
          // The note changes while the user watches: at 00:00 it says what
          // mostrod is about to do (#569). Announced; the figure is not, or
          // it would be read every second (DS-A11Y-2).
          Semantics(
            liveRegion: true,
            child: Text(
              note!,
              style: TextStyle(
                fontSize: 11,
                height: 1.45,
                color: book.textFaint,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
