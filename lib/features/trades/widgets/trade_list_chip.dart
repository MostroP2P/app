import 'package:flutter/material.dart';

import 'package:mostro/core/activity_palette.dart';
import 'package:mostro/features/trades/models/trades_list_rules.dart';
import 'package:mostro/l10n/app_localizations.dart';

/// The one status chip of a trade card (handoff 11a): a dot and an
/// upper-case label, in the palette — lime for the user's turn, amber for a
/// wait, neutral once closed, coral for a dispute.
class TradeListChip extends StatelessWidget {
  const TradeListChip({super.key, required this.label});

  final TradeChipLabel label;

  static String text(TradeChipLabel label, AppLocalizations l10n) =>
      switch (label) {
        TradeChipLabel.yourTurn => l10n.tradeListChipYourTurn,
        TradeChipLabel.published => l10n.tradeListChipPublished,
        TradeChipLabel.inProgress => l10n.tradeListChipInProgress,
        TradeChipLabel.waitingInvoice => l10n.tradeListChipWaitingInvoice,
        TradeChipLabel.waitingPayment => l10n.tradeListChipWaitingPayment,
        TradeChipLabel.waitingSats => l10n.tradeListChipWaitingSats,
        TradeChipLabel.dispute => l10n.tradeListChipDispute,
        TradeChipLabel.completed => l10n.tradeListChipCompleted,
        TradeChipLabel.cancelled => l10n.tradeListChipCancelled,
        TradeChipLabel.expired => l10n.tradeListChipExpired,
      };

  @override
  Widget build(BuildContext context) {
    final pal = ActivityPalette.of(context);
    final kind =
        TradeRowState(
          group: TradeGroup.inProgress,
          chip: label,
          verb: TradeRowVerb.none,
        ).chipKind;
    final (bg, border, ink, dot) = switch (kind) {
      TradeChipKind.action => (
        pal.chipActionBg,
        pal.chipActionBorder,
        pal.chipActionInk,
        pal.chipActionDot,
      ),
      TradeChipKind.waiting => (
        pal.chipWaitBg,
        pal.chipWaitBorder,
        pal.chipWaitInk,
        pal.chipWaitDot,
      ),
      TradeChipKind.done => (
        pal.chipDoneBg,
        pal.chipDoneBorder,
        pal.chipDoneInk,
        pal.chipDoneDot,
      ),
      TradeChipKind.dispute => (
        pal.chipDisputeBg,
        pal.chipDisputeBorder,
        pal.chipDisputeInk,
        pal.chipDisputeInk,
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
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            text(label, AppLocalizations.of(context)).toUpperCase(),
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
