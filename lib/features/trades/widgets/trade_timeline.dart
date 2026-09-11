import 'package:flutter/material.dart';

import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/core/trade_palette.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// `YOUR TRADE`: one row per step, written from the user's side. Done steps
/// get a lime check, the current one a lime ring with a dot, the rest a
/// faint ring.
class TradeTimeline extends StatelessWidget {
  const TradeTimeline({super.key, required this.steps, required this.current});

  final List<String> steps;

  /// Index of the current step; `steps.length` once every step is done.
  final int current;

  @override
  Widget build(BuildContext context) {
    final book = OrderBookPalette.of(context);
    final trade = TradePalette.of(context);
    final l10n = AppLocalizations.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: book.surface,
        border: Border.all(color: book.border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.yourTradeTimelineTitle,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: book.textFaint,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _StepRow(
              label: steps[i],
              state:
                  i < current
                      ? _StepState.done
                      : i == current
                      ? _StepState.current
                      : _StepState.pending,
              book: book,
              trade: trade,
            ),
          ],
        ],
      ),
    );
  }
}

enum _StepState { done, current, pending }

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.state,
    required this.book,
    required this.trade,
  });

  final String label;
  final _StepState state;
  final OrderBookPalette book;
  final TradePalette trade;

  @override
  Widget build(BuildContext context) {
    final marker = switch (state) {
      _StepState.done => Icon(Icons.check, size: 16, color: book.limeText),
      _StepState.current => Container(
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: book.limeText, width: 2),
        ),
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: book.limeText,
          ),
        ),
      ),
      _StepState.pending => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: trade.stepPending, width: 1.5),
        ),
      ),
    };
    final style = switch (state) {
      _StepState.done => TextStyle(fontSize: 12, color: book.textTertiary),
      _StepState.current => TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: book.textStrong,
      ),
      _StepState.pending => TextStyle(fontSize: 12, color: book.textFaint),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 16, height: 17, child: Center(child: marker)),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: style.copyWith(height: 1.4))),
      ],
    );
  }
}
