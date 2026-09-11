import 'package:flutter/material.dart';

import 'package:mostro/core/app_theme.dart';
import 'package:mostro/core/trade_palette.dart';

/// Urgency of the remaining time, which sets the countdown's colour.
enum CountdownTier {
  /// An hour or more left.
  calm,

  /// Under an hour.
  underHour,

  /// Under five minutes: the bar turns coral too.
  urgent,
}

const _hour = Duration(hours: 1);
const _fiveMinutes = Duration(minutes: 5);

/// `23:57` (h:mm) from an hour up, `12:40` (mm:ss) below. Never `23:57:48`:
/// seconds at that scale force a repaint every second and decide nothing.
String formatTradeCountdown(Duration remaining) {
  if (remaining <= Duration.zero) return '00:00';
  if (remaining >= _hour) {
    final minutes = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    return '${remaining.inHours}:$minutes';
  }
  final minutes = remaining.inMinutes.toString().padLeft(2, '0');
  final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

CountdownTier countdownTier(Duration remaining) {
  if (remaining < _fiveMinutes) return CountdownTier.urgent;
  if (remaining < _hour) return CountdownTier.underHour;
  return CountdownTier.calm;
}

/// How long until the displayed value changes: every second from an hour
/// down (at exactly `1:00` the next value is `59:59`, one second later),
/// otherwise at the next whole minute, so an hour-scale clock repaints once
/// a minute and lands exactly on the hour.
Duration nextCountdownTick(Duration remaining) {
  if (remaining <= _hour) return const Duration(seconds: 1);
  final intoMinute = remaining.inSeconds % 60;
  return Duration(seconds: intoMinute == 0 ? 60 : intoMinute);
}

/// The countdown of the step block: label + time, a progress bar that fills
/// with the elapsed share of the window, and an optional note.
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
    final tier = countdownTier(remaining);
    final color = switch (tier) {
      CountdownTier.urgent => trade.timerUrgent,
      CountdownTier.underHour => trade.timerWait,
      CountdownTier.calm => isWaiting ? trade.timerWait : trade.timerActive,
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
            Text(
              formatTradeCountdown(remaining),
              style: TextStyle(
                fontFamily: AppFonts.figures,
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
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
          Text(
            note!,
            style: TextStyle(fontSize: 11, height: 1.45, color: book.textFaint),
          ),
        ],
      ],
    );
  }
}
