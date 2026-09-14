import 'package:flutter/material.dart';

import 'package:mostro/core/automation/automation_id.dart';
import 'package:mostro/core/automation/automation_ids.dart';
import 'package:mostro/core/order_book_palette.dart';
import 'package:mostro/core/trade_palette.dart';
import 'package:mostro/features/trades/models/trade_view.dart';

/// The main block of the trade screen: `STEP n OF 5` with the status chip,
/// the title of what is happening, its body, the optional release warning
/// and the countdown.
class TradeStepBlock extends StatelessWidget {
  const TradeStepBlock({
    super.key,
    required this.stepLabel,
    required this.chip,
    required this.chipLabel,
    required this.title,
    this.body,
    this.warning,
    this.countdown,
    this.statusReadout,
  });

  /// `STEP 3 OF 5`, or null when the timeline is hidden.
  final String? stepLabel;
  final TradeChip chip;
  final String chipLabel;

  /// Figures inside are already set in Manrope by the caller.
  final InlineSpan title;
  final InlineSpan? body;

  /// `Releasing the sats cannot be undone.` (8d).
  final String? warning;
  final Widget? countdown;

  /// Machine name of the status for the `order.status` readout, attached to
  /// the header row (or the title when there is no header) — never to the
  /// whole block, which would swallow its descendants' semantics.
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
    final hasHeader = stepLabel != null || chip != TradeChip.none;
    final border = switch (chip) {
      TradeChip.waiting => trade.stepBorderWait,
      TradeChip.active || TradeChip.yourTurn => trade.stepBorderActive,
      TradeChip.dispute => trade.chipDisputeBorder,
      TradeChip.none => book.border,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: book.surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasHeader) ...[
            _readout(
              Row(
                children: [
                  if (stepLabel != null)
                    Expanded(
                      child: Text(
                        stepLabel!,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.6,
                          color: book.textTertiary,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  if (chip != TradeChip.none)
                    TradeStatusChip(kind: chip, label: chipLabel),
                ],
              ),
            ),
            const SizedBox(height: 11),
          ],
          _title(hasHeader, book),
          if (body != null) ...[
            const SizedBox(height: 11),
            Text.rich(
              body!,
              style: TextStyle(
                fontSize: 12,
                height: 1.5,
                color: book.textSecondary,
              ),
            ),
          ],
          if (warning != null) ...[
            const SizedBox(height: 11),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: trade.warnBg,
                border: Border.all(color: trade.warnBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: book.yellow,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      warning!,
                      style: TextStyle(fontSize: 11, color: trade.warnInk),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (countdown != null) ...[const SizedBox(height: 11), countdown!],
        ],
      ),
    );
  }
}

extension on TradeStepBlock {
  Widget _title(bool hasHeader, OrderBookPalette book) {
    final text = Text.rich(
      title,
      style: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        height: 1.25,
        letterSpacing: -0.19,
        color: book.textPrimary,
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    );
    return hasHeader ? text : _readout(text);
  }
}

/// `WAITING` (amber) / `ACTIVE` · `YOUR TURN` (lime) / `DISPUTE` (coral):
/// a dot and an uppercase label. It tells wait from act at a glance.
class TradeStatusChip extends StatelessWidget {
  const TradeStatusChip({super.key, required this.kind, required this.label});

  final TradeChip kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final trade = TradePalette.of(context);
    final book = OrderBookPalette.of(context);
    final (bg, border, ink, dot) = switch (kind) {
      TradeChip.waiting => (
        trade.chipWaitBg,
        trade.chipWaitBorder,
        trade.chipWaitInk,
        book.yellow,
      ),
      TradeChip.dispute => (
        trade.chipDisputeBg,
        trade.chipDisputeBorder,
        trade.chipDisputeInk,
        book.sell,
      ),
      TradeChip.active || TradeChip.yourTurn || TradeChip.none => (
        trade.chipActiveBg,
        trade.chipActiveBorder,
        trade.chipActiveInk,
        book.lime,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: dot),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}
